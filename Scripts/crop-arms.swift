#!/usr/bin/env swift
// Cuts the shield out of a coat of arms render, for arms on Commons that only come with their
// supporters, mantle and motto. Called by Scripts/fetch-wikimedia-art.py.
//
//   swift Scripts/crop-arms.swift in.png out.png left top right bottom shape height
//
// left/top/right/bottom: the shield's box as fractions of the image (origin at the top left).
// shape: the outline outside of which everything is cleared, so supporters' paws and hooves
//   touching the shield don't show in the corners:
//   rect          keep the whole box
//   heater:F      straight sides for the top F of the height, then curving in to a point
//   round:F       straight sides for the top F, then a half ellipse
//   oval          an ellipse filling the box
// height: the output height in pixels; the width follows the box's aspect ratio.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count == 9, let box = Optional(args[3...6].compactMap(Double.init)), box.count == 4,
      let outHeight = Int(args[8]) else {
    FileHandle.standardError.write("usage: crop-arms.swift in.png out.png left top right bottom shape height\n".data(using: .utf8)!)
    exit(2)
}
guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    FileHandle.standardError.write("cannot read \(args[1])\n".data(using: .utf8)!)
    exit(1)
}

let imageWidth = Double(image.width), imageHeight = Double(image.height)
let crop = CGRect(x: box[0] * imageWidth, y: box[1] * imageHeight,
                  width: (box[2] - box[0]) * imageWidth, height: (box[3] - box[1]) * imageHeight).integral
guard let cropped = image.cropping(to: crop) else { exit(1) }

let height = outHeight
let width = max(1, Int((Double(height) * crop.width / crop.height).rounded()))
let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
context.interpolationQuality = .high

// The outline, in output pixels with the origin at the bottom left (so "top" is maxY).
let w = CGFloat(width), h = CGFloat(height)
let path = CGMutablePath()
let parts = args[7].split(separator: ":")
let straight = parts.count > 1 ? CGFloat(Double(parts[1]) ?? 0.6) : 0.6
let sideBottom = h * (1 - straight)  // where the straight sides end
switch parts[0] {
case "rect":
    path.addRect(CGRect(x: 0, y: 0, width: w, height: h))
case "heater":
    path.move(to: CGPoint(x: 0, y: h))
    path.addLine(to: CGPoint(x: w, y: h))
    path.addLine(to: CGPoint(x: w, y: sideBottom))
    path.addQuadCurve(to: CGPoint(x: w / 2, y: 0), control: CGPoint(x: w, y: sideBottom * 0.35))
    path.addQuadCurve(to: CGPoint(x: 0, y: sideBottom), control: CGPoint(x: 0, y: sideBottom * 0.35))
    path.closeSubpath()
case "round":
    path.move(to: CGPoint(x: 0, y: h))
    path.addLine(to: CGPoint(x: w, y: h))
    path.addLine(to: CGPoint(x: w, y: sideBottom))
    path.addArc(center: .zero, radius: 1, startAngle: 0, endAngle: -.pi, clockwise: true,
                transform: CGAffineTransform(translationX: w / 2, y: sideBottom).scaledBy(x: w / 2, y: sideBottom))
    path.closeSubpath()
case "oval":
    path.addEllipse(in: CGRect(x: 0, y: 0, width: w, height: h))
default:
    FileHandle.standardError.write("unknown shape \(args[7])\n".data(using: .utf8)!)
    exit(2)
}
context.addPath(path)
context.clip()
context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))

guard let result = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[2]) as CFURL,
                                                        UTType.png.identifier as CFString, 1, nil) else { exit(1) }
CGImageDestinationAddImage(destination, result, nil)
exit(CGImageDestinationFinalize(destination) ? 0 : 1)
