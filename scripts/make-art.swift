// Draws the README demo (docs/demo.gif) and the link preview image (docs/social.png).
// Everything is drawn here rather than recorded, so the art never shows anyone's real desktop.
// The app that steals focus is made up, so no real developer's app is shown misbehaving.
//
//   swift scripts/make-art.swift
import AppKit
import ImageIO
import UniformTypeIdentifiers

let ink = NSColor(srgbRed: 0.05, green: 0.06, blue: 0.07, alpha: 1)
let alert = NSColor(srgbRed: 1.0, green: 0.42, blue: 0.36, alpha: 1)

func bitmap(_ width: Int, _ height: Int, draw: () -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

/// Cool silver light on a dark wallpaper, like Show Desktop's art.
func wallpaper(_ rect: NSRect) {
    NSGradient(starting: NSColor(srgbRed: 0.08, green: 0.09, blue: 0.13, alpha: 1), ending: ink)!.draw(in: rect, angle: -90)
    let glows: [(CGFloat, CGFloat, CGFloat, NSColor)] = [
        (0.18, 0.75, 0.42, NSColor(srgbRed: 0.84, green: 0.89, blue: 0.95, alpha: 0.45)),
        (0.85, 0.72, 0.38, NSColor(srgbRed: 0.59, green: 0.68, blue: 0.81, alpha: 0.40)),
        (0.70, 0.12, 0.46, NSColor(srgbRed: 0.75, green: 0.81, blue: 0.89, alpha: 0.32)),
        (0.22, 0.15, 0.30, NSColor(srgbRed: 0.44, green: 0.53, blue: 0.65, alpha: 0.32)),
    ]
    for (x, y, r, color) in glows {
        let center = NSPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        NSGradient(starting: color, ending: color.withAlphaComponent(0))!
            .draw(fromCenter: center, radius: 0, toCenter: center, radius: rect.width * r, options: [])
    }
}

func symbol(_ name: String, size: CGFloat, colors: [NSColor], weight: NSFont.Weight = .regular) -> NSImage {
    let config = NSImage.SymbolConfiguration(pointSize: size, weight: weight).applying(.init(paletteColors: colors))
    return NSImage(systemSymbolName: name, accessibilityDescription: nil)!.withSymbolConfiguration(config)!
}

@discardableResult
func text(
    _ string: String, at point: NSPoint, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .white,
    centered: Bool = false, mono: Bool = false
) -> CGFloat {
    let font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let width = (string as NSString).size(withAttributes: attributes).width
    (string as NSString).draw(at: NSPoint(x: centered ? point.x - width / 2 : point.x, y: point.y), withAttributes: attributes)
    return width
}

/// A made-up app's icon: a gradient tile with a symbol on it.
func appTile(_ rect: NSRect, symbolName: String) {
    let body = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.23, yRadius: rect.width * 0.23)
    NSGradient(
        starting: NSColor(srgbRed: 0.36, green: 0.62, blue: 0.98, alpha: 1),
        ending: NSColor(srgbRed: 0.16, green: 0.36, blue: 0.86, alpha: 1)
    )!.draw(in: body, angle: -90)
    let image = symbol(symbolName, size: rect.width * 0.5, colors: [.white], weight: .semibold)
    image.draw(at: NSPoint(x: rect.midX - image.size.width / 2, y: rect.midY - image.size.height / 2), from: .zero, operation: .sourceOver, fraction: 1)
}

/// A dark app window with a title bar. Returns the content area.
@discardableResult
func window(_ frame: NSRect, title: String, alpha: CGFloat = 1, scale: CGFloat = 1, key: Bool) -> NSRect {
    let rect = NSRect(
        x: frame.midX - frame.width * scale / 2, y: frame.midY - frame.height * scale / 2,
        width: frame.width * scale, height: frame.height * scale
    )
    let body = NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = .black.withAlphaComponent((key ? 0.55 : 0.35) * alpha)
    shadow.shadowBlurRadius = key ? 30 : 18
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    NSColor(srgbRed: 0.15, green: 0.16, blue: 0.19, alpha: alpha).setFill()
    body.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSColor.white.withAlphaComponent(0.12 * alpha).setStroke()
    body.lineWidth = 1
    body.stroke()
    let colors: [NSColor] = key ? [.systemRed, .systemYellow, .systemGreen] : [.gray, .gray, .gray]
    for (index, color) in colors.enumerated() {
        color.withAlphaComponent(alpha * (key ? 1 : 0.5)).setFill()
        NSBezierPath(ovalIn: NSRect(x: rect.minX + 14 + CGFloat(index) * 18, y: rect.maxY - 22, width: 11, height: 11)).fill()
    }
    text(title, at: NSPoint(x: rect.midX, y: rect.maxY - 24), size: 12, weight: .semibold, color: .white.withAlphaComponent((key ? 0.85 : 0.45) * alpha), centered: true)
    return NSRect(x: rect.minX + 18, y: rect.minY + 14, width: rect.width - 36, height: rect.height - 50)
}

