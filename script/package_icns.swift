#!/usr/bin/env swift
import Foundation

private struct IconEntry {
  let type: String
  let filename: String
}

private let entries = [
  IconEntry(type: "icp4", filename: "icon_16x16.png"),
  IconEntry(type: "ic11", filename: "icon_16x16@2x.png"),
  IconEntry(type: "icp5", filename: "icon_32x32.png"),
  IconEntry(type: "ic12", filename: "icon_32x32@2x.png"),
  IconEntry(type: "icp6", filename: "icon_32x32@2x.png"),
  IconEntry(type: "ic07", filename: "icon_128x128.png"),
  IconEntry(type: "ic13", filename: "icon_128x128@2x.png"),
  IconEntry(type: "ic08", filename: "icon_256x256.png"),
  IconEntry(type: "ic14", filename: "icon_256x256@2x.png"),
  IconEntry(type: "ic09", filename: "icon_512x512.png"),
  IconEntry(type: "ic10", filename: "icon_512x512@2x.png"),
]

private func encoded(_ value: UInt32) -> Data {
  var bigEndian = value.bigEndian
  return withUnsafeBytes(of: &bigEndian) { Data($0) }
}

private func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data("\(message)\n".utf8))
  exit(1)
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
  fail("usage: package_icns.swift <iconset-directory> <output.icns>")
}

let iconsetURL = URL(fileURLWithPath: arguments[1], isDirectory: true)
let outputURL = URL(fileURLWithPath: arguments[2])
var output = Data("icns".utf8)
output.append(encoded(0))

for entry in entries {
  guard let type = entry.type.data(using: .ascii), type.count == 4 else {
    fail("Invalid ICNS entry type: \(entry.type)")
  }

  let sourceURL = iconsetURL.appendingPathComponent(entry.filename)
  let image: Data
  do {
    image = try Data(contentsOf: sourceURL)
  } catch {
    fail("Could not read \(sourceURL.path): \(error.localizedDescription)")
  }

  let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
  guard image.starts(with: pngSignature) else {
    fail("Expected a PNG file at \(sourceURL.path)")
  }
  guard image.count <= Int(UInt32.max) - 8 else {
    fail("Icon entry is too large: \(sourceURL.path)")
  }

  output.append(type)
  output.append(encoded(UInt32(image.count + 8)))
  output.append(image)
}

guard output.count <= Int(UInt32.max) else {
  fail("ICNS output is too large")
}
output.replaceSubrange(4..<8, with: encoded(UInt32(output.count)))

do {
  try output.write(to: outputURL, options: .atomic)
} catch {
  fail("Could not write \(outputURL.path): \(error.localizedDescription)")
}
