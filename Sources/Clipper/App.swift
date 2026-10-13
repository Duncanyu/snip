import AppKit
import Carbon
import Combine
import ScreenCaptureKit
import SwiftUI

enum CaptureResolution: String, Codable, CaseIterable, Identifiable {
    case half, normal, retina, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .half: "Half (0.5× logical)"
        case .normal: "Normal (1× logical)"
        case .retina: "Retina (full render resolution)"
        case .custom: "Custom output size"
        }
    }

}

private enum QualityPreset: String, CaseIterable, Identifiable {
    case automatic, performance, balanced, quality, maximum

    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .performance: "Performance"
        case .balanced: "Balanced"
        case .quality: "Quality"
        case .maximum: "Maximum"
        }
    }

    var values: (fps: Int, resolution: CaptureResolution, bitrate: Int) {
        switch self {
        case .automatic: (60, .retina, 0)
        case .performance: (30, .normal, 8)
        case .balanced: (60, .normal, 25)
        case .quality: (60, .retina, 50)
        case .maximum: (120, .retina, 100)
        }
    }

    var summary: String {
        let v = values
        let resolution = switch v.resolution {
        case .half: "Half"
        case .normal: "Normal"
        case .retina: "Retina"
        case .custom: "Custom"
        }
        let bitrate = v.bitrate == 0 ? "Auto" : "\(v.bitrate) Mbps"
        return "\(title) · \(v.fps) FPS · \(resolution) · \(bitrate)"
    }
}

private let bitrateSteps = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 14, 16, 18, 20,
                            25, 30, 35, 40, 45, 50, 60, 70, 80, 90, 100, 120, 140, 160, 180, 200]

struct CaptureSettings: Codable, Equatable {
    var clipDuration = 30
    var fps = 60
    var resolution: CaptureResolution = .retina
    var memoryLimitMB = 1024
    var displayID: CGDirectDisplayID?
    var includeAudio = true
    var excludeAppAudio = true
    var showInMenuBar = true
    var menuBarPreferenceInitialized = false
    // Compatibility for settings data and older callers.
    var showInDock: Bool {
        get { showInMenuBar }
        set { showInMenuBar = newValue }
    }
    var customWidth = 2560
    var customHeight = 1440
    var bitrateMbps = 0
    var clipName = "Clip"
    var clipDirectoryPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Movies/Clips", isDirectory: true).path
    var playSoundOnSave = true
    var soundPreferenceInitialized = false
    var hotkeyKeyCode = UInt32(kVK_ANSI_9)
    var hotkeyModifiers = UInt32(cmdKey | shiftKey)
    var hotkeyLabel = "⌘⇧9"
    var pauseHotkeyKeyCode = UInt32(kVK_ANSI_P)
    var pauseHotkeyModifiers = UInt32(cmdKey | optionKey)
    var pauseHotkeyLabel = "⌘⌥P"

    init() {}

    private enum CodingKeys: String, CodingKey {
        case clipDuration, fps, resolution, memoryLimitMB, displayID, includeAudio, excludeAppAudio
        case showInMenuBar, menuBarPreferenceInitialized
        case customWidth, customHeight, bitrateMbps, clipName, clipDirectoryPath, playSoundOnSave, soundPreferenceInitialized
        case hotkeyKeyCode, hotkeyModifiers, hotkeyLabel
        case pauseHotkeyKeyCode, pauseHotkeyModifiers, pauseHotkeyLabel
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case showInDock
    }

