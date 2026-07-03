import Foundation
import SwiftUI

struct Project: Identifiable, Codable, Equatable, Hashable {
    var id: String
    var name: String
    var colorHex: String?
    var clientName: String?

    var color: Color {
        guard let colorHex else { return .accentColor }
        return Color(hex: colorHex) ?? .accentColor
    }
}

extension Color {
    /// Parse a `#RRGGBB` (or `RRGGBB`) hex string.
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt64(s, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        self = Color(red: r, green: g, blue: b)
    }
}
