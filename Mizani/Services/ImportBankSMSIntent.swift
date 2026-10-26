import AppIntents
import Foundation

struct ImportBankSMSIntent: AppIntent {
    static var title: LocalizedStringResource = "تسجيل رسالة بنكية"
    static var description = IntentDescription("حلّل نص رسالة بنك مسقط واحفظ العملية محلياً في ميزاني.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "نص الرسالة", description: "اختر محتوى الرسالة من إدخال الاختصار.")
    var message: String

    static var parameterSummary: some ParameterSummary { Summary("تسجيل الرسالة \(\.$message)") }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let result = try WalletStore.shared.perform("import", ["text": message])
        let issues = result.errors ?? []
        if result.added == 0 && result.duplicates == 0 {
            throw WalletError(message: issues.first?.message ?? "لم يتم العثور على عملية بنكية.")
        }
        let report = "أضيفت \(result.added ?? 0) عملية، وتجاهلت \(result.duplicates ?? 0) مكررة، وتعذر تحليل \(issues.count)."
        return .result(value: report)
    }
}
