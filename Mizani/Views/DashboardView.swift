import SwiftUI
import Charts

struct DashboardView: View {
    @EnvironmentObject private var store: WalletStore
    @State private var importing = false
    @State private var manual = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("أهلاً بك في ميزاني").font(.caption).foregroundStyle(.secondary)
                            Text("كل ريال، له خطة.").font(.title.bold())
                        }
                        Spacer()
                        Image(systemName: "chart.pie.fill").font(.title).foregroundStyle(Theme.teal)
                    }.padding(.top, 8)
                    if let summary = store.data?.snapshot {
                        if summary.accounts.isEmpty {
                            Card { EmptyWallet(symbol: "bubble.left.and.text.bubble.right", title: "ابدأ برسالة من البنك", message: "الصق رسالة بنكية ليظهر رصيدك، أو أدخل الرصيد الحالي من الإعدادات.") }
                        }
                        ForEach(summary.accounts) { a in
                            VStack(alignment: .leading, spacing: 18) {
                                HStack { Text(a.shortName).font(.subheadline); Spacer(); Image(systemName: "building.columns") }
                                VStack(alignment: .leading, spacing: 5) { Text("الرصيد المتاح في البنك").font(.caption).opacity(0.75); MoneyLabel(amount: a.balance, large: true) }
                                Divider().overlay(.white.opacity(0.2))
                                HStack {
                                    VStack(alignment: .leading, spacing: 6) { Text("موزّع على خطتي").font(.caption); MoneyLabel(amount: a.reserved) }
                                    Spacer()
                                    VStack(alignment: .leading, spacing: 6) { Text("متاح للتوزيع").font(.caption); MoneyLabel(amount: a.available) }
                                }
                                if let date = a.balanceDate { Text((a.origin == "sms" ? "رصيد آخر رسالة: " : "تثبيت يدوي: ") + Dates.display(date)).font(.caption2).opacity(0.7) }
                                Text("التقسيم داخل التطبيق لتنظيم أموالك؛ الأموال تبقى في البنك.").font(.caption2).opacity(0.75)
                            }.padding(24).foregroundStyle(.white)
                                .background(LinearGradient(colors: [Theme.ink, Theme.teal], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 28))
                        }
                        HStack(spacing: 12) {
                            Button { importing = true } label: { Label("إضافة رسالة", systemImage: "plus.bubble") }.buttonStyle(PrimaryButton())
                            Button { manual = true } label: { Image(systemName: "plus").font(.headline).padding(16).background(Theme.teal.opacity(0.1), in: RoundedRectangle(cornerRadius: 16)) }.accessibilityLabel("إضافة عملية يدوية")
                        }
                        HStack(spacing: 12) {
                            Card { VStack(alignment: .leading, spacing: 9) { Label("الدخل المسجل", systemImage: "arrow.down.left").font(.caption).foregroundStyle(.secondary); MoneyLabel(amount: summary.income) } }
                            Card { VStack(alignment: .leading, spacing: 9) { Label("صافي المصروف", systemImage: "arrow.up.right").font(.caption).foregroundStyle(.secondary); MoneyLabel(amount: summary.netExpense) } }
                        }
                        Text("أرقام الشهر الحالي من العمليات المستوردة والمؤكدة فقط. يشمل المصروف التحويلات الصادرة ما لم تستبعدها.").font(.caption).foregroundStyle(.secondary)
                        if !summary.alerts.isEmpty {
                            Text("تحتاج انتباهك").font(.headline)
                            ForEach(summary.alerts) { a in
                                Card {
                                    HStack(alignment: .top, spacing: 12) {
                                        Image(systemName: a.level == "info" ? "info.circle" : "exclamationmark.circle").foregroundStyle(a.level == "danger" ? .red : Theme.amber)
                                        VStack(alignment: .leading, spacing: 6) { Text(a.title).font(.subheadline.bold()); Text(a.detail).font(.caption).foregroundStyle(.secondary) }
                                    }
                                }
                            }
                        }
                        if !summary.envelopes.isEmpty {
                            Text("خطتك المالية").font(.headline)
                            ForEach(summary.envelopes.prefix(3)) { e in Card { EnvelopeRow(envelope: e) } }
                        }
                        if !summary.categories.isEmpty {
                            Card {
                                VStack(alignment: .leading, spacing: 15) {
                                    Text("أين يذهب المال هذا الشهر؟").font(.headline)
                                    Chart(summary.categories.filter { $0.amount > 0 }) { c in
                                        BarMark(x: .value("ر.ع", Double(c.amount) / 1000), y: .value("الفئة", c.name)).foregroundStyle(Theme.teal.gradient).cornerRadius(5)
                                    }.frame(height: CGFloat(max(summary.categories.count, 2) * 42))
                                }
                            }
                        }
                        let recent = (store.data?.state.transactions ?? []).sorted { $0.occurredAt > $1.occurredAt }.prefix(5)
                        if !recent.isEmpty {
                            Text("آخر العمليات").font(.headline)
                            Card { VStack { ForEach(Array(recent)) { t in NavigationLink(value: t) { TransactionRow(transaction: t) }.buttonStyle(.plain); if t.id != recent.last?.id { Divider() } } } }
                        }
                    }
                }.padding(20)
            }.background(Theme.background).navigationTitle("ميزاني").navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: Transaction.self) { TransactionDetail(transaction: $0) }
                .refreshable { store.reload() }
                .sheet(isPresented: $importing) { ImportSMSView().modifier(WalletErrorBanner()) }
                .sheet(isPresented: $manual) { ManualTransactionView().modifier(WalletErrorBanner()) }
        }
    }
}
