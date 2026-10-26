import SwiftUI
import UniformTypeIdentifiers
import LocalAuthentication

struct SettingsView: View {
    @EnvironmentObject private var store: WalletStore
    @AppStorage("appLockEnabled") private var lockEnabled = false
    @State private var lowBalance = "10.000"
    @State private var monthlyLimit = "0.000"
    @State private var percent = 80
    @State private var status = ""
    @State private var showingAnchor = false
    @State private var showingRule = false
    @State private var exportURL: URL?
    @State private var importingBackup = false
    @State private var pendingBackup: String?
    @State private var confirmRestore = false
    var body: some View {
        NavigationStack {
            Form {
                Section("الرسائل والاختصارات") {
                    NavigationLink { ShortcutsGuideView() } label: { Label("إعداد الالتقاط التلقائي", systemImage: "square.stack.3d.up") }
                    Text("يستقبل التطبيق النص من اختصار الرسائل. إعداد الأتمتة يتم مرة واحدة على هاتفك.").font(.caption).foregroundStyle(.secondary)
                }
                Section("حدود وتنبيهات") {
                    AmountField(title: "حد انخفاض الرصيد", text: $lowBalance)
                    AmountField(title: "حد المصروف الشهري", text: $monthlyLimit)
                    Stepper("تنبيه عند استهلاك \(percent)%", value: $percent, in: 1...100)
                    Text("ضع حد المصروف الشهري 0 لتعطيله. حدود المخصصات مستمرة، والحد الشهري يُحسب حسب توقيت مسقط.").font(.caption).foregroundStyle(.secondary)
                    Button("حفظ الحدود") { if store.save("settings", ["lowBalance": lowBalance, "monthlyLimit": monthlyLimit, "warningPercent": percent]) { status = "تم حفظ الحدود." } }
                    Button("السماح بإشعارات iPhone") { Task { status = await Notifications.requestPermission() } }
                }
                Section("الحساب والخصوصية") {
                    Button("إدخال أو تصحيح الرصيد الحالي") { showingAnchor = true }
                    Toggle("قفل التطبيق بـ Face ID أو رمز الجهاز", isOn: Binding(get: { lockEnabled }, set: { value in
                        Task { @MainActor in
                            do {
                                let verified = try await LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "تأكيد تغيير قفل ميزاني")
                                if verified { lockEnabled = value }
                            } catch { status = "لم يتغير إعداد القفل. فعّل رمز قفل الجهاز وأعد المحاولة." }
                        }
                    }))
                    Text("التحليل محلي، بلا حساب أو خدمات خارجية. حماية ملف البيانات تسمح للاختصار بالعمل بعد أول فتح للهاتف عقب إعادة التشغيل. قفل الواجهة لا يوقف استقبال الاختصار.").font(.caption).foregroundStyle(.secondary)
                }
                Section("قواعد التصنيف التلقائي") {
                    ForEach(store.data?.state.rules ?? []) { r in
                        HStack { VStack(alignment: .leading) { Text(r.keyword); Text(r.category).font(.caption).foregroundStyle(.secondary) }; Spacer(); Button(role: .destructive) { _ = store.save("deleteRule", ["keyword": r.keyword]) } label: { Image(systemName: "trash") } }
                    }
                    Button("إضافة قاعدة جديدة") { showingRule = true }
                    Text("تُطبّق القواعد على الرسائل الجديدة حسب اسم الجهة. راجع تصنيف التحويلات والاسترجاعات من تفاصيل العملية.").font(.caption).foregroundStyle(.secondary)
                }
                Section("نسخة احتياطية وتصدير") {
                    Button("تجهيز نسخة احتياطية JSON") { do { exportURL = try store.exportJSON() } catch { status = error.localizedDescription } }
                    Button("تصدير العمليات CSV") { do { exportURL = try store.exportCSV() } catch { status = error.localizedDescription } }
                    if let exportURL { ShareLink(item: exportURL) { Label("مشاركة الملف الجاهز", systemImage: "square.and.arrow.up") } }
                    Button("استعادة نسخة احتياطية") { importingBackup = true }
                    Text("ملفات التصدير تحتوي بياناتك المالية بنص مقروء. احفظها في مكان خاص. الاستعادة تستبدل البيانات الحالية بعد التأكيد.").font(.caption).foregroundStyle(.secondary)
                }
                if !status.isEmpty { Section { Text(status).font(.subheadline) } }
                Section { Text("ميزاني • نسخة أولية 0.1\nيدعم قوالب رسائل بنك مسقط المرفقة بالعربية والإنجليزية. الرصيد المعروض يتبع آخر إشعار مستورد وليس اتصالاً مباشراً بالبنك.").font(.caption).foregroundStyle(.secondary) }
            }.navigationTitle("الإعدادات")
                .onAppear { if let s = store.data?.state.settings { lowBalance = Amount.text(s.lowBalance); monthlyLimit = Amount.text(s.monthlyLimit); percent = s.warningPercent } }
                .sheet(isPresented: $showingAnchor) { BalanceEditor().modifier(WalletErrorBanner()) }
                .sheet(isPresented: $showingRule) { RuleEditor().modifier(WalletErrorBanner()) }
                .fileImporter(isPresented: $importingBackup, allowedContentTypes: [.json]) { result in
                    do {
                        let url = try result.get(); let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                        guard let size = attributes[.size] as? NSNumber, size.intValue <= 20_000_000 else { throw WalletError(message: "ملف النسخة أكبر من الحد المسموح.") }
                        pendingBackup = try String(contentsOf: url, encoding: .utf8); confirmRestore = true
                    } catch { status = error.localizedDescription }
                }
                .confirmationDialog("استبدال بيانات ميزاني الحالية بالنسخة المختارة؟ صدّر نسخة من بياناتك أولاً عند الحاجة.", isPresented: $confirmRestore, titleVisibility: .visible) {
                    Button("استبدال البيانات", role: .destructive) {
                        if let pendingBackup, store.save("restore", ["data": pendingBackup]) { status = "تمت الاستعادة." }
                        pendingBackup = nil
                    }
                    Button("إلغاء", role: .cancel) { pendingBackup = nil }
                }
        }
    }
}

