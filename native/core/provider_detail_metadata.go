package core

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"strconv"
	"strings"
)

func parseHongguoSortDetail(body, id string) (Drama, error) {
	row := nestedMap(routerLoaderMap(parseRouterData(body), "detail_page", "detail_"), "seriesDetail")
	if mapString(row, "series_id", "series_id_str") != id || mapString(row, "series_name", "series_title") == "" {
		return Drama{}, errors.New("红果网页详情与请求剧集不符")
	}
	patch := hongguoDramaFromAny(row, "")
	patch.Title = mapString(row, "series_name", "series_title")
	patch.Name = patch.Title
	patch.OnlineDate = providerTimestampDate(mapString(row, "first_visible_time"))
	if cover := hongguoCoverAddress(mapString(row, "series_cover", "cover")); cover != "" {
		patch.Cover, patch.CoverURL = cover, cover
	}
	return patch, nil
}

func parseHuangguoSortDetail(body, pageURL string, patch Drama) (Drama, error) {
	type entry struct {
		Type      string `json:"@type"`
		ID        string `json:"@id"`
		URL       string `json:"url"`
		Name      string `json:"name"`
		Published string `json:"datePublished"`
		Uploaded  string `json:"uploadDate"`
		Image     any    `json:"image"`
		Thumbnail any    `json:"thumbnailUrl"`
	}
	expected, _ := url.Parse(pageURL)
	matched := false
	playerTitle := false
	playerCover := false
	if patch.Source == sourceHuangguoAI {
		if data, ok := parseAIVideoInitialDataMap(body); ok {
			actualID := cleanID(mapString(data, "id", "videoId", "video_id"))
			expectedID := cleanID(firstNonEmpty(patch.SourceID, detailIDFromString(pageURL)))
			if actualID != "" && actualID == expectedID {
				matched = true
				if title := firstNonEmpty(mapString(data, "title", "name", "videoTitle", "video_title"), patch.Title); title != "" && !huangguoTitleNeedsRepair(title, patch.SourceID) {
					patch.Title = title
					patch.Name = title
					playerTitle = true
				}
				for _, key := range []string{"coverSrc", "posterSrc", "coverUrl", "posterUrl", "cover", "poster"} {
					if address := huangguoArtworkAddress(data[key], pageURL, body); address != "" {
						patch.Cover, patch.CoverURL = address, address
						playerCover = true
						break
					}
				}
				for _, key := range []string{"episodeCount", "episode_count", "totalEpisode", "total_episode", "totalEpisodes", "episodes"} {
					if count, err := strconv.Atoi(mapString(data, key)); err == nil && count > 0 {
						patch.TotalEpisode, patch.EpisodeCount = count, count
						break
					}
				}
			}
		}
		if data := parseHuangguoAIHistoryMap(body); data != nil {
			actualID := cleanID(mapString(data, "id", "videoId", "video_id"))
			expectedID := cleanID(firstNonEmpty(patch.SourceID, detailIDFromString(pageURL)))
			if actualID != "" && actualID == expectedID {
				matched = true
				if title := firstNonEmpty(mapString(data, "title", "name"), patch.Title); !playerTitle && title != "" && !huangguoTitleNeedsRepair(title, patch.SourceID) {
					patch.Title = title
					patch.Name = title
				}
				if !playerCover && nativeNormalize(patch).Cover == "" {
					if address := huangguoArtworkAddress(firstNonEmpty(mapString(data, "cover"), mapString(data, "coverSrc"), mapString(data, "posterSrc")), pageURL, body); address != "" {
						patch.Cover, patch.CoverURL = address, address
					}
				}
				for _, key := range []string{"total", "episode", "episodes", "episodeCount", "episode_count"} {
					if count := episodeIndex(mapString(data, key), 0); count > 0 {
						patch.TotalEpisode, patch.EpisodeCount = count, count
						break
					}
				}
			}
		}
	}
	for _, block := range rankingJSONLD.FindAllStringSubmatch(body, -1) {
		var graph struct {
			Graph []entry `json:"@graph"`
			entry
		}
		if json.Unmarshal([]byte(block[1]), &graph) != nil {
			continue
		}
		for _, row := range append(graph.Graph, graph.entry) {
			if row.Type != "WebPage" && row.Type != "VideoObject" && row.Type != "TVSeries" && row.Type != "Movie" {
				continue
			}
			actual, err := url.Parse(firstNonEmpty(row.URL, row.ID))
			if err != nil || !huangguoSortDetailIdentityMatches(actual, expected, patch) || row.Name == "" || patch.Source == sourceHuangguoAI && huangguoTitleNeedsRepair(row.Name, patch.SourceID) {
				continue
			}
			matched = true
			if !playerTitle {
				patch.Title = row.Name
				patch.Name = row.Name
			}
			if !playerCover {
				if address := firstNonEmpty(providerCoverAddress(row.Image, pageURL), providerCoverAddress(row.Thumbnail, pageURL)); address != "" {
					patch.Cover, patch.CoverURL = address, address
				}
			} else if nativeNormalize(patch).Cover == "" {
				if address := firstNonEmpty(providerCoverAddress(row.Image, pageURL), providerCoverAddress(row.Thumbnail, pageURL)); address != "" {
					patch.Cover, patch.CoverURL = address, address
				}
			}
			if date := providerReleaseDate(firstNonEmpty(row.Uploaded, row.Published)); date != "" && (patch.OnlineDate == "" || row.Type == "VideoObject") {
				patch.OnlineDate = date
			}
		}
	}
	if !matched {
		return patch, fmt.Errorf("黄果详情没有返回所请求剧集的元数据")
	}
	if nativeNormalize(patch).Cover == "" {
		for _, tag := range coverMetaTag.FindAllString(body, -1) {
			if strings.ToLower(extractAttr(tag, "property", "name")) == "og:image" {
				if address := providerCoverAddress(extractAttr(tag, "content"), pageURL); address != "" {
					patch.Cover, patch.CoverURL = address, address
					break
				}
			}
		}
	}
	markup := huangguoNonContent.ReplaceAllString(body, "")
	metaBlock := huangguoClassBlock(markup, "hg-web-detail__meta")
	meta := cleanText(metaBlock)
	patch.Views = normalizeViews(firstMatchText(reViewsText, meta))
	if patch.OnlineDate == "" && strings.Contains(meta, "上线") {
		patch.OnlineDate = providerReleaseDate(firstMatchText(reDateText, meta))
	}
	if patch.Source == sourceHuangguoAI {
		episode := firstNonEmpty(extractAttr(metaBlock, "data-ep-base"), meta)
		if count := episodeIndex(episode, 0); count > 0 {
			patch.TotalEpisode, patch.EpisodeCount = count, count
		}
		if count := episodeIndex(extractDescription(body), 0); count > 0 && valueEmpty(patch.TotalEpisode) {
			patch.TotalEpisode, patch.EpisodeCount = count, count
		}
	}
	return patch, nil
}

