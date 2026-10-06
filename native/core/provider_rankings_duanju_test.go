package core

import (
	"context"
	"net/http"
	"net/url"
	"strings"
	"testing"
)

func TestDuanjuRankingBoardsCoverEverySource(t *testing.T) {
	want := map[string]int{
		sourceYaguo: 2, sourceMaoguo: 1, sourceFanguo: 3, sourceGuanguo: 1,
		sourceHeguo: 3, sourceXingguo: 1, sourceHuaguo: 1, sourceNiuguo: 5,
		sourcePiguo: 3, sourceWuguo: 5, sourceChaoguo: 8,
	}
	got := map[string]int{}
	for _, board := range rankingBoards {
		if isDuanjuProviderSource(board.Source) {
			got[board.Source]++
		}
	}
	for source, count := range want {
		if got[source] != count {
			t.Fatalf("%s should expose %d ranking boards, got %d", source, count, got[source])
		}
	}
	for _, spec := range duanjuProviderCatalog {
		if got[spec.ID] == 0 {
			t.Fatalf("%s has no ranking board", spec.ID)
		}
	}
}

func TestDuanjuRankingBoardCategoriesMatchTheirSource(t *testing.T) {
	for _, board := range rankingBoards {
		if !isDuanjuProviderSource(board.Source) {
			continue
		}
		if board.path == "" {
			if board.Source != sourceGuanguo && board.Source != sourceChaoguo {
				t.Fatalf("%s has no category", board.ID)
			}
			continue
		}
		if !duanjuValidCategory(board.Source, board.path) {
			t.Fatalf("%s uses category %q that %s does not accept", board.ID, board.path, board.Source)
		}
	}
}

func TestDuanjuRankingRoutesThroughTheSourceCatalog(t *testing.T) {
	for _, source := range []string{sourceHuaguo, sourceWuguo, sourcePiguo} {
		var board rankingBoard
		found := false
		for _, candidate := range rankingBoards {
			if candidate.Source == source {
				board, found = candidate, true
				break
			}
		}
		if !found {
			t.Fatalf("%s has no ranking board", source)
		}
		requested := ""
		d, server := duanjuFixtureDownloader(t, func(writer http.ResponseWriter, request *http.Request) {
			requested = request.URL.RequestURI()
			writer.Header().Set("Content-Type", "text/html; charset=utf-8")
			_, _ = writer.Write([]byte(duanjuRankingFixture(source)))
		})
		d.providerHosts[source] = server.URL
		page, err := d.fetchRankingPage(context.Background(), board, 1)
		if err != nil {
			t.Fatalf("%s failed: %v", board.ID, err)
		}
		if !duanjuRankingRequestMatches(board, requested) {
			t.Fatalf("%s did not request its category %q: %s", board.ID, board.path, requested)
		}
		if len(page.Items) == 0 {
			t.Fatalf("%s returned no items", board.ID)
		}
		for _, item := range page.Items {
			if item.Drama.ID == "" || item.Drama.Source != source {
				t.Fatalf("%s returned a foreign item: %+v", board.ID, item.Drama)
			}
			if item.Drama.Cover != nil || item.Drama.CoverURL != nil || item.Drama.Pic != nil {
				t.Fatalf("%s must not expose source images", board.ID)
			}
		}
		if page.Items[0].Rank != 1 {
			t.Fatalf("%s did not rank the first item: %+v", board.ID, page.Items[0])
		}
	}
}

func TestDuanjuRankingBoardIdentifiersAreUnique(t *testing.T) {
	seen := map[string]bool{}
	for _, board := range rankingBoards {
		if seen[board.ID] {
			t.Fatalf("duplicate ranking board id %q", board.ID)
		}
		seen[board.ID] = true
		if board.ID == "" || board.Source == "" || board.Name == "" {
			t.Fatalf("incomplete ranking board %+v", board)
		}
	}
}

func duanjuRankingRequestMatches(board rankingBoard, requested string) bool {
	if board.path == "" {
		return true
	}
	for _, form := range []string{board.path, url.QueryEscape(board.path), url.PathEscape(board.path)} {
		if strings.Contains(requested, form) {
			return true
		}
	}
	return false
}

func duanjuValidCategory(source, category string) bool {
	if static, found := duanjuStaticCategories[source]; found {
		for _, entry := range static {
			if entry.ID == category {
				return true
			}
		}
		return false
	}
	return true
}

func duanjuRankingFixture(source string) string {
	switch source {
	case sourceHuaguo:
		return `<html><body><div class="module-item"><a href="/detail/9001.html" title="网页剧"><span class="pic-text">第2集</span></a></div></body></html>`
	default:
		return `<html><body><div class="module-item"><a href="/detail/9001.html" title="网页剧"><span class="pic-text">第2集</span></a></div></body></html>`
	}
}
