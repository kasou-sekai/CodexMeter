import Foundation

/// A purchased Codex credit balance reported by the local App Server.
/// This is distinct from banked rate-limit reset opportunities.
struct CodexPurchasedCreditsSnapshot: Equatable, Sendable {
    let balance: Decimal?
    let hasCredits: Bool
    let unlimited: Bool

    /// Codex bills 25 credits per US dollar.
    var dollarBalance: Decimal? {
        balance.map { $0 / 25 }
    }

    static func decode(fromRateLimitsResult result: [String: Any]) -> Self? {
        let snapshots: [[String: Any]]
        if let buckets = result["rateLimitsByLimitId"] as? [String: Any] {
            snapshots = buckets.keys.sorted().compactMap { buckets[$0] as? [String: Any] }
        } else if let snapshot = result["rateLimits"] as? [String: Any] {
            snapshots = [snapshot]
        } else {
            return nil
        }

        for snapshot in snapshots {
            guard let credits = snapshot["credits"] as? [String: Any],
                  let hasCredits = credits["hasCredits"] as? Bool,
                  let unlimited = credits["unlimited"] as? Bool else {
                continue
            }

            let balance = (credits["balance"] as? String).flatMap {
                Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX"))
            }
            return Self(balance: balance, hasCredits: hasCredits, unlimited: unlimited)
        }
        return nil
    }
}
