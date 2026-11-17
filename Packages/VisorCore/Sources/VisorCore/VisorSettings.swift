/// User settings with defaults and validation. Missing keys decode to defaults; `nil` modifier/combo mean "Off".
public struct VisorSettings: Codable, Equatable, Sendable {
    public static let heightPercentRange = 20...90
    public static let heightPercentStep = 5
    public static let defaultHeightPercent = 50
    public static let allowedHeightPercents = Array(stride(from: heightPercentRange.lowerBound,
                                                           through: heightPercentRange.upperBound,
                                                           by: heightPercentStep))

    /// Double-tap trigger; `nil` = Off.
    public var doubleTapModifier: ModifierKey?
    /// Key combo trigger; `nil` = cleared/disabled.
    public var combo: KeyCombo?
    /// Always one of `allowedHeightPercents`.
    public var heightPercent: Int {
        didSet { heightPercent = Self.validatedHeightPercent(heightPercent) }
    }

    public init(
        doubleTapModifier: ModifierKey? = .option,
        combo: KeyCombo? = .defaultCombo,
        heightPercent: Int = defaultHeightPercent
    ) {
        self.doubleTapModifier = doubleTapModifier
        self.combo = combo
        self.heightPercent = Self.validatedHeightPercent(heightPercent)
    }

    public static let `default` = VisorSettings()

    /// Clamps to 20...90 and rounds to the nearest multiple of 5 (halves round up).
    public static func validatedHeightPercent(_ value: Int) -> Int {
        let clamped = min(max(value, heightPercentRange.lowerBound), heightPercentRange.upperBound)
        let steps = (Double(clamped) / Double(heightPercentStep)).rounded(.toNearestOrAwayFromZero)
        return Int(steps) * heightPercentStep
    }

    private enum CodingKeys: String, CodingKey { case doubleTapModifier, combo, heightPercent }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = VisorSettings()
        self.init(
            doubleTapModifier: c.contains(.doubleTapModifier)
                ? try c.decodeIfPresent(ModifierKey.self, forKey: .doubleTapModifier)
                : defaults.doubleTapModifier,
            combo: c.contains(.combo) ? try c.decodeIfPresent(KeyCombo.self, forKey: .combo) : defaults.combo,
            heightPercent: try c.decodeIfPresent(Int.self, forKey: .heightPercent) ?? defaults.heightPercent
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        // Encode nil explicitly so "Off" survives a round trip instead of reverting to the default.
        try c.encode(doubleTapModifier, forKey: .doubleTapModifier)
        try c.encode(combo, forKey: .combo)
        try c.encode(heightPercent, forKey: .heightPercent)
    }
}
