import AppKit
import Carbon
import Combine
import ScreenCaptureKit
import SwiftUI
import UniformTypeIdentifiers

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

enum AppSourceMode: String, Codable, CaseIterable, Identifiable {
    case all, only, exclude

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "All apps"
        case .only: "Only selected apps"
        case .exclude: "All except selected apps"
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
    var recordMicrophone = false
    var microphoneDeviceID: String?
    var excludeAppAudio = true
    var videoAppMode: AppSourceMode = .all
    var videoAppIDs: [String] = []
    var audioAppMode: AppSourceMode = .all
    var audioAppIDs: [String] = []
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
    var brightness = 0.0
    var contrast = 1.0
    var saturation = 1.0
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
        case clipDuration, fps, resolution, memoryLimitMB, displayID, includeAudio, recordMicrophone, microphoneDeviceID, excludeAppAudio
        case videoAppMode, videoAppIDs, audioAppMode, audioAppIDs
        case showInMenuBar, menuBarPreferenceInitialized
        case customWidth, customHeight, bitrateMbps, brightness, contrast, saturation
        case clipName, clipDirectoryPath, playSoundOnSave, soundPreferenceInitialized
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
        recordMicrophone = try values.decodeIfPresent(Bool.self, forKey: .recordMicrophone) ?? recordMicrophone
        microphoneDeviceID = try values.decodeIfPresent(String.self, forKey: .microphoneDeviceID)
        excludeAppAudio = try values.decodeIfPresent(Bool.self, forKey: .excludeAppAudio) ?? excludeAppAudio
        videoAppMode = try values.decodeIfPresent(AppSourceMode.self, forKey: .videoAppMode) ?? videoAppMode
        videoAppIDs = try values.decodeIfPresent([String].self, forKey: .videoAppIDs) ?? videoAppIDs
        audioAppMode = try values.decodeIfPresent(AppSourceMode.self, forKey: .audioAppMode) ?? audioAppMode
        audioAppIDs = try values.decodeIfPresent([String].self, forKey: .audioAppIDs) ?? audioAppIDs
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
        brightness = try values.decodeIfPresent(Double.self, forKey: .brightness) ?? brightness
        contrast = try values.decodeIfPresent(Double.self, forKey: .contrast) ?? contrast
        saturation = try values.decodeIfPresent(Double.self, forKey: .saturation) ?? saturation
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
        value.brightness = brightness.isFinite ? min(max(brightness, -0.25), 0.25) : 0
        value.contrast = contrast.isFinite ? min(max(contrast, 0.5), 1.5) : 1
        value.saturation = saturation.isFinite ? min(max(saturation, 0), 2) : 1
        value.videoAppIDs = Array(Set(videoAppIDs.filter { !$0.isEmpty })).sorted()
        value.audioAppIDs = Array(Set(audioAppIDs.filter { !$0.isEmpty })).sorted()
        if value.microphoneDeviceID?.isEmpty == true { value.microphoneDeviceID = nil }
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

    var hasColorEdit: Bool {
        brightness != 0 || contrast != 1 || saturation != 1
    }

