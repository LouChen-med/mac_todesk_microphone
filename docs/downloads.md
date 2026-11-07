# 下载链接与版本

链接核对日期：2026-11-07。安装包由各软件官方提供，本仓库不保存或再分发 `.pkg`、`.dmg`、`.exe`、解包文件和第三方源码。固定版本用于复现本次结果，不代表未来应一直使用该版本。

| 软件 | 本次版本／状态 | 官方来源 |
| --- | --- | --- |
| BlackHole 2ch | 0.7.1，已在本机安装及回环测试 | [官方下载 `.pkg`](https://existential.audio/downloads/BlackHole2ch-0.7.1.pkg) · [官网](https://existential.audio/blackhole/) · [开源仓库](https://github.com/ExistentialAudio/BlackHole) |
| ToDesk | Mac 5.2.1.0，本次已安装环境 | [官方下载页](https://www.todesk.com/download.html) |
| 豆包输入法 | Mac 1.1.0，本次已安装环境 | [官网](https://shurufa.doubao.com/) |
| SonoBus Windows | 1.7.2，候选传输端，未连接测试 | [官方 `.exe`](https://sonobus.net/releases/sonobus-1.7.2-win.exe) |
| SonoBus Mac | 1.7.2，仅下载并检查安装介质，未安装连接 | [官方 `.dmg`](https://sonobus.net/releases/sonobus-1.7.2-mac.dmg) |
| SonoBus 文档 | 候选方案配置参考 | [官网](https://www.sonobus.net/) · [用户指南](https://www.sonobus.net/sonobus_userguide.html) · [开源仓库](https://github.com/sonosaurus/sonobus) |
| VDO.Ninja | 在线候选方案，未测试 | [在线入口](https://vdo.ninja/) · [官方文档](https://docs.vdo.ninja/) |

若固定下载链接失效，请回到对应官网确认版本和下载地址，不使用来历不明的镜像。更新版本后重新做设备、回环、跨机声音和豆包识别检查，不沿用“旧版本已通过”的结论。

## BlackHole 0.7.1 校验

本次下载文件 `BlackHole2ch-0.7.1.pkg` 的 SHA-256：

```text
57b540f27a3e29c37e310e01bee0fdfab76733087e47f997ef9dccf851400dcf
```

下载后在 Mac 核对：

```sh
shasum -a 256 "$HOME/Downloads/BlackHole2ch-0.7.1.pkg"
pkgutil --check-signature "$HOME/Downloads/BlackHole2ch-0.7.1.pkg"
spctl --assess --type install --verbose=2 "$HOME/Downloads/BlackHole2ch-0.7.1.pkg"
```

此哈希是本次安装介质的复现值，不是对未来下载的自动信任。若不一致，先确认官网下载、版本和签名，不跳过校验直接执行。安装脚本核对签名、Gatekeeper 评估和 BlackHole 2ch 包标识，不对未来版本作可用性保证；安装包结构变更时可能需要先更新脚本。

已安装驱动可复核：

```sh
codesign --verify --deep --strict --verbose=2 /Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver
```

本次包签名、公证评估和驱动代码签名检查均通过。SonoBus Mac 安装介质也检查过签名和公证，但没有在本次机器上安装并运行，不能据此宣称音频传输通过。

## 官方能力说明

- [ToDesk 麦克风映射](https://www.todesk.com/helpcenter/solo-376.html)：页面更新于 2026-11-04，当前仅支持 Windows 被控端。
- [ToDesk 协作模式](https://todesk.com/helpcenter/solo-461.html)：页面更新于 2026-10-27，说明一对一协作入口及语音功能合并。
- [ToDesk 协作权益](https://www.todesk.com/special_multi-usercollaboration.html)：入口可用性与账号版本相关。
- [ToDesk 远程声音](https://www.todesk.com/faq/24.html)：被控端输出回传方向说明。
- [SonoBus 用户指南](https://www.sonobus.net/sonobus_userguide.html)：设备、入群、连接、缓冲及不加密限制。
- [VDO.Ninja 参数](https://docs.vdo.ninja/advanced-settings/setup-parameters)：发送、接收、仅麦克风和密码提示等候选配置。
