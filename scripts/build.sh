#!/bin/bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
output_dir="$repo_root/audio-tools"
mkdir -p "$output_dir"

if ! /usr/bin/xcrun --find swiftc >/dev/null 2>&1 || ! /usr/bin/xcrun --find clang >/dev/null 2>&1; then
    printf '%s\n' '请先运行 xcode-select --install 安装 Apple Command Line Tools。' >&2
    exit 1
fi

# Native architecture, with macOS 12 as the minimum supported OS.
export MACOSX_DEPLOYMENT_TARGET=12.0
for source in audio_route audio_diag window_list input_source; do
    /usr/bin/xcrun swiftc -O "$repo_root/src/$source.swift" -o "$output_dir/$source"
done
/usr/bin/xcrun clang -std=c11 -O2 -Wall -Wextra -Werror \
    "$repo_root/src/blackhole_loopback_check.c" \
    -framework CoreAudio -framework CoreFoundation -lm \
    -o "$output_dir/blackhole_loopback_check"
printf '%s\n' "已编译至：$output_dir" '编译不会安装驱动或更改音频路由。'