    func needsCaptureRestart(comparedTo other: Self) -> Bool {
        let customSizeChanged = (resolution == .custom || other.resolution == .custom) &&
            (customWidth != other.customWidth || customHeight != other.customHeight)
        return displayID != other.displayID || fps != other.fps || resolution != other.resolution ||
        customSizeChanged || bitrateMbps != other.bitrateMbps || clipDuration != other.clipDuration ||
        memoryLimitMB != other.memoryLimitMB || includeAudio != other.includeAudio ||
        recordMicrophone != other.recordMicrophone ||
        ((recordMicrophone || other.recordMicrophone) && microphoneDeviceID != other.microphoneDeviceID) ||
        excludeAppAudio != other.excludeAppAudio || videoAppMode != other.videoAppMode ||
        videoAppIDs != other.videoAppIDs || audioAppMode != other.audioAppMode ||
        audioAppIDs != other.audioAppIDs || brightness != other.brightness ||
        contrast != other.contrast || saturation != other.saturation
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

    func apply() async -> Bool {
        settings = settings.normalized()
        if CaptureEngine.shared.isRunning,
           let active = CaptureEngine.shared.activeSettings,
           settings.needsCaptureRestart(comparedTo: active) {
            await CaptureEngine.shared.stop()
            await CaptureEngine.shared.start(settings: settings)
            if !CaptureEngine.shared.isRunning { return false }
        }
        return true
    }
}

@MainActor
private final class CaptureAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var controlsPopover: NSPopover?
    private var observers = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
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
        CaptureEngine.shared.$isRunning.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateStatusItem() }
        }.store(in: &observers)
        CaptureEngine.shared.$status.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateStatusItem() }
        }.store(in: &observers)
        CaptureSettingsStore.shared.$settings.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateStatusItem() }
        }.store(in: &observers)
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .merge(with: workspace.publisher(for: NSWorkspace.didTerminateApplicationNotification),
                   workspace.publisher(for: NSWorkspace.didActivateApplicationNotification))
            .sink { _ in Task { await CaptureEngine.shared.refreshSourceFilters() } }
            .store(in: &observers)
    }

    private func updateStatusItem() {
        let policy: NSApplication.ActivationPolicy =
            CaptureSettingsStore.shared.settings.showInMenuBar ? .accessory : .regular
        if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
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
        statusItem.button?.action = #selector(showControls(_:))
        NSApp.applicationIconImage = MenuBarIcon.applicationImage(iconState)
    }

    @objc private func openSettingsWindow() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 600, height: 740),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.identifier = NSUserInterfaceItemIdentifier("SnipSettings")
            window.title = "Snip"
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: CaptureSettingsView())
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func showControls(_ sender: NSStatusBarButton) {
        if controlsPopover == nil {
            let popover = NSPopover()
            popover.behavior = .transient
            popover.contentSize = NSSize(width: 410, height: 590)
            popover.contentViewController = NSHostingController(rootView: CompactControlsView(
                openEditor: { [weak self] in
                    self?.controlsPopover?.performClose(nil)
                    self?.openSettingsWindow()
                },
                quit: { NSApp.terminate(nil) }
            ))
            controlsPopover = popover
        }
        if controlsPopover?.isShown == true {
            controlsPopover?.performClose(nil)
        } else {
            controlsPopover?.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        }
    }

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
        if status == "Ready" || status == "Stopped" { return .idle }
        return .warning
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
private struct CaptureSettingsView: View {
    @ObservedObject private var engine = CaptureEngine.shared
    @ObservedObject private var store = CaptureSettingsStore.shared
    @State private var page = 0
    @State private var settingsPage = 0
    @State private var microphoneRefresh = 0

    private let background = Color(red: 0.115, green: 0.12, blue: 0.17)
    private let surface = Color(red: 0.15, green: 0.16, blue: 0.21)
    private let accent = Color(red: 0.08, green: 0.48, blue: 0.98)

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Image(systemName: "record.circle")
                    .font(.system(size: 27)).foregroundStyle(accent)
                    .frame(width: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(page == 0 ? "Snip recorder" : "Settings").font(.title2.bold())
                    Text(page == 0 ? "Save the last moments of your screen" : "Capture preferences and sources")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    page = 1 - page
                } label: {
                    Label(page == 0 ? "Settings" : "Controls",
                          systemImage: page == 0 ? "gearshape" : "slider.horizontal.3")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(surface, in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                Toggle("On", isOn: captureBinding).toggleStyle(.switch)
                    .fixedSize()
            }
            .padding(.horizontal, 24).padding(.top, 30).padding(.bottom, 16)

            HStack(spacing: 12) {
                Text("Display").font(.headline)
                displayPicker
                Spacer()
            }
            .padding(.horizontal, 24)
            HStack(spacing: 7) {
                Image(systemName: engine.isRunning ? "record.circle.fill" : "pause.circle.fill")
                Text(engine.isRunning ? "Capture active" :
                     (["Ready", "Stopped"].contains(engine.status) ? "Capture paused" : engine.status))
            }
            .font(.caption).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24).padding(.top, 6).padding(.bottom, 12)

