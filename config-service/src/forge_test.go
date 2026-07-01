package main

import (
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"sort"
	"testing"

	"go.woodpecker-ci.org/woodpecker/v3/server/model"
)

func TestParseCloneURL(t *testing.T) {
	cases := []struct {
		in, owner, repo string
	}{
		{"https://github.com/barryw/NovaVM.git", "barryw", "NovaVM"},
		{"https://github.com/barryw/NovaVM", "barryw", "NovaVM"},
		{"https://github.com/barryw/go-pihole.git", "barryw", "go-pihole"},
		{"not a url with spaces", "", ""},
	}
	for _, c := range cases {
		o, r := parseCloneURL(c.in)
		if o != c.owner || r != c.repo {
			t.Errorf("parseCloneURL(%q) = (%q,%q), want (%q,%q)", c.in, o, r, c.owner, c.repo)
		}
	}
}

func TestStripYAMLSuffix(t *testing.T) {
	cases := map[string]string{
		"ci.yaml":      "ci",
		"01-bump.yml":  "01-bump",
		"metal-ui.yaml": "metal-ui",
		"noext":        "noext",
	}
	for in, want := range cases {
		if got := stripYAMLSuffix(in); got != want {
			t.Errorf("stripYAMLSuffix(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestEscapeContentsPath(t *testing.T) {
	if got := escapeContentsPath(".woodpecker/ci.yaml"); got != ".woodpecker/ci.yaml" {
		t.Errorf("escapeContentsPath kept separator wrong: %q", got)
	}
	if got := escapeContentsPath(".woodpecker/a b.yaml"); got != ".woodpecker/a%20b.yaml" {
		t.Errorf("escapeContentsPath did not escape space: %q", got)
	}
}

func TestHasConfigNamed(t *testing.T) {
	cfgs := []configData{{Name: "pipeline"}, {Name: "ci"}}
	if !hasConfigNamed(cfgs, "ci") {
		t.Error("expected ci to be present")
	}
	if hasConfigNamed(cfgs, "bump") {
		t.Error("did not expect bump to be present")
	}
}

// fakeForge mounts a GitHub Contents API subset backed by an in-memory tree.
// dir maps a directory path to its child file names; files maps a file path to
// its raw contents.
func fakeForge(t *testing.T, dir map[string][]string, files map[string]string) *httptest.Server {
	t.Helper()
	mux := http.NewServeMux()
	mux.HandleFunc("/repos/barryw/NovaVM/contents/", func(w http.ResponseWriter, r *http.Request) {
		// Strip the API prefix to recover the repo-relative path.
		const prefix = "/repos/barryw/NovaVM/contents/"
		p := r.URL.Path[len(prefix):]

		if names, ok := dir[p]; ok {
			var entries []githubContentsEntry
			for _, n := range names {
				entries = append(entries, githubContentsEntry{Name: n, Path: p + "/" + n, Type: "file"})
			}
			_ = json.NewEncoder(w).Encode(entries)
			return
		}
		if content, ok := files[p]; ok {
			_ = json.NewEncoder(w).Encode(githubContentsResponse{
				Encoding: "base64",
				Content:  base64.StdEncoding.EncodeToString([]byte(content)),
			})
			return
		}
		http.Error(w, "not found", http.StatusNotFound)
	})
	srv := httptest.NewServer(mux)
	t.Setenv("GITHUB_API_BASE", srv.URL)
	t.Cleanup(srv.Close)
	return srv
}

func req() woodpeckerRequest {
	return woodpeckerRequest{
		Repo:     &model.Repo{Clone: "https://github.com/barryw/NovaVM.git"},
		Pipeline: &model.Pipeline{Commit: "deadbeef"},
	}
}

func names(cfgs []configData) []string {
	var out []string
	for _, c := range cfgs {
		out = append(out, c.Name)
	}
	sort.Strings(out)
	return out
}

func TestGetRepoConfigsFromForge_MergesPipelinesAndSkipsStubAndScripts(t *testing.T) {
	fakeForge(t,
		map[string][]string{
			".woodpecker": {"woodpecker-template.yaml", "ci.yaml", "build-gate.yaml", "install-linux-ci-deps.sh"},
		},
		map[string]string{
			".woodpecker/ci.yaml":         "when:\n  - event: push\nsteps:\n  bump: {}\n",
			".woodpecker/build-gate.yaml": "when:\n  - event: tag\nsteps:\n  gate: {}\n",
			// The stub and the shell script must both be excluded.
			".woodpecker/woodpecker-template.yaml": "template: release-static-site\n",
			".woodpecker/install-linux-ci-deps.sh": "#!/bin/sh\n",
		},
	)

	got := getRepoConfigsFromForge(req())
	want := []string{"build-gate", "ci"}
	gotNames := names(got)
	if len(gotNames) != len(want) {
		t.Fatalf("got configs %v, want %v", gotNames, want)
	}
	for i := range want {
		if gotNames[i] != want[i] {
			t.Fatalf("got configs %v, want %v", gotNames, want)
		}
	}
}

func TestGetRepoConfigsFromForge_TemplateOnlyRepoYieldsNothing(t *testing.T) {
	fakeForge(t,
		map[string][]string{".woodpecker": {"woodpecker-template.yaml"}},
		map[string]string{".woodpecker/woodpecker-template.yaml": "template: release-static-site\n"},
	)
	if got := getRepoConfigsFromForge(req()); len(got) != 0 {
		t.Fatalf("template-only repo should merge nothing, got %v", names(got))
	}
}

func TestMergeDedupPrefersGeneratedConfig(t *testing.T) {
	// Simulate the main.go merge loop: a generated template config named
	// "pipeline" must win over a repo file that happens to also be "pipeline".
	generated := []configData{{Name: "pipeline", Data: "TEMPLATE"}}
	repo := []configData{{Name: "pipeline", Data: "REPO"}, {Name: "ci", Data: "CI"}}

	for _, rc := range repo {
		if hasConfigNamed(generated, rc.Name) {
			continue
		}
		generated = append(generated, rc)
	}

	if len(generated) != 2 {
		t.Fatalf("expected 2 configs after dedup, got %d", len(generated))
	}
	if generated[0].Name != "pipeline" || generated[0].Data != "TEMPLATE" {
		t.Fatalf("generated template config should have won, got %+v", generated[0])
	}
}