func huangguoSortDetailIdentityMatches(actual, expected *url.URL, patch Drama) bool {
	if actual == nil || expected == nil {
		return false
	}
	if actual.Host != "" && !strings.EqualFold(actual.Host, expected.Host) && providerSourceForURL(actual.String()) != patch.Source {
		return false
	}
	if patch.Source == sourceHuangguoAI {
		expectedID := firstNonEmpty(patch.SourceID, detailIDFromString(expected.String()))
		return detailIDFromString(actual.String()) == expectedID
	}
	return strings.TrimRight(actual.Path, "/") == strings.TrimRight(expected.Path, "/")
}

func huangguoDetailMetadata(body, pageURL, source, sourceID string) Drama {
	drama := Drama{ID: providerDramaID(source, sourceID), Source: source, SourceID: sourceID,
		Title: firstNonEmpty(extractPageTitle(body), "短剧"), Desc: extractDescription(body), Tags: extractTags(body)}
	if patch, err := parseHuangguoSortDetail(body, pageURL, drama); err == nil {
		drama = patch
	}
	drama.Name, drama.Intro = drama.Title, drama.Desc
	meta := cleanText(huangguoClassBlock(huangguoNonContent.ReplaceAllString(body, ""), "hg-web-detail__meta"))
	drama.ReleaseStatus = releaseStatusFromRemark(meta)
	return drama
}
