package core

import (
	"encoding/base64"
	"strings"
)

const (
	duanjuKeyPayloadSeparator = "~"
	duanjuKeyPayloadRunes     = 80
	duanjuKeyPayloadLimit     = 400
)

func duanjuKeyPayload(value string) string {
	value = strings.TrimSpace(value)
	if value == "" {
		return ""
	}
	runes := []rune(value)
	if len(runes) > duanjuKeyPayloadRunes {
		value = string(runes[:duanjuKeyPayloadRunes])
	}
	return base64.RawURLEncoding.EncodeToString([]byte(value))
}

func duanjuKeyWithPayload(id, value string) string {
	id = strings.TrimSpace(id)
	payload := duanjuKeyPayload(value)
	if id == "" || payload == "" {
		return id
	}
	if len(id)+len(payload)+1 > duanjuKeyPayloadLimit {
		return id
	}
	return id + duanjuKeyPayloadSeparator + payload
}

func duanjuKeyBaseID(sourceID string) string {
	id, _, _ := strings.Cut(strings.TrimSpace(sourceID), duanjuKeyPayloadSeparator)
	return id
}

func duanjuKeyPayloadValue(sourceID string) string {
	_, encoded, found := strings.Cut(strings.TrimSpace(sourceID), duanjuKeyPayloadSeparator)
	if !found || encoded == "" {
		return ""
	}
	decoded, err := base64.RawURLEncoding.DecodeString(encoded)
	if err != nil {
		return ""
	}
	return string(decoded)
}

func migrateDuanjuPayloadKey(drama nativeDrama) nativeDrama {
	source, sourceID, valid := splitProviderDramaID(drama.ID)
	if !valid {
		return drama
	}
	key := sourceID
	switch source {
	case sourceXingguo:
		if id, intro, found := strings.Cut(sourceID, "@"); found {
			key = duanjuKeyWithPayload(id, intro)
		}
	case sourceFanguo:
		if id, reference, found := strings.Cut(sourceID, "#"); found {
			key = duanjuKeyWithPayload(id, reference)
		}
	}
	if key == sourceID {
		return drama
	}
	drama.SourceID = key
	drama.ID = providerDramaID(source, key)
	return drama
}
