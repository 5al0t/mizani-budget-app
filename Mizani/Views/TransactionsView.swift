import SwiftUI

struct TransactionsView: View {
    @EnvironmentObject private var store: WalletStore
    @State private var search = ""
    @State private var filter = "all"
    @State private var importing = false
    @State private var manual = false
    var filtered: [Transaction] {
        (store.data?.state.transactions ?? []).filter { t in
            (search.isEmpty || (t.party + t.category + t.account + (t.transactionID ?? "")).localizedCaseInsensitiveContains(search)) &&
            (filter == "all" || (filter == "debit" && t.isDebit) || (filter == "credit" && !t.isDebit) || (filter == "review" && t.dateEstimated))
        }.sorted { $0.occurredAt > $1.occurredAt }
    }
    var body: some View {
        NavigationStack {
            List {
                Picker("عرض", selection: $filter) { Text("الكل").tag("all"); Text("مصروف").tag("debit"); Text("وارد").tag("credit"); Text("للمراجعة").tag("review") }.pickerStyle(.segmented).listRowBackground(Color.clear)
                if filtered.isEmpty { EmptyWallet(title: "لا توجد عمليات", message: "أضف رسائلك البنكية أو غيّر خيارات البحث.").listRowBackground(Color.clear) }
                ForEach(filtered) { t in NavigationLink(value: t) { TransactionRow(transaction: t) } }
            }.navigationTitle("العمليات").searchable(text: $search, prompt: "ابحث عن جهة أو تصنيف")
                .navigationDestination(for: Transaction.self) { TransactionDetail(transaction: $0) }
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Menu { Button("إضافة رسالة", systemImage: "plus.bubble") { importing = true }; Button("عملية يدوية", systemImage: "square.and.pencil") { manual = true } } label: { Image(systemName: "plus") } } }
                .sheet(isPresented: $importing) { ImportSMSView().modifier(WalletErrorBanner()) }.sheet(isPresented: $manual) { ManualTransactionView().modifier(WalletErrorBanner()) }
        }
    }
}

struct ImportSMSView: View {
    @EnvironmentObject private var store: WalletStore
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var result: ActionResult?
    @State private var localError: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text).frame(minHeight: 220).environment(\.layoutDirection, .leftToRight).font(.system(.body, design: .monospaced)).autocorrectionDisabled()
                    PasteButton(payloadType: String.self) { values in text = values.joined(separator: "\n\n"); result = nil }
                } header: { Text("نص رسالة بنك مسقط") } footer: { Text("يمكن لصق عدة رسائل، مع سطر فارغ بين كل رسالة وأخرى. لا يُحفظ النص الخام بعد التحليل.") }
                Section {
                    Button("تحليل وحفظ") {
                        do { result = try store.perform("import", ["text": text]); localError = nil }
                        catch { localError = error.localizedDescription }
                    }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let localError { Text(localError).foregroundStyle(.red) }
                if let result {
                    Section("نتيجة الاستيراد") {
                        Label("أضيفت \(result.added ?? 0) عملية", systemImage: "checkmark.circle")
                        Text("تم تجاهل \(result.duplicates ?? 0) رسالة مكررة")
                        ForEach(result.errors ?? []) { issue in Text("الرسالة \(issue.index): \(issue.message)").foregroundStyle(.orange) }
                    }
                }
            }.navigationTitle("إضافة رسائل").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("تم") { dismiss() } } }
        }
    }
}