    init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        clipDuration = try values.decodeIfPresent(Int.self, forKey: .clipDuration) ?? clipDuration
        fps = try values.decodeIfPresent(Int.self, forKey: .fps) ?? fps
        resolution = try values.decodeIfPresent(CaptureResolution.self, forKey: .resolution) ?? resolution
        memoryLimitMB = try values.decodeIfPresent(Int.self, forKey: .memoryLimitMB) ?? memoryLimitMB
        displayID = try values.decodeIfPresent(CGDirectDisplayID.self, forKey: .displayID)
        includeAudio = try values.decodeIfPresent(Bool.self, forKey: .includeAudio) ?? includeAudio
        excludeAppAudio = try values.decodeIfPresent(Bool.self, forKey: .excludeAppAudio) ?? excludeAppAudio
        if let value = try values.decodeIfPresent(Bool.self, forKey: .showInMenuBar) {
            showInMenuBar = value
        } else {
            let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
            if let oldValue = try legacy.decodeIfPresent(Bool.self, forKey: .showInDock) {
                showInMenuBar = oldValue
            }
        }
        menuBarPreferenceInitialized = try values.decodeIfPresent(Bool.self, forKey: .menuBarPreferenceInitialized) ?? false
        customWidth = try values.decodeIfPresent(Int.self, forKey: .customWidth) ?? customWidth
        customHeight = try values.decodeIfPresent(Int.self, forKey: .customHeight) ?? customHeight
        bitrateMbps = try values.decodeIfPresent(Int.self, forKey: .bitrateMbps) ?? bitrateMbps
        clipName = try values.decodeIfPresent(String.self, forKey: .clipName) ?? clipName
        clipDirectoryPath = try values.decodeIfPresent(String.self, forKey: .clipDirectoryPath) ?? clipDirectoryPath
        playSoundOnSave = try values.decodeIfPresent(Bool.self, forKey: .playSoundOnSave) ?? playSoundOnSave
        soundPreferenceInitialized = try values.decodeIfPresent(Bool.self, forKey: .soundPreferenceInitialized) ?? false
        hotkeyKeyCode = try values.decodeIfPresent(UInt32.self, forKey: .hotkeyKeyCode) ?? hotkeyKeyCode
        hotkeyModifiers = try values.decodeIfPresent(UInt32.self, forKey: .hotkeyModifiers) ?? hotkeyModifiers
        hotkeyLabel = try values.decodeIfPresent(String.self, forKey: .hotkeyLabel) ?? hotkeyLabel
        pauseHotkeyKeyCode = try values.decodeIfPresent(UInt32.self, forKey: .pauseHotkeyKeyCode) ?? pauseHotkeyKeyCode
        pauseHotkeyModifiers = try values.decodeIfPresent(UInt32.self, forKey: .pauseHotkeyModifiers) ?? pauseHotkeyModifiers
        pauseHotkeyLabel = try values.decodeIfPresent(String.self, forKey: .pauseHotkeyLabel) ?? pauseHotkeyLabel
    }

    func normalized() -> Self {
        var value = self
        value.clipDuration = min(max(clipDuration, 1), 3600)
        value.fps = [30, 60, 120].contains(fps) ? fps : 60
        value.memoryLimitMB = min(max(memoryLimitMB, 64), 8192)
        value.customWidth = min(max(customWidth, 320), 8192) & ~1
        value.customHeight = min(max(customHeight, 180), 8192) & ~1
        value.bitrateMbps = min(max(bitrateMbps, 0), 200)
        value.clipName = clipName.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        if value.clipName.isEmpty { value.clipName = "Clip" }
        value.clipName = String(value.clipName.prefix(80))
        if value.clipDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            value.clipDirectoryPath = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Movies/Clips", isDirectory: true).path
        }
        let allowedModifiers = UInt32(cmdKey | optionKey | controlKey | shiftKey)
        value.hotkeyModifiers &= allowedModifiers
        if value.hotkeyModifiers & UInt32(cmdKey | optionKey | controlKey) == 0 {
            value.hotkeyKeyCode = UInt32(kVK_ANSI_9)
            value.hotkeyModifiers = UInt32(cmdKey | shiftKey)
            value.hotkeyLabel = "⌘⇧9"
        }
        if value.hotkeyKeyCode == UInt32(kVK_Tab), value.hotkeyModifiers == UInt32(cmdKey) {
            value.hotkeyKeyCode = UInt32(kVK_ANSI_9)
            value.hotkeyModifiers = UInt32(cmdKey | shiftKey)
            value.hotkeyLabel = "⌘⇧9"
        }
        if value.hotkeyKeyCode == UInt32(kVK_ANSI_9),
           value.hotkeyModifiers == UInt32(cmdKey | shiftKey) {
            value.hotkeyLabel = "⌘⇧9"
        }
        value.pauseHotkeyModifiers &= allowedModifiers
        if value.pauseHotkeyModifiers & UInt32(cmdKey | optionKey | controlKey) == 0 {
            value.pauseHotkeyKeyCode = UInt32(kVK_ANSI_P)
            value.pauseHotkeyModifiers = UInt32(cmdKey | optionKey)
            value.pauseHotkeyLabel = "⌘⌥P"
        }
        if value.pauseHotkeyKeyCode == UInt32(kVK_ANSI_P),
           value.pauseHotkeyModifiers == UInt32(cmdKey | optionKey) {
            value.pauseHotkeyLabel = "⌘⌥P"
        }
        return value
    }

    func needsCaptureRestart(comparedTo other: Self) -> Bool {
        let customSizeChanged = (resolution == .custom || other.resolution == .custom) &&
            (customWidth != other.customWidth || customHeight != other.customHeight)
        return displayID != other.displayID || fps != other.fps || resolution != other.resolution ||
        customSizeChanged || bitrateMbps != other.bitrateMbps || clipDuration != other.clipDuration ||
        memoryLimitMB != other.memoryLimitMB || includeAudio != other.includeAudio ||
        excludeAppAudio != other.excludeAppAudio
    }
}

