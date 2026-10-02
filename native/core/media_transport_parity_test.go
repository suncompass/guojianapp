package core

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"strings"
	"testing"
	"time"
)

func TestMediaCredentialsStayOnExactOrigin(t *testing.T) {
	var requests int
	d := sourceFixtureDownloader(t, func(request *http.Request) (*http.Response, error) {
		requests++
		if request.Header.Get("Sec-Fetch-Mode") != "cors" ||
			request.Header.Get("Sec-Fetch-Dest") != "empty" ||
			request.Header.Get("Referer") != "https://site.example.test/episode/1" {
			t.Error("media request lost required headers")
		}
		response := sourceFixtureResponse(request, http.StatusOK, "fixture")
		if request.URL.Host == "media.example.test" {
			if request.Header.Get("Cookie") != "Signed=fixture" {
				t.Error("credential missing on its origin")
			}
			response.StatusCode = http.StatusFound
			response.Header.Set("Location", "https://other.example.test/segment")
		} else if request.Header.Get("Cookie") != "" {
			t.Error("signed credential leaked on redirect")
		}
		return response, nil
	})
	credentials := &providerMediaCredentials{
		origin:  "https://media.example.test",
		cookie:  "Signed=fixture",
		referer: "https://site.example.test/episode/1",
		expires: time.Now().Add(time.Minute),
	}
	request, err := http.NewRequestWithContext(
		providerMediaContext(context.Background(), credentials),
		http.MethodGet,
		"https://media.example.test/segment",
		nil,
	)
	if err != nil {
		t.Fatal(err)
	}
	response, err := d.doMediaRequest(request)
	if err != nil {
		t.Fatal(err)
	}
	response.Body.Close()
	if requests != 2 || request.Header.Get("Cookie") != "" {
		t.Fatal("redirect not followed or caller request mutated")
	}
}

func TestMediaFallsBackToSameQualityBackup(t *testing.T) {
	var paths []string
	d := sourceFixtureDownloader(t, func(request *http.Request) (*http.Response, error) {
		paths = append(paths, request.URL.Path)
		switch request.URL.Path {
		case "/primary.m3u8":
			return sourceFixtureResponse(request, http.StatusServiceUnavailable, "down"), nil
		case "/backup.m3u8":
			return sourceFixtureResponse(request, http.StatusOK, "#EXTM3U\n#EXTINF:4,\nsegment.ts\n#EXT-X-ENDLIST\n"), nil
		default:
			return nil, fmt.Errorf("unexpected request: %s", request.URL.Path)
		}
	})
	media := providerMedia{
		URL:     "https://media.example.test/primary.m3u8",
		Referer: "https://site.example.test/",
		Quality: 720,
		Variants: []providerMedia{
			{URL: "https://media.example.test/backup.m3u8", Quality: 720},
			{URL: "https://media.example.test/other.m3u8", Quality: 1080},
		},
	}
	selected, err := d.fetchMediaPlaylistForMedia(context.Background(), media)
	if err != nil || selected.URL != "https://media.example.test/backup.m3u8" ||
		len(paths) != 2 || paths[0] != "/primary.m3u8" || paths[1] != "/backup.m3u8" {
		t.Fatalf("same quality backup was not selected: %+v %v %v", selected, paths, err)
	}
}

func TestNativeStreamFallsBackAcrossWirqedMediaEdges(t *testing.T) {
	var calls []string
	d := sourceFixtureDownloader(t, func(request *http.Request) (*http.Response, error) {
		calls = append(calls, request.URL.Hostname())
		if request.URL.Hostname() == "tp2.wirqed.cn" {
			return nil, fmt.Errorf("fixture edge reset")
		}
		switch request.URL.Path {
		case "/videos5/fixture/crypt.key":
			return sourceFixtureResponse(request, http.StatusOK, "0123456789abcdef"), nil
		case "/videos5/fixture/fixture0.ts":
			return sourceFixtureResponse(request, http.StatusOK, "synthetic-segment"), nil
		default:
			return nil, fmt.Errorf("unexpected request: %s", request.URL.String())
		}
	})
	media := providerMedia{
		URL:      "https://yd-hls.tktjpm.cn/videos5/fixture/index.m3u8",
		Playlist: "#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI=\"https://tp2.wirqed.cn/videos5/fixture/crypt.key?auth_key=fixture\"\n#EXTINF:4,\nhttps://tp2.wirqed.cn/videos5/fixture/fixture0.ts?auth_key=fixture\n#EXT-X-ENDLIST\n",
		Referer:  "https://ujvhqo.hwqlgzvsk.cc/video/6139/",
	}
	stream, err := newNativeStreamServer(d)
	if err != nil {
		t.Fatal(err)
	}
	defer stream.server.Close()
	address, token := stream.nativeOpen(media)
	defer stream.nativeRelease(token)

	read := func(raw string) string {
		t.Helper()
		response, err := http.Get(raw)
		if err != nil {
			t.Fatal(err)
		}
		defer response.Body.Close()
		body, err := io.ReadAll(response.Body)
		if err != nil {
			t.Fatal(err)
		}
		if response.StatusCode != http.StatusOK {
			t.Fatalf("stream response %d: %s", response.StatusCode, string(body))
		}
		return string(body)
	}
	playlist := read(address)
	key := nativePlaylistURI.FindStringSubmatch(playlist)
	if len(key) != 2 || read(key[1]) != "0123456789abcdef" {
		t.Fatalf("key did not recover through a backup edge: %q", playlist)
	}
	segment := ""
	for _, line := range strings.Split(playlist, "\n") {
		if line != "" && !strings.HasPrefix(line, "#") {
			segment = line
			break
		}
	}
	if segment == "" || read(segment) != "synthetic-segment" {
		t.Fatal("segment did not recover through a backup edge")
	}
	if len(calls) < 3 || calls[0] != "tp2.wirqed.cn" || calls[1] != "tp1.wirqed.cn" || calls[2] != "tp1.wirqed.cn" {
		t.Fatalf("unexpected edge fallback order: %v", calls)
	}
}
