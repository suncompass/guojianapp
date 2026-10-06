package core

import (
	"context"
	"errors"
	"html"
	"net/http"
	"net/url"
	"regexp"
	"strings"
)

var coverMetaTag = regexp.MustCompile(`(?is)<meta\b[^>]*>`)
var huangguoCDNDomain = regexp.MustCompile(`(?is)(?:["']?cdnDomain["']?)\s*[:=]\s*["']([^"']+)["']`)

func (d *Downloader) nativeCoverAddress(ctx context.Context, drama nativeDrama) (string, error) {
	source, id, valid := splitProviderDramaID(drama.ID)
	if !valid {
		return "", errors.New("无效的剧集 ID")
	}
	switch source {
	case sourceHongguo:
		if !hongguoNumericID.MatchString(id) {
			return "", errors.New("无效的红果剧集 ID")
		}
		result, err := d.hongguoAppRequest(ctx, http.MethodPost, "/novel/player/video_detail/v1/", nil, map[string]any{"series_id": id})
		if err != nil {
			return "", err
		}
		row := nestedMap(result, "data", "video_data")
		if mapString(row, "series_id_str", "series_id") != id {
			return "", errors.New("红果详情与请求剧集不符")
		}
		return hongguoCoverAddress(mapString(row, "series_cover", "cover")), nil
	}
	return "", errors.New("该站源暂无封面补齐接口")
}

func providerCoverAddress(value any, pageURL string) string {
	switch item := value.(type) {
	case []any:
		for _, value := range item {
			if address := providerCoverAddress(value, pageURL); address != "" {
				return address
			}
		}
	case map[string]any:
		for _, key := range []string{"url", "contentUrl", "thumbnailUrl"} {
			if address := providerCoverAddress(item[key], pageURL); address != "" {
				return address
			}
		}
	case string:
		if strings.TrimSpace(item) == "" {
			return ""
		}
		address, err := url.Parse(strings.TrimSpace(item))
		if err != nil {
			return ""
		}
		if base, err := url.Parse(pageURL); err == nil && base.IsAbs() {
			address = base.ResolveReference(address)
		}
		if validNativeCoverURL(address) {
			return address.String()
		}
	}
	return ""
}

func huangguoCDNBaseURL(rawHTML string) string {
	match := huangguoCDNDomain.FindStringSubmatch(rawHTML)
	if len(match) < 2 {
		return ""
	}
	raw := strings.TrimSpace(html.UnescapeString(strings.ReplaceAll(match[1], `\/`, `/`)))
	if raw == "" {
		return ""
	}
	if strings.HasPrefix(raw, "//") {
		raw = "https:" + raw
	} else if !strings.Contains(raw, "://") {
		raw = "https://" + strings.TrimLeft(raw, "/")
	}
	address, err := url.Parse(raw)
	if err != nil || !validNativeCoverURL(address) {
		return ""
	}
	address.Path = ""
	address.RawQuery = ""
	address.Fragment = ""
	return strings.TrimRight(address.String(), "/") + "/"
}

func huangguoArtworkAddress(value any, pageURL, rawHTML string) string {
	switch item := value.(type) {
	case []any:
		for _, value := range item {
			if address := huangguoArtworkAddress(value, pageURL, rawHTML); address != "" {
				return address
			}
		}
	case map[string]any:
		for _, key := range []string{"url", "src", "path", "cover", "coverUrl", "cover_url", "image", "pic", "poster", "thumbnailUrl"} {
			if address := huangguoArtworkAddress(item[key], pageURL, rawHTML); address != "" {
				return address
			}
		}
	case string:
		raw := strings.TrimSpace(html.UnescapeString(strings.ReplaceAll(item, `\/`, `/`)))
		if raw == "" {
			return ""
		}
		address, err := url.Parse(raw)
		if err != nil {
			return ""
		}
		if address.IsAbs() || strings.HasPrefix(raw, "//") {
			return providerCoverAddress(raw, pageURL)
		}
		if base := huangguoCDNBaseURL(rawHTML); base != "" {
			if resolved := providerCoverAddress(raw, base); resolved != "" {
				return resolved
			}
		}
		return providerCoverAddress(raw, pageURL)
	}
	return ""
}

func hongguoCoverAddress(values ...string) string {
	for _, value := range values {
		value = strings.TrimSpace(value)
		if value == "" || len(value) > 8192 {
			continue
		}
		if strings.HasPrefix(value, "//") {
			value = "https:" + value
		}
		parsed, err := url.Parse(value)
		if err == nil && validNativeCoverURL(parsed) {
			return value
		}
	}
	return ""
}
