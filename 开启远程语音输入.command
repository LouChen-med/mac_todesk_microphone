#!/bin/zsh
set -euo pipefail
cd -- "${0:A:h}"
if [[ ! -x ./audio-tools/audio_route || ./src/audio_route.swift -nt ./audio-tools/audio_route ]]; then
    /bin/bash ./scripts/build.sh
fi
./audio-tools/audio_route enable
print 'Mac 已将默认播放声音送入 BlackHole 麦克风。'
print '请在 Windows ToDesk「互动 → 协作成员」中检查语音连接与 Windows 麦克风。'
print 'Mac 通话麦克风保持关闭以避免回声；是否成功仍需 Windows 讲话实测。'
print '其他 Mac 播放声音也可能被豆包识别，测试时暂停其他音频。'
print '使用结束后运行「恢复声音播放.command」。'
