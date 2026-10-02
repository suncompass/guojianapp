package core

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"path"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"
)

const (
	nativeMediaSniffBytes = 256 << 10
	nativePlaylistBytes   = 4 << 20
)

type nativeStreamAsset struct {
	address     string
	fallbacks   []string
	data        []byte
	contentType string
	total       int64
	etag        string
	modified    string
}

type nativeStreamSession struct {
	credentials *providerMediaCredentials
	mu          sync.Mutex
	assets      map[string]nativeStreamAsset
	referer     string
	key         []byte
	ctx         context.Context
	cancel      context.CancelFunc
	lastUsed    time.Time
	preferred   string
}

type nativeStreamServer struct {
	mu         sync.Mutex
	downloader *Downloader
	address    string
	sessions   map[string]*nativeStreamSession
	server     *http.Server
}

func (stream *nativeStreamServer) nativeRequest(request *http.Request) (*http.Response, error) {
	client := *stream.downloader.client
	client.Timeout = 0
	return stream.downloader.doMediaRequestWithClient(request, &client)
}

var nativePlaylistURI = regexp.MustCompile(`URI="([^"]+)"`)

func nativePlaylistPrefix(data []byte) bool {
	return bytes.HasPrefix(bytes.TrimSpace(bytes.TrimPrefix(data, []byte("\ufeff"))), []byte("#EXTM3U"))
}

func nativeMediaEdgeHost(raw string) string {
	address, err := url.Parse(raw)
	if err != nil {
		return ""
	}
	labels := strings.Split(strings.ToLower(address.Hostname()), ".")
	if len(labels) < 3 || !strings.HasPrefix(labels[0], "tp") {
		return ""
	}
	index, err := strconv.Atoi(strings.TrimPrefix(labels[0], "tp"))
	if err != nil || index < 1 || index > 8 {
		return ""
	}
	return strings.Join(labels, ".")
}

func nativeMediaURLFallbacks(raw string) []string {
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
	order := []int{1, 4, 7, 8, 2, 3, 5, 6}
	port := ""
	if value := address.Port(); value != "" {
		port = ":" + value
	}
	suffix := strings.Join(labels[1:], ".")
	seen := map[string]bool{address.String(): true}
	result := make([]string, 0, len(order)-1)
	for _, index := range order {
		if index == current {
			continue
		}
		candidate := *address
		candidate.Host = "tp" + strconv.Itoa(index) + "." + suffix + port
		value := candidate.String()
		if !seen[value] {
			seen[value] = true
			result = append(result, value)
		}
	}
	return result
}

func nativeStreamCandidates(asset nativeStreamAsset, preferred string) []string {
	candidates := append([]string{asset.address}, asset.fallbacks...)
	if preferred == "" {
		return candidates
	}
	for index, candidate := range candidates {
		if nativeMediaEdgeHost(candidate) != preferred {
			continue
		}
		if index == 0 {
			return candidates
		}
		return append([]string{candidate}, append(candidates[:index], candidates[index+1:]...)...)
	}
	return candidates
}

