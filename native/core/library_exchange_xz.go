package core

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strings"
	"time"

	"github.com/ulikunitz/xz"
)

var nativeLibraryExchangeXZMagic = []byte{0xFD, '7', 'z', 'X', 'Z', 0x00}

var nativeLibraryExchangeXZBinaries = []string{
	"/opt/homebrew/bin/xz",
	"/usr/local/bin/xz",
	"/usr/bin/xz",
	"/bin/xz",
}

const nativeLibraryExchangeXZTimeout = 3 * time.Minute

func nativeLibraryExchangeIsXZ(payload []byte) bool {
	return len(payload) >= len(nativeLibraryExchangeXZMagic) && bytes.Equal(payload[:len(nativeLibraryExchangeXZMagic)], nativeLibraryExchangeXZMagic)
}

func nativeLibraryExchangeXZBinary() string {
	if binary, err := exec.LookPath("xz"); err == nil {
		return binary
	}
	for _, binary := range nativeLibraryExchangeXZBinaries {
		info, err := os.Stat(binary)
		if err == nil && !info.IsDir() && info.Mode().Perm()&0o111 != 0 {
			return binary
		}
	}
	return ""
}

func nativeLibraryExchangeCompress(document []byte) ([]byte, error) {
	payload, err := nativeLibraryExchangeCompressExternal(document)
	if err == nil {
		return payload, nil
	}
	return nativeLibraryExchangeCompressPure(document)
}

func nativeLibraryExchangeCompressExternal(document []byte) ([]byte, error) {
	binary := nativeLibraryExchangeXZBinary()
	if binary == "" {
		return nil, errors.New("未找到系统 xz 命令")
	}
	ctx, cancel := context.WithTimeout(context.Background(), nativeLibraryExchangeXZTimeout)
	defer cancel()
	command := exec.CommandContext(ctx, binary, "-9e", "-T", "1", "-c")
	command.Stdin = bytes.NewReader(document)
	var stdout, stderr bytes.Buffer
	command.Stdout, command.Stderr = &stdout, &stderr
	if err := command.Run(); err != nil {
		return nil, fmt.Errorf("系统 xz 压缩失败: %w %s", err, strings.TrimSpace(stderr.String()))
	}
	payload := stdout.Bytes()
	if !nativeLibraryExchangeIsXZ(payload) {
		return nil, errors.New("系统 xz 输出不是有效的压缩包")
	}
	return payload, nil
}

func nativeLibraryExchangeCompressPure(document []byte) ([]byte, error) {
	var buffer bytes.Buffer
	writer, err := xz.NewWriter(&buffer)
	if err != nil {
		return nil, err
	}
	_, writeErr := writer.Write(document)
	if closeErr := writer.Close(); writeErr == nil {
		writeErr = closeErr
	}
	if writeErr != nil {
		return nil, writeErr
	}
	return buffer.Bytes(), nil
}

func nativeLibraryExchangeDecompress(payload []byte) ([]byte, error) {
	reader, err := xz.NewReader(bytes.NewReader(payload))
	if err != nil {
		return nil, err
	}
	document, err := io.ReadAll(io.LimitReader(reader, nativeLibraryExchangeBytes+1))
	if err != nil {
		return nil, err
	}
	if len(document) > nativeLibraryExchangeBytes {
		return nil, errors.New("剧库文件解压后超过 32 MB")
	}
	return document, nil
}