@MainActor
final class CaptureSettingsStore: ObservableObject {
    static let shared = CaptureSettingsStore()

    @Published var isRecordingHotkey = false
    @Published var hotkeyError: String?

    @Published var settings: CaptureSettings {
        didSet {
            if let data = try? JSONEncoder().encode(settings) {
                UserDefaults.standard.set(data, forKey: Self.storageKey)
            }
        }
    }

    private static let storageKey = "captureSettings"

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(CaptureSettings.self, from: data) {
            var migrated = saved.normalized()
            if !migrated.menuBarPreferenceInitialized {
                migrated.showInMenuBar = true
                migrated.menuBarPreferenceInitialized = true
            }
            if !migrated.soundPreferenceInitialized {
                migrated.playSoundOnSave = true
                migrated.soundPreferenceInitialized = true
            }
            settings = migrated
            if let updated = try? JSONEncoder().encode(migrated) {
                UserDefaults.standard.set(updated, forKey: Self.storageKey)
            }
        } else {
            settings = CaptureSettings()
        }
    }

    func apply() async {
        settings = settings.normalized()
        if CaptureEngine.shared.isRunning,
           let active = CaptureEngine.shared.activeSettings,
           settings.needsCaptureRestart(comparedTo: active) {
            await CaptureEngine.shared.stop()
            await CaptureEngine.shared.start(settings: settings)
        }
        NSApp.setActivationPolicy(.regular)
    }
}

