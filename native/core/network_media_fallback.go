package core

import (
	"context"
	"errors"
	"net/url"
	"strconv"
	"strings"
)

func mediaFallbackVariants(media providerMedia) []providerMedia {
	seen := map[string]bool{media.URL: true}
	fallbacks := make([]providerMedia, 0, len(media.Variants))
	for _, fallback := range media.Variants {
		if !isProviderHTTPMediaURL(fallback.URL) || seen[fallback.URL] || media.Quality > 0 && fallback.Quality != media.Quality {
			continue
		}
		seen[fallback.URL] = true
		if fallback.Referer == "" {
			fallback.Referer = media.Referer
		}
		if fallback.credentials == nil {
			fallback.credentials = media.credentials
		}
		if !validProviderMediaCredentials(fallback.credentials, providerMediaCredentialReserve) {
			continue
		}
		if fallback.Duration == 0 {
			fallback.Duration = media.Duration
		}
		if fallback.Quality == 0 {
			fallback.Quality = media.Quality
		}
		fallback.HLSKey = firstNonEmptyBytes(fallback.HLSKey, media.HLSKey)
		fallback.CENCKey = firstNonEmptyBytes(fallback.CENCKey, media.CENCKey)
		fallback.Variants = media.Variants
		fallbacks = append(fallbacks, fallback)
	}
	return fallbacks
}

func firstNonEmptyBytes(values ...[]byte) []byte {
	for _, value := range values {
		if len(value) > 0 {
			return value
		}
	}
	return nil
}

func mediaURLFallbacks(raw string) []string {
	address, err := url.Parse(raw)
	if err != nil {
		return nil
	}
	labels := strings.Split(strings.ToLower(address.Hostname()), ".")
	if len(labels) < 3 || !strings.HasPrefix(labels[0], "tp") {
		return nil
	}
	current, err := strconv.Atoi(strings.TrimPrefix(labels[0], "tp"))
	if err != nil || current < 1 || current > 8 {
		return nil
	}
	suffix := strings.Join(labels[1:], ".")
	port := ""
	if value := address.Port(); value != "" {
		port = ":" + value
	}
	order := []int{1, 4, 7, 8, 2, 3, 5, 6}
	seen := map[string]bool{address.String(): true}
	out := make([]string, 0, len(order)-1)
	for _, index := range order {
		if index == current {
			continue
		}
		candidate := *address
		candidate.Host = "tp" + strconv.Itoa(index) + "." + suffix + port
		value := candidate.String()
		if !seen[value] {
			seen[value] = true
			out = append(out, value)
		}
	}
	return out
}

func mediaRequestAttemptsForURL(raw string, retries int) int {
	if mediaEdgeHost(raw) != "" {
		return 1
	}
	if retries < 1 {
		return 1
	}
	if retries > 3 {
		return 3
	}
	return retries
}

func providerMediaUsesEdgeFallback(media providerMedia) bool {
	if mediaEdgeHost(media.URL) != "" {
		return true
	}
	if strings.TrimSpace(media.Playlist) == "" {
		return false
	}
	base, err := url.Parse(media.URL)
	if err != nil {
		return false
	}
	check := func(raw string) bool {
		reference, err := url.Parse(strings.TrimSpace(raw))
		return err == nil && mediaEdgeHost(base.ResolveReference(reference).String()) != ""
	}
	nextPlaylist := false
	for _, line := range strings.Split(media.Playlist, "\n") {
		trimmed := strings.TrimSpace(line)
		if trimmed == "" {
			continue
		}
		if strings.HasPrefix(trimmed, "#EXT-X-STREAM-INF:") {
			nextPlaylist = true
			continue
		}
		if !strings.HasPrefix(trimmed, "#") {
			if check(trimmed) {
				return true
			}
			nextPlaylist = false
			continue
		}
		for _, match := range nativePlaylistURI.FindAllStringSubmatch(trimmed, -1) {
			if check(match[1]) {
				return true
			}
		}
		_ = nextPlaylist
	}
	return false
}

func (d *Downloader) fetchMediaPlaylistForMedia(ctx context.Context, media providerMedia) (providerMedia, error) {
	fetch := func(candidate providerMedia) (providerMedia, error) {
		playlist, finalURL, err := d.fetchMediaPlaylist(providerMediaContext(ctx, candidate.credentials), candidate.URL, candidate.Referer)
		if err != nil {
			return providerMedia{}, err
		}
		candidate.Playlist, candidate.URL = playlist, finalURL
		if duration := m3u8Duration(playlist); duration > 0 {
			candidate.Duration = duration
		}
		return candidate, nil
	}
	selected, err := fetch(media)
	if err == nil {
		return selected, nil
	}
	failures := []error{err}
	for _, fallback := range mediaFallbackVariants(media) {
		address, parseErr := url.Parse(fallback.URL)
		if parseErr != nil || !strings.HasSuffix(strings.ToLower(address.Path), ".m3u8") {
			continue
		}
		selected, err = fetch(fallback)
		if err == nil {
			return selected, nil
		}
		failures = append(failures, err)
	}
	return providerMedia{}, errors.Join(failures...)
}
