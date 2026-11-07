# 配置与验证

本页面向“Windows 作为主控，Mac 作为被控，Windows 麦克风用于 Mac 豆包输入法”的场景。Mac 本机回环已验证，跨机链路仍需实际讲话和豆包识别验收。

当前 Mac 无人值守；ToDesk 协作需要在 Mac 端完成确认，用户无法完成该步骤，所以它不作为本工作流的默认传输方案。用户最终要求只用 ToDesk，不能直接连接就停止；独立的 SonoBus 或浏览器音频保留为[未实施的候选](alternatives.md)。排查结束已恢复普通播放输出。下文保留配置步骤供以后主动复现。

## 配置前记录

1. 保留 ToDesk 远控连接，先不要重启 Mac 或结束 ToDesk 进程。
2. 在 Mac“声音 → 输出”选择正常播放设备，在“输入”中记录已有设备。
3. 安装 Apple Command Line Tools，并在仓库根目录执行 `./scripts/build.sh`。
4. 执行 `./audio-tools/audio_route status` 和 `./audio-tools/audio_route save`。

路由工具默认将恢复信息写入 `audio-tools/audio-before.json`。这是当前电脑的状态文件，包含设备标识，只在本机保存。已有快照不会被覆盖；如确需建立新基线，应先恢复并核实正常播放状态，再将旧文件移至本机临时目录后重新 `save`。不得删除本次尚需使用的恢复记录。

## 安装 BlackHole

使用[下载页](downloads.md)列出的官方 `BlackHole2ch-0.7.1.pkg`。可以双击安装，也可以执行：

```sh
./scripts/install-blackhole.sh "$HOME/Downloads/BlackHole2ch-0.7.1.pkg"
```

脚本核对开发者签名 `Existential Audio Inc. (Q5C99V536K)`、Gatekeeper 评估和 BlackHole 2ch 包标识，在 `/private/tmp` 中建立暂存目录，再通过 AppleScript 请求系统管理员认证；安装后刷新音频服务。用户只在 macOS 原生窗口输入密码，不把密码写入终端、脚本或聊天。

只检查安装包、不进行安装：

```sh
./scripts/install-blackhole.sh --check-only "$HOME/Downloads/BlackHole2ch-0.7.1.pkg"
```

本次第一次安装时，从桌面工作目录向提权的 `installer` 传包路径，出现“package path specified was invalid”。转存到 `/private/tmp` 后安装成功。这是本次实际遇到的路径访问问题，不能据此推断所有安装错误都是同一原因。

安装后可手动复核：

```sh
pkgutil --check-signature "$HOME/Downloads/BlackHole2ch-0.7.1.pkg"
spctl --assess --type install --verbose=2 "$HOME/Downloads/BlackHole2ch-0.7.1.pkg"
codesign --verify --deep --strict --verbose=2 /Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver
./audio-tools/audio_route list
```

如果已安装但设备列表未刷新，可通过管理员认证重启音频服务：

```sh
osascript -e 'do shell script "/usr/bin/killall coreaudiod" with administrator privileges'
```

这会短暂中断所有 Mac 应用的音频。运行后重新检查设备、默认路由及远程会话音频。本次只重启音频服务，没有重启整台 Mac；若驱动仍未出现，应按官方安装说明排查，而不是反复杀进程。

## 路由工具接口

```text
audio_route status
audio_route list
audio_route save [--state PATH]
audio_route enable [--state PATH]
audio_route restore-output [--state PATH]
audio_route restore [--state PATH]
```

| 命令 | 作用 |
| --- | --- |
| `list` | 列出设备和通道 |
| `status` | 显示默认输入、普通输出和系统声音输出 |
| `save` | 创建恢复快照，不覆盖已有文件；没有旧快照且当前输出已是 BlackHole 时拒绝保存 |
| `enable` | 先确保恢复快照存在，再将默认输入和普通输出设为 BlackHole 2ch |
| `restore-output` | 从快照恢复输出，保留当前输入 |
| `restore` | 从快照恢复输入和输出 |
| `--state PATH` | 使用另一个本地快照路径，避免与原快照混用 |