func cursor(at point: NSPoint, pressed: Bool) {
    let arrow = NSBezierPath()
    let s: CGFloat = pressed ? 0.9 : 1
    arrow.move(to: point)
    arrow.line(to: NSPoint(x: point.x, y: point.y - 22 * s))
    arrow.line(to: NSPoint(x: point.x + 5.5 * s, y: point.y - 17 * s))
    arrow.line(to: NSPoint(x: point.x + 9.5 * s, y: point.y - 25.5 * s))
    arrow.line(to: NSPoint(x: point.x + 13 * s, y: point.y - 24 * s))
    arrow.line(to: NSPoint(x: point.x + 9 * s, y: point.y - 15.5 * s))
    arrow.line(to: NSPoint(x: point.x + 16 * s, y: point.y - 15.5 * s))
    arrow.close()
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = .black.withAlphaComponent(0.4)
    shadow.shadowBlurRadius = 3
    shadow.shadowOffset = NSSize(width: 0, height: -1)
    shadow.set()
    NSColor.black.setFill()
    arrow.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSColor.white.setStroke()
    arrow.lineWidth = 1.5
    arrow.stroke()
}

// MARK: Scene

let width: CGFloat = 720
let height: CGFloat = 450
let menuBarHeight: CGFloat = 26
let iconCenter = NSPoint(x: width - 168, y: height - menuBarHeight / 2)
let editorFrame = NSRect(x: 44, y: 54, width: 440, height: 300)
let thiefFrame = NSRect(x: 250, y: 120, width: 340, height: 170)

let inEditor = "Ship the rele"
let inThief = "ase notes by Fri"

struct Moment {
    var typedInEditor = 0
    var typedInThief = 0
    /// 0 before the other app appears, 1 once it's fully in front.
    var thief: CGFloat = 0
    var caretOn = true
    var alerting = false
    var cursorAt = NSPoint(x: 560, y: 90)
    var pressed = false
    var menuOpen = false
}

