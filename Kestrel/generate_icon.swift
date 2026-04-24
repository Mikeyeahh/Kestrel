#!/usr/bin/env swift

import AppKit
import CoreGraphics
import CoreText
import UniformTypeIdentifiers

let size = 1024
let w = CGFloat(size), h = CGFloat(size)
let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                          bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }

ctx.translateBy(x: 0, y: h); ctx.scaleBy(x: 1, y: -1)

// ── Black background ──
ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

// ── Radial glow ──
let gc: [CGFloat] = [1.0,0.55,0.12,0.18, 0.60,0.30,0.05,0.04, 0,0,0,0]
if let g = CGGradient(colorSpace: cs, colorComponents: gc, locations: [0,0.5,1], count: 3) {
    ctx.saveGState(); ctx.translateBy(x: 0, y: h); ctx.scaleBy(x: 1, y: -1)
    ctx.drawRadialGradient(g, startCenter: CGPoint(x: w*0.50, y: h*0.56),
                           startRadius: 0, endCenter: CGPoint(x: w*0.50, y: h*0.56),
                           endRadius: w*0.42, options: [])
    ctx.restoreGState()
}

func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: w*x, y: h*y) }

// ── Kestrel hovering — wings raised, viewed from front ──
let bird = CGMutablePath()
let dy: CGFloat = 0.08  // vertical offset — nudge bird downward

// Head top centre
bird.move(to: p(0.488, 0.215 + dy))
// Head right contour
bird.addCurve(to: p(0.520, 0.260 + dy), control1: p(0.510, 0.215 + dy), control2: p(0.520, 0.238 + dy))

// Right shoulder
bird.addCurve(to: p(0.555, 0.270 + dy), control1: p(0.528, 0.268 + dy), control2: p(0.540, 0.270 + dy))

// Right wing leading edge — sweeping up and out
bird.addCurve(to: p(0.720, 0.195 + dy), control1: p(0.610, 0.258 + dy), control2: p(0.670, 0.225 + dy))
bird.addCurve(to: p(0.870, 0.140 + dy), control1: p(0.770, 0.170 + dy), control2: p(0.825, 0.148 + dy))

// Right wingtip — sharp point angled slightly up
bird.addCurve(to: p(0.950, 0.155 + dy), control1: p(0.910, 0.134 + dy), control2: p(0.938, 0.140 + dy))

// Right wing trailing edge — curves back down
bird.addCurve(to: p(0.830, 0.240 + dy), control1: p(0.945, 0.175 + dy), control2: p(0.895, 0.210 + dy))
bird.addCurve(to: p(0.680, 0.320 + dy), control1: p(0.770, 0.270 + dy), control2: p(0.725, 0.298 + dy))
bird.addCurve(to: p(0.575, 0.375 + dy), control1: p(0.640, 0.340 + dy), control2: p(0.605, 0.360 + dy))

// Right flank down
bird.addCurve(to: p(0.548, 0.475 + dy), control1: p(0.558, 0.400 + dy), control2: p(0.552, 0.440 + dy))

// Right side into tail
bird.addCurve(to: p(0.540, 0.600 + dy), control1: p(0.545, 0.520 + dy), control2: p(0.543, 0.565 + dy))

// Tail — wide fan, slight V-notch
bird.addCurve(to: p(0.565, 0.700 + dy), control1: p(0.545, 0.640 + dy), control2: p(0.555, 0.675 + dy))
bird.addLine(to: p(0.560, 0.730 + dy))
bird.addLine(to: p(0.540, 0.740 + dy))
bird.addLine(to: p(0.515, 0.750 + dy))
bird.addLine(to: p(0.500, 0.745 + dy)) // centre notch
bird.addLine(to: p(0.485, 0.750 + dy))
bird.addLine(to: p(0.460, 0.740 + dy))
bird.addLine(to: p(0.440, 0.730 + dy))
bird.addLine(to: p(0.435, 0.700 + dy))

// Left side from tail up
bird.addCurve(to: p(0.460, 0.600 + dy), control1: p(0.445, 0.675 + dy), control2: p(0.457, 0.640 + dy))
bird.addCurve(to: p(0.452, 0.475 + dy), control1: p(0.457, 0.565 + dy), control2: p(0.455, 0.520 + dy))

// Left flank up to wing
bird.addCurve(to: p(0.425, 0.375 + dy), control1: p(0.448, 0.440 + dy), control2: p(0.442, 0.400 + dy))

// Left wing trailing edge
bird.addCurve(to: p(0.320, 0.320 + dy), control1: p(0.395, 0.360 + dy), control2: p(0.360, 0.340 + dy))
bird.addCurve(to: p(0.170, 0.240 + dy), control1: p(0.275, 0.298 + dy), control2: p(0.230, 0.270 + dy))
bird.addCurve(to: p(0.050, 0.155 + dy), control1: p(0.105, 0.210 + dy), control2: p(0.055, 0.175 + dy))