struct TransactionDetail: View {
    var transaction: Transaction
    @EnvironmentObject private var store: WalletStore
    @Environment(\.dismiss) private var dismiss
    @State private var category = ""
    @State private var envelopeID = ""
    @State private var excluded = false
    @State private var date = Date.now
    @State private var confirmDate = false
    @State private var deleting = false
    var current: Transaction { store.data?.state.transactions.first { $0.id == transaction.id } ?? transaction }
    var body: some View {
        Form {
            Section {
                HStack { Text(current.kindTitle); Spacer(); MoneyLabel(amount: current.amount) }
                LabeledContent("الجهة", value: current.party)
                LabeledContent("الحساب", value: current.account).environment(\.layoutDirection, .leftToRight)
                if let id = current.transactionID { LabeledContent("رقم العملية", value: id).textSelection(.enabled) }
                if let balance = current.bankBalance { LabeledContent("رصيد الرسالة", value: Amount.currency(balance)) }
                Text(current.dateEstimated ? "الرسالة لا تحتوي تاريخاً. تاريخ العرض هو وقت الاستيراد فقط." : Dates.display(current.occurredAt)).font(.caption).foregroundStyle(.secondary)
            }
            Section("تنظيم العملية") {
                TextField("التصنيف", text: $category)
                EnvelopePicker(selection: $envelopeID, account: current.account)
                Toggle("استبعاد من تقارير المصروفات", isOn: $excluded)
                Text("استخدم الاستبعاد لتحويلاتك بين حساباتك. يبقى تأثيرها على رصيد البنك كما ورد في الرسالة.").font(.caption).foregroundStyle(.secondary)
            }
            if current.dateEstimated {
                Section("تأكيد التاريخ المفقود") {
                    Toggle("أعرف تاريخ العملية", isOn: $confirmDate)
                    if confirmDate { DatePicker("التاريخ والوقت", selection: $date, in: ...Date.now).environment(\.timeZone, TimeZone(identifier: "Asia/Muscat")!) }
                }
            }
            Section {
                Button("حفظ التغييرات") {
                    var p: [String: Any] = ["id": current.id, "category": category, "envelopeID": envelopeID, "excluded": excluded]
                    if current.dateEstimated && confirmDate { p["date"] = Dates.iso(date) }
                    if store.save("editTransaction", p) { dismiss() }
                }
                Button("حذف العملية", role: .destructive) { deleting = true }
            }
        }.navigationTitle("تفاصيل العملية").navigationBarTitleDisplayMode(.inline)
            .onAppear { category = current.category; envelopeID = current.envelopeID ?? ""; excluded = current.excluded; date = min(current.date, .now) }
            .confirmationDialog("حذف العملية سيعيد حساب الرصيد والتقارير.", isPresented: $deleting, titleVisibility: .visible) {
                Button("حذف", role: .destructive) { if store.save("deleteTransaction", ["id": current.id]) { dismiss() } }
            }
    }
}

struct ManualTransactionView: View {
    @EnvironmentObject private var store: WalletStore
    @Environment(\.dismiss) private var dismiss
    @State private var account = ""
    @State private var amount = ""
    @State private var party = ""
    @State private var category = "أخرى"
    @State private var kind = "expense"
    @State private var envelopeID = ""
    @State private var date = Date.now
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    AccountPicker(account: $account)
                    Picker("النوع", selection: $kind) { Text("مصروف").tag("expense"); Text("دخل").tag("income") }.pickerStyle(.segmented)
                    AmountField(title: "المبلغ", text: $amount)
                    TextField("الجهة أو الوصف", text: $party)
                    TextField("التصنيف", text: $category)
                    EnvelopePicker(selection: $envelopeID, account: account)
                    DatePicker("التاريخ", selection: $date, in: ...Date.now)
                } footer: { Text("هذه العملية تؤثر على رصيد الحساب إذا جاءت بعد آخر رصيد مثبت. لا تضف يدوياً عملية سبق استيراد رسالتها.") }
                Button("حفظ العملية") {
                    if store.save("manual", ["account": account, "amount": amount, "kind": kind, "party": party, "category": category, "envelopeID": envelopeID, "date": Dates.iso(date)]) { dismiss() }
                }.disabled(account.isEmpty || amount.isEmpty)
            }.navigationTitle("عملية يدوية").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } } }
                .onAppear { account = store.data?.snapshot.accounts.first?.account ?? "" }
                .onChange(of: account) { _, _ in envelopeID = "" }
        }
    }
}
