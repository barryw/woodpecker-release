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

// githubContentsResponse represents the GitHub Contents API response.
type githubContentsResponse struct {
	Content  string `json:"content"`
	Encoding string `json:"encoding"`
}

// getTemplateFileFromForge fetches .woodpecker/woodpecker-template.yaml
// via the GitHub Contents API. One HTTP request, zero git cloning.
func getTemplateFileFromForge(req woodpeckerRequest, _ []byte) ([]byte, bool) {
	// Extract owner/repo from clone URL
	// e.g., "https://github.com/barryw/go-pihole.git" -> "barryw/go-pihole"
	owner, repo := parseCloneURL(req.Repo.Clone)
	if owner == "" || repo == "" {
		log.Printf("Could not parse clone URL: '%s'", req.Repo.Clone)
		return nil, false
	}

	commit := req.Pipeline.Commit

	// GitHub Contents API: GET /repos/{owner}/{repo}/contents/{path}?ref={commit}
	apiURL := fmt.Sprintf(
		"https://api.github.com/repos/%s/%s/contents/.woodpecker/woodpecker-template.yaml?ref=%s",
		url.PathEscape(owner),
		url.PathEscape(repo),
		url.QueryEscape(commit),
	)

	httpReq, err := http.NewRequest(http.MethodGet, apiURL, nil)
	if err != nil {
		log.Printf("Error creating request: '%v'", err)
		return nil, false
	}

	httpReq.Header.Set("Accept", "application/vnd.github.v3+json")
	if req.Netrc != nil && req.Netrc.Password != "" {
		httpReq.SetBasicAuth(req.Netrc.Login, req.Netrc.Password)
	}

	resp, err := http.DefaultClient.Do(httpReq)
	if err != nil {
		log.Printf("Error fetching template file: '%v'", err)
		return nil, false
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusNotFound {
		// No template file — this is the normal case for repos that don't use templates.
		return nil, false
	}

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		log.Printf("GitHub API returned %d for %s/%s: %s", resp.StatusCode, owner, repo, string(body))
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

	log.Printf("Loaded template config for %s/%s (%d bytes)", owner, repo, len(data))
	return data, true
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
