import Foundation

/// Fetches EUR↔USD rates from Frankfurter (European Central Bank data): free, no API
/// key, no rate limit. Rates are cached in-memory and refreshed at most once per day
/// (ECB publishes daily), so this makes at most one request per launch/day.
actor ExchangeRateService {
    static let shared = ExchangeRateService()

    private struct Cached {
        let rate: Double
        let fetched: Date
    }
    private var cache: [String: Cached] = [:]
    private let ttl: TimeInterval = 2 * 3600

    /// Rate to multiply an amount in `from` to get `to`. Nil if offline and uncached.
    func rate(from: Currency, to: Currency, now: Date = Date()) async -> Double? {
        if from == to { return 1 }
        let key = "\(from.rawValue)_\(to.rawValue)"
        if let c = cache[key], now.timeIntervalSince(c.fetched) < ttl {
            return c.rate
        }
        let base = from.rawValue.uppercased()
        let symbol = to.rawValue.uppercased()
        guard let url = URL(string: "https://api.frankfurter.dev/v1/latest?base=\(base)&symbols=\(symbol)") else {
            return cache[key]?.rate
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            guard let rate = decoded.rates[symbol] else { return cache[key]?.rate }
            cache[key] = Cached(rate: rate, fetched: now)
            return rate
        } catch {
            return cache[key]?.rate // fall back to a stale value if we have one
        }
    }

    private struct Response: Decodable {
        let rates: [String: Double]
    }
}

extension Currency {
    var other: Currency { self == .eur ? .usd : .eur }
}
