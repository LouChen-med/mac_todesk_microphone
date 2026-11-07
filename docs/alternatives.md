# 配置方案与替代传输

BlackHole 是 Mac 内部的虚拟音频线，不负责把 Windows 麦克风通过网络传过来。选择传输方案时，仍使用“Mac 电平随 Windows 讲话变化 → 豆包识别测试句”作为验收标准。

## 方案比较

| 方案 | 声音路径 | 本次状态 | 适用条件 |
| --- | --- | --- | --- |
| ToDesk 直接麦克风映射 | Windows 麦克风 → ToDesk 虚拟输入 | 对被控 Mac 不适用 | 官方目前限定 Windows 被控端 |
| ToDesk 协作语音 + BlackHole | Windows 麦克风 → 协作语音 → Mac 播放 → BlackHole | Mac 回环通过，跨机待验证 | 两端有协作入口及相应权益 |
| SonoBus + BlackHole | Windows 麦克风 → SonoBus → Mac 的 BlackHole 输出 | 候选；安装包已检查，未安装连接 | 愿意增加音频传输软件，且接受其加密限制 |
| VDO.Ninja + BlackHole | Windows 浏览器麦克风 → WebRTC → Mac 浏览器播放 → BlackHole | 候选，未测试网络和浏览器兼容性 | 两端浏览器可用且网络允许连接 |
| 聚合设备包装 ToDesk 驱动 | 尝试把 ToDesk 输入通道包装为普通输入 | 仅研究，未实施 | 需另做 CoreAudio 验证，不保证能接收远端麦克风 |

ToDesk 映射能力依据[官方映射说明](https://www.todesk.com/helpcenter/solo-376.html)。它与协作语音是不同功能。官方[远程声音](https://www.todesk.com/faq/24.html)说明的方向也不能作为 Windows 麦克风已经接通的证据。

## A. ToDesk 协作语音 + BlackHole

这是现有 ToDesk 工作流的优先验证路径。

1. Mac 安装 BlackHole，并运行仓库的 `audio_route enable`。
2. Windows 的 ToDesk 会话打开“悬浮球 → 互动 → 协作成员”，邀请 Mac 加入。
3. Windows 开启实体麦克风；Mac 关闭自己的协作麦克风。
4. 用只读电平模式确认 Windows 讲话进入 BlackHole，然后验证豆包。
5. 结束后执行 `audio_route restore-output`。

完整步骤见[配置文档](setup.md)。语音入口已合并到[协作模式](https://todesk.com/helpcenter/solo-461.html)；入口缺失时核对[版本与权益](https://www.todesk.com/special_multi-usercollaboration.html)。本项目没有验证该账号的协作音频传输已经可用。

## B. SonoBus + BlackHole

**验证状态：**本次仅下载 Mac 1.7.2 安装介质，检查签名、公证和解包内容，并研究相关源码；没有完成安装、双端加入或传输测试。以下为待验证配置，不是已跑通的结果。

参考 [SonoBus 官方指南](https://www.sonobus.net/sonobus_userguide.html)和[下载链接](downloads.md)。配置思路：

1. Windows 与 Mac 安装 SonoBus 1.7.2。
2. Windows 的音频输入选择自己的实体麦克风。使用不与其他群重名的私有群名，设置群密码；Mac 加入同一群。
3. Mac 的 SonoBus 输出选择 `BlackHole 2ch`；Mac 默认输入选择 `BlackHole 2ch`。
4. Mac 关闭自身发送，确保从 BlackHole 收到的音频不会再次传回群里。Windows 使用耳机，并关闭不需要的本机监听。
5. 先看 Windows 输入电平，再看 Mac 收到的成员电平，最后运行本仓库的 BlackHole 只读电平检查和豆包识别测试。
6. 有断续时先检查网络质量、收发静音和音频设备，再按官方指南调整接收缓冲。不要一开始就改大量参数。

如果 SonoBus 能将自己的输出独立指定为 BlackHole，可以让 Mac 系统普通输出继续使用扬声器，以减少其他应用声音进入语音输入；这一路由在本项目中尚未验证。使用 `audio_route enable` 的简单方案则会把所有普通播放送入 BlackHole。

**SonoBus 官方明确说明音频数据目前不加密。群名和密码是入群控制，不能当作音频传输加密。** 涉及敏感内容时，应先选用合适的传输方式。[官方说明](https://www.sonobus.net/)

## C. VDO.Ninja 浏览器音频 + BlackHole

**验证状态：**仅形成候选配置，没有测试当前 Windows/Mac 浏览器、网络可达性、跨网延迟或中国网络环境。

在两端自行生成一组相同的随机流标识和口令，不复用公开示例值。以下 URL 仅展示参数结构：

```text
Windows 发送：
https://vdo.ninja/?push=REPLACE_WITH_RANDOM_STREAM_ID&miconly&password

Mac 接收：
https://vdo.ninja/?view=REPLACE_WITH_RANDOM_STREAM_ID&novideo&password
```

1. Windows 打开发送页，允许浏览器使用实体麦克风；在页面提示时输入新口令。
2. Mac 打开接收页，输入相同口令，按页面要求点击开始播放或解除浏览器自动播放限制。
3. Mac 执行 `audio_route enable`，或在支持独立输出选择的浏览器中将此页面输出指定到 BlackHole，并将默认输入设为 BlackHole。
4. Windows 轮流讲话和静默，运行 BlackHole 只读电平检查，再测试豆包。
5. 测试结束关闭发送与接收页面，并恢复 Mac 输出。

`push`/`view` 指定发送和接收流；`miconly` 限定发送音频，`novideo` 关闭接收视频；不带值的 `password` 让页面提示输入口令，避免把实际口令直接写入仓库示例。[官方参数概览](https://docs.vdo.ninja/advanced-settings/setup-parameters)、[接收端视频参数](https://docs.vdo.ninja/advanced-settings/video-parameters/and-novideo)、[密码参数](https://docs.vdo.ninja/advanced-settings/setup-parameters/and-password)

浏览器必须保持运行；网络、防火墙、自动播放策略和浏览器的输出设备支持都可能影响结果。没有实测前不承诺该方案可替代 ToDesk。

## D. 聚合设备包装 ToDesk 驱动

本次看到 ToDesk 设备有输入通道，但不具备默认输入能力，因此研究过 CoreAudio 聚合设备或包装设备的可能性。没有建立或运行该方案，没有证据表明 ToDesk 的这两个输入通道承载 Windows 麦克风。

聚合设备只能改变本机设备组合，不能补齐上游未提供的声音传输。仓库不把这一设想作为可直接使用的修复脚本；若后续研究，应先证明通道中有真实远端音频，再验证系统输入可见性和豆包兼容性。
