package core

import (
	"crypto/rand"
	"encoding/binary"
	"net/http"
	"strconv"
	"time"
)

func newHongguoDeviceID() string {
	var random [8]byte
	if _, err := rand.Read(random[:]); err != nil {
		return strconv.FormatInt(time.Now().UnixNano(), 10)
	}
	return strconv.FormatUint(1_000_000_000_000_000_000+binary.BigEndian.Uint64(random[:])%8_000_000_000_000_000_000, 10)
}

// 播放请求不带任何签名头：上游对该路径只校验公共头与 Query 参数，
// 一旦出现 X-Gorgon / X-Khronos / X-SS-STUB 反而被判为无效。
func prepareHongguoPlaybackRequest(request *http.Request, now time.Time) {
	request.Header.Del("X-Gorgon")
	request.Header.Del("X-Khronos")
	request.Header.Del("X-Argus")
	request.Header.Del("X-Ladon")
	request.Header.Del("X-SS-STUB")
	request.Header.Set("X-SS-Req-Ticket", strconv.FormatInt(now.UnixMilli(), 10))
	request.Header.Set("X-TT-Request-Tag", "t=0;n=0")
}
