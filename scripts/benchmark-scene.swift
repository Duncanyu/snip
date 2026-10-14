// A small, repeatable moving desktop workload for capture measurements.
import AppKit
import QuartzCore

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let screen = NSScreen.main!.visibleFrame
let size = NSSize(width: min(1100, screen.width - 60), height: min(700, screen.height - 60))
let frame = NSRect(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2,
                   width: size.width, height: size.height)
let window = NSWindow(contentRect: frame, styleMask: [.titled, .closable],
                      backing: .buffered, defer: false)
window.title = "Snip benchmark: moving tiles"
let view = NSView(frame: NSRect(origin: .zero, size: size))
view.wantsLayer = true
view.layer?.backgroundColor = NSColor.black.cgColor
window.contentView = view

for index in 0..<36 {
    let column = index % 6
    let row = index / 6
    let tile = CALayer()
    tile.frame = CGRect(x: CGFloat(column) * size.width / 6 + 10,
                        y: CGFloat(row) * size.height / 6 + 10,
                        width: size.width / 8, height: size.height / 9)
    tile.backgroundColor = NSColor(calibratedHue: CGFloat(index) / 36,
                                  saturation: 0.85, brightness: 0.9, alpha: 1).cgColor
    tile.cornerRadius = 12
    view.layer?.addSublayer(tile)
    let motion = CABasicAnimation(keyPath: "position.x")
    motion.fromValue = tile.position.x - 10
    motion.toValue = tile.position.x + 35
    motion.duration = 0.35 + Double(index % 6) * 0.09
    motion.autoreverses = true
    motion.repeatCount = .infinity
    tile.add(motion, forKey: "horizontalMotion")
}

window.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)
DispatchQueue.main.asyncAfter(deadline: .now() + 50) { app.terminate(nil) }
app.run()
