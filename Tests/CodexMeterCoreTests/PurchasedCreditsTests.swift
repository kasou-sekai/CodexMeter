import XCTest
@testable import CodexMeterCore

final class PurchasedCreditsTests: XCTestCase {
    func testDecodesBalanceAndConvertsCreditsToDollars() throws {
        let result: [String: Any] = [
            "rateLimits": [
                "credits": [
                    "balance": "2500",
                    "hasCredits": true,
                    "unlimited": false
                ]
            ]
        ]

        let snapshot = try XCTUnwrap(
            CodexPurchasedCreditsSnapshot.decode(fromRateLimitsResult: result)
        )
        XCTAssertEqual(snapshot.balance, Decimal(2500))
        XCTAssertEqual(snapshot.dollarBalance, Decimal(100))
    }

    func testDecodesCreditsFromMultiBucketResponse() throws {
        let result: [String: Any] = [
            "rateLimitsByLimitId": [
                "codex": [
                    "credits": [
                        "balance": "12.5",
                        "hasCredits": true,
                        "unlimited": false
                    ]
                ]
            ]
        ]

        let snapshot = try XCTUnwrap(
            CodexPurchasedCreditsSnapshot.decode(fromRateLimitsResult: result)
        )
        XCTAssertEqual(snapshot.balance, Decimal(string: "12.5"))
        XCTAssertEqual(snapshot.dollarBalance, Decimal(string: "0.5"))
    }

    func testMissingCreditsRemainUnavailable() {
        XCTAssertNil(
            CodexPurchasedCreditsSnapshot.decode(
                fromRateLimitsResult: ["rateLimits": ["primary": [:]]]
            )
        )
    }
}