func nativeStreamAttempts(raw string, retries int) int {
	if nativeMediaEdgeHost(raw) != "" {
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

func newNativeStreamServer(d *Downloader) (*nativeStreamServer, error) {
	listener, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		return nil, errors.New("无法初始化本机播放器")
	}
	stream := &nativeStreamServer{downloader: d, address: "http://" + listener.Addr().String(), sessions: map[string]*nativeStreamSession{}}
	server := &http.Server{Handler: http.HandlerFunc(stream.nativeServe), ReadHeaderTimeout: 5 * time.Second, IdleTimeout: 30 * time.Second, MaxHeaderBytes: 16384}
	stream.server = server
	go func() { _ = server.Serve(listener) }()
	return stream, nil
}

func (stream *nativeStreamServer) nativeOpen(media providerMedia) (string, string) {
	tokenBytes := make([]byte, 24)
	if _, err := rand.Read(tokenBytes); err != nil {
		panic(err)
	}
	token := hex.EncodeToString(tokenBytes)
	ctx, cancel := context.WithCancel(providerMediaContext(context.Background(), media.credentials))
	session := &nativeStreamSession{assets: map[string]nativeStreamAsset{}, referer: media.Referer, key: media.HLSKey, ctx: ctx, cancel: cancel, lastUsed: time.Now(), credentials: media.credentials}
	stream.mu.Lock()
	for id, old := range stream.sessions {
		if time.Since(old.lastUsed) > 10*time.Minute {
			old.cancel()
			delete(stream.sessions, id)
		}
	}
	if len(stream.sessions) >= 8 {
		oldest := ""
		for id, old := range stream.sessions {
			if oldest == "" || old.lastUsed.Before(stream.sessions[oldest].lastUsed) {
				oldest = id
			}
		}
		stream.sessions[oldest].cancel()
		delete(stream.sessions, oldest)
	}
	stream.sessions[token] = session
	stream.mu.Unlock()
	entry := nativeStreamAsset{address: media.URL, contentType: "video/mp4"}
	if parsed, err := url.Parse(media.URL); err == nil && strings.HasSuffix(strings.ToLower(parsed.Path), ".m3u8") {
		entry.contentType = "application/vnd.apple.mpegurl"
	}
	entry.fallbacks = nativeMediaURLFallbacks(media.URL)
	if media.Playlist != "" {
		entry.data = []byte(media.Playlist)
		entry.contentType = "application/vnd.apple.mpegurl"
	}
	return stream.nativeAsset(token, session, entry), token
}

func (stream *nativeStreamServer) nativeRelease(token string) {
	stream.mu.Lock()
	if session := stream.sessions[token]; session != nil {
		session.cancel()
		delete(stream.sessions, token)
	}
	stream.mu.Unlock()
}

func (stream *nativeStreamServer) nativeAsset(token string, session *nativeStreamSession, asset nativeStreamAsset) string {
	digest := sha256.Sum256([]byte(asset.address + "\x00" + asset.contentType))
	extension := ".ts"
	if parsed, err := url.Parse(asset.address); err == nil {
		switch candidate := strings.ToLower(path.Ext(parsed.Path)); candidate {
		case ".m3u8", ".ts", ".m4s", ".mp4", ".aac", ".m4a", ".mp3", ".vtt", ".webvtt", ".key":
			extension = candidate
		}
	}
	switch asset.contentType {
	case "application/vnd.apple.mpegurl":
		extension = ".m3u8"
	case "application/octet-stream":
		extension = ".key"
	case "video/mp4":
		extension = ".mp4"
	}
	id := hex.EncodeToString(digest[:12]) + extension
	session.mu.Lock()
	if previous, found := session.assets[id]; !found || len(previous.data) == 0 || len(asset.data) > 0 {
		session.assets[id] = asset
	}
	session.mu.Unlock()
	return stream.address + "/" + token + "/" + id
}

func (stream *nativeStreamServer) nativeRewrite(token string, session *nativeStreamSession, body, base string) (string, error) {
	var output []string
	nextPlaylist := false
	for _, line := range strings.Split(strings.ReplaceAll(body, "\r\n", "\n"), "\n") {
		text := strings.TrimSpace(line)
		rewrite := func(reference string, key bool, contentType string) string {
			if strings.HasPrefix(reference, "data:") {
				return reference
			}
			parsed, err := url.Parse(base)
			if err != nil {
				return ""
			}
			relative, err := url.Parse(reference)
			if err != nil {
				return ""
			}
			address := parsed.ResolveReference(relative).String()
			if !isProviderHTTPMediaURL(address) {
				return ""
			}
			asset := nativeStreamAsset{address: address, fallbacks: nativeMediaURLFallbacks(address), contentType: contentType}
			if key && len(session.key) == 16 {
				asset.data = append([]byte{}, session.key...)
				asset.contentType = "application/octet-stream"
			}
			return stream.nativeAsset(token, session, asset)
		}
		if text != "" && !strings.HasPrefix(text, "#") {
			contentType := ""
			if nextPlaylist {
				contentType = "application/vnd.apple.mpegurl"
			}
			line = rewrite(text, false, contentType)
			nextPlaylist = false
			if line == "" {
				return "", errors.New("播放列表中的媒体地址无效")
			}
		} else if strings.Contains(text, "URI=") {
			invalid := false
			line = nativePlaylistURI.ReplaceAllStringFunc(line, func(match string) string {
				reference := nativePlaylistURI.FindStringSubmatch(match)[1]
				key := strings.HasPrefix(text, "#EXT-X-KEY:") || strings.HasPrefix(text, "#EXT-X-SESSION-KEY:")
				contentType := ""
				switch {
				case key:
					contentType = "application/octet-stream"
				case strings.HasPrefix(text, "#EXT-X-MAP:"):
					contentType = "video/mp4"
				case strings.HasPrefix(text, "#EXT-X-MEDIA:"), strings.HasPrefix(text, "#EXT-X-I-FRAME-STREAM-INF:"), strings.HasPrefix(text, "#EXT-X-RENDITION-REPORT:"):
					contentType = "application/vnd.apple.mpegurl"
				}
				updated := rewrite(reference, key, contentType)
				if updated == "" {
					invalid = true
				}
				return "URI=\"" + updated + "\""
			})
			if invalid {
				return "", errors.New("播放列表中的附属地址无效")
			}
		}
		if strings.HasPrefix(text, "#EXT-X-STREAM-INF:") {
			nextPlaylist = true
		}
		output = append(output, line)
	}
	return strings.Join(output, "\n"), nil
}

func (stream *nativeStreamServer) nativeServe(writer http.ResponseWriter, request *http.Request) {
	if request.Method != http.MethodGet && request.Method != http.MethodHead {
		writer.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	parts := strings.Split(strings.Trim(request.URL.Path, "/"), "/")
	if len(parts) != 2 {
		http.NotFound(writer, request)
		return
	}
	stream.mu.Lock()
	session := stream.sessions[parts[0]]
	if session != nil {
		session.lastUsed = time.Now()
	}
	stream.mu.Unlock()
	if session == nil {
		http.Error(writer, "播放已结束", http.StatusGone)
		return
	}
	session.mu.Lock()
	asset, found := session.assets[parts[1]]
	session.mu.Unlock()
	if !found {
		http.NotFound(writer, request)
		return
	}
	ctx, cancel := context.WithCancel(providerMediaContext(request.Context(), session.credentials))
	defer cancel()
	stop := context.AfterFunc(session.ctx, cancel)
	defer stop()
	writer.Header().Set("Cache-Control", "no-store")
	if len(asset.data) > 0 && asset.total > int64(len(asset.data)) {
		if stream.nativeServePrefix(ctx, writer, request, session, asset) {
			return
		}
		session.invalidate(asset.address)
		asset.data = nil
	}
	if len(asset.data) > 0 {
		if strings.Contains(asset.contentType, "mpegurl") {
			body, err := stream.nativeRewrite(parts[0], session, string(asset.data), asset.address)
			if err != nil {
				http.Error(writer, err.Error(), http.StatusBadGateway)
				return
			}
			writer.Header().Set("Content-Type", "application/vnd.apple.mpegurl")
			if request.Method == http.MethodGet {
				_, _ = io.WriteString(writer, body)
			}
		} else {
			writer.Header().Set("Content-Type", asset.contentType)
			if asset.etag != "" {
				writer.Header().Set("ETag", asset.etag)
			}
			http.ServeContent(writer, request, parts[1], time.Time{}, bytes.NewReader(asset.data))
		}
		return
	}
	session.mu.Lock()
	preferred := session.preferred
	session.mu.Unlock()
	candidates := nativeStreamCandidates(asset, preferred)
	var upstream *http.Request
	var response *http.Response
	var err error
	var lastErr error
	attempted := make([]string, 0, len(candidates))
	for _, address := range candidates {
		attempted = append(attempted, address)
		method := request.Method
		playlistAsset := strings.Contains(strings.ToLower(asset.contentType), "mpegurl")
		if playlistAsset {
			method = http.MethodGet
		}
		upstream, err = http.NewRequestWithContext(ctx, method, address, nil)
		if err != nil {
			lastErr = err
			continue
		}
		upstream.Header.Set("User-Agent", userAgent)
		upstream.Header.Set("Referer", session.referer)
		upstream.Header.Set("Accept-Encoding", "identity")
		if !playlistAsset {
			for _, name := range []string{"Range", "If-Range"} {
				if value := request.Header.Get(name); value != "" {
					upstream.Header.Set(name, value)
				}
			}
		}
		attempts := nativeStreamAttempts(address, stream.downloader.cfg.Retries)
		for attempt := 0; attempt < attempts; attempt++ {
			if attempt > 0 {
				timer := time.NewTimer(time.Duration(attempt) * 250 * time.Millisecond)
				select {
				case <-timer.C:
				case <-ctx.Done():
					timer.Stop()
					lastErr = ctx.Err()
					break
				}
			}
			if ctx.Err() != nil {
				lastErr = ctx.Err()
				break
			}
			response, err = stream.nativeRequest(upstream.Clone(ctx))
			if err == nil {
				break
			}
			lastErr = err
		}
		if response == nil {
			continue
		}
		if response.StatusCode < http.StatusOK || response.StatusCode >= http.StatusMultipleChoices {
			lastErr = fmt.Errorf("HTTP %d", response.StatusCode)
			_ = response.Body.Close()
			response = nil
			if lastErr != nil && response == nil && ctx.Err() != nil {
				break
			}
			continue
		}
		playlist := playlistAsset || strings.Contains(strings.ToLower(response.Header.Get("Content-Type")), "mpegurl") ||
			strings.HasSuffix(strings.ToLower(upstream.URL.Path), ".m3u8")
		var buffered []byte
		bufferedComplete := false
		if !playlist && request.Method == http.MethodGet && path.Ext(upstream.URL.Path) == "" {
			buffered, err = io.ReadAll(io.LimitReader(response.Body, nativeMediaSniffBytes+1))
			if err != nil {
				_ = response.Body.Close()
				lastErr = errors.New("媒体读取失败")
				response = nil
				continue
			}
			switch {
			case len(buffered) > nativeMediaSniffBytes && !nativePlaylistPrefix(buffered):
				playlist, bufferedComplete = false, false
			case len(buffered) > nativeMediaSniffBytes:
				rest, readErr := io.ReadAll(io.LimitReader(response.Body, nativePlaylistBytes+1-int64(len(buffered))))
				_ = response.Body.Close()
				if readErr != nil || int64(len(buffered)+len(rest)) > nativePlaylistBytes {
					lastErr = errors.New("播放列表读取失败")
					response = nil
					continue
				}
				buffered = append(buffered, rest...)
				playlist, bufferedComplete = true, true
			default:
				_ = response.Body.Close()
				playlist, bufferedComplete = nativePlaylistPrefix(buffered), true
			}
		}
		if playlist && request.Method == http.MethodGet {
			body := buffered
			var readErr error
			if body == nil {
				body, readErr = io.ReadAll(io.LimitReader(response.Body, nativePlaylistBytes+1))
				_ = response.Body.Close()
			}
			if readErr != nil || int64(len(body)) > nativePlaylistBytes {
				lastErr = errors.New("播放列表读取失败")
				response = nil
				continue
			}
			text := strings.TrimSpace(strings.TrimPrefix(string(body), "\ufeff"))
			if !strings.HasPrefix(text, "#EXTM3U") {
				lastErr = errors.New("播放列表无效")
				response = nil
				continue
			}
			finalURL := upstream.URL
			if response.Request != nil && response.Request.URL != nil {
				finalURL = response.Request.URL
			}
			rewritten, rewriteErr := stream.nativeRewrite(parts[0], session, text, finalURL.String())
			if rewriteErr != nil {
				lastErr = rewriteErr
				response = nil
				continue
			}
			session.mu.Lock()
			session.preferred = nativeMediaEdgeHost(address)
			session.mu.Unlock()
			writer.Header().Set("Content-Type", "application/vnd.apple.mpegurl")
			_, _ = io.WriteString(writer, rewritten)
			return
		}
		session.mu.Lock()
		session.preferred = nativeMediaEdgeHost(address)
		session.mu.Unlock()
		if playlist {
			_ = response.Body.Close()
			writer.Header().Set("Content-Type", "application/vnd.apple.mpegurl")
			writer.WriteHeader(http.StatusOK)
			return
		}
		if buffered != nil && bufferedComplete {
			writer.Header().Set("Content-Type", response.Header.Get("Content-Type"))
			writer.Header().Set("Content-Length", fmt.Sprintf("%d", len(buffered)))
			writer.WriteHeader(response.StatusCode)
			_, _ = writer.Write(buffered)
			return
		}
		defer response.Body.Close()
		for _, name := range []string{"Content-Type", "Content-Length", "Content-Range", "Accept-Ranges", "ETag", "Last-Modified"} {
			if value := response.Header.Get(name); value != "" {
				writer.Header().Set(name, value)
			}
		}
		writer.WriteHeader(response.StatusCode)
		if request.Method == http.MethodGet {
			if len(buffered) > 0 {
				if _, err := writer.Write(buffered); err != nil {
					return
				}
			}
			_, _ = io.Copy(writer, response.Body)
		}
		return
	}
	if response == nil || upstream == nil {
		if stream.downloader != nil {
			stream.downloader.recordDiagnostic(diagnosticEvent{
				Event:   "media.failed",
				Host:    nativeMediaEdgeHost(asset.address),
				Message: fmt.Sprintf("已尝试 %d 条媒体线路：%v", len(attempted), lastErr),
			})
		}
		http.Error(writer, "读取媒体失败，请重试", http.StatusBadGateway)
		return
	}
	if response.Body != nil {
		_ = response.Body.Close()
	}
	http.Error(writer, "读取媒体失败，请重试", http.StatusBadGateway)
}
