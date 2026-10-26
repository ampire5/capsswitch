// capsswitch — Caps Lock toggles between the two most recently used keyboard layouts.
// Caps Lock is remapped to F18 via hidutil (no Caps state, no system delay);
// F18 is a Carbon hot key, so no Accessibility / Input Monitoring permission is needed.
import AppKit
import Carbon

let capsUsage = 0x700000039, f18Usage = 0x70000006D

// `capsswitch indicator on|off`: the macOS language bubble next to the text cursor.
// A global preference; apps pick it up when they are relaunched.
let args = CommandLine.arguments
if args.count > 1, args[1] == "indicator" {
    let key = "TSMLanguageIndicatorEnabled" as CFString, app = kCFPreferencesAnyApplication
    switch args.count > 2 ? args[2] : "" {
    case "on": CFPreferencesSetAppValue(key, nil, app)  // removing the key restores the default (shown)
    case "off": CFPreferencesSetAppValue(key, kCFBooleanFalse, app)
    case "": break
    default: print("usage: capsswitch indicator [on|off]"); exit(2)
    }
    CFPreferencesAppSynchronize(app)
    let shown = CFPreferencesCopyAppValue(key, app) as? Bool ?? true
    print("indicator: \(shown ? "on" : "off")")
    exit(0)
}

func hidutil(_ json: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
    p.arguments = ["property", "--set", json]
    p.standardOutput = FileHandle.nullDevice
    try? p.run(); p.waitUntilExit()
}
func remapCaps(_ on: Bool) {
    hidutil(on ? #"{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":\#(capsUsage),"HIDKeyboardModifierMappingDst":\#(f18Usage)}]}"#
               : #"{"UserKeyMapping":[]}"#)
}

func prop<T>(_ s: TISInputSource, _ k: CFString) -> T? {
    TISGetInputSourceProperty(s, k).map { Unmanaged<AnyObject>.fromOpaque($0).takeUnretainedValue() as! T }
}
func sourceID(_ s: TISInputSource) -> String { prop(s, kTISPropertyInputSourceID) ?? "" }
func sourceName(_ s: TISInputSource) -> String { prop(s, kTISPropertyLocalizedName) ?? "" }
func current() -> TISInputSource { TISCopyCurrentKeyboardInputSource().takeRetainedValue() }
func selectable() -> [TISInputSource] {
    let filter = [kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource!,
                  kTISPropertyInputSourceIsSelectCapable: true] as CFDictionary
    return TISCreateInputSourceList(filter, false).takeRetainedValue() as! [TISInputSource]
}

// Two most recent layouts as [id, name], newest first. Persisted so the pair survives restarts;
// the name is a fallback because macOS sometimes re-registers third-party layouts under a new ID.
let defaults = UserDefaults(suiteName: "com.github.ampire5.capsswitch")!
var history = (defaults.array(forKey: "history") as? [[String]] ?? []).filter { $0.count == 2 }
func same(_ s: TISInputSource, _ entry: [String]) -> Bool {
    sourceID(s) == entry[0] || (!entry[1].isEmpty && sourceName(s) == entry[1])
}
func noteCurrent() {
    let cur = current()
    history.removeAll { same(cur, $0) }
    history.insert([sourceID(cur), sourceName(cur)], at: 0)
    history = Array(history.prefix(2))
    defaults.set(history, forKey: "history")
}
noteCurrent()

func toggle() {
    let sources = selectable()
    let cur = current()
    // Previous layout if it is still enabled, otherwise any other enabled layout.
    let target = history.lazy.filter { !same(cur, $0) }
        .compactMap { entry in sources.first { same($0, entry) } }.first
        ?? sources.first { sourceID($0) != sourceID(cur) }
    guard let target else { return }
    let t = Date()
    TISSelectInputSource(target)
    if args.contains("-v") {
        print("\(sourceName(cur)) -> \(sourceName(target)) in \(Int(Date().timeIntervalSince(t) * 1000)) ms"); fflush(stdout)
    }
}

DistributedNotificationCenter.default().addObserver(
    forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
    object: nil, queue: .main) { _ in noteCurrent() }

var hotKeyRef: EventHotKeyRef?
var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in toggle(); return noErr }, 1, &spec, nil, nil)
RegisterEventHotKey(UInt32(kVK_F18), 0, EventHotKeyID(signature: OSType(0x4353_5743), id: 1),
                    GetApplicationEventTarget(), 0, &hotKeyRef)

remapCaps(true)
var signalSources: [DispatchSourceSignal] = []
for sig in [SIGINT, SIGTERM, SIGHUP] {
    signal(sig, SIG_IGN)
    let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    src.setEventHandler { remapCaps(false); exit(0) }
    src.resume()
    signalSources.append(src)
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
app.run()
