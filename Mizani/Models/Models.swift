import Foundation

struct Transaction: Codable, Identifiable, Hashable {
    var id: String
    var fingerprint: String?
    var transactionID: String?
    var account: String
    var kind: String
    var amount: Int64
    var bankBalance: Int64?
    var party: String
    var occurredAt: String
    var dateEstimated: Bool
    var receivedAt: String
    var category: String
    var envelopeID: String?
    var excluded: Bool
    var source: String
    var isDebit: Bool { ["outgoing", "purchase", "expense"].contains(kind) }
    var date: Date { Dates.parse(occurredAt) ?? .now }
    var kindTitle: String {
        switch kind {
        case "outgoing": return "تحويل صادر"
        case "incoming": return "تحويل وارد"
        case "purchase": return "شراء بالبطاقة"
        case "refund": return "استرجاع"
        case "deposit": return "إيداع نقدي"
        case "expense": return "مصروف يدوي"
        default: return "دخل يدوي"
        }
    }
    var symbol: String {
        switch kind {
        case "refund": return "arrow.uturn.backward"
        case "purchase", "expense": return "creditcard"
        case "deposit": return "banknote"
        default: return isDebit ? "arrow.up.right" : "arrow.down.left"
        }
    }
}

struct Envelope: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var account: String
    var kind: String
    var allocated: Int64
}
struct EnvelopeSummary: Codable, Identifiable {
    var id: String
    var name: String
    var account: String
    var kind: String
    var allocated: Int64
    var spent: Int64
    var remaining: Int64
    var overspent: Int64
    var percent: Int
}
struct ClassificationRule: Codable, Identifiable {
    var keyword: String
    var category: String
    var envelopeID: String?
    var id: String { keyword }
}
struct BalanceAnchor: Codable { var account: String; var amount: Int64; var date: String }
struct Settings: Codable { var lowBalance: Int64; var monthlyLimit: Int64; var warningPercent: Int }
struct WalletState: Codable {
    var version: Int
    var transactions: [Transaction]
    var envelopes: [Envelope]
    var rules: [ClassificationRule]
    var anchors: [BalanceAnchor]
    var settings: Settings
}
struct AccountSummary: Codable, Identifiable {
    var account: String
    var balance: Int64?
    var balanceDate: String?
    var origin: String?
    var reserved: Int64
    var available: Int64?
    var id: String { account }
    var shortName: String { "الحساب • " + account.suffix(4) }
}
struct WalletAlert: Codable, Identifiable {
    var id: String; var title: String; var detail: String; var level: String
    var signature: String { id + "|" + title + "|" + level }
}
struct CategorySummary: Codable, Identifiable { var name: String; var amount: Int64; var id: String { name } }
struct WalletSummary: Codable {
    var accounts: [AccountSummary]
    var envelopes: [EnvelopeSummary]
    var alerts: [WalletAlert]
    var expenses: Int64
    var refunds: Int64
    var netExpense: Int64
    var income: Int64
    var pending: Int
    var month: String
    var categories: [CategorySummary]
}
struct ImportIssue: Codable, Identifiable { var index: Int; var message: String; var id: Int { index } }
struct ActionResult: Codable {
    var added: Int?
    var duplicates: Int?
    var errors: [ImportIssue]?
    var restored: Bool?
}
struct EngineData: Codable { var state: WalletState; var snapshot: WalletSummary; var result: ActionResult }
struct EngineReply: Decodable { var ok: Bool; var data: EngineData?; var error: String? }

enum Dates {
    static func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }
    static func parse(_ value: String) -> Date? {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
    static func display(_ value: String) -> String {
        guard let d = parse(value) else { return "—" }
        let f = DateFormatter(); f.locale = Locale(identifier: "ar_OM"); f.timeZone = TimeZone(identifier: "Asia/Muscat")
        f.dateStyle = .medium; f.timeStyle = .short; return f.string(from: d)
    }
}
enum Amount {
    static func text(_ baisa: Int64) -> String {
        let n = abs(baisa)
        return (baisa < 0 ? "−" : "") + String(n / 1000) + "." + String(format: "%03lld", n % 1000)
    }
    static func currency(_ value: Int64?) -> String { value.map { text($0) + " ر.ع" } ?? "غير محدد" }
}
struct WalletError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}
