import CoreAudio
import Darwin
import Foundation

// Stores device UIDs, never transient CoreAudio device IDs. No driver installation.
private let audioSystem = AudioObjectID(kAudioObjectSystemObject)
private let blackHoleUID = "BlackHole2ch_UID"
private let defaults: [(String, AudioObjectPropertySelector)] = [
    ("input", kAudioHardwarePropertyDefaultInputDevice),
    ("output", kAudioHardwarePropertyDefaultOutputDevice),
    ("systemOutput", kAudioHardwarePropertyDefaultSystemOutputDevice)
]

struct RouteError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

func address(_ selector: AudioObjectPropertySelector,
             _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
}

func readUInt(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector,
              _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) throws -> UInt32 {
    var property = address(selector, scope)
    var value: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    let status = AudioObjectGetPropertyData(id, &property, 0, nil, &size, &value)
    guard status == noErr else { throw RouteError(message: "读取音频属性失败：device=\(id), status=\(status)") }
    return value
}

func readString(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> String {
    guard id != kAudioObjectUnknown else { return "" }
    var property = address(selector)
    var value: CFString = "" as CFString
    var size = UInt32(MemoryLayout<CFString>.size)
    let status = AudioObjectGetPropertyData(id, &property, 0, nil, &size, &value)
    guard status == noErr else { throw RouteError(message: "读取音频设备名称或 UID 失败：device=\(id), status=\(status)") }
    return value as String
}

func allDevices() throws -> [AudioDeviceID] {
    var property = address(kAudioHardwarePropertyDevices)
    var size: UInt32 = 0
    var status = AudioObjectGetPropertyDataSize(audioSystem, &property, 0, nil, &size)
    guard status == noErr else { throw RouteError(message: "无法枚举音频设备：status=\(status)") }
    guard size > 0 else { return [] }
    var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    status = devices.withUnsafeMutableBytes { bytes in
        AudioObjectGetPropertyData(audioSystem, &property, 0, nil, &size, bytes.baseAddress!)
    }
    guard status == noErr else { throw RouteError(message: "无法读取音频设备列表：status=\(status)") }
    return Array(devices.prefix(Int(size) / MemoryLayout<AudioDeviceID>.size))
}

func channelCount(_ id: AudioDeviceID, _ scope: AudioObjectPropertyScope) throws -> UInt32 {
    var property = address(kAudioDevicePropertyStreamConfiguration, scope)
    var size: UInt32 = 0
    var status = AudioObjectGetPropertyDataSize(id, &property, 0, nil, &size)
    guard status == noErr else { throw RouteError(message: "无法读取声道数：device=\(id), status=\(status)") }
    guard size >= MemoryLayout<AudioBufferList>.size else { return 0 }
    let memory = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
    defer { memory.deallocate() }
    status = AudioObjectGetPropertyData(id, &property, 0, nil, &size, memory)
    guard status == noErr else { throw RouteError(message: "无法读取声道配置：device=\(id), status=\(status)") }
    return UnsafeMutableAudioBufferListPointer(memory.assumingMemoryBound(to: AudioBufferList.self))
        .reduce(UInt32(0)) { $0 + $1.mNumberChannels }
}

func capable(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) throws -> Bool {
    guard try readUInt(id, kAudioDevicePropertyDeviceIsAlive) != 0 else { return false }
    let scope = selector == kAudioHardwarePropertyDefaultInputDevice ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput
    guard try channelCount(id, scope) > 0 else { return false }
    let capability = selector == kAudioHardwarePropertyDefaultSystemOutputDevice
        ? kAudioDevicePropertyDeviceCanBeDefaultSystemDevice : kAudioDevicePropertyDeviceCanBeDefaultDevice
    return try readUInt(id, capability, scope) != 0
}

func findDevice(_ uid: String, _ selector: AudioObjectPropertySelector) throws -> AudioDeviceID? {
    guard !uid.isEmpty else { return nil }
    for device in try allDevices() {
        if try readString(device, kAudioDevicePropertyDeviceUID) == uid, try capable(device, selector) { return device }
    }
    return nil
}

func select(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector) throws {
    guard try readUInt(audioSystem, selector) != device else { return }
    var property = address(selector)
    var value = device
    let status = AudioObjectSetPropertyData(audioSystem, &property, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &value)
    guard status == noErr else { throw RouteError(message: "切换音频设备失败：device=\(device), status=\(status)") }
    for _ in 0..<20 {
        if try readUInt(audioSystem, selector) == device { return }
        usleep(50_000)
    }
    throw RouteError(message: "音频设备切换后校验失败：device=\(device)。请运行 status 检查当前状态。")
}

func printStatus() throws {
    for (name, selector) in defaults {
        let id = try readUInt(audioSystem, selector)
        print("\(name): id=\(id) name=\(try readString(id, kAudioObjectPropertyName)) uid=\(try readString(id, kAudioDevicePropertyDeviceUID))")
    }
}

func saveState(_ url: URL) throws {
    if FileManager.default.fileExists(atPath: url.path) {
        _ = try loadState(url) // Do not silently accept an unreadable or malformed recovery file.
        print("保留已有恢复快照：\(url.path)")
        return
    }
    var state: [String: String] = [:]
    for (name, selector) in defaults {
        state[name] = try readString(readUInt(audioSystem, selector), kAudioDevicePropertyDeviceUID)
    }
    guard state["output"] != blackHoleUID else {
        throw RouteError(message: "当前输出已是 BlackHole，且没有恢复快照。请先在系统声音设置选择原播放设备，再运行 save 或 enable。")
    }
    let data = try JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys])
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    // O_EXCL protects an existing snapshot even when two launchers run together.
    let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
    guard fd >= 0 else {
        if errno == EEXIST { _ = try loadState(url); print("保留已有恢复快照：\(url.path)"); return }
        throw RouteError(message: "无法创建恢复快照：\(String(cString: strerror(errno)))")
    }
    let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    do {
        try file.write(contentsOf: data)
        try file.synchronize()
        try file.close()
    } catch {
        try? file.close()
        try? FileManager.default.removeItem(at: url)
        throw error
    }
    print("已保存原始音频默认设备：\(url.path)")
}

