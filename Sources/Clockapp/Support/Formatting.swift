import Foundation

enum Format {
    /// "2:14:37" (menubar, seconds) or "2:14" (compact).
    static func clock(_ interval: TimeInterval, seconds: Bool = true) -> String {
        let total = max(0, Int(interval))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if seconds {
            return h > 0
                ? String(format: "%d:%02d:%02d", h, m, s)
                : String(format: "%d:%02d", m, s)
        }
        return String(format: "%d:%02d", h, m)
    }

    /// "6h12" from minutes.
    static func hoursMinutes(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        return h > 0 ? "\(h)h\(String(format: "%02d", m))" : "\(m)min"
    }

    /// "6h12" from a duration.
    static func hoursMinutes(_ interval: TimeInterval) -> String {
        hoursMinutes(Int(interval) / 60)
    }

    private static let moneyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = " "
        f.maximumFractionDigits = 0
        return f
    }()

    /// "1 234 €" or "$1 234" — grouped, no decimals, symbol per currency convention.
    static func money(_ amount: Double, _ currency: Currency) -> String {
        let n = moneyFormatter.string(from: NSNumber(value: amount)) ?? "0"
        return currency.symbolBefore ? "\(currency.symbol)\(n)" : "\(n) \(currency.symbol)"
    }

    /// "1 234 € (~1 409 $)" — primary amount plus its converted equivalent when known.
    static func money(_ amount: Double, _ currency: Currency, converted: Double?) -> String {
        let primary = money(amount, currency)
        guard let converted else { return primary }
        return "\(primary) (~\(money(converted, currency.other)))"
    }
}
