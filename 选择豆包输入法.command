#!/bin/zsh
set -euo pipefail
cd -- "${0:A:h}"
if [[ ! -x ./audio-tools/input_source || ./src/input_source.swift -nt ./audio-tools/input_source ]]; then
    /bin/bash ./scripts/build.sh
fi
./audio-tools/input_source select-doubao
print '请在文字输入框中按豆包已配置的语音快捷键，并检查是否出现录音界面。'
print '此操作不更改音频路由；录音能否收到 Windows 声音仍需分别验证。'
print '若系统按输入上下文记忆输入法，请在 VSCode 的实际输入框聚焦后，从菜单栏选择豆包；Terminal 中的选择不保证应用到其他输入框。'