// Left wingtip
bird.addCurve(to: p(0.130, 0.140 + dy), control1: p(0.062, 0.140 + dy), control2: p(0.090, 0.134 + dy))

// Left wing leading edge back to shoulder
bird.addCurve(to: p(0.280, 0.195 + dy), control1: p(0.175, 0.148 + dy), control2: p(0.230, 0.170 + dy))
bird.addCurve(to: p(0.445, 0.270 + dy), control1: p(0.330, 0.225 + dy), control2: p(0.390, 0.258 + dy))

// Left shoulder to neck
bird.addCurve(to: p(0.480, 0.260 + dy), control1: p(0.460, 0.270 + dy), control2: p(0.472, 0.268 + dy))

// Head left side back to top
bird.addCurve(to: p(0.488, 0.215 + dy), control1: p(0.480, 0.238 + dy), control2: p(0.478, 0.215 + dy))

bird.closeSubpath()

// Fill bird
ctx.setFillColor(CGColor(red: 1.0, green: 0.55, blue: 0.12, alpha: 1))
ctx.addPath(bird); ctx.fillPath()

// ── Eye ──
let er: CGFloat = w*0.011
ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
ctx.fillEllipse(in: CGRect(x: w*0.507-er, y: h*(0.242+dy)-er, width: er*2, height: er*2))

// ── Subtle wing line detail ──
ctx.setStrokeColor(CGColor(red: 0.65, green: 0.35, blue: 0.08, alpha: 0.25))
ctx.setLineWidth(1.2)
ctx.setLineCap(.round)

// Right wing feather lines
for i in 0..<3 {
    let f = CGFloat(i) * 0.08 + 0.04
    let lp = CGMutablePath()
    lp.move(to: p(0.56 + f*1.6, 0.285 + f*0.6 + dy))
    lp.addCurve(to: p(0.60 + f*2.8, 0.245 - f*0.3 + dy),
                control1: p(0.58 + f*2.0, 0.275 + f*0.2 + dy),
                control2: p(0.59 + f*2.4, 0.260 + dy))
    ctx.addPath(lp); ctx.strokePath()
}
// Left mirror
for i in 0..<3 {
    let f = CGFloat(i) * 0.08 + 0.04
    let lp = CGMutablePath()
    lp.move(to: p(0.44 - f*1.6, 0.285 + f*0.6 + dy))
    lp.addCurve(to: p(0.40 - f*2.8, 0.245 - f*0.3 + dy),
                control1: p(0.42 - f*2.0, 0.275 + f*0.2 + dy),
                control2: p(0.41 - f*2.4, 0.260 + dy))
    ctx.addPath(lp); ctx.strokePath()
}

// Tail barring
ctx.setStrokeColor(CGColor(red: 0.65, green: 0.35, blue: 0.08, alpha: 0.2))
for i in 0..<3 {
    let ty = 0.62 + CGFloat(i)*0.035 + dy
    let tw = 0.035 + CGFloat(i)*0.008
    let lp = CGMutablePath()
    lp.move(to: p(0.50 - tw, ty))
    lp.addLine(to: p(0.50 + tw, ty))
    ctx.addPath(lp); ctx.strokePath()
}

// ── Scanlines ──
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.03))
var sy: CGFloat = 0
while sy < h { ctx.fill(CGRect(x: 0, y: sy, width: w, height: 1)); sy += 3 }

// ── "KESTREL" text ──
let font = CTFontCreateWithName("Menlo-Regular" as CFString, w*0.040, nil)
let attrs: [NSAttributedString.Key: Any] = [
    NSAttributedString.Key(rawValue: kCTFontAttributeName as String): font,
    NSAttributedString.Key(rawValue: kCTForegroundColorAttributeName as String):
        CGColor(red: 1.0, green: 0.55, blue: 0.12, alpha: 0.50),
    NSAttributedString.Key(rawValue: kCTKernAttributeName as String): w * 0.016
]
let line = CTLineCreateWithAttributedString(NSAttributedString(string: "KESTREL", attributes: attrs))
let tb = CTLineGetBoundsWithOptions(line, [])
ctx.saveGState(); ctx.translateBy(x: 0, y: h); ctx.scaleBy(x: 1, y: -1)
ctx.textPosition = CGPoint(x: (w-tb.width)/2 - tb.origin.x, y: h*0.095)
CTLineDraw(line, ctx); ctx.restoreGState()

// ── Export ──
guard let img = ctx.makeImage() else { exit(1) }
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "KestrelAppIcon.png"
guard let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL,
                                               UTType.png.identifier as CFString, 1, nil) else { exit(1) }
CGImageDestinationAddImage(d, img, nil)
guard CGImageDestinationFinalize(d) else { exit(1) }
if let a = try? FileManager.default.attributesOfItem(atPath: out), let s = a[.size] as? Int {
    print("✓ \(out) — 1024×1024, \(s/1024) KB")
}
