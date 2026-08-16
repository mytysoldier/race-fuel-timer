import Foundation

enum DistanceParser {
    static func kilometers(from text: String, locale: Locale = .current) -> Double? {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.isLenient = false

        return formatter.number(from: text)?.doubleValue
    }
}
