#!/bin/bash
set -euo pipefail

usage() {
    printf '%s\n' '用法：scripts/install-blackhole.sh [--check-only] /path/to/BlackHole2ch.pkg' \
        '仅接受 Existential Audio Inc. 官方签名且通过 Gatekeeper 校验的 BlackHole 2ch 安装包。' \
        '安装时在 macOS 原生认证窗口输入管理员密码；脚本不读取或保存密码。'
}

check_only=0
if [[ "${1:-}" == '--check-only' ]]; then check_only=1; shift; fi
if [[ "${1:-}" == '--help' || "${1:-}" == '-h' ]]; then usage; exit 0; fi
if [[ $# -ne 1 || ! -f "$1" ]]; then usage >&2; exit 64; fi

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
package_path="$(cd -- "$(dirname -- "$1")" && pwd)/$(basename -- "$1")"

# installer runs as root and can be denied access to Desktop/Downloads by TCC.
# A private, temporary staging copy avoids that invalid-package-path failure.
staging_dir="$(/usr/bin/mktemp -d /private/tmp/mac-todesk-blackhole.XXXXXX)"
trap '/bin/rm -rf -- "$staging_dir"' EXIT
staged_package="$staging_dir/BlackHole2ch.pkg"
/bin/cp -- "$package_path" "$staged_package"
/bin/chmod 400 "$staged_package"

signature_output="$(LC_ALL=C /usr/sbin/pkgutil --check-signature "$staged_package")"
printf '%s\n' "$signature_output"
case "$signature_output" in
    *'Developer ID Installer: Existential Audio Inc. (Q5C99V536K)'*) ;;
    *) printf '%s\n' '官方安装者身份校验失败，停止安装。' >&2; exit 1 ;;
esac
/usr/sbin/spctl --assess --type install --verbose=2 "$staged_package"
/usr/sbin/pkgutil --expand "$staged_package" "$staging_dir/expanded"
package_info="$staging_dir/expanded/BlackHole.pkg/PackageInfo"
if [[ ! -f "$package_info" ]] || \
    [[ "$(/usr/bin/xmllint --xpath 'string(/pkg-info/@identifier)' "$package_info")" != 'audio.existential.BlackHole2ch' ]]; then
    printf '%s\n' '此安装包不是支持的 BlackHole 2ch 官方安装包结构，停止安装。' >&2
    exit 1
fi
printf '%s\n' '签名、Gatekeeper 和 BlackHole 2ch 包标识校验通过。'
if [[ $check_only -eq 1 ]]; then exit 0; fi

/usr/bin/osascript "$repo_root/scripts/install-blackhole.applescript" "$staged_package"
printf '%s\n' 'BlackHole 安装完成，已刷新 CoreAudio。此脚本不执行 Mac 重启。' \
    '请运行 scripts/build.sh，然后运行 audio-tools/audio_route list 确认 BlackHole 已出现。'
