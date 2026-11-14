import Foundation
import ImageIO

guard CommandLine.arguments.count == 2 else {
    fputs("使い方: swift inspect-image-metadata.swift <画像ファイル>\n", stderr)
    exit(2)
}
let url = URL(fileURLWithPath: CommandLine.arguments[1])
guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
    fputs("画像のプロパティを読み取れませんでした\n", stderr)
    exit(2)
}
let hasGPS = properties[kCGImagePropertyGPSDictionary as String] != nil
print("画像形式: \(CGImageSourceGetType(source) ?? "不明" as CFString)")
print("サイズ: \(properties[kCGImagePropertyPixelWidth as String] ?? "?") × \(properties[kCGImagePropertyPixelHeight as String] ?? "?")")
print("GPS辞書: \(hasGPS ? "あり" : "なし")")
print("プロパティのキー: \(properties.keys.sorted().joined(separator: ", "))")
if hasGPS { exit(1) }
