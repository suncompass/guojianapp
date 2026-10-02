package core

import (
	"bytes"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func nativeStreamTestServer(t *testing.T) *nativeStreamServer {
	t.Helper()
	engine, err := newNativeEngine(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	stream, err := newNativeStreamServer(engine.downloader)
	if err != nil {
		t.Fatal(err)
	}
	return stream
}

func nativeStreamFetch(t *testing.T, address string) (int, []byte) {
	t.Helper()
	response, err := http.Get(address)
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	body, err := io.ReadAll(response.Body)
	if err != nil {
		t.Fatal(err)
	}
	return response.StatusCode, body
}

func TestNativeStreamServesLargeExtensionlessMedia(t *testing.T) {
	payload := make([]byte, 6<<20)
	for index := range payload {
		payload[index] = byte(index * 7)
	}
	upstream := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		writer.Header().Set("Content-Type", "video/mp4")
		writer.Header().Set("Content-Length", fmt.Sprintf("%d", len(payload)))
		_, _ = writer.Write(payload)
	}))
	defer upstream.Close()
	stream := nativeStreamTestServer(t)
	local, token := stream.nativeOpen(providerMedia{URL: upstream.URL + "/video/tos/item/", Referer: upstream.URL + "/"})
	defer stream.nativeRelease(token)
	status, body := nativeStreamFetch(t, local)
	if status != http.StatusOK || !bytes.Equal(body, payload) {
		t.Fatalf("large extensionless media mismatch: status=%d bytes=%d want=%d", status, len(body), len(payload))
	}
}

func TestNativeStreamServesRangedExtensionlessMedia(t *testing.T) {
	payload := bytes.Repeat([]byte("0123456789abcdef"), 512)
	upstream := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		writer.Header().Set("Content-Type", "video/mp4")
		writer.Header().Set("Accept-Ranges", "bytes")
		http.ServeContent(writer, request, "item.mp4", time.Unix(0, 0), bytes.NewReader(payload))
	}))
	defer upstream.Close()
	stream := nativeStreamTestServer(t)
	local, token := stream.nativeOpen(providerMedia{URL: upstream.URL + "/video/tos/item/", Referer: upstream.URL + "/"})
	defer stream.nativeRelease(token)
	request, err := http.NewRequest(http.MethodGet, local, nil)
	if err != nil {
		t.Fatal(err)
	}
	request.Header.Set("Range", "bytes=1000-1999")
	response, err := http.DefaultClient.Do(request)
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	body, err := io.ReadAll(response.Body)
	if err != nil {
		t.Fatal(err)
	}
	if response.StatusCode != http.StatusPartialContent || !bytes.Equal(body, payload[1000:2000]) {
		t.Fatalf("ranged extensionless media mismatch: status=%d bytes=%d", response.StatusCode, len(body))
	}
}

func TestNativeStreamRewritesExtensionlessPlaylist(t *testing.T) {
	segment := bytes.Repeat([]byte("segment-data"), 64)
	const template = "#EXTM3U\n#EXT-X-VERSION:3\n#EXTINF:4.0,\n%s/segments/first.ts\n#EXT-X-ENDLIST\n"
	mux := http.NewServeMux()
	mux.HandleFunc("/video/tos/list/", func(writer http.ResponseWriter, request *http.Request) {
		writer.Header().Set("Content-Type", "text/plain")
		_, _ = io.WriteString(writer, fmt.Sprintf(template, "http://"+request.Host))
	})
	mux.HandleFunc("/segments/first.ts", func(writer http.ResponseWriter, request *http.Request) {
		writer.Header().Set("Content-Type", "video/mp2t")
		_, _ = writer.Write(segment)
	})
	upstream := httptest.NewServer(mux)
	defer upstream.Close()
	stream := nativeStreamTestServer(t)
	local, token := stream.nativeOpen(providerMedia{URL: upstream.URL + "/video/tos/list/", Referer: upstream.URL + "/"})
	defer stream.nativeRelease(token)
	status, body := nativeStreamFetch(t, local)
	text := string(body)
	if status != http.StatusOK || !strings.HasPrefix(text, "#EXTM3U") || strings.Contains(text, upstream.URL+"/segments/first.ts") {
		t.Fatalf("extensionless playlist was not rewritten: status=%d %s", status, text)
	}
	reference := ""
	for _, line := range strings.Split(text, "\n") {
		if strings.HasPrefix(strings.TrimSpace(line), "http://127.0.0.1:") {
			reference = strings.TrimSpace(line)
		}
	}
	if reference == "" {
		t.Fatalf("playlist segment was not mapped locally: %s", text)
	}
	segmentStatus, segmentBody := nativeStreamFetch(t, reference)
	if segmentStatus != http.StatusOK || !bytes.Equal(segmentBody, segment) {
		t.Fatalf("segment proxy mismatch: status=%d bytes=%d", segmentStatus, len(segmentBody))
	}
}
