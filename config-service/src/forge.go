package main

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"strings"
)

// githubContentsResponse represents the GitHub Contents API response for a file.
type githubContentsResponse struct {
	Content  string `json:"content"`
	Encoding string `json:"encoding"`
}

// githubContentsEntry represents one entry of a GitHub Contents API directory
// listing. Directory listings do NOT include file content — only metadata — so
// each file has to be fetched individually via getForgeFile.
type githubContentsEntry struct {
	Name string `json:"name"`
	Path string `json:"path"`
	Type string `json:"type"`
}

// getTemplateFileFromForge fetches .woodpecker/woodpecker-template.yaml
// via the GitHub Contents API. One HTTP request, zero git cloning.
func getTemplateFileFromForge(req woodpeckerRequest, _ []byte) ([]byte, bool) {
	return getForgeFile(req, ".woodpecker/woodpecker-template.yaml")
}

// getForgeFile fetches a single file at `repoPath` (repo-relative, e.g.
// ".woodpecker/ci.yaml") from the pipeline's commit via the GitHub Contents API
// and returns its decoded bytes. Returns (nil, false) on 404 or any error.
func getForgeFile(req woodpeckerRequest, repoPath string) ([]byte, bool) {
	owner, repo := parseCloneURL(req.Repo.Clone)
	if owner == "" || repo == "" {
		log.Printf("Could not parse clone URL: '%s'", req.Repo.Clone)
		return nil, false
	}

	commit := req.Pipeline.Commit

	// GitHub Contents API: GET /repos/{owner}/{repo}/contents/{path}?ref={commit}
	apiURL := fmt.Sprintf(
		"%s/repos/%s/%s/contents/%s?ref=%s",
		githubAPIBase(),
		url.PathEscape(owner),
		url.PathEscape(repo),
		escapeContentsPath(repoPath),
		url.QueryEscape(commit),
	)

	resp, ok := doForgeRequest(req, apiURL)
	if !ok {
		return nil, false
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusNotFound {
		// No such file — the normal case for repos that don't use templates.
		return nil, false
	}

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		log.Printf("GitHub API returned %d for %s (%s/%s): %s", resp.StatusCode, repoPath, owner, repo, string(body))
		return nil, false
	}

	var contents githubContentsResponse
	if err := json.NewDecoder(resp.Body).Decode(&contents); err != nil {
		log.Printf("Error decoding GitHub response: '%v'", err)
		return nil, false
	}

	if contents.Encoding != "base64" {
		log.Printf("Unexpected encoding: '%s'", contents.Encoding)
		return nil, false
	}

	// GitHub returns base64 with newlines — strip them
	cleaned := strings.ReplaceAll(contents.Content, "\n", "")
	data, err := base64.StdEncoding.DecodeString(cleaned)
	if err != nil {
		log.Printf("Error decoding base64 content: '%v'", err)
		return nil, false
	}

	log.Printf("Loaded %s for %s/%s (%d bytes)", repoPath, owner, repo, len(data))
	return data, true
}

// getRepoConfigsFromForge fetches the repo's own .woodpecker/*.{yml,yaml}
// pipeline definitions (EXCLUDING the woodpecker-template.yaml stub) so they can
// be merged alongside the rendered house template. Without this, a repo that
// adopts woodpecker-template.yaml silently loses every other pipeline it defines
// — its bump/build/release/test workflows never run on push (WAL-162), because
// returning template configs to Woodpecker fully replaces the raw repo config.
//
// Any forge error is logged and yields an empty slice: a merge failure must
// never block the template pipeline that already rendered successfully.
func getRepoConfigsFromForge(req woodpeckerRequest) []configData {
	entries, ok := listForgeDir(req, ".woodpecker")
	if !ok {
		return nil
	}

	var configs []configData
	for _, entry := range entries {
		if entry.Type != "file" {
			continue
		}
		name := entry.Name
		// The stub itself is template data, not a runnable pipeline.
		if name == "woodpecker-template.yaml" {
			continue
		}
		if !strings.HasSuffix(name, ".yml") && !strings.HasSuffix(name, ".yaml") {
			continue
		}

		data, ok := getForgeFile(req, entry.Path)
		if !ok {
			log.Printf("Could not fetch repo config %s — skipping", entry.Path)
			continue
		}

		configs = append(configs, configData{
			Name: stripYAMLSuffix(name),
			Data: string(data),
		})
	}

	return configs
}

