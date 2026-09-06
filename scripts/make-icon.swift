// Renders the NoteIt app icon (1024×1024 PNG) and writes it to build/AppIcon.png.
// Usage: swift scripts/make-icon.swift  (then scripts/make-icon.sh builds the .icns)
//
// Design: macOS squircle with an indigo→violet→magenta gradient, a white
// note card with a folded corner, syntax-highlight colored text lines and a
// text caret — a note app for code and prose.
import AppKit

let size: CGFloat = 1024
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { fatalError("could not create bitmap") }
rep.size = NSSize(width: size, height: size)

NSGraphicsContext.saveGraphicsState()
guard let nsCtx = NSGraphicsContext(bitmapImageRep: rep) else { fatalError("no context") }
NSGraphicsContext.current = nsCtx
let ctx = nsCtx.cgContext

// MARK: - Squircle body (macOS proportions: ~824pt body on 1024 canvas)
let margin: CGFloat = 100
let body = NSRect(x: margin, y: margin, width: size - 2 * margin, height: size - 2 * margin)
let bodyRadius: CGFloat = 185.4
let bodyPath = NSBezierPath(roundedRect: body, xRadius: bodyRadius, yRadius: bodyRadius)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: r, green: g, blue: b, alpha: a)
}

// Background gradient with a soft drop shadow beneath the squircle.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -16), blur: 34,
              color: CGColor(red: 0.10, green: 0.06, blue: 0.28, alpha: 0.42))
bodyPath.addClip()
let grad = CGGradient(
    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
    colors: [
        CGColor(red: 0.29, green: 0.43, blue: 0.93, alpha: 1),  // indigo blue
        CGColor(red: 0.55, green: 0.34, blue: 0.95, alpha: 1),  // violet
        CGColor(red: 0.90, green: 0.28, blue: 0.72, alpha: 1),  // magenta
    ] as CFArray,
    locations: [0.0, 0.55, 1.0]
)!
ctx.drawLinearGradient(
    grad,
    start: CGPoint(x: body.minX, y: body.maxY),
    end: CGPoint(x: body.maxX, y: body.minY),
    options: []
)

// Subtle top gloss for depth.
let gloss = CGGradient(
    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
    colors: [
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.16),
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.0),
    ] as CFArray,
    locations: [0.0, 0.62]
)!
ctx.drawLinearGradient(
    gloss,
    start: CGPoint(x: body.midX, y: body.maxY),
    end: CGPoint(x: body.midX, y: body.minY + body.height * 0.35),
    options: []
)
ctx.restoreGState()

// Inner hairline border — the finishing touch on macOS icons.
ctx.saveGState()
bodyPath.lineWidth = 3
rgb(1, 1, 1, 0.28).setStroke()
bodyPath.stroke()
ctx.restoreGState()

// MARK: - Note card with folded top-right corner
let cardW: CGFloat = 500, cardH: CGFloat = 620
let card = NSRect(x: (size - cardW) / 2, y: (size - cardH) / 2, width: cardW, height: cardH)
let fold: CGFloat = 108       // folded-corner size
let cardRadius: CGFloat = 54
let tr = NSPoint(x: card.maxX, y: card.maxY)

// Card: a plain rounded rect (no hand-built arc paths — those sweep the
// wrong way and leave holes), filled white with a soft shadow.
let cardPath = NSBezierPath(roundedRect: card, xRadius: cardRadius, yRadius: cardRadius)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30,
              color: CGColor(red: 0.16, green: 0.05, blue: 0.30, alpha: 0.35))
rgb(1, 1, 1).setFill()
cardPath.fill()
ctx.restoreGState()

