import Carbon
import Darwin
import Foundation

// Input-source selection is independent of audio routing and Doubao preferences.
private let doubaoID = "com.bytedance.inputmethod.doubaoime.pinyin"

struct InputSourceError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

func string(_ source: TISInputSource, _ key: CFString) -> String {
    guard let pointer = TISGetInputSourceProperty(source, key) else { return "" }
    return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
}

func boolean(_ source: TISInputSource, _ key: CFString) -> Bool {
    guard let pointer = TISGetInputSourceProperty(source, key) else { return false }
    return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue())
}

func sources() -> [TISInputSource] {
    TISCreateInputSourceList(nil, true).takeRetainedValue() as! [TISInputSource]
}

func currentID() -> String {
    string(TISCopyCurrentKeyboardInputSource().takeRetainedValue(), kTISPropertyInputSourceID)
}

func describe(_ source: TISInputSource) -> String {
    "id=\(string(source, kTISPropertyInputSourceID)) " +
        "enabled=\(boolean(source, kTISPropertyInputSourceIsEnabled)) " +
        "selected=\(boolean(source, kTISPropertyInputSourceIsSelected)) " +
        "selectable=\(boolean(source, kTISPropertyInputSourceIsSelectCapable))"
}

func status() {
    print("currentInputSourceID=\(currentID())")
    if let source = sources().first(where: { string($0, kTISPropertyInputSourceID) == doubaoID }) {
        print("doubao: \(describe(source))")
    } else { print("doubao: 未找到已安装的豆包拼音输入法。") }
}

func loadState(_ url: URL) throws -> String {
    guard let state = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: String],
          let sourceID = state["inputSourceID"], !sourceID.isEmpty else {
        throw InputSourceError(message: "输入法恢复快照格式错误：需要非空 inputSourceID 字符串。")
    }
    return sourceID
}

func saveState(_ sourceID: String, _ url: URL) throws {
    guard !sourceID.isEmpty else { throw InputSourceError(message: "无法读取当前输入法；没有切换。") }
    if FileManager.default.fileExists(atPath: url.path) {
        _ = try loadState(url)
        print("保留已有输入法恢复快照：\(url.path)")
        return
    }
    let data = try JSONSerialization.data(withJSONObject: ["inputSourceID": sourceID], options: [.prettyPrinted, .sortedKeys])
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
    guard fd >= 0 else {
        if errno == EEXIST { _ = try loadState(url); print("保留已有输入法恢复快照：\(url.path)"); return }
        throw InputSourceError(message: "无法创建输入法恢复快照：\(String(cString: strerror(errno)))")
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
    print("已保存原输入法：\(sourceID)")
}

func target(_ sourceID: String) throws -> TISInputSource {
    guard let source = sources().first(where: { string($0, kTISPropertyInputSourceID) == sourceID }),
          boolean(source, kTISPropertyInputSourceIsEnabled),
          boolean(source, kTISPropertyInputSourceIsSelectCapable) else {
        throw InputSourceError(message: "输入法未安装、未启用或不可选择：\(sourceID)。请先在 macOS 键盘设置中添加它。")
    }
    return source
}

func select(_ source: TISInputSource, _ sourceID: String) throws {
    let result = TISSelectInputSource(source)
    guard result == noErr else { throw InputSourceError(message: "切换输入法失败：status=\(result)。") }
    for _ in 0..<20 {
        if currentID() == sourceID { return }
        usleep(50_000)
    }
    throw InputSourceError(message: "切换后当前输入法与目标不一致；请运行 status 检查，未报告成功。")
}

let usage = """
用法：input_source [status|list|select-doubao|restore] [--state PATH]
  status          只读：当前输入法和豆包的启用/选中状态（默认）
  list            只读：列出已安装输入源的 ID 和状态
  select-doubao   保存原输入法 ID，再选择已启用的豆包拼音
  restore         恢复快照中已启用且可选的原输入法
  --state PATH    指定快照；默认可执行文件旁的 input-before.json
已有快照不会覆盖或自动删除。此工具不修改音频、豆包热键或系统权限。
"""

do {
    var arguments = Array(CommandLine.arguments.dropFirst())
    var stateURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        .deletingLastPathComponent().appendingPathComponent("input-before.json")
    if let index = arguments.firstIndex(of: "--state") {
        guard index + 1 < arguments.count else { throw InputSourceError(message: "--state 需要文件路径。") }
        stateURL = URL(fileURLWithPath: arguments[index + 1]).standardizedFileURL
        arguments.removeSubrange(index...(index + 1))
    }
    if arguments == ["--help"] || arguments == ["-h"] { print(usage); exit(0) }
    guard arguments.count <= 1 else { throw InputSourceError(message: usage) }
    switch arguments.first ?? "status" {
    case "status": status()
    case "list": for source in sources() { print(describe(source)) }
    case "select-doubao":
        let source = try target(doubaoID)
        if currentID() == doubaoID {
            print("当前已选择豆包拼音，没有改动。")
        } else {
            try saveState(currentID(), stateURL)
            try select(source, doubaoID)
            print("已选择豆包拼音输入法。")
        }
        status()
    case "restore":
        let sourceID = try loadState(stateURL)
        try select(target(sourceID), sourceID)
        print("已恢复原输入法：\(sourceID)")
        status()
    default: throw InputSourceError(message: usage)
    }
} catch {
    fputs("错误：\(error.localizedDescription)\n", stderr)
    exit(1)
}
