import CoreAudio
import Foundation

// Read-only diagnostics. Does not request recording or change any audio default.
let element = kAudioObjectPropertyElementMain
let system = AudioObjectID(kAudioObjectSystemObject)

func property(_ selector: AudioObjectPropertySelector,
              _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
}

func text(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String {
    guard device != kAudioObjectUnknown else { return "<none>" }
    var address = property(selector)
    var value: CFString = "" as CFString
    var size = UInt32(MemoryLayout<CFString>.size)
    let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
    return status == noErr ? value as String : "<error \(status)>"
}

func number(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector,
            _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> String {
    var address = property(selector, scope)
    var value: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
    return status == noErr ? String(value) : "<error \(status)>"
}

func channels(_ device: AudioDeviceID, _ scope: AudioObjectPropertyScope) -> String {
    var address = property(kAudioDevicePropertyStreamConfiguration, scope)
    var size: UInt32 = 0
    var status = AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size)
    guard status == noErr else { return "<error \(status)>" }
    guard size >= MemoryLayout<AudioBufferList>.size else { return "0" }
    let memory = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
    defer { memory.deallocate() }
    status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, memory)
    guard status == noErr else { return "<error \(status)>" }
    let list = UnsafeMutableAudioBufferListPointer(memory.assumingMemoryBound(to: AudioBufferList.self))
    return String(list.reduce(UInt32(0)) { $0 + $1.mNumberChannels })
}

guard CommandLine.arguments.count == 1 else {
    fputs("用法：audio_diag（只读诊断，无切换设备功能）\n", stderr)
    exit(64)
}
for (name, selector) in [
    ("defaultInput", kAudioHardwarePropertyDefaultInputDevice),
    ("defaultOutput", kAudioHardwarePropertyDefaultOutputDevice),
    ("systemOutput", kAudioHardwarePropertyDefaultSystemOutputDevice)
] {
    print("\(name)ID=\(number(system, selector))")
}
var address = property(kAudioHardwarePropertyDevices)
var size: UInt32 = 0
var status = AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size)
guard status == noErr else {
    fputs("AudioObjectGetPropertyDataSize failed: \(status)\n", stderr)
    exit(1)
}
var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
if size > 0 {
    status = devices.withUnsafeMutableBytes { AudioObjectGetPropertyData(system, &address, 0, nil, &size, $0.baseAddress!) }
}
guard status == noErr else {
    fputs("AudioObjectGetPropertyData failed: \(status)\n", stderr)
    exit(1)
}
for device in devices.prefix(Int(size) / MemoryLayout<AudioDeviceID>.size) {
    print("id=\(device) uid=\(text(device, kAudioDevicePropertyDeviceUID)) name=\(text(device, kAudioObjectPropertyName)) " +
        "manufacturer=\(text(device, kAudioObjectPropertyManufacturer)) " +
        "inputChannels=\(channels(device, kAudioDevicePropertyScopeInput)) outputChannels=\(channels(device, kAudioDevicePropertyScopeOutput)) " +
        "hidden=\(number(device, kAudioDevicePropertyIsHidden)) alive=\(number(device, kAudioDevicePropertyDeviceIsAlive)) " +
        "defaultCapableInput=\(number(device, kAudioDevicePropertyDeviceCanBeDefaultDevice, kAudioDevicePropertyScopeInput)) " +
        "defaultCapableOutput=\(number(device, kAudioDevicePropertyDeviceCanBeDefaultDevice, kAudioDevicePropertyScopeOutput))")
}
