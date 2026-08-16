import Foundation

enum DistanceParser {
    static func kilometers(from text: String, locale: Locale = .current) -> Double? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.isLenient = false

        var number: AnyObject?
        var parsedRange = NSRange(location: 0, length: trimmedText.utf16.count)

        do {
            try formatter.getObjectValue(&number, for: trimmedText, range: &parsedRange)
        } catch {
            return nil
        }

        guard parsedRange.length == trimmedText.utf16.count else {
            return nil
        }

        return (number as? NSNumber)?.doubleValue
    }
}