func loadState(_ url: URL) throws -> [String: String] {
    guard let state = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: String],
          defaults.allSatisfy({ state[$0.0] != nil }) else {
        throw RouteError(message: "恢复快照格式错误：需要 input、output、systemOutput 三个 UID 字符串。")
    }
    return state
}

func enable(_ url: URL, input: Bool, output: Bool) throws {
    var targets: [(AudioDeviceID, AudioObjectPropertySelector)] = []
    for (requested, selector) in [(input, kAudioHardwarePropertyDefaultInputDevice), (output, kAudioHardwarePropertyDefaultOutputDevice)] where requested {
        guard let device = try findDevice(blackHoleUID, selector) else {
            throw RouteError(message: "BlackHole 2ch 未加载，或不支持所需的输入/输出。请先安装官方驱动并检查 list。")
        }
        targets.append((device, selector))
    }
    try saveState(url)
    for (device, selector) in targets { try select(device, selector) }
    print("已切换所请求的 BlackHole 输入/输出。系统提示音输出未修改。")
}

func restore(_ url: URL, outputOnly: Bool) throws {
    let state = try loadState(url)
    var targets: [(String, AudioDeviceID, AudioObjectPropertySelector)] = []
    // Resolve everything before changing a default to avoid predictable partial restores.
    for (name, selector) in defaults {
        if outputOnly && name != "output" { continue }
        let uid = state[name]!
        if name == "input" && uid.isEmpty {
            print("原始快照没有输入设备；保留当前输入。需要取消虚拟输入时请在系统设置手动选择其他输入。")
            continue
        }
        if let device = try findDevice(uid, selector) {
            targets.append((name, device, selector))
        } else if name == "output", let fallback = try findDevice(state["systemOutput"]!, selector) {
            print("原播放设备不可用（UID=\(uid)）；改用快照中的系统提示音输出设备：\(try readString(fallback, kAudioObjectPropertyName))")
            targets.append((name, fallback, selector))
        } else {
            throw RouteError(message: "无法恢复 \(name)：快照设备当前不可用（UID=\(uid)）。请手动连接/选择可用设备；未执行此次恢复。")
        }
    }
    for (_, device, selector) in targets { try select(device, selector) }
    print(outputOnly ? "声音播放已恢复；输入和系统提示音输出保持当前设置。" : "已恢复快照中可还原的音频默认设备。")
}