@MainActor
private final class CaptureAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var observers = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        NSApp.setActivationPolicy(.regular)
        observeState()
        updateStatusItem()
        GlobalHotkey.shared.install()
        Task {
            NSApp.activate(ignoringOtherApps: true)
            _ = CGRequestScreenCaptureAccess()
            await CaptureEngine.shared.refreshDisplays()
            await CaptureEngine.shared.start(settings: CaptureSettingsStore.shared.settings)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettingsWindow()
        return true
    }

    private func observeState() {
        CaptureEngine.shared.$isRunning.sink { [weak self] _ in self?.updateStatusItem() }.store(in: &observers)
        CaptureEngine.shared.$status.sink { [weak self] _ in self?.updateStatusItem() }.store(in: &observers)
        CaptureSettingsStore.shared.$settings.sink { [weak self] _ in self?.updateStatusItem() }.store(in: &observers)
    }

    private func updateStatusItem() {
        guard CaptureSettingsStore.shared.settings.showInMenuBar else {
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
            return
        }
        if statusItem == nil { statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength) }
        guard let statusItem else { return }
        let iconState = MenuBarIcon.state(recording: CaptureEngine.shared.isRunning, status: CaptureEngine.shared.status)
        statusItem.button?.image = MenuBarIcon.menuBarImage(iconState)
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.target = self
        statusItem.button?.action = #selector(showStatusMenu(_:))
        NSApp.applicationIconImage = MenuBarIcon.applicationImage(iconState)
    }

    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        let engine = CaptureEngine.shared
        let settings = CaptureSettingsStore.shared.settings
        let status = menu.addItem(withTitle: engine.status, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(.separator())
        let save = menu.addItem(withTitle: "Save Last \(engine.activeSettings?.clipDuration ?? settings.clipDuration) Seconds", action: #selector(saveLastClip), keyEquivalent: "")
        save.target = self
        save.isEnabled = engine.isRunning
        let capture = menu.addItem(withTitle: engine.isRunning ? "Pause Capture" : "Start Capture", action: #selector(toggleCapture), keyEquivalent: "")
        capture.target = self
        menu.addItem(.separator())
        let folder = menu.addItem(withTitle: "Open Clips Folder", action: #selector(openClipsFolder), keyEquivalent: "")
        folder.target = self
        let preferences = menu.addItem(withTitle: "Settings…", action: #selector(openSettingsWindow), keyEquivalent: ",")
        preferences.target = self
        let permissions = menu.addItem(withTitle: "Open Screen Recording Settings", action: #selector(openScreenRecordingSettings), keyEquivalent: "")
        permissions.target = self
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "Quit Snip", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        return menu
    }

    @objc private func saveLastClip() {
        Task { await CaptureEngine.shared.saveClip(seconds: CaptureEngine.shared.activeSettings?.clipDuration ?? CaptureSettingsStore.shared.settings.clipDuration) }
    }

    @objc private func toggleCapture() {
        Task {
            if CaptureEngine.shared.isRunning { await CaptureEngine.shared.stop() }
            else { await CaptureEngine.shared.start(settings: CaptureSettingsStore.shared.settings) }
        }
    }

    @objc private func openClipsFolder() {
        let folder = URL(fileURLWithPath: CaptureSettingsStore.shared.settings.clipDirectoryPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }

    @objc private func openSettingsWindow() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 820, height: 820),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.identifier = NSUserInterfaceItemIdentifier("SnipSettings")
            window.title = "Snip Settings"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: CaptureSettingsView())
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func showStatusMenu(_ sender: NSStatusBarButton) {
        makeStatusMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
    }

    @objc private func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() { NSApp.terminate(nil) }

}

@MainActor
private enum HotkeyAction: UInt32 {
    case save = 1
    case toggleCapture = 2
}

@MainActor
private final class GlobalHotkey {
    static let shared = GlobalHotkey()
    private var handler: EventHandlerRef?
    private var hotkeys: [HotkeyAction: EventHotKeyRef] = [:]
    private var active: [HotkeyAction: (keyCode: UInt32, modifiers: UInt32)] = [:]
    private var recordingMonitor: Any?
    private var recordingAction: HotkeyAction?
    private var nextID: UInt32 = 1

    func install() {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                  eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, _ in
            guard let event else { return noErr }
            var hotKeyID = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                    UInt32(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size,
                                    nil, &hotKeyID) == noErr,
                  let action = HotkeyAction(rawValue: hotKeyID.id) else { return noErr }
            Task { @MainActor in
                if action == .save {
                    let seconds = CaptureEngine.shared.activeSettings?.clipDuration
                        ?? CaptureSettingsStore.shared.settings.clipDuration
                    await CaptureEngine.shared.saveClip(seconds: seconds)
                } else if CaptureEngine.shared.isRunning {
                    await CaptureEngine.shared.stop()
                } else {
                    await CaptureEngine.shared.start(settings: CaptureSettingsStore.shared.settings)
                }
            }
            return noErr
        }
        guard InstallEventHandler(GetApplicationEventTarget(), callback, 1, &event, nil, &handler) == noErr else {
            CaptureSettingsStore.shared.hotkeyError = "Could not install the global shortcut handler."
            return
        }
        let settings = CaptureSettingsStore.shared.settings
        if let error = register(.save, keyCode: settings.hotkeyKeyCode, modifiers: settings.hotkeyModifiers) {
            let fallbackKey = UInt32(kVK_ANSI_9)
            let fallbackModifiers = UInt32(cmdKey | shiftKey)
            if register(.save, keyCode: fallbackKey, modifiers: fallbackModifiers) == nil {
                CaptureSettingsStore.shared.settings.hotkeyKeyCode = fallbackKey
                CaptureSettingsStore.shared.settings.hotkeyModifiers = fallbackModifiers
                CaptureSettingsStore.shared.settings.hotkeyLabel = "⌘⇧9"
                CaptureSettingsStore.shared.hotkeyError = "Saved shortcut was unavailable (\(error)); using ⌘⇧9."
            } else {
                CaptureSettingsStore.shared.hotkeyError = error
            }
        }
        if let error = register(.toggleCapture, keyCode: settings.pauseHotkeyKeyCode,
                                modifiers: settings.pauseHotkeyModifiers) {
            CaptureSettingsStore.shared.hotkeyError = "Pause shortcut unavailable: \(error)"
        }
    }

    func beginRecording(_ action: HotkeyAction) {
        guard recordingMonitor == nil else { return }
        recordingAction = action
        CaptureSettingsStore.shared.hotkeyError = nil
        CaptureSettingsStore.shared.isRecordingHotkey = true
        NSApp.activate(ignoringOtherApps: true)
        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor [weak self] in self?.record(event) }
            return nil
        }
    }

    func cancelRecording() {
        if let recordingMonitor { NSEvent.removeMonitor(recordingMonitor) }
        recordingMonitor = nil
        recordingAction = nil
        CaptureSettingsStore.shared.isRecordingHotkey = false
    }

    private func record(_ event: NSEvent) {
        guard recordingMonitor != nil else { return }
        if event.keyCode == UInt16(kVK_Escape) {
            cancelRecording()
            return
        }
        let flags = event.modifierFlags
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        guard modifiers & UInt32(cmdKey | optionKey | controlKey) != 0 else {
            CaptureSettingsStore.shared.hotkeyError = "Use Command, Option, or Control with a key."
            NSSound.beep()
            return
        }
        let key = keyLabel(for: event)
        guard !key.isEmpty else {
            CaptureSettingsStore.shared.hotkeyError = "That key cannot be used as a shortcut."
            NSSound.beep()
            return
        }
        guard let action = recordingAction else { return }
        if let error = register(action, keyCode: UInt32(event.keyCode), modifiers: modifiers) {
            CaptureSettingsStore.shared.hotkeyError = error
            NSSound.beep()
            return
        }
        let label = (flags.contains(.command) ? "⌘" : "") +
                    (flags.contains(.control) ? "⌃" : "") +
                    (flags.contains(.option) ? "⌥" : "") +
                    (flags.contains(.shift) ? "⇧" : "") + key
        if action == .save {
            CaptureSettingsStore.shared.settings.hotkeyKeyCode = UInt32(event.keyCode)
            CaptureSettingsStore.shared.settings.hotkeyModifiers = modifiers
            CaptureSettingsStore.shared.settings.hotkeyLabel = label
        } else {
            CaptureSettingsStore.shared.settings.pauseHotkeyKeyCode = UInt32(event.keyCode)
            CaptureSettingsStore.shared.settings.pauseHotkeyModifiers = modifiers
            CaptureSettingsStore.shared.settings.pauseHotkeyLabel = label
        }
        CaptureSettingsStore.shared.hotkeyError = nil
        cancelRecording()
    }

    private func register(_ action: HotkeyAction, keyCode: UInt32, modifiers: UInt32) -> String? {
        if active[action]?.keyCode == keyCode, active[action]?.modifiers == modifiers { return nil }
        var replacement: EventHotKeyRef?
        let id = EventHotKeyID(signature: 0x434C4950, id: action.rawValue)
        let result = RegisterEventHotKey(keyCode, modifiers, id,
                                         GetApplicationEventTarget(), 0, &replacement)
        guard result == noErr, let replacement else {
            return "Shortcut unavailable (code \(result)). Choose another combination."
        }
        if let hotkey = hotkeys[action] { UnregisterEventHotKey(hotkey) }
        hotkeys[action] = replacement
        active[action] = (keyCode, modifiers)
        nextID &+= 1
        return nil
    }

    private func keyLabel(for event: NSEvent) -> String {
        switch event.keyCode {
        case UInt16(kVK_ANSI_0): "0"
        case UInt16(kVK_ANSI_1): "1"
        case UInt16(kVK_ANSI_2): "2"
        case UInt16(kVK_ANSI_3): "3"
        case UInt16(kVK_ANSI_4): "4"
        case UInt16(kVK_ANSI_5): "5"
        case UInt16(kVK_ANSI_6): "6"
        case UInt16(kVK_ANSI_7): "7"
        case UInt16(kVK_ANSI_8): "8"
        case UInt16(kVK_ANSI_9): "9"
        case UInt16(kVK_Space): "Space"
        case UInt16(kVK_Return): "Return"
        case UInt16(kVK_Tab): "Tab"
        case UInt16(kVK_Delete): "Delete"
        case UInt16(kVK_ForwardDelete): "Forward Delete"
        case UInt16(kVK_LeftArrow): "←"
        case UInt16(kVK_RightArrow): "→"
        case UInt16(kVK_UpArrow): "↑"
        case UInt16(kVK_DownArrow): "↓"
        default: event.charactersIgnoringModifiers?.uppercased() ?? ""
        }
    }
}