            if page == 0 {
                ScrollView {
                    recordingPage
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(spacing: 12) {
                    Picker("Settings section", selection: $settingsPage) {
                        Text("Sources").tag(0)
                        Text("Video").tag(1)
                        Text("Clips").tag(2)
                        Text("Color").tag(3)
                        Text("App").tag(4)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 510)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    ScrollView {
                        Group {
                            switch settingsPage {
                            case 0: sourcesTab
                            case 1: captureTab
                            case 2: clipsTab
                            case 3: colorTab
                            default: appTab
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
            Spacer(minLength: 0)
            HStack {
                if let sourceValidation {
                    Text(sourceValidation).foregroundStyle(.orange).font(.caption)
                } else {
                    Text("\(store.settings.hotkeyLabel) saves the recent clip.")
                        .foregroundStyle(.secondary).font(.caption)
                }
                Spacer()
                Button("Apply") { Task { _ = await store.apply() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(sourceValidation != nil)
                Button("Done") {
                    Task { if await store.apply() { closeSettingsWindow() } }
                }
                .disabled(sourceValidation != nil)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24).padding(.vertical, 14)
        }
        .frame(width: 600, height: 740)
        .background(background)
        .tint(accent)
        .preferredColorScheme(.dark)
        .onAppear { bringSettingsToFront() }
        .task { await engine.refreshDisplays() }
        .onDisappear { GlobalHotkey.shared.cancelRecording() }
    }

    private var captureBinding: Binding<Bool> {
        Binding(get: { engine.isRunning }, set: { enabled in
            Task {
                if enabled { await engine.start(settings: store.settings.normalized()) }
                else { await engine.stop() }
            }
        })
    }

    private var displayPicker: some View {
        Picker("Display", selection: $store.settings.displayID) {
            Text("Main display").tag(Optional<CGDirectDisplayID>.none)
            ForEach(engine.availableDisplays, id: \.displayID) { display in
                Text(displayName(display.displayID)).tag(Optional(display.displayID))
            }
        }
        .labelsHidden().pickerStyle(.menu)
        .frame(width: 340, alignment: .leading).tint(.white)
    }

    private func displayName(_ id: CGDirectDisplayID) -> String {
        let name = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == id
        }?.localizedName ?? "Display \(id)"
        return id == CGMainDisplayID() ? "\(name) · Main" : name
    }

    private var recordingPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Recent clip").font(.headline)
                Text(engine.isRunning ? "Snip is keeping the latest moments ready." :
                     "Start capture to keep recent video ready to save.")
                    .foregroundStyle(.secondary)
                if engine.isRunning && !engine.captureDetails.isEmpty {
                    Text(engine.captureDetails).font(.caption).foregroundStyle(.secondary)
                }
                Button("Save last \(engine.activeSettings?.clipDuration ?? store.settings.clipDuration) seconds") {
                    Task { await engine.saveClip(seconds: engine.activeSettings?.clipDuration
                                                 ?? store.settings.clipDuration) }
                }
                .buttonStyle(.borderedProminent).disabled(!engine.isRunning)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(surface, in: RoundedRectangle(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 10) {
                Text("Recording setup").font(.headline)
                HStack(spacing: 16) {
                    setting("Clip length (seconds)") {
                        TextField("Seconds", value: $store.settings.clipDuration, format: .number)
                            .textFieldStyle(.roundedBorder).frame(width: 110)
                    }
                    setting("Quality") {
                        Menu(qualityTitle) {
                            ForEach(QualityPreset.allCases) { preset in
                                Button(preset.summary) { apply(preset) }
                            }
                        }
                    }
                }
                Text("\(store.settings.fps) FPS · \(store.settings.resolution.title)")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Video settings…") { page = 1; settingsPage = 1 }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(surface, in: RoundedRectangle(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("Sources").font(.headline)
                    Spacer()
                    Button("Choose sources…") { page = 1; settingsPage = 0 }
                }
                sourceSummary("Video", detail: store.settings.videoAppMode.title)
                sourceSummary("App audio", detail: store.settings.includeAudio
                              ? store.settings.audioAppMode.title : "Off")
                sourceSummary("Microphone", detail: microphoneSummary)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(surface, in: RoundedRectangle(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 8) {
                Text("Save location").font(.headline)
                Text(folderLabel).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2).textSelection(.enabled)
                Button("Clip settings…") { page = 1; settingsPage = 2 }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(surface, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func sourceSummary(_ title: String, detail: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(detail).foregroundStyle(.secondary).lineLimit(1)
        }
        .font(.subheadline)
    }

    private var microphoneDevices: [AVCaptureDevice] {
        _ = microphoneRefresh
        return AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone], mediaType: .audio, position: .unspecified
        ).devices
    }

    private var microphoneSummary: String {
        guard store.settings.recordMicrophone else { return "Off" }
        guard let id = store.settings.microphoneDeviceID else { return "System default" }
        return microphoneDevices.first(where: { $0.uniqueID == id })?.localizedName ?? "Unavailable"
    }

    private var captureTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox("Quality preset") {
                HStack {
                    Menu(qualityTitle) {
                        ForEach(QualityPreset.allCases) { preset in
                            Button(preset.summary) { apply(preset) }
                        }
                    }
                    Spacer()
                    Text(qualitySelectionSummary).font(.caption).foregroundStyle(.secondary)
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
                    if let displayRefreshFPS, store.settings.fps > displayRefreshFPS {
                        Text("This display is \(displayRefreshFPS) Hz, so capture runs at up to \(displayRefreshFPS) FPS.")
                            .font(.caption).foregroundStyle(.secondary)
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
            Spacer()
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var colorTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recorded video color").font(.headline)
            Text("These optional adjustments affect saved clips only.")
                .font(.caption).foregroundStyle(.secondary)
            VStack(spacing: 12) {
                colorSlider("Brightness", value: $store.settings.brightness,
                            range: -0.25...0.25, neutral: 0)
                colorSlider("Contrast", value: $store.settings.contrast,
                            range: 0.5...1.5, neutral: 1)
                colorSlider("Saturation", value: $store.settings.saturation,
                            range: 0...2, neutral: 1)
            }
            .padding(14).background(surface, in: RoundedRectangle(cornerRadius: 16))
            Button("Reset color") { setColor(brightness: 0, contrast: 1, saturation: 1) }
                .disabled(!store.settings.hasColorEdit)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func setColor(brightness: Double, contrast: Double, saturation: Double) {
        store.settings.brightness = brightness
        store.settings.contrast = contrast
        store.settings.saturation = saturation
    }

    private func colorSlider(_ title: String, value: Binding<Double>,
                             range: ClosedRange<Double>, neutral: Double) -> some View {
        VStack(spacing: 5) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Text(value.wrappedValue, format: .number.precision(.fractionLength(2)))
                    .monospacedDigit().foregroundStyle(.secondary)
                Button { value.wrappedValue = neutral } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.plain)
                .disabled(abs(value.wrappedValue - neutral) < 0.001)
                .accessibilityLabel("Reset \(title)")
            }
            Slider(value: value, in: range)
        }
    }

    private var sourcesTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            sourceRule("Video sources", mode: $store.settings.videoAppMode,
                       ids: $store.settings.videoAppIDs)
            GroupBox("Audio sources") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Record app audio", isOn: $store.settings.includeAudio)
                    Toggle("Exclude Snip's save sound", isOn: $store.settings.excludeAppAudio)
                        .disabled(!store.settings.includeAudio)
                    sourceRule("Apps to hear", mode: $store.settings.audioAppMode,
                               ids: $store.settings.audioAppIDs)
                        .disabled(!store.settings.includeAudio)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("Microphone sources") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Record microphone", isOn: $store.settings.recordMicrophone)
                    Picker("Microphone", selection: $store.settings.microphoneDeviceID) {
                        Text("System default").tag(Optional<String>.none)
                        ForEach(microphoneDevices, id: \.uniqueID) { device in
                            Text(device.localizedName).tag(Optional(device.uniqueID))
                        }
                        if let id = store.settings.microphoneDeviceID,
                           !microphoneDevices.contains(where: { $0.uniqueID == id }) {
                            Text("Unavailable microphone").tag(Optional(id))
                        }
                    }
                    .disabled(!store.settings.recordMicrophone)
                    Button("Refresh microphones") { microphoneRefresh += 1 }
                    if store.settings.recordMicrophone,
                       let id = store.settings.microphoneDeviceID,
                       !microphoneDevices.contains(where: { $0.uniqueID == id }) {
                        Text("Selected microphone is disconnected. Choose another before recording.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("Video and app audio rules follow running apps. Microphone selection is independent.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(8)
    }

    private var clipsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox("Clip") {
                VStack(alignment: .leading, spacing: 10) {
                    setting("File name") {
                        TextField("Clip or clip_{time}_{date}", text: $store.settings.clipName)
                            .textFieldStyle(.roundedBorder)
                        Text("Use {date} and {time} to place the recording date and time. A short ID keeps names unique.")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("Example: " + ClipExporter.fileName(template: store.settings.clipName,
                                                                 at: Date(), suffix: "a1b2c3"))
                            .font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    HStack {
                        Text("Save to").font(.subheadline.weight(.semibold))
                        Text(folderLabel).foregroundStyle(.secondary).lineLimit(1)
                        Button("Choose…") { chooseFolder() }
                        Button("Open folder") {
                            let folder = URL(fileURLWithPath: store.settings.clipDirectoryPath,
                                             isDirectory: true)
                            try? FileManager.default.createDirectory(at: folder,
                                                                     withIntermediateDirectories: true)
                            NSWorkspace.shared.open(folder)
                        }
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
            Spacer()
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var appTab: some View {
        VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 8) {
                Text("App location").font(.headline)
                HStack {
                    Text("Show in")
                    Picker("Show in", selection: $store.settings.showInMenuBar) {
                        Text("Dock").tag(false)
                        Text("Menu bar").tag(true)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 270)
                }
                .padding(8).background(surface, in: RoundedRectangle(cornerRadius: 14))
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Keyboard shortcut").font(.headline)
                hotkeySetting("Toggle capture", label: store.settings.pauseHotkeyLabel,
                              action: .toggleCapture)
                    .padding(12).background(surface, in: RoundedRectangle(cornerRadius: 14))
                if let error = store.hotkeyError {
                    Text(error).font(.caption).foregroundStyle(.red)
                } else if store.isRecordingHotkey {
                    Text("Press Escape to cancel.").font(.caption).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Displays").font(.headline)
                HStack {
                    Button("Refresh displays") { Task { await engine.refreshDisplays() } }
                    Spacer()
                    Button("Reset recorded color") {
                        setColor(brightness: 0, contrast: 1, saturation: 1)
                    }
                    .disabled(!store.settings.hasColorEdit)
                }
                .padding(10).background(surface, in: RoundedRectangle(cornerRadius: 14))
            }
            Toggle("Play a sound when a clip is saved", isOn: $store.settings.playSoundOnSave)
            Button("Open Screen Recording settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var selectableApps: [SCRunningApplication] {
        var seen = Set<String>()
        return engine.availableApplications
            .filter { !$0.bundleIdentifier.isEmpty && $0.bundleIdentifier != Bundle.main.bundleIdentifier && seen.insert($0.bundleIdentifier).inserted }
            .sorted { $0.applicationName.localizedCaseInsensitiveCompare($1.applicationName) == .orderedAscending }
    }

    private var sourceValidation: String? {
        let s = store.settings
        if s.videoAppMode == .only && s.videoAppIDs.isEmpty { return "Choose a video app to record." }
        if s.includeAudio && s.audioAppMode == .only && s.audioAppIDs.isEmpty {
            return "Choose an app whose sound to record."
        }
        if s.recordMicrophone, let id = s.microphoneDeviceID,
           !microphoneDevices.contains(where: { $0.uniqueID == id }) {
            return "Choose an available microphone."
        }
        return nil
    }

    private func sourceRule(_ title: String, mode: Binding<AppSourceMode>, ids: Binding<[String]>) -> some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Capture", selection: mode) {
                    ForEach(AppSourceMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
                .frame(maxWidth: .infinity)
                if mode.wrappedValue != .all {
                    if ids.wrappedValue.isEmpty {
                        Text("No apps selected").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(ids.wrappedValue, id: \.self) { id in
                        let app = selectableApps.first(where: { $0.bundleIdentifier == id })
                        let running = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == id }
                        HStack {
                            Text(app?.applicationName ?? id)
                            if app == nil {
                                Text(running ? "No capturable window" : "Not running")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Remove") { ids.wrappedValue.removeAll { $0 == id } }
                                .buttonStyle(.borderless)
                        }
                    }
                    HStack {
                        Menu("Add running app") {
                            let available = selectableApps.filter { !ids.wrappedValue.contains($0.bundleIdentifier) }
                            if available.isEmpty { Text("No other running apps") }
                            ForEach(available, id: \.bundleIdentifier) { app in
                                Button(app.applicationName) { ids.wrappedValue.append(app.bundleIdentifier) }
                            }
                        }
                        Button("Choose app…") { chooseApp(for: ids) }
                        Button("Refresh") { Task { await engine.refreshDisplays() } }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func chooseApp(for ids: Binding<[String]>) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose an application to add to this rule"
        guard panel.runModal() == .OK, let url = panel.url,
              let id = Bundle(url: url)?.bundleIdentifier, !ids.wrappedValue.contains(id) else { return }
        ids.wrappedValue.append(id)
    }

    private var qualitySelectionSummary: String {
        String(store.settings.fps) + " FPS · " + store.settings.resolution.title
    }

    private var displayRefreshFPS: Int? {
        let id = store.settings.displayID ?? CGMainDisplayID()
        return NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == id
        }?.maximumFramesPerSecond
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

@MainActor
private struct CompactControlsView: View {
    @ObservedObject private var engine = CaptureEngine.shared
    @ObservedObject private var store = CaptureSettingsStore.shared
    let openEditor: () -> Void
    let quit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("Snip recorder").font(.title3.bold())
                Spacer()
                Button(action: openEditor) { Image(systemName: "gearshape") }
                    .buttonStyle(.plain).accessibilityLabel("Open settings")
                Toggle("Capture", isOn: captureBinding).labelsHidden().toggleStyle(.switch)
            }
            Text(engine.isRunning ? "Keeping recent video ready" : "Capture paused")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("Display").font(.headline)
                Picker("Display", selection: $store.settings.displayID) {
                    Text("Main display").tag(Optional<CGDirectDisplayID>.none)
                    ForEach(engine.availableDisplays, id: \.displayID) { display in
                        Text(display.displayID == CGMainDisplayID()
                             ? "Main display" : "Display \(display.displayID)")
                            .tag(Optional(display.displayID))
                    }
                }
                .labelsHidden().pickerStyle(.menu)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Recent clip").font(.headline)
                HStack {
                    Text("Length")
                    TextField("Seconds", value: $store.settings.clipDuration, format: .number)
                        .textFieldStyle(.roundedBorder).frame(width: 75)
                    Text("seconds")
                    Spacer()
                }
                Button("Save last \(engine.activeSettings?.clipDuration ?? store.settings.clipDuration) seconds") {
                    Task { await engine.saveClip(seconds: engine.activeSettings?.clipDuration
                                                 ?? store.settings.clipDuration) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!engine.isRunning)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 8) {
                Text("Sources").font(.headline)
                sourceRow("Video", detail: store.settings.videoAppMode.title)
                sourceRow("App audio", detail: store.settings.includeAudio
                          ? store.settings.audioAppMode.title : "Off")
                sourceRow("Microphone", detail: microphoneSummary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
            Text(engine.status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            Divider()
            HStack {
                Button("Full editor", action: openEditor)
                Spacer()
                Button("Quit", action: quit)
            }
        }
        .padding(18)
        .frame(width: 410)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.14)))
        .tint(Color(red: 0.08, green: 0.48, blue: 0.98))
        .preferredColorScheme(.dark)
        .task { await engine.refreshDisplays() }
    }

    private var captureBinding: Binding<Bool> {
        Binding(get: { engine.isRunning }, set: { enabled in
            Task {
                if enabled { await engine.start(settings: store.settings.normalized()) }
                else { await engine.stop() }
            }
        })
    }

    private var microphoneSummary: String {
        guard store.settings.recordMicrophone else { return "Off" }
        guard let id = store.settings.microphoneDeviceID else { return "System default" }
        return AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone], mediaType: .audio, position: .unspecified
        ).devices.first(where: { $0.uniqueID == id })?.localizedName ?? "Unavailable"
    }

    private func sourceRow(_ title: String, detail: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(detail).foregroundStyle(.secondary).lineLimit(1)
        }
        .font(.subheadline)
    }
}
