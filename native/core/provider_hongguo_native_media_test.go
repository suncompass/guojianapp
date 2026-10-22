package core

import (
	"context"
	"encoding/json"
	"net/http"
	"strconv"
	"strings"
	"testing"
)

func TestHongguoAppMediaReadsTopLevelFields(t *testing.T) {
	media, err := selectHongguoAppMedia(map[string]any{"video_list": []any{
		map[string]any{"main_url": "https://media.test/new.mp4", "codec_type": "bytevc2", "definition": "2160p"},
		map[string]any{"main_url": "https://media.test/high.mp4", "codec_type": "h264", "definition": "1080p", "vheight": 720},
	}})
	if err != nil || media.Quality != 1080 || !strings.HasSuffix(media.URL, "high.mp4") {
		t.Fatalf("top-level codec/definition were ignored: %+v %v", media, err)
	}
	_, err = selectHongguoAppMedia(map[string]any{"video_list": []any{
		map[string]any{"main_url": "https://media.test/cenc.mp4", "encrypt": true, "encryption_method": "cenc-aes-ctr", "spade_a": "not-a-key"},
	}})
	if err == nil || !strings.Contains(err.Error(), "媒体密钥") {
		t.Fatalf("top-level CENC fields were ignored: %v", err)
	}
	_, err = selectHongguoAppMedia(map[string]any{"video_list": []any{
		map[string]any{"main_url": "https://media.test/nested.mp4", "encrypt_info": map[string]any{"encrypt": true, "spade_a": "not-a-key"}},
	}})
	if err == nil || !strings.Contains(err.Error(), "媒体密钥") {
		t.Fatalf("nested CENC fields were ignored: %v", err)
	}
}

func TestHongguoAppMediaPlaybackRequestUnsigned(t *testing.T) {
	var playbackDevice, catalogDevice string
	d := rankingTestDownloader(t, func(request *http.Request) (*http.Response, error) {
		switch request.URL.Path {
		case "/novel/player/multi_video_model/v1/":
			if request.Header.Get("X-Gorgon") != "" || request.Header.Get("X-Khronos") != "" || request.Header.Get("X-SS-STUB") != "" {
				t.Fatal("playback request must skip X-Gorgon/X-Khronos/X-SS-STUB")
			}
			if request.Header.Get("X-TT-Request-Tag") == "" || request.Header.Get("X-SS-Req-Ticket") == "" {
				t.Fatal("playback request must carry X-TT-Request-Tag and X-SS-Req-Ticket")
			}
			query := request.URL.Query()
			if query.Get("ts") == "" || query.Get("_rticket") == "" || query.Get("cdid") == "" {
				t.Fatal("playback request must include ts/_rticket/cdid")
			}
			playbackDevice = query.Get("device_id")
			var payload map[string]any
			if err := json.NewDecoder(request.Body).Decode(&payload); err != nil {
				t.Fatal(err)
			}
			mixed, _ := payload["mixed_video_id_map"].(map[string]any)
			ids, _ := mixed["1004"].([]any)
			if len(ids) != 1 || ids[0] != "800001" {
				t.Fatalf("unexpected mixed_video_id_map: %+v", payload)
			}
			biz, _ := payload["biz_param"].(map[string]any)
			if biz["video_platform"] != float64(1024) || biz["need_all_video_definition"] != true {
				t.Fatalf("unexpected biz_param: %+v", payload)
			}
			model := `{"video_list":[{"main_url":"https://media.test/play.mp4","video_meta":{"codec_type":"h264","definition":"720p"}}]}`
			return rankingHTTPResponse(request, 200, `{"code":0,"data":{"800001":{"video_model":`+strconv.Quote(model)+`}}}`), nil
		case "/novel/player/video_detail/v1/":
			if request.Header.Get("X-Gorgon") == "" || request.Header.Get("X-Khronos") == "" {
				t.Fatal("regular app requests must still send signatures")
			}
			catalogDevice = request.URL.Query().Get("device_id")
			return rankingHTTPResponse(request, 200, `{"code":0}`), nil
		default:
			t.Fatalf("unexpected path: %s", request.URL.Path)
			return nil, nil
		}
	})
	media, err := d.resolveHongguoAppMedia(context.Background(), "800001")
	if err != nil || media.URL != "https://media.test/play.mp4" || media.Quality != 720 {
		t.Fatalf("top-level media fields were ignored: %+v %v", media, err)
	}
	if _, err := d.hongguoAppRequest(context.Background(), http.MethodPost, "/novel/player/video_detail/v1/", nil, map[string]string{"series_id": "700001"}); err != nil {
		t.Fatal(err)
	}
	if playbackDevice == "" || catalogDevice == "" {
		t.Fatalf("device ids were not captured: playback=%q catalog=%q", playbackDevice, catalogDevice)
	}
	if playbackDevice == catalogDevice {
		t.Fatal("playback requests must use an independent device id")
	}
}