@main
struct SnipApp: App {
    @NSApplicationDelegateAdaptor(CaptureAppDelegate.self) private var delegate

    var body: some Scene {
        Settings {
            CaptureSettingsView()
        }
    }
}

private enum MenuBarIcon {
    enum State: String { case idle, recording, warning }

    static func state(recording: Bool, status: String) -> State {
        if recording { return .recording }
        return status == "Ready" || status == "Stopped" ? .idle : .warning
    }

    static func menuBarImage(_ state: State) -> NSImage {
        let image = applicationImage(state)
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }

    static func applicationImage(_ state: State) -> NSImage {
        Bundle.main.url(forResource: "clipper-\(state.rawValue)", withExtension: "png")
            .flatMap { NSImage(contentsOf: $0) }
            ?? NSImage(systemSymbolName: "record.circle", accessibilityDescription: "Snip")!
    }
}

@MainActor
private func bringSettingsToFront() {
    NSApp.activate(ignoringOtherApps: true)
    DispatchQueue.main.async {
        NSApp.windows.first(where: { $0.identifier?.rawValue == "SnipSettings" })?
            .makeKeyAndOrderFront(nil)
    }
}

@MainActor
private func closeSettingsWindow() {
    NSApp.windows.first(where: { $0.identifier?.rawValue == "SnipSettings" })?.performClose(nil)
}

