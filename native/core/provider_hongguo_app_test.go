package core

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"testing"
)

func TestHongguoPlaybackRequestIsUnsignedWithIsolatedDevice(t *testing.T) {
	var seen *http.Request
	d := rankingTestDownloader(t, func(request *http.Request) (*http.Response, error) {
		seen = request
		return rankingHTTPResponse(request, 200, `{"code":0,"data":{"video_model":{"video_list":[]}}}`), nil
	})
	ctx := context.WithValue(context.Background(), hongguoPlaybackKey{}, true)
	if _, err := d.hongguoAppRequest(ctx, http.MethodPost, "/novel/player/multi_video_model/v1/", nil, map[string]any{"video_id": "7300000000000000000"}); err != nil {
		t.Fatalf("playback request failed: %v", err)
	}
	if seen == nil {
		t.Fatal("playback request was not sent")
	}
	if seen.URL.Path != "/novel/player/multi_video_model/v1/" {
		t.Errorf("wrong playback path: %s", seen.URL.Path)
	}
	for _, name := range []string{"X-Gorgon", "X-Khronos", "X-SS-STUB", "X-Argus", "X-Ladon", "Comment-Source"} {
		if seen.Header.Get(name) != "" {
			t.Errorf("playback request must not carry signature header: %s", name)
		}
	}
	query := seen.URL.Query()
	for _, name := range []string{"ts", "_rticket", "device_id", "iid", "cid"} {
		if query.Get(name) == "" {
			t.Errorf("playback request missing query parameter: %s", name)
		}
	}
	client := d.hongguoClient()
	client.mu.Lock()
	playbackDevice, playbackInstall := client.playerDeviceID, client.playerInstallID
	catalogDevice, catalogInstall := client.state.DeviceID, client.state.InstallID
	client.mu.Unlock()
	if playbackDevice == "" || playbackInstall == "" {
		t.Fatal("playback device identity must be generated at startup")
	}
	if query.Get("device_id") != playbackDevice || query.Get("iid") != playbackInstall {
		t.Error("playback request must use the isolated device identity")
	}
	if playbackDevice == catalogDevice || playbackInstall == catalogInstall {
		t.Error("playback device identity must differ from the catalog identity")
	}
}

func TestHongguoCatalogRequestKeepsSignature(t *testing.T) {
	var seen *http.Request
	d := rankingTestDownloader(t, func(request *http.Request) (*http.Response, error) {
		seen = request
		return rankingHTTPResponse(request, 200, `{"code":0}`), nil
	})
	if _, err := d.hongguoAppRequest(context.Background(), http.MethodPost, "/novel/player/video_detail/v1/", nil, map[string]string{"series_id": "7300000000000000000"}); err != nil {
		t.Fatalf("catalog request failed: %v", err)
	}
	if seen == nil {
		t.Fatal("catalog request was not sent")
	}
	for _, name := range []string{"X-Gorgon", "X-Khronos", "X-Argus", "X-Ladon"} {
		if seen.Header.Get(name) == "" {
			t.Errorf("catalog request missing signature header: %s", name)
		}
	}
}

func TestHongguoPlaybackDeviceIdentityIsNotPersisted(t *testing.T) {
	d := rankingTestDownloader(t, func(request *http.Request) (*http.Response, error) {
		return rankingHTTPResponse(request, 200, `{"code":0}`), nil
	})
	snapshot := d.hongguoCatalogSnapshot()
	encoded, err := json.Marshal(snapshot)
	if err != nil {
		t.Fatalf("snapshot encode failed: %v", err)
	}
	client := d.hongguoClient()
	client.mu.Lock()
	playbackDevice, playbackInstall := client.playerDeviceID, client.playerInstallID
	client.mu.Unlock()
	for _, value := range []string{playbackDevice, playbackInstall} {
		if value == "" {
			t.Fatal("playback device identity must not be empty")
		}
		if strings.Contains(string(encoded), value) {
			t.Error("playback device identity must not be persisted into the catalog cache")
		}
	}
}
