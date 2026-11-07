# Windows 麦克风 → ToDesk → Mac → 豆包输入法

记录一台无可用物理麦克风的 Mac，如何通过 BlackHole 虚拟声卡接收远端音频，以及这次排查用到的配置、源码和恢复方法。

**当前完成的是 Mac 虚拟输入设备安装与本机回环验证。Windows 麦克风传到 Mac、再由豆包识别的完整链路尚未验证成功。** BlackHole 负责 Mac 内部音频路由；跨电脑传输仍需 ToDesk 协作语音或其他音频工具。

## 为什么 Mac 显示“找不到输入设备”

本机原先没有可作为默认输入的设备。虽然 CoreAudio 能枚举到 ToDesk 的音频驱动及其输入通道，该驱动报告 `defaultCapableInput=0`，不能据此当作普通麦克风使用。单独开放麦克风权限无法补出一个输入设备。

ToDesk 官方截至 2026-11-07 的说明将“麦克风映射”限定为 **Windows 被控端**，不能直接套用到被控 Mac。这里采用“远端语音在 Mac 播放 → BlackHole 回环 → Mac 输入”的路径。[官方映射说明](https://www.todesk.com/helpcenter/solo-376.html)

```mermaid
flowchart LR
    A[Windows 实体麦克风] --> B[ToDesk 协作语音：待验证]
    B --> C[Mac 默认输出 BlackHole 2ch]
    C --> D[Mac 默认输入 BlackHole 2ch]
    D --> E[豆包输入法：待验证]
```

## 已验证的范围

排查环境：Intel Mac、macOS 12.7.6、ToDesk 5.2.1.0、豆包输入法 1.1.0；记录日期为 2026-11-07。其他系统和版本请按下列步骤复测。

| 项目 | 结果 |
| --- | --- |
| BlackHole 2ch 0.7.1 安装、包签名及驱动签名检查 | 已完成 |
| BlackHole 作为 Mac 默认输入、默认输出 | 已完成 |
| 合成测试音 → BlackHole 输出 → BlackHole 输入 | 已通过，峰值 `0.100000`，RMS `0.070459` |
| Windows 麦克风 → ToDesk → BlackHole | 尚未通过；此前待测时电平为 `0` |
| 豆包识别 Windows 语音 | 尚未验证 |
| SonoBus、VDO.Ninja 替代传输 | 候选方案，未完成跨机验证 |

## 快速配置

### 1. 准备下载与编译工具

Mac 下载并安装 [BlackHole 2ch 0.7.1 官方安装包](https://existential.audio/downloads/BlackHole2ch-0.7.1.pkg)。其他软件及校验方法见[下载来源](docs/downloads.md)。本仓库只保存源码和链接，不包含安装包、生成的二进制文件或个人设备快照。

本机工具使用 Apple 的 Swift、Clang 和系统音频框架，无第三方代码依赖。先检查 Command Line Tools，缺少时执行 `xcode-select --install` 并完成系统安装窗口：

```sh
xcode-select -p
git clone https://github.com/LouChen-med/mac_todesk_microphone.git
cd mac_todesk_microphone
./scripts/build.sh
```

若尚未安装 BlackHole，可双击官方 `.pkg`，或使用仓库脚本。安装需要在 **macOS 的系统认证窗口**输入管理员凭据：

```sh
./scripts/install-blackhole.sh "$HOME/Downloads/BlackHole2ch-0.7.1.pkg"
```

脚本将安装包转存到系统临时目录后安装，避免本次排查遇到的桌面路径访问问题。安装细节见[配置与验证](docs/setup.md)。

### 2. 保存正常播放状态，启用虚拟输入

首次配置前，在 Mac“声音 → 输出”中选回平时使用的扬声器、耳机或 HDMI，退出其他虚拟输入模式，再保存快照。**不要把已切到 BlackHole 的状态当作正常播放状态保存。**

```sh
./audio-tools/audio_route status
./audio-tools/audio_route save
./audio-tools/audio_route enable
```

`enable` 将默认输入和默认输出都设为 `BlackHole 2ch`，保留系统提示音输出；若尚无快照，会自动保存当前状态。已有快照不会被覆盖。若当前输出已是 BlackHole 且没有快照，工具会拒绝创建恢复记录，需先选回正常播放设备。快照 `audio-tools/audio-before.json` 只用于本机恢复，不提交到 Git。

也可以在完成编译后双击 **[开启远程语音输入.command](开启远程语音输入.command)**。

### 3. Windows 打开 ToDesk 协作麦克风

在 Windows 的远程会话中，打开：

**悬浮球／工具栏 → 互动 → 协作成员 → 邀请 Mac 进入协作模式。**

新版已将语音通话并入协作模式。进入后，Windows 端打开自己的麦克风，Mac 端关闭自己的协作麦克风，避免将回环音频发回 Windows。每端只能切换自己的麦克风。[官方入口说明](https://todesk.com/helpcenter/solo-461.html)

若看不到协作入口，检查客户端版本及账号权益；官方说明要求协作版或包含该能力的版本，不能假定任意免费账号均可使用。[官方权益说明](https://www.todesk.com/special_multi-usercollaboration.html)

Windows 还需在系统麦克风设置中允许 ToDesk 使用所选实体麦克风。Mac 的豆包输入法需获得麦克风权限；如果它能选设备，选 `BlackHole 2ch`，否则使用系统默认输入。入口名称随系统版本可能不同。

### 4. 分层验证

先测 Mac 内部回环。下面的命令会向 **BlackHole 设备**写入短暂合成测试音，并读取其输入，避免在豆包录音期间执行：

```sh
./audio-tools/audio_route status
./audio-tools/blackhole_loopback_check
```

再关闭其他发声应用，让 Windows 对着麦克风讲话，执行只读电平检查：

```sh
./audio-tools/blackhole_loopback_check --meter-only --duration 15
```

电平应随 Windows 说话明显变化。只读模式不生成测试音、不保存录音，但电平也可能来自 Mac 的其他播放声音；请用“说话／静默”交替确认。电平始终为 `0` 时，先解决跨机声音接入，再测豆包。

最后打开 Mac 文本框，启动豆包语音输入，说一句有辨识度的测试句，确认出现对应文字。以这一步作为完整链路通过的标准。

### 5. 用完恢复声音播放

```sh
./audio-tools/audio_route restore-output
```

或双击 **[恢复声音播放.command](恢复声音播放.command)**。该操作恢复输出并保留 BlackHole 输入；需要恢复快照中的输入和输出时，执行 `./audio-tools/audio_route restore`。若快照记录的是“原先没有输入设备”，完整恢复会保留当前输入。

**启用期间，Mac 普通应用的播放声音也会进入 BlackHole 输入，普通扬声器可能听不到声音。** 语音输入时暂停音乐、视频、通知等音源。原 ToDesk 输出设备若已失效，恢复工具会尝试快照中的系统声音输出；仍失败时，在 Mac“声音 → 输出”手动选回可用设备。

## 仓库内容

| 文件 | 用途 |
| --- | --- |
| `src/audio_route.swift` | 列举设备、查看状态、保存和切换默认音频路由、恢复 |
| `src/audio_diag.swift` | CoreAudio 只读诊断，查看通道及默认设备能力 |
| `src/blackhole_loopback_check.c` | BlackHole 合成回环测试、只读电平检查 |
| `src/window_list.swift` | 只读窗口列表，用于定位系统或应用界面 |
| `scripts/build.sh` | 编译源码至本机 `audio-tools/` |
| `scripts/install-blackhole.sh` | 校验、暂存并通过系统认证安装 BlackHole |
| `scripts/install-blackhole.applescript` | 请求原生管理员认证，执行安装和音频服务刷新 |
| 两个 `.command` 文件 | 日常启用和恢复入口 |
| `docs/` | 配置、诊断过程、候选方案及下载链接 |
| `AGENTS.md` | 后续维护、测试和发布约定 |

常用工具命令：

```sh
./audio-tools/audio_route list
./audio-tools/audio_route status
./audio-tools/audio_diag
./audio-tools/window_list
```

详细说明：

- [配置、工具接口与验证步骤](docs/setup.md)
- [本次诊断证据与常见故障](docs/diagnosis.md)
- [全部方案与替代传输配置](docs/alternatives.md)
- [官方下载链接、版本与校验](docs/downloads.md)

第三方软件继续遵循各自的许可与服务条款；仓库没有再分发这些软件。