struct BalanceEditor: View {
    @EnvironmentObject private var store: WalletStore
    @Environment(\.dismiss) private var dismiss
    @State private var account = ""
    @State private var amount = ""
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if !(store.data?.snapshot.accounts ?? []).isEmpty { AccountPicker(account: $account) }
                    TextField("رقم الحساب كما يظهر في الرسالة", text: $account).textInputAutocapitalization(.characters).autocorrectionDisabled().environment(\.layoutDirection, .leftToRight)
                    AmountField(title: "الرصيد المتاح الآن", text: $amount)
                } footer: { Text("استخدم رقم الحساب المقنّع نفسه الموجود في رسائلك لربط العمليات به. سيثبت الرصيد في الوقت الحالي، وتتجاوزه الرسائل الأحدث فقط.") }
                Button("تثبيت الرصيد") { if store.save("anchor", ["account": account, "amount": amount]) { dismiss() } }.disabled(account.isEmpty || amount.isEmpty)
            }.navigationTitle("رصيد الحساب").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } } }
                .onAppear { account = store.data?.snapshot.accounts.first?.account ?? "" }
        }
    }
}

struct RuleEditor: View {
    @EnvironmentObject private var store: WalletStore
    @Environment(\.dismiss) private var dismiss
    @State private var keyword = ""
    @State private var category = ""
    @State private var account = ""
    @State private var envelopeID = ""
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("جزء من اسم الجهة، مثل ROP", text: $keyword).autocorrectionDisabled()
                    TextField("التصنيف، مثل خدمات حكومية", text: $category)
                    AccountPicker(account: $account)
                    EnvelopePicker(selection: $envelopeID, account: account)
                } footer: { Text("إذا احتوى اسم الجهة على النص، سيُستخدم التصنيف تلقائياً. يربط المخصص فقط بعمليات الحساب نفسه. القاعدة الجديدة تستبدل القاعدة التي تحمل النص نفسه.") }
                Button("حفظ القاعدة") { if store.save("rule", ["keyword": keyword, "category": category, "envelopeID": envelopeID]) { dismiss() } }.disabled(keyword.isEmpty || category.isEmpty)
            }.navigationTitle("قاعدة تصنيف").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } } }
                .onAppear { account = store.data?.snapshot.accounts.first?.account ?? "" }
                .onChange(of: account) { _, _ in envelopeID = "" }
        }
    }
}

struct ShortcutsGuideView: View {
    var body: some View {
        List {
            Section {
                Text("بعد تثبيت التطبيق وفتحه مرة واحدة، أنشئ أتمتة على الآيفون لاستقبال الرسائل. التطبيق لا يقرأ صندوق رسائلك السابق بنفسه.")
            }
            Section("الإعداد") {
                step("1", "افتح تطبيق الاختصارات", "أنشئ أتمتة جديدة، واختر عند استلام رسالة. قد يختلف مكان الأتمتة حسب إصدار iOS.")
                step("2", "اختر رسائل البنك", "اختر مرسل البنك إذا أمكن، أو شرط احتواء الرسالة على OMR. إن أضفت الشرطين معاً، يجب تحققهما معاً.")
                step("3", "فعّل التشغيل التلقائي", "اختر التشغيل فوراً أو أوقف التأكيد قبل التشغيل بحسب الخيارات التي تظهر في إصدارك.")
                step("4", "أضف إجراء ميزاني", "ابحث عن إجراء: تسجيل رسالة بنكية. حدّد حقل نص الرسالة ثم اختر إدخال الاختصار، ومنه خاصية محتوى الرسالة / Message أو Body؛ اختر النص، وليس اسم المرسل.")
                step("5", "اختبره أولاً", "جرّب الإجراء بنص رسالة مؤرخة، ثم تأكد من وصول عملية جديدة تلقائياً. فعّل الإشعارات من إعدادات ميزاني.")
            }
            Section("إذا لم يظهر الإجراء") {
                Text("افتح ميزاني مرة ثم أعد فتح الاختصارات. يمكنك دائماً نسخ الرسالة ولصقها في إضافة رسالة داخل التطبيق.")
            }
            Section("الرسائل بلا تاريخ") {
                Text("بعض رسائل الاستلام لا تحتوي تاريخاً. ستُحفظ للمراجعة، وتحتاج تأكيد تاريخها من تفاصيل العملية قبل استخدامها في الرصيد أو التقرير.")
            }
            Section {
                Link("دليل Apple لمحفزات الرسائل", destination: URL(string: "https://support.apple.com/en-ae/guide/shortcuts/apdd711f9dff/ios")!)
            }
        }.navigationTitle("ربط الاختصارات").navigationBarTitleDisplayMode(.inline)
    }
    private func step(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Text(number).font(.headline).foregroundStyle(Theme.teal).frame(width: 28, height: 28).background(Theme.teal.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 7) { Text(title).font(.headline); Text(detail).font(.subheadline).foregroundStyle(.secondary) }.padding(.vertical, 6)
        }
    }
}