工具使用设备 UID 解析当前设备，不应将某次运行的数字 AudioDeviceID 写死。默认输入和默认输出不同于系统提示音输出；启用操作将普通播放送入 BlackHole，不要求系统提示音也跟随。

快照若记录了原先没有默认输入，`restore` 保留当前输入，不尝试把系统强制切回“无设备”。已有快照损坏或不可读时，工具会报错，不会静默覆盖。

旧脚本中的 `--blackhole-input --blackhole-output`、`--restore-output` 等标志保留兼容；新操作优先使用上表的命令。

## ToDesk 协作语音配置（需能完成 Mac 确认）

1. Windows 连接 Mac 后，在悬浮球或顶部工具栏点击“互动 → 协作成员”，邀请被控 Mac 进入协作模式。
2. Mac 处理加入提示。Windows 成员开启自己的实体麦克风；Mac 成员关闭自己的麦克风。
3. 检查 Windows 的隐私设置允许桌面应用访问麦克风，并核对 ToDesk 使用的麦克风及成员电平。
4. Mac 执行 `./audio-tools/audio_route enable`，确保普通输出与默认输入均为 `BlackHole 2ch`。
5. 若 ToDesk 提供独立扬声器设备选项，选择 `BlackHole 2ch` 或确认“系统默认”随系统路由生效。若仍沿用旧设备，先重新进入协作语音，再观察电平。

