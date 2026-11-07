# Windows 麦克风 → Mac → 豆包输入法（ToDesk 远控）

# 开发失败，放弃

记录通过 ToDesk 远控一台无可用物理麦克风的 Mac 时，如何用 BlackHole 虚拟声卡接收远端音频，以及这次排查用到的配置、源码和恢复方法。

**当前完成的是 Mac 虚拟输入设备安装与本机回环验证。Windows 麦克风传到 Mac、再由豆包识别的完整链路尚未验证成功。** BlackHole 负责 Mac 内部音频路由；跨电脑传输仍需独立的声音通道。

后续已确认能进入 ToDesk 协作、Windows 麦克风也已开启，但该流程要求在被控 Mac 确认，当前无人值守工作流无法完成这一步。**协作语音不作为本工作流的默认推荐。** 用户最终选择只使用 ToDesk，不能直接接入就停止，因此没有部署 SonoBus 或浏览器传声。仓库保留候选方案供参考。

结束排查时已恢复 Mac 普通声音播放至原系统输出 HDMI，不再把全部播放送进 BlackHole；BlackHole 驱动及默认输入保留。下方启用命令用于日后主动复现，整理文档不会自动执行它们。

## 为什么 Mac 显示“找不到输入设备”

本机原先没有可作为默认输入的设备。虽然 CoreAudio 能枚举到 ToDesk 的音频驱动及其输入通道，该驱动报告 `defaultCapableInput=0`，不能据此当作普通麦克风使用。单独开放麦克风权限无法补出一个输入设备。

ToDesk 官方截至 2026-11-07 的说明将“麦克风映射”限定为 **Windows 被控端**，不能直接套用到被控 Mac。这里采用“远端语音在 Mac 播放 → BlackHole 回环 → Mac 输入”的路径。[官方映射说明](https://www.todesk.com/helpcenter/solo-376.html)

```mermaid
flowchart LR
    A[Windows 实体麦克风] --> B[独立音频传输：待选择与验证]
    B --> C[Mac 默认输出 BlackHole 2ch]
    C --> D[Mac 默认输入 BlackHole 2ch]
    D --> E[豆包输入法：待验证]
```

## 已验证的范围

排查环境：Intel Mac、macOS 12.7.6、ToDesk 5.2.1.0、豆包输入法 1.1.0；记录日期为 2026-11-07。其他系统和版本请按下列步骤复测。

| 项目 | 结果 |
| --- | --- |
| BlackHole 2ch 0.7.1 安装、包签名及驱动签名检查 | 已完成 |
| BlackHole 作为 Mac 默认输入、默认输出 | 配置和本机测试已完成；结束时已恢复普通输出，保留 BlackHole 输入 |
| 合成测试音 → BlackHole 输出 → BlackHole 输入 | 已通过，峰值 `0.100000`，RMS `0.070459` |
| Windows 麦克风 → ToDesk → BlackHole | 尚未通过；15 秒检测电平为 `0`，协作还受 Mac 确认限制 |
| 豆包识别 Windows 语音 | 尚未验证 |
| SonoBus、VDO.Ninja 替代传输 | 候选方案，未完成跨机验证 |
| 左 Option 语音触发 | 文本编辑可出现录音框，VS Code 的 AI 扩展聊天框未出现；快捷键已配置，问题未确认修复 |
| 输入法随焦点变化 | 已观察到 ABC／豆包按上下文切换，需要在目标输入框选择豆包 |

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

### 3. 建立 Windows 到 Mac 的声音通道

本次无人值守场景若要继续，需要另选并验证 [SonoBus 或浏览器音频方案](docs/alternatives.md)。用户已选择停止这一步，以下仅为复现说明。ToDesk 继续承担桌面远控。

以下协作路径仅保留供能完成 Mac 确认的场景参考；不能把“Windows 麦克风已开启”当作声音已到达 Mac 的证明。

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

如果左 Option 在文本编辑能显示录音框、在 VS Code 中不显示，先在 **VS Code 实际目标输入框**（编辑器、终端或扩展输入框）聚焦，再从 Mac 菜单栏选择豆包输入法。本次左 Option 配置正确，但全局语音开关为关闭状态，且系统按输入上下文记忆 ABC／豆包。详细排查见[输入法与 VS Code](docs/setup.md#输入法与-vs-code)。

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
| `src/input_source.swift` | 检查已启用输入法，保存原输入法后选择豆包，或恢复 |
| `scripts/build.sh` | 编译源码至本机 `audio-tools/` |
| `scripts/install-blackhole.sh` | 校验、暂存并通过系统认证安装 BlackHole |
| `scripts/install-blackhole.applescript` | 请求原生管理员认证，执行安装和音频服务刷新 |
| 三个 `.command` 文件 | 日常启用音频、恢复播放和选择豆包入口 |
| `docs/` | 配置、诊断过程、候选方案及下载链接 |
| `AGENTS.md` | 后续维护、测试和发布约定 |

常用工具命令：

```sh
./audio-tools/audio_route list
./audio-tools/audio_route status
./audio-tools/audio_diag
./audio-tools/window_list
./audio-tools/input_source status
./audio-tools/input_source list
```

需要切换当前输入上下文时，可执行 `./audio-tools/input_source select-doubao`，或双击[选择豆包输入法.command](选择豆包输入法.command)。它只选择系统已启用的豆包，不强制添加输入法；首次选择前保存 `audio-tools/input-before.json`，已有快照不覆盖。执行 `./audio-tools/input_source restore` 可恢复已启用的原输入法。

从 Terminal 切换输入法不能保证 VS Code 的另一个输入上下文也随之改变。在 VS Code 内聚焦目标输入框后从菜单栏选择，才是这一问题的直接检查方式。输入法快照同样只保存在本机。

详细说明：

- [配置、工具接口与验证步骤](docs/setup.md)
- [本次诊断证据与常见故障](docs/diagnosis.md)
- [全部方案与替代传输配置](docs/alternatives.md)
- [官方下载链接、版本与校验](docs/downloads.md)

第三方软件继续遵循各自的许可与服务条款；仓库没有再分发这些软件。