let usage = """
用法：audio_route [status|list|save|enable|restore-output|restore] [--state PATH]
  status          只读：当前默认输入、播放输出、系统提示音输出（默认命令）
  list            只读：列出设备及输入/输出声道
  save            保存原始 UID；已有快照不覆盖
  enable          自动保存快照，然后将默认输入和播放输出切换为 BlackHole 2ch
  restore-output  恢复播放输出；原设备不可用时回退快照中的系统输出
  restore         还原全部可还原的默认设备；原本无输入时保留当前输入
  --state PATH    使用指定恢复快照，默认在可执行文件旁的 audio-before.json
旧参数兼容：--save --blackhole-input --blackhole-output --restore-output --restore
快照不会自动删除；新的一轮配置请在确认已恢复后手动归档快照。
"""

do {
    var arguments = Array(CommandLine.arguments.dropFirst())
    var stateURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        .deletingLastPathComponent().appendingPathComponent("audio-before.json")
    if let index = arguments.firstIndex(of: "--state") {
        guard index + 1 < arguments.count else { throw RouteError(message: "--state 需要一个文件路径。") }
        stateURL = URL(fileURLWithPath: arguments[index + 1]).standardizedFileURL
        arguments.removeSubrange(index...(index + 1))
    }
    if arguments.contains("--help") || arguments.contains("-h") { print(usage); exit(0) }
    let commands = ["status", "list", "save", "enable", "restore-output", "restore"]
    let legacy = ["--save", "--blackhole-input", "--blackhole-output", "--restore-output", "--restore"]
    guard arguments.allSatisfy({ commands.contains($0) || legacy.contains($0) }) else { throw RouteError(message: usage) }
    let modern = arguments.filter { commands.contains($0) }
    guard modern.count <= 1, modern.isEmpty || arguments.count == 1 else { throw RouteError(message: "不能组合多个命令。\n" + usage) }
    if let command = modern.first {
        switch command {
        case "status": try printStatus()
        case "list":
            for device in try allDevices() {
                print("id=\(device) name=\(try readString(device, kAudioObjectPropertyName)) uid=\(try readString(device, kAudioDevicePropertyDeviceUID)) inputChannels=\(try channelCount(device, kAudioDevicePropertyScopeInput)) outputChannels=\(try channelCount(device, kAudioDevicePropertyScopeOutput))")
            }
        case "save": try saveState(stateURL)
        case "enable": try enable(stateURL, input: true, output: true); try printStatus()
        case "restore-output": try restore(stateURL, outputOnly: true); try printStatus()
        case "restore": try restore(stateURL, outputOnly: false); try printStatus()
        default: break
        }
    } else if !arguments.isEmpty {
        let restoring = arguments.contains("--restore") || arguments.contains("--restore-output")
        let enabling = arguments.contains("--blackhole-input") || arguments.contains("--blackhole-output")
        guard !(restoring && enabling), !(arguments.contains("--restore") && arguments.contains("--restore-output")) else {
            throw RouteError(message: "不能同时启用和恢复，或组合两种恢复命令。")
        }
        if enabling { try enable(stateURL, input: arguments.contains("--blackhole-input"), output: arguments.contains("--blackhole-output")) }
        else if arguments.contains("--save") { try saveState(stateURL) }
        if restoring { try restore(stateURL, outputOnly: arguments.contains("--restore-output")) }
        try printStatus()
    } else { try printStatus() }
} catch {
    fputs("错误：\(error.localizedDescription)\n", stderr)
    exit(1)
}
