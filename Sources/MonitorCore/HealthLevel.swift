/// Traffic-light level for a metric or for the whole system.
public enum HealthLevel: Int, Comparable, Sendable {
    case ok = 0
    case warning = 1
    case critical = 2

    public static func < (lhs: HealthLevel, rhs: HealthLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