// listForgeDir returns the directory listing for `repoPath` via the GitHub
// Contents API. Returns (nil, false) on 404 or any error.
func listForgeDir(req woodpeckerRequest, repoPath string) ([]githubContentsEntry, bool) {
	owner, repo := parseCloneURL(req.Repo.Clone)
	if owner == "" || repo == "" {
		log.Printf("Could not parse clone URL: '%s'", req.Repo.Clone)
		return nil, false
	}

	commit := req.Pipeline.Commit

	apiURL := fmt.Sprintf(
		"%s/repos/%s/%s/contents/%s?ref=%s",
		githubAPIBase(),
		url.PathEscape(owner),
		url.PathEscape(repo),
		escapeContentsPath(repoPath),
		url.QueryEscape(commit),
	)

	resp, ok := doForgeRequest(req, apiURL)
	if !ok {
		return nil, false
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		if resp.StatusCode != http.StatusNotFound {
			body, _ := io.ReadAll(resp.Body)
			log.Printf("GitHub API returned %d listing %s (%s/%s): %s", resp.StatusCode, repoPath, owner, repo, string(body))
		}
		return nil, false
	}

	var entries []githubContentsEntry
	if err := json.NewDecoder(resp.Body).Decode(&entries); err != nil {
		log.Printf("Error decoding GitHub directory listing: '%v'", err)
		return nil, false
	}

	return entries, true
}

// doForgeRequest issues an authenticated GET to the GitHub Contents API.
// Auth precedence matches the template fetch: a dedicated CONFIG_SERVICE_GITHUB_TOKEN
// (read access to the private repos) takes precedence; the per-pipeline netrc is
// the fallback. PUBLIC repos resolve unauthenticated; PRIVATE repos 404 without a
// credential — which every caller treats as "not found" and skips.
func doForgeRequest(req woodpeckerRequest, apiURL string) (*http.Response, bool) {
	httpReq, err := http.NewRequest(http.MethodGet, apiURL, nil)
	if err != nil {
		log.Printf("Error creating request: '%v'", err)
		return nil, false
	}

	httpReq.Header.Set("Accept", "application/vnd.github.v3+json")
	if token := lookupEnvOrDefault("CONFIG_SERVICE_GITHUB_TOKEN", ""); token != "" {
		httpReq.Header.Set("Authorization", "Bearer "+token)
	} else if req.Netrc != nil && req.Netrc.Password != "" {
		httpReq.SetBasicAuth(req.Netrc.Login, req.Netrc.Password)
	}

	resp, err := http.DefaultClient.Do(httpReq)
	if err != nil {
		log.Printf("Error performing forge request: '%v'", err)
		return nil, false
	}

	return resp, true
}

// githubAPIBase returns the GitHub API root. Overridable via GITHUB_API_BASE
// (no trailing slash) for tests and for pointing at a GHES/proxy host; defaults
// to the public GitHub API.
func githubAPIBase() string {
	return strings.TrimRight(lookupEnvOrDefault("GITHUB_API_BASE", "https://api.github.com"), "/")
}

// escapeContentsPath path-escapes each segment of a repo-relative path while
// preserving the "/" separators the Contents API expects.
func escapeContentsPath(repoPath string) string {
	segments := strings.Split(repoPath, "/")
	for i, s := range segments {
		segments[i] = url.PathEscape(s)
	}
	return strings.Join(segments, "/")
}

// stripYAMLSuffix trims a trailing .yaml or .yml extension.
func stripYAMLSuffix(name string) string {
	if strings.HasSuffix(name, ".yaml") {
		return strings.TrimSuffix(name, ".yaml")
	}
	return strings.TrimSuffix(name, ".yml")
}

// parseCloneURL extracts owner and repo from a GitHub clone URL.
func parseCloneURL(cloneURL string) (string, string) {
	// Handle both HTTPS and SSH URLs
	// https://github.com/barryw/go-pihole.git
	// git@github.com:barryw/go-pihole.git
	u, err := url.Parse(cloneURL)
	if err != nil {
		return "", ""
	}

	path := strings.TrimPrefix(u.Path, "/")
	path = strings.TrimSuffix(path, ".git")

	parts := strings.SplitN(path, "/", 2)
	if len(parts) != 2 {
		return "", ""
	}

	return parts[0], parts[1]
}