func scene(_ m: Moment) {
    wallpaper(NSRect(x: 0, y: 0, width: width, height: height))

    // The editor you're typing in.
    let editorKey = m.thief < 0.5
    let page = window(editorFrame, title: "Draft — Release checklist", key: editorKey)
    text("Release checklist", at: NSPoint(x: page.minX, y: page.maxY - 30), size: 20, weight: .bold)
    text("☑  Tag the build", at: NSPoint(x: page.minX, y: page.maxY - 64), size: 14, color: .white.withAlphaComponent(0.7))
    text("☑  Run the tests", at: NSPoint(x: page.minX, y: page.maxY - 90), size: 14, color: .white.withAlphaComponent(0.7))
    let typed = String(inEditor.prefix(m.typedInEditor))
    let lineY = page.maxY - 116
    let w = text("☐  " + typed, at: NSPoint(x: page.minX, y: lineY), size: 14)
    if editorKey && m.caretOn {
        NSColor.systemBlue.setFill()
        NSRect(x: page.minX + w + 1, y: lineY - 1, width: 2, height: 19).fill()
    }

    // The app that jumps in front.
    if m.thief > 0 {
        let e = m.thief * m.thief * (3 - 2 * m.thief)
        let field = window(thiefFrame, title: "Driftwood Sync", alpha: e, scale: 0.9 + 0.1 * e, key: true)
        if e > 0.6 {
            appTile(NSRect(x: field.minX, y: field.maxY - 40, width: 36, height: 36), symbolName: "arrow.triangle.2.circlepath.icloud.fill")
            text("Everything's up to date", at: NSPoint(x: field.minX + 48, y: field.maxY - 18), size: 13, weight: .semibold)
            text("Search your synced files", at: NSPoint(x: field.minX + 48, y: field.maxY - 36), size: 11, color: .white.withAlphaComponent(0.55))
            let box = NSRect(x: field.minX, y: field.minY + 22, width: field.width, height: 30)
            NSColor.white.withAlphaComponent(0.08).setFill()
            NSBezierPath(roundedRect: box, xRadius: 7, yRadius: 7).fill()
            NSColor.systemBlue.withAlphaComponent(0.8).setStroke()
            let ring = NSBezierPath(roundedRect: box, xRadius: 7, yRadius: 7)
            ring.lineWidth = 2
            ring.stroke()
            let stolen = String(inThief.prefix(m.typedInThief))
            let tw = text(stolen.isEmpty ? "" : stolen, at: NSPoint(x: box.minX + 10, y: box.minY + 7), size: 13)
            if stolen.isEmpty {
                text("Search", at: NSPoint(x: box.minX + 10, y: box.minY + 7), size: 13, color: .white.withAlphaComponent(0.35))
            }
            if m.caretOn {
                NSColor.systemBlue.setFill()
                NSRect(x: box.minX + 10 + tw + 1, y: box.minY + 6, width: 2, height: 18).fill()
            }
        }
    }

    // The menu bar.
    NSColor(srgbRed: 0.06, green: 0.07, blue: 0.09, alpha: 0.72).setFill()
    NSRect(x: 0, y: height - menuBarHeight, width: width, height: menuBarHeight).fill()
    text(m.thief >= 0.5 ? "Driftwood Sync" : "Draft", at: NSPoint(x: 18, y: height - 19), size: 12.5, weight: .bold)
    for (index, word) in ["File", "Edit", "View", "Window"].enumerated() {
        text(word, at: NSPoint(x: (m.thief >= 0.5 ? 130 : 70) + CGFloat(index) * 46, y: height - 19), size: 12.5)
    }
    if m.pressed || m.menuOpen {
        NSColor.white.withAlphaComponent(0.22).setFill()
        NSBezierPath(roundedRect: NSRect(x: iconCenter.x - 14, y: height - menuBarHeight + 3, width: 28, height: menuBarHeight - 6), xRadius: 5, yRadius: 5).fill()
    }
    let menuIcon = m.alerting && !m.menuOpen
        ? symbol("viewfinder.trianglebadge.exclamationmark", size: 14, colors: [.white, alert])
        : symbol("viewfinder", size: 14, colors: [.white])
    menuIcon.draw(at: NSPoint(x: iconCenter.x - menuIcon.size.width / 2, y: iconCenter.y - menuIcon.size.height / 2), from: .zero, operation: .sourceOver, fraction: 1)
    for (index, name) in ["wifi", "magnifyingglass", "switch.2"].enumerated() {
        let image = symbol(name, size: 13, colors: [.white])
        image.draw(at: NSPoint(x: width - 128 + CGFloat(index) * 30, y: height - 20), from: .zero, operation: .sourceOver, fraction: 1)
    }
    text("9:41", at: NSPoint(x: width - 40, y: height - 19), size: 12.5, weight: .medium)

    if m.menuOpen { menu() }
    cursor(at: m.cursorAt, pressed: m.pressed)
}

/// The app's menu, drawn as it looks open.
func menu() {
    // Shifted left to fit on screen, as macOS does with menus near the edge.
    let panelWidth: CGFloat = 330
    let panel = NSRect(x: min(iconCenter.x - 14, width - 8 - panelWidth), y: height - menuBarHeight - 4 - 196, width: panelWidth, height: 196)
    let body = NSBezierPath(roundedRect: panel, xRadius: 10, yRadius: 10)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = .black.withAlphaComponent(0.5)
    shadow.shadowBlurRadius = 22
    shadow.shadowOffset = NSSize(width: 0, height: -8)
    shadow.set()
    NSColor(srgbRed: 0.17, green: 0.18, blue: 0.21, alpha: 1).setFill()
    body.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSColor.white.withAlphaComponent(0.14).setStroke()
    body.lineWidth = 1
    body.stroke()

    let left = panel.minX + 14
    var y = panel.maxY - 26
    text("1 steal today", at: NSPoint(x: left, y: y), size: 13, color: .white.withAlphaComponent(0.45))
    y -= 14
    NSColor.white.withAlphaComponent(0.12).setFill()
    NSRect(x: panel.minX + 10, y: y, width: panel.width - 20, height: 1).fill()
    y -= 22
    text("Recent Steals", at: NSPoint(x: left, y: y), size: 11, weight: .bold, color: .white.withAlphaComponent(0.45))

    // The highlighted steal.
    y -= 48
    NSColor.systemBlue.withAlphaComponent(0.85).setFill()
    NSBezierPath(roundedRect: NSRect(x: panel.minX + 6, y: y - 4, width: panel.width - 12, height: 44), xRadius: 6, yRadius: 6).fill()
    appTile(NSRect(x: left, y: y + 4, width: 26, height: 26), symbolName: "arrow.triangle.2.circlepath.icloud.fill")
    text("Driftwood Sync stole focus from Draft", at: NSPoint(x: left + 36, y: y + 20), size: 13, weight: .medium)
    text("just now · While you were typing", at: NSPoint(x: left + 36, y: y + 2), size: 11, color: .white.withAlphaComponent(0.8))

    y -= 16
    NSColor.white.withAlphaComponent(0.12).setFill()
    NSRect(x: panel.minX + 10, y: y, width: panel.width - 20, height: 1).fill()
    y -= 24
    text("Top Offenders", at: NSPoint(x: left, y: y), size: 13)
    text("›", at: NSPoint(x: panel.maxX - 24, y: y), size: 13, color: .white.withAlphaComponent(0.5))
    y -= 24
    text("Open Log…", at: NSPoint(x: left, y: y), size: 13)
    text("⌘L", at: NSPoint(x: panel.maxX - 36, y: y), size: 13, color: .white.withAlphaComponent(0.5))
}