@MainActor
private struct CaptureMenu: View {
    @Environment(\.openSettings) private var openSettings
    @ObservedObject private var engine = CaptureEngine.shared
    @ObservedObject private var store = CaptureSettingsStore.shared

    var body: some View {
        Text(engine.status)
        Divider()
        Button("Save Last \(engine.activeSettings?.clipDuration ?? store.settings.clipDuration) Seconds") {
            Task { await engine.saveClip(seconds: engine.activeSettings?.clipDuration ?? store.settings.clipDuration) }
        }
        .disabled(!engine.isRunning)
        Button(engine.isRunning ? "Pause Capture" : "Start Capture") {
            Task {
                if engine.isRunning {
                    await engine.stop()
                } else {
                    await engine.start(settings: store.settings)
                }
            }
        }
        Divider()
        Button("Open Clips Folder") {
            let folder = URL(fileURLWithPath: store.settings.clipDirectoryPath, isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            NSWorkspace.shared.open(folder)
        }
        Button("Settings…") {
            openSettings()
            bringSettingsToFront()
        }
        Text("Save: \(store.settings.hotkeyLabel)  Pause: \(store.settings.pauseHotkeyLabel)")
        if let error = store.hotkeyError {
            Text(error)
        }
        Divider()
        Button("Quit") { NSApp.terminate(nil) }
    }
}

@MainActor
private struct CaptureSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var engine = CaptureEngine.shared
    @ObservedObject private var store = CaptureSettingsStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Capture settings").font(.title2.bold())
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(draftSummary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Text(store.settings.clipName + " → " + folderLabel)
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    Text(engine.status).font(.caption2).foregroundStyle(engine.isRunning ? .green : .orange)
                }
            }
            GroupBox("Capture") {
                VStack(alignment: .leading, spacing: 10) {
                    setting("Display") {
                        Picker("Display", selection: $store.settings.displayID) {
                            Text("Main display").tag(Optional<CGDirectDisplayID>.none)
                            ForEach(engine.availableDisplays, id: \.displayID) { display in
                                Text("Display \(display.displayID) (\(display.width) × \(display.height))")
                                    .tag(Optional(display.displayID))
                            }
                        }
                        .labelsHidden().pickerStyle(.menu)
                    }
                    HStack(spacing: 14) {
                        setting("Frame rate") {
                            Picker("Frame rate", selection: $store.settings.fps) {
                                Text("30 FPS").tag(30); Text("60 FPS").tag(60); Text("120 FPS").tag(120)
                            }
                            .labelsHidden().pickerStyle(.menu)
                        }
                        setting("Resolution") {
                            Picker("Resolution", selection: $store.settings.resolution) {
                                ForEach(CaptureResolution.allCases) { Text($0.title).tag($0) }
                            }
                            .labelsHidden().pickerStyle(.menu)
                        }
                    }
                    if store.settings.resolution == .custom {
                        HStack(spacing: 14) {
                            setting("Width") { TextField("Pixels", value: $store.settings.customWidth, format: .number) }
                            setting("Height") { TextField("Pixels", value: $store.settings.customHeight, format: .number) }
                        }
                    }
                    HStack(spacing: 14) {
                        setting("Clip length") { TextField("Seconds", value: $store.settings.clipDuration, format: .number) }
                        setting("Buffer cap") { TextField("MB", value: $store.settings.memoryLimitMB, format: .number) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("Quality preset") {
                HStack {
                    Text("FPS and resolution").font(.subheadline.weight(.semibold))
                    Menu(qualityTitle) {
                        ForEach(QualityPreset.allCases) { preset in
                            Button(preset.summary) { apply(preset) }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    Spacer()
                    Text(qualitySelectionSummary).font(.caption).foregroundStyle(.secondary)
                }
            }
            GroupBox("Bitrate") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Slider(value: bitrateIndexBinding, in: 0...Double(bitrateSteps.count - 1), step: 1)
                        Text(store.settings.bitrateMbps == 0 ? "Auto" : "\(store.settings.bitrateMbps) Mbps")
                            .monospacedDigit().frame(width: 80, alignment: .trailing)
                    }
                    Text("0 uses automatic quality. Higher bitrates shorten history under the memory cap.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            GroupBox("Clip") {
                VStack(alignment: .leading, spacing: 10) {
                    setting("File name") { TextField("Clip", text: $store.settings.clipName) }
                    HStack {
                        Text("Save to").font(.subheadline.weight(.semibold))
                        Text(folderLabel).foregroundStyle(.secondary).lineLimit(1)
                        Button("Choose…") { chooseFolder() }
                    }
                    HStack(spacing: 18) {
                        hotkeySetting("Save clip", label: store.settings.hotkeyLabel, action: .save)
                        hotkeySetting("Pause / start", label: store.settings.pauseHotkeyLabel, action: .toggleCapture)
                    }
                    if let error = store.hotkeyError {
                        Text(error).foregroundStyle(.red).font(.caption)
                    } else if store.isRecordingHotkey {
                        Text("Press Escape to cancel.").foregroundStyle(.secondary).font(.caption)
                    }
                }
            }
            HStack(alignment: .top, spacing: 12) {
                GroupBox("Audio") {
                    VStack(alignment: .leading, spacing: 7) {
                        Toggle("Include system audio", isOn: $store.settings.includeAudio)
                        Toggle("Exclude snip audio", isOn: $store.settings.excludeAppAudio)
                            .disabled(!store.settings.includeAudio)
                        Toggle("Play save sound", isOn: $store.settings.playSoundOnSave)
                    }
                }
                GroupBox("App") {
                        Toggle("Show in menu bar", isOn: $store.settings.showInMenuBar)
                }
            }
            HStack {
                Spacer()
                Button("Apply and Close") {
                    Task {
                        await store.apply()
                        closeSettingsWindow()
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 820, height: 820, alignment: .topLeading)
        .onAppear { bringSettingsToFront() }
        .task { await engine.refreshDisplays() }
        .onDisappear { GlobalHotkey.shared.cancelRecording() }
    }

    private var draftSummary: String {
        let s = store.settings
        let bitrate = s.bitrateMbps == 0 ? "Auto" : String(s.bitrateMbps) + " Mbps"
        let audio = s.includeAudio ? (s.excludeAppAudio ? "system audio, snip excluded" : "system audio") : "no audio"
        let location = s.showInMenuBar ? "menu bar" : "Dock"
        let resolution = s.resolution == .custom
            ? String(s.customWidth) + "×" + String(s.customHeight)
            : s.resolution.title
        return resolution + " · " + String(s.fps) + " FPS · " + bitrate + " · " +
            String(s.clipDuration) + "s · " + audio + " · " + location
    }

    private var qualitySelectionSummary: String {
        String(store.settings.fps) + " FPS · " + store.settings.resolution.title
    }

    private var folderLabel: String {
        let url = URL(fileURLWithPath: store.settings.clipDirectoryPath, isDirectory: true)
        return url.path
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.directoryURL = URL(fileURLWithPath: store.settings.clipDirectoryPath, isDirectory: true)
        if panel.runModal() == .OK, let url = panel.url {
            store.settings.clipDirectoryPath = url.path
        }
    }

    private var qualityTitle: String {
        guard let preset = QualityPreset.allCases.first(where: {
            let v = $0.values
            return v.fps == store.settings.fps && v.resolution == store.settings.resolution && v.bitrate == store.settings.bitrateMbps
        }) else { return "Custom" }
        return preset.title
    }

    private var bitrateIndexBinding: Binding<Double> {
        Binding(
            get: { Double(bitrateSteps.enumerated().min(by: { abs($0.element - store.settings.bitrateMbps) < abs($1.element - store.settings.bitrateMbps) })?.offset ?? 0) },
            set: { store.settings.bitrateMbps = bitrateSteps[min(max(Int($0.rounded()), 0), bitrateSteps.count - 1)] }
        )
    }

    private func apply(_ preset: QualityPreset) {
        let v = preset.values
        store.settings.fps = v.fps
        store.settings.resolution = v.resolution
        store.settings.bitrateMbps = v.bitrate
    }

    @ViewBuilder
    private func hotkeySetting(_ title: String, label: String, action: HotkeyAction) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.subheadline.weight(.semibold))
            Button(store.isRecordingHotkey ? "Press a modified key…" : label) {
                GlobalHotkey.shared.beginRecording(action)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func setting<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