// Notch: "cut" the top-right corner off by re-painting the exact background
// (same gradient + gloss, clipped) over a triangle that covers the corner.
// Reusing the identical draw calls guarantees a pixel-perfect match.
let notch = NSBezierPath()
notch.move(to: NSPoint(x: tr.x - fold, y: tr.y))
notch.line(to: NSPoint(x: tr.x + 16, y: tr.y))
notch.line(to: NSPoint(x: tr.x + 16, y: tr.y - fold - 16))
notch.close()
ctx.saveGState()
bodyPath.addClip()
notch.addClip()
ctx.drawLinearGradient(
    grad,
    start: CGPoint(x: body.minX, y: body.maxY),
    end: CGPoint(x: body.maxX, y: body.minY),
    options: []
)
ctx.drawLinearGradient(
    gloss,
    start: CGPoint(x: body.midX, y: body.maxY),
    end: CGPoint(x: body.midX, y: body.minY + body.height * 0.35),
    options: []
)
ctx.restoreGState()

// The fold: back side of the page (a slightly darker triangle) tucked into
// the notch, with a hint of shadow along the diagonal.
let flap = NSBezierPath()
flap.move(to: NSPoint(x: tr.x - fold, y: tr.y))
flap.line(to: NSPoint(x: tr.x, y: tr.y - fold))
flap.line(to: NSPoint(x: tr.x - fold, y: tr.y - fold))
flap.close()
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: -4, height: 4), blur: 7,
              color: CGColor(red: 0.1, green: 0.1, blue: 0.2, alpha: 0.28))
rgb(0.914, 0.929, 0.965).setFill()   // #E9EEDF6
flap.fill()
ctx.restoreGState()

// MARK: - Text lines (syntax-highlight palette) + caret
struct LineSpec { let widthFrac: CGFloat; let color: NSColor }
let lines: [LineSpec] = [
    LineSpec(widthFrac: 0.62, color: rgb(0.388, 0.396, 0.945)),  // #6366F1 indigo
    LineSpec(widthFrac: 0.80, color: rgb(0.976, 0.463, 0.094)),  // #F97618 orange
    LineSpec(widthFrac: 0.52, color: rgb(0.184, 0.722, 0.502)),  // #2FB880 emerald
    LineSpec(widthFrac: 0.74, color: rgb(0.231, 0.510, 0.965)),  // #3B82F6 blue
    LineSpec(widthFrac: 0.46, color: rgb(0.925, 0.282, 0.600)),  // #EC4899 pink
    LineSpec(widthFrac: 0.34, color: rgb(0.580, 0.639, 0.729)),  // #94A3BA slate
]
let lineH: CGFloat = 32
let pitch: CGFloat = 76     // line height + gap; 6 lines fit the card with margins
let textTop = card.maxY - 100   // first line's top edge
let textLeft = card.minX + 64

for (i, spec) in lines.enumerated() {
    let y = textTop - CGFloat(i) * pitch - lineH
    let w = cardW * spec.widthFrac
    let lineRect = NSRect(x: textLeft, y: y, width: w, height: lineH)
    let pill = NSBezierPath(roundedRect: lineRect, xRadius: lineH / 2, yRadius: lineH / 2)
    spec.color.setFill()
    pill.fill()
}

// Caret right after the last (gray) line, bottom-aligned with it.
let lastW = cardW * lines[lines.count - 1].widthFrac
let lastTop = textTop - CGFloat(lines.count - 1) * pitch
let caretRect = NSRect(x: textLeft + lastW + 24, y: lastTop - lineH,
                       width: 16, height: 58)
let caret = NSBezierPath(roundedRect: caretRect, xRadius: 8, yRadius: 8)
rgb(0.310, 0.275, 0.898).setFill()   // #4F46E5 indigo
caret.fill()

NSGraphicsContext.restoreGraphicsState()

// MARK: - Write PNG
let png = rep.representation(using: .png, properties: [:])!
let outDir = URL(fileURLWithPath: "build", isDirectory: true)
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
let outURL = outDir.appendingPathComponent("AppIcon.png")
try! png.write(to: outURL)
print("wrote \(outURL.path)")
