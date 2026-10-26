import Foundation
import JavaScriptCore
import SwiftUI
import UserNotifications

@MainActor
final class WalletEngine {
    private let context: JSContext
    init() throws {
        guard let context = JSContext(), let url = Bundle.main.url(forResource: "core", withExtension: "js") else {
            throw WalletError(message: "تعذر تحميل محرك الحسابات.")
        }
        self.context = context
        context.evaluateScript(try String(contentsOf: url, encoding: .utf8))
        guard context.exception == nil else { throw WalletError(message: "تعذر تشغيل محرك الحسابات.") }
    }
    func execute(action: String, state: WalletState?, payload: [String: Any] = [:]) throws -> EngineData {
        var request: [String: Any] = ["action": action, "payload": payload, "now": Dates.iso(.now)]
        if let state { request["state"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) }
        let data = try JSONSerialization.data(withJSONObject: request, options: [.sortedKeys])
        guard let json = String(data: data, encoding: .utf8) else { throw WalletError(message: "تعذر تجهيز البيانات.") }
        context.exception = nil
        guard let value = context.objectForKeyedSubscript("mizaniExecute")?.call(withArguments: [json]),
              context.exception == nil, let output = value.toString()?.data(using: .utf8) else {
            throw WalletError(message: "تعذر معالجة العملية.")
        }
        let reply = try JSONDecoder().decode(EngineReply.self, from: output)
        guard reply.ok, let result = reply.data else { throw WalletError(message: reply.error ?? "حدث خطأ في البيانات.") }
        return result
    }
}

@MainActor
final class WalletStore: ObservableObject {
    static let shared = WalletStore()
    @Published private(set) var data: EngineData?
    @Published var errorMessage: String?
    private var engine: WalletEngine?
    private var fileURL: URL?

    private init() {
        do {
            engine = try WalletEngine()
            let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("Mizani", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            fileURL = folder.appendingPathComponent("wallet-v1.json")
            reload()
        } catch { errorMessage = error.localizedDescription }
    }
    private func coordinated(action: String, payload: [String: Any], write: Bool) throws -> EngineData {
        guard let engine, let fileURL else { throw WalletError(message: "المخزن غير متاح. أعد فتح التطبيق.") }
        var coordinationError: NSError?
        var outcome: Result<EngineData, Error>?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: fileURL, options: .forMerging, error: &coordinationError) { url in
            outcome = Result {
                let current: WalletState?
                if FileManager.default.fileExists(atPath: url.path) {
                    current = try JSONDecoder().decode(WalletState.self, from: Data(contentsOf: url))
                } else { current = nil }
                let result = try engine.execute(action: action, state: current, payload: payload)
                if write {
                    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
                    let encoded = try encoder.encode(result.state)
                    try encoded.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                }
                return result
            }
        }
        if let coordinationError { throw coordinationError }
        guard let outcome else { throw WalletError(message: "تعذر الوصول إلى ملف البيانات.") }
        return try outcome.get()
    }
    func reload() {
        do { data = try coordinated(action: "snapshot", payload: [:], write: false) }
        catch { errorMessage = "تعذر قراءة البيانات. لم يتم استبدال الملف. " + error.localizedDescription }
    }
    @discardableResult
    func perform(_ action: String, _ payload: [String: Any] = [:]) throws -> ActionResult {
        let previous = data?.snapshot.alerts ?? []
        let updated = try coordinated(action: action, payload: payload, write: true)
        data = updated
        if action != "restore" { Notifications.notifyNew(updated.snapshot.alerts, previous: previous) }
        return updated.result
    }
    @discardableResult
    func save(_ action: String, _ payload: [String: Any]) -> Bool {
        do { try perform(action, payload); return true }
        catch { errorMessage = error.localizedDescription; return false }
    }
    func exportJSON() throws -> URL {
        reload()
        guard let state = data?.state else { throw WalletError(message: "لا توجد بيانات للتصدير.") }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try temporaryExport(encoder.encode(state), name: "Mizani-backup.json")
    }
    func exportCSV() throws -> URL {
        reload()
        func cell(_ raw: String) -> String {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let safe = ["=", "+", "-", "@"].contains(String(trimmed.prefix(1))) ? "'" + raw : raw
            return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        var rows = ["date,type,amount_OMR,account,party,category,needs_date_review,excluded"]
        for t in data?.state.transactions ?? [] {
            rows.append([t.occurredAt, t.kindTitle, Amount.text(t.amount), t.account, t.party, t.category,
                         String(t.dateEstimated), String(t.excluded)].map(cell).joined(separator: ","))
        }
        return try temporaryExport(Data(("\u{FEFF}" + rows.joined(separator: "\r\n")).utf8), name: "Mizani-transactions.csv")
    }
    private func temporaryExport(_ content: Data, name: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        try content.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }
}

@MainActor
enum Notifications {
    static func requestPermission() async -> String {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            return granted ? "تم تفعيل التنبيهات." : "التنبيهات مغلقة. يمكنك تفعيلها من إعدادات iPhone."
        } catch { return error.localizedDescription }
    }
    static func notifyNew(_ alerts: [WalletAlert], previous: [WalletAlert]) {
        let old = Set(previous.map(\.signature))
        for alert in alerts where alert.level != "info" && !old.contains(alert.signature) {
            let content = UNMutableNotificationContent()
            content.title = "ميزاني • " + alert.title
            content.body = alert.detail
            content.sound = .default
            let request = UNNotificationRequest(identifier: alert.id, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request) { _ in }
        }
    }
}
