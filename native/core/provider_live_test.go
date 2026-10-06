package core

import (
	"context"
	"encoding/json"
	"os"
	"strconv"
	"strings"
	"testing"
	"time"
)

func TestLiveProviderCatalogRankingDetailAndPlaybackSmoke(t *testing.T) {
	if os.Getenv("CHECK_LIVE_PROVIDERS") != "true" {
		t.Skip("set CHECK_LIVE_PROVIDERS=true to touch live provider text APIs")
	}
	engine, err := newNativeEngine(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(engine.downloads.close)
	ctx, cancel := context.WithTimeout(context.Background(), 4*time.Minute)
	defer cancel()
	for _, scenario := range []struct {
		source string
		board  string
	}{
		{source: sourceHuangju, board: "huangju-hot"},
		{source: sourceYeguo, board: "yeguo-recommend"},
		{source: sourceDSD, board: "dsd-catalog"},
	} {
		t.Run(scenario.source, func(t *testing.T) {
			dramas, more, err := fetchLiveCatalogPage(ctx, engine.downloader, scenario.source)
			if err != nil || len(dramas) == 0 {
				t.Fatalf("catalog failed: count=%d more=%t err=%v", len(dramas), more, err)
			}
			board, found := findRankingBoard(scenario.board)
			if !found {
				t.Fatal("ranking board missing")
			}
			ranking, err := engine.downloader.loadRankingPage(ctx, board, 1, true)
			if err != nil || len(ranking.Items) == 0 {
				t.Fatalf("ranking failed: count=%d err=%v", len(ranking.Items), err)
			}
			var lastErr error
			for index, drama := range dramas {
				if index >= 8 {
					break
				}
				raw, chapters, err := fetchLiveDetail(ctx, engine.downloader, scenario.source, drama.SourceID)
				if err != nil {
					lastErr = err
					continue
				}
				if raw.ID != drama.ID || len(chapters) == 0 {
					lastErr = err
					continue
				}
				for chapterIndex, chapter := range chapters {
					if chapterIndex >= 4 {
						break
					}
					media, err := engine.downloader.resolveProviderMedia(ctx, Task{DramaID: raw.ID, DramaTitle: raw.DisplayTitle(), Chapter: chapter, Index: chapterIndex + 1})
					if err != nil {
						lastErr = err
						continue
					}
					choice := nativePlaybackChoices(media, 0)
					if len(choice.media) == 0 {
						lastErr = err
						continue
					}
					plan, err := engine.nativeOpenPlayback(ctx, choice)
					if err != nil {
						lastErr = err
						continue
					}
					engine.nativeReleasePlayback(plan.Session)
					if !strings.HasPrefix(plan.URL, "http://127.0.0.1:") || plan.RouteCount < 1 {
						t.Fatalf("playback plan did not use local stream route: %+v", plan)
					}
					t.Logf("%s live smoke ok: catalog=%d ranking=%d detail=%s chapters=%d routes=%d quality=%d", scenario.source, len(dramas), len(ranking.Items), raw.ID, len(chapters), plan.RouteCount, plan.Quality)
					return
				}
			}
			t.Fatalf("could not resolve a playable %s episode; last error: %v", scenario.source, lastErr)
		})
	}
}

func fetchLiveCatalogPage(ctx context.Context, d *Downloader, source string) ([]Drama, bool, error) {
	switch source {
	case sourceHuangju:
		return d.fetchHuangjuCatalogPage(ctx, 1, "", "")
	case sourceYeguo:
		return d.fetchYeguoCatalogPage(ctx, 1, "", "")
	case sourceDSD:
		return d.fetchDSDCatalogPage(ctx, 1, "", "")
	default:
		return nil, false, errNativeBuildSource
	}
}

func TestLiveChaoguoCatalogSearchRankingAndDetail(t *testing.T) {
	if os.Getenv("CHECK_LIVE_PROVIDERS") != "true" {
		t.Skip("set CHECK_LIVE_PROVIDERS=true to touch live provider text APIs")
	}
	engine, err := newNativeEngine(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(engine.downloads.close)
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Minute)
	defer cancel()
	d := engine.downloader

	first, more, err := d.fetchChaoguoCatalogPage(ctx, 1, "class:mainstream")
	if err != nil || len(first) == 0 {
		t.Fatalf("chaoguo catalog failed: count=%d more=%t err=%v", len(first), more, err)
	}
	second, _, err := d.fetchChaoguoCatalogPage(ctx, 2, "class:mainstream")
	if err != nil || len(second) == 0 {
		t.Fatalf("chaoguo second page failed: count=%d err=%v", len(second), err)
	}
	seen := map[string]bool{}
	for _, drama := range append(append([]Drama{}, first...), second...) {
		if drama.ID == "" || drama.Source != sourceChaoguo || drama.Title == "" {
			t.Fatalf("chaoguo catalog item is incomplete: %+v", drama)
		}
		if seen[drama.ID] {
			t.Fatalf("chaoguo paging repeated %s", drama.ID)
		}
		seen[drama.ID] = true
	}

	results, _, err := d.searchChaoguoPage(ctx, "长生", 1)
	if err != nil || len(results) == 0 {
		t.Fatalf("chaoguo search failed: count=%d err=%v", len(results), err)
	}

	for _, id := range []string{"chaoguo-hot", "chaoguo-urban"} {
		board, found := findRankingBoard(id)
		if !found {
			t.Fatalf("chaoguo board %s is missing", id)
		}
		page, err := d.loadRankingPage(ctx, board, 1, true)
		if err != nil || len(page.Items) == 0 {
			t.Fatalf("chaoguo ranking %s failed: count=%d err=%v", id, len(page.Items), err)
		}
		for _, item := range page.Items {
			if item.Drama.ID == "" || item.Drama.Source != sourceChaoguo || item.Drama.Cover != nil {
				t.Fatalf("chaoguo ranking %s item is wrong: %+v", id, item.Drama)
			}
		}
	}

	drama, chapters, err := d.fetchChaoguoDetail(ctx, first[0].SourceID)
	if err != nil || len(chapters) == 0 {
		t.Fatalf("chaoguo detail failed: chapters=%d err=%v", len(chapters), err)
	}
	if drama.Title == "" || drama.EpisodeCount != json.Number(strconv.Itoa(len(chapters))) {
		t.Fatalf("chaoguo detail metadata is wrong: %+v", drama)
	}
	for _, chapter := range chapters {
		if !duanjuLooksLikeMedia(chapter.VideoURL) || chapter.Referer == "" {
			t.Fatalf("chaoguo chapter is not directly playable: %+v", chapter)
		}
	}
	t.Logf("chaoguo live ok: catalog=%d+%d search=%d hot=%d detail=%s chapters=%d",
		len(first), len(second), len(results), 50, drama.ID, len(chapters))
}

func fetchLiveDetail(ctx context.Context, d *Downloader, source, sourceID string) (Drama, []Chapter, error) {
	switch source {
	case sourceHuangju:
		return d.fetchHuangjuDetail(ctx, sourceID)
	case sourceYeguo:
		return d.fetchYeguoDetail(ctx, sourceID)
	case sourceDSD:
		return d.fetchDSDDetail(ctx, sourceID)
	default:
		return Drama{}, nil, errNativeBuildSource
	}
}