新版入口和语音功能合并见 [ToDesk 协作帮助](https://todesk.com/helpcenter/solo-461.html)。找不到入口时，核对 [协作功能权益与客户端要求](https://www.todesk.com/special_multi-usercollaboration.html)。账号缺少入口时可按[替代方案](alternatives.md)测试独立音频传输。

Mac 协作麦克风必须保持关闭，因为它的默认输入是 BlackHole；开启会把收到的远端声音再次发送出去。Windows 宜使用耳机，减少扬声器声音重新被实体麦克风采集。

本次已确认协作入口可进入、Windows 麦克风已开启，但被控 Mac 仍有待确认步骤，无法满足当前无人值守操作。没有证据表明这一操作流程可跳过，也没有将其改成自动同意。

## 输入法与 VS Code

本次另一个现象是：按住左 Option，在 Mac 文本编辑中能出现豆包录音框，在 VS Code 中不出现。这与“是否有音频进入 BlackHole”是两项独立检查；录音框出现也不表示 Windows 语音已经接通。

只读检查结果：

- 豆包的左 Option 快捷键已配置，不能据此判定快捷键配置错误。
- `isGloableASRShortcutEnable=false`，当前没有启用全局语音快捷键。
- 系统 `TextInputGlobalPropertyPerContextInput=1`，按输入上下文记忆输入法；随焦点切换，观察到了 ABC 与豆包交替成为当前输入法。
- VS Code 未发现与此相关的自定义键位覆盖。

先在 VS Code 中点击实际要输入的位置：编辑器正文、集成终端、扩展聊天框可能分别处于不同输入上下文。保持该输入框聚焦，从 Mac 菜单栏选择“豆包输入法”，再按左 Option，先确认能否出现录音界面。若需要跨输入法使用语音，在豆包自身设置中查找并启用其支持的全局语音功能，再分别验证目标输入框；不直接编辑应用的 MMKV 数据文件。

仓库提供输入法工具，用于检查和切换系统已经启用的输入法：

```text
input_source status
input_source list
input_source select-doubao [--state PATH]
input_source restore [--state PATH]
```

```sh
./scripts/build.sh
./audio-tools/input_source status
./audio-tools/input_source list
./audio-tools/input_source select-doubao
```

也可以双击根目录的[选择豆包输入法.command](../选择豆包输入法.command)。工具在首次切换前保存 `audio-tools/input-before.json`，不覆盖已有快照；当前已经是豆包时不重复切换；豆包尚未在系统中启用时明确失败，不强制添加。原输入法仍已启用且可选择时，可运行：

```sh
./audio-tools/input_source restore
```

`--state PATH` 可指定另一份本机输入法快照。它与音频路由的 `audio-before.json` 是两类文件，不能混用。

**工具选择的是当前输入上下文。** 从 Terminal 运行命令或双击 `.command` 会涉及 Terminal 的焦点，不保证同时改变 VS Code 内另一个上下文。因此仍需回到 VS Code 的目标输入框核对菜单栏输入法，不能把脚本成功退出当作 VS Code 语音已修好。

## 四层验收

### 第一层：设备存在

```sh
./audio-tools/audio_route list
./audio-tools/audio_route status
```

应能看到 `BlackHole 2ch` 的输入和输出，启用后默认输入、默认普通输出均指向它。在系统声音输入列表中也应出现 BlackHole。安装前 `defaultInputID=0` 的情况不应继续存在。

### 第二层：Mac 内部回环

```sh
./audio-tools/blackhole_loopback_check --duration 3
```

程序直接选择 BlackHole 写入合成测试音，并检查从同一设备读回的音频。它不证明 Windows 已接通，也不证明豆包权限或识别正常。程序不会保存音频文件。

本次原始实现的一次通过结果：

```text
peak=0.100000
rms=0.070459
samples=289792
callbacks=283
```

回调次数和样本数受测试时长、设备和调度影响，不应要求每次完全一致。

### 第三层：跨机语音

先结束合成测试、关闭 Mac 上的其他播放音源，在 Windows 对着麦克风轮流讲话和静默：

```sh
./audio-tools/blackhole_loopback_check --meter-only --duration 15
```

`--meter-only` 只从 BlackHole 输入统计电平，不写入测试音。`--duration` 支持 `1` 至 `120` 秒；未指定时合成测试默认 `3` 秒，只读电平默认 `10` 秒。

电平应随讲话改变。本次后续使用整理后的工具检测 15 秒，`inputRate=48000`、`inputChannels=2`、`invalidBuffers=0`，但 `peak=0.000000`、`rms=0.000000`。在该采样窗口中没有检测到声音。只有这一层通过，才能说 Windows 麦克风已传入 Mac。

### 第四层：豆包实际识别

Mac 的“系统偏好设置 → 安全性与隐私 → 隐私 → 麦克风”（新系统为“系统设置 → 隐私与安全性 → 麦克风”）中允许豆包输入法访问麦克风。若有多个豆包相关进程，以系统实际申请权限的应用为准。

退出正在运行的豆包语音录制，在实际目标输入框聚焦后确认当前输入法为豆包，再按已配置的左 Option 或所选语音快捷键。先确认录音界面出现，再说出测试句，确认文字与远端讲话一致；随后静默，确认不会误录 Mac 的播放声音。

若文本编辑能出现录音框而 VS Code 不能，先按[输入法与 VS Code](#输入法与-vs-code)核对当前输入上下文。若两者都能出现录音框但没有声音，回到第三层检查。界面触发、跨机电平和最终识别必须分别验收。

没有文字但第三层电平正常时，排查豆包的麦克风权限、选定设备、语音快捷键和应用自身状态。不要把此时的问题重新归因于“系统没有输入设备”。

## 恢复

日常结束语音输入：

```sh
./audio-tools/audio_route restore-output
./audio-tools/audio_route status
```

恢复完整快照：

```sh
./audio-tools/audio_route restore
```

ToDesk 的虚拟输出设备可能在会话断开或音频服务刷新后暂时不活跃。若原普通输出已失效，工具尝试快照中的系统声音输出。恢复后仍无声时，在 Mac“声音 → 输出”手动选择当前可用的 HDMI、扬声器或耳机，再核对应用音量与静音状态。

保留 BlackHole 已安装不会强制所有声音继续进入它；关键是当前默认输出的选择。本仓库不自动卸载驱动或修改 ToDesk、豆包的内部配置。
