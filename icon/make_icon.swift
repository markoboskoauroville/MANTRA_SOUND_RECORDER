// The app's icon, drawn (swift-apps.md: the icon shows what the app IS): its own window in small, a dark tile with
// a waveform half played (green) and half waiting (grey), the white playhead between, the red record dot below,
// and the version under it (version-visible.md). Usage: swift make_icon.swift <version> <out.png>
import AppKit

let args = CommandLine.arguments
let version = args.count > 1 ? args[1] : "1"
let out = args.count > 2 ? args[2] : "icon_1024.png"
let S: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S), bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
func c(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: a)
}
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
ctx.addPath(CGPath(roundedRect: tile, cornerWidth: 180, cornerHeight: 180, transform: nil))
ctx.setFillColor(c(0x1F1F20).cgColor); ctx.fillPath()
// the well, as in the window
let well = CGRect(x: 170, y: 420, width: 684, height: 380)
ctx.addPath(CGPath(roundedRect: well, cornerWidth: 40, cornerHeight: 40, transform: nil))
ctx.setFillColor(c(0x161617).cgColor); ctx.fillPath()
let mid = well.midY, n = 38, step = well.width / CGFloat(n + 2)
let playX = well.minX + well.width * 0.55
for i in 0..<n {
    let t = CGFloat(i) / CGFloat(n - 1)
    let env = 0.25 + 0.75 * abs(sin(t * 7.3) * sin(t * 2.1 + 0.5))
    let h = (well.height / 2 - 30) * env
    let x = well.minX + step * CGFloat(i + 1)
    (x < playX ? c(0x33D17A) : c(0x7A8087)).setFill()
    NSBezierPath(roundedRect: CGRect(x: x, y: mid - h, width: step * 0.62, height: 2 * h), xRadius: 5, yRadius: 5).fill()
}
NSColor.white.setFill()
NSBezierPath(rect: CGRect(x: playX - 4, y: well.minY + 14, width: 8, height: well.height - 28)).fill()
// the record key: a ring round a red dot
let rc = CGPoint(x: 330, y: 280)
c(0xC8CDD2).setStroke()
let ring = NSBezierPath(ovalIn: CGRect(x: rc.x - 82, y: rc.y - 82, width: 164, height: 164)); ring.lineWidth = 14; ring.stroke()
c(0xFF3B30).setFill()
NSBezierPath(ovalIn: CGRect(x: rc.x - 42, y: rc.y - 42, width: 84, height: 84)).fill()
// the version
let v = "v" + version as NSString
let font = NSFont.monospacedSystemFont(ofSize: 150, weight: .bold)
let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: c(0xECECEC)]
let sz = v.size(withAttributes: attrs)
v.draw(at: CGPoint(x: 700 - sz.width / 2, y: 280 - sz.height / 2), withAttributes: attrs)
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