// MARK: Demo

func lerp(_ a: NSPoint, _ b: NSPoint, _ t: CGFloat) -> NSPoint {
    let e = t * t * (3 - 2 * t)
    return NSPoint(x: a.x + (b.x - a.x) * e, y: a.y + (b.y - a.y) * e)
}

var frames: [(NSBitmapImageRep, Double)] = []
func frame(_ m: Moment, hold: Double = 0.07) {
    // Drawn at 2x so the GIF looks sharp on Retina screens when shown at 720 points.
    let rep = bitmap(Int(width * 2), Int(height * 2)) {
        let transform = NSAffineTransform()
        transform.scale(by: 2)
        transform.concat()
        scene(m)
    }
    frames.append((rep, hold))
}

var m = Moment()
frame(m, hold: 0.8)
// Typing away in the editor.
for count in 1...inEditor.count {
    m.typedInEditor = count
    m.caretOn = true
    frame(m, hold: count % 4 == 0 ? 0.12 : 0.08)
}
// Another app jumps in front mid-word...
for step in 1...4 {
    m.thief = CGFloat(step) / 4
    frame(m, hold: 0.04)
}
// ...and the rest of the sentence lands in its search box.
for count in 1...inThief.count {
    m.typedInThief = count
    if count == 4 { m.alerting = true }
    frame(m, hold: 0.08)
}
m.caretOn = false
frame(m, hold: 0.9)
// Who did that? Check the menu bar.
let start = m.cursorAt
let onIcon = NSPoint(x: iconCenter.x - 2, y: iconCenter.y + 6)
for step in 1...12 {
    m.cursorAt = lerp(start, onIcon, CGFloat(step) / 12)
    frame(m, hold: 0.04)
}
m.pressed = true
frame(m, hold: 0.12)
m.pressed = false
m.menuOpen = true
frame(m, hold: 3.2)

let gifURL = URL(fileURLWithPath: "docs/demo.gif")
let destination = CGImageDestinationCreateWithURL(gifURL as CFURL, UTType.gif.identifier as CFString, frames.count, nil)!
CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
for (rep, hold) in frames {
    CGImageDestinationAddImage(destination, rep.cgImage!, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: hold]] as CFDictionary)
}
guard CGImageDestinationFinalize(destination) else { fatalError("Couldn't write the GIF") }

// The last frame on its own, for checking the art without playing the GIF.
if let preview = ProcessInfo.processInfo.environment["PREVIEW"] {
    try frames.last!.0.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: preview))
}

// MARK: Link preview

let social = bitmap(1280, 640) {
    let rect = NSRect(x: 0, y: 0, width: 1280, height: 640)
    wallpaper(rect)
    if let icon = NSImage(contentsOfFile: "docs/icon.png") {
        icon.draw(in: NSRect(x: 640 - 80, y: 380, width: 160, height: 160))
    }
    text("Who Stole My Focus", at: NSPoint(x: 640, y: 270), size: 84, weight: .semibold, centered: true)
    text("Find out which app keeps jumping in front of your work.", at: NSPoint(x: 640, y: 205), size: 30, color: .white.withAlphaComponent(0.75), centered: true)
    text("free · open source · macos 14+ · no internet access", at: NSPoint(x: 640, y: 120), size: 22, weight: .medium, color: .white.withAlphaComponent(0.5), centered: true)
}
try social.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "docs/social.png"))
print("Wrote docs/demo.gif and docs/social.png")
