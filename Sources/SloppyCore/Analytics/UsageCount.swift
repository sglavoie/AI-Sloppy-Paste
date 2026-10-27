/// Arithmetic for usage counters decoded from externally editable data.
public enum UsageCount {
    /// Adds without trapping or wrapping when imported counts reach an Int
    /// boundary. Ordinary counts remain exact; overflow saturates at the bound.
    public static func adding(_ lhs: Int, _ rhs: Int) -> Int {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? (rhs >= 0 ? Int.max : Int.min) : sum
    }
}
