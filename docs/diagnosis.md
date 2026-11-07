# 诊断记录与故障定位

记录日期：2026-11-07。环境为 Intel Mac、macOS 12.7.6、ToDesk 5.2.1.0、豆包输入法 1.1.0。以下结果来自本次检查，不能直接推广到其他硬件或版本。

## 原始问题

通过 Windows 的 ToDesk 远控 Mac，希望使用 Windows 的麦克风在 Mac 上完成豆包语音输入。Mac“声音 → 输入”显示“找不到输入设备”。

这包含两个独立环节：Mac 必须具有可用输入设备；Windows 的声音必须真正传到该设备。安装虚拟声卡只能补齐前一个环节。

## 安装前证据

使用 `audio_diag.swift` 读取 CoreAudio 设备及属性：

| 项目 | 观察 | 含义 |
| --- | --- | --- |
| 系统默认输入 | `defaultInputID=0` | 当时无有效默认输入 |
| 物理输入设备 | 未发现可用设备 | 没有可直接选用的本机麦克风 |
| ToDesk 设备 UID | `ToDeskOutputDriver2ch_UID` | ToDesk 自带音频设备 |
| ToDesk 通道 | 输入 `2`，输出 `2` | 枚举到输入通道不等于可作为系统麦克风 |
| ToDesk `hidden` / `alive` | `0` / `1` | 当时并非简单“隐藏”或完全未加载 |
| ToDesk `defaultCapableInput` | `0` | 当时不能成为默认输入 |

这解释了“驱动看似存在，系统输入列表仍为空”的现象。它不是仅靠给豆包或 ToDesk 授予麦克风权限即可解决的问题。权限仍是后续应用采集的必要条件，但权限和设备能力需要分开检查。

ToDesk 的“远程声音”描述的是被控端声音回到主控端，与 Windows 麦克风送入 Mac 的方向不同。[官方远程声音说明](https://www.todesk.com/faq/24.html)；官方“麦克风映射”目前仅支持 Windows 被控端。[官方映射限制](https://www.todesk.com/helpcenter/solo-376.html)

## 采用的本机修复

1. 从官方源下载 BlackHole 2ch 0.7.1，核对 SHA-256、包签名、公证评估和驱动签名。
2. 经 macOS 原生管理员认证安装。桌面路径安装报无效后，改为 `/private/tmp` 暂存成功。
3. 重启 `coreaudiod` 以刷新设备，本次没有重启 Mac。
4. 默认输入和普通输出设为 BlackHole，系统声音输出保留 HDMI。
5. 使用 C 工具向 BlackHole 输出合成音，并从其输入读回，测得 `peak=0.100000`、`rms=0.070459`。

安装后，“系统无输入设备”这一问题已处理。BlackHole 不自带网络收音能力，还需另一个工具把 Windows 麦克风送到 Mac 的播放端。

## 尚未完成的部分

Windows 端未找到旧的“语音通话”入口。查阅更新于 2026-10-27 的官方帮助后，确认一对一会话入口是“悬浮球 → 互动 → 协作成员”，语音已并入协作模式。[官方协作说明](https://todesk.com/helpcenter/solo-461.html)

后续用户已确认可以进入协作模式，并已开启 Windows 麦克风；是否真正接收到对应讲话仍需检查 Mac 电平。此前待测时 Mac 只读电平曾保持 `0`，豆包识别也没有通过记录。因此不能只根据“麦克风已开启”就宣称跨机传输或识别成功。后续验收按[配置文档的四层检查](setup.md#四层验收)完成。

用户后续截图中的“外接设备 → 麦克风”呈灰色，并提示“被控系统暂不支持此功能”。这是原生麦克风映射入口，不是“互动 → 协作成员”语音入口；它与官方的被控 Mac 限制一致，不能据此判断 BlackHole 安装失败。无需反复安装 ToDesk 驱动来解除该限制。

用户确认开启协作麦克风后，使用整理后的工具检测 15 秒，得到 `inputRate=48000`、`inputChannels=2`、`invalidBuffers=0`、`peak=0.000000`、`rms=0.000000`：该采样窗口中 BlackHole 没有收到可检测信号。用户反馈按住左 Option 仍不能输入；需要分开确认“是否出现豆包录音界面”和“Windows 讲话是否送达 BlackHole”，不能只改快捷键就认定声音路径已经接通。

## 按现象排查

| 现象 | 优先检查 |
| --- | --- |
| 输入列表仍为空 | `audio_route list` 是否有 BlackHole；是否安装成功；音频服务是否刷新 |
| BlackHole 存在但默认输入错误 | `audio_route status`；执行 `enable` 后复查；应用是否仍绑定旧设备 |
| 合成回环失败 | BlackHole 是否 `alive`、输入输出通道、驱动安装和测试程序错误码 |
| 合成回环通过，Windows 讲话时电平为零 | Windows 实体麦克风、ToDesk 协作是否加入、发言是否静音、Mac 播放设备 |
| 找不到“语音通话” | 查“互动 → 协作成员”；核对版本和协作权益 |
| 电平随讲话变化，豆包不出字 | 豆包麦克风权限、设备选择、快捷键及应用状态 |
| 豆包录入音乐、视频或提示声 | Mac 所有普通输出均送入 BlackHole；暂停其他音源或改用独立应用输出 |
| 回声或声音循环 | 关闭 Mac 的协作麦克风和发送；Windows 使用耳机 |
| Mac 扬声器无声 | BlackHole 输出本身不负责实体播放；执行 `restore-output` |
| 恢复时报旧设备不可用 | ToDesk 会话或音频服务刷新后驱动失活；手动选择当前 HDMI/扬声器 |

辅助命令：

```sh
./audio-tools/audio_diag
./audio-tools/audio_route status
./audio-tools/audio_route list
./audio-tools/blackhole_loopback_check --meter-only --duration 15
```

`audio_diag` 输出可能包含本机设备 UID，`window_list` 可能包含窗口标题。分享日志前删除个人信息；不要把完整日志、截图、凭据或设备状态文件加入仓库。
