import SwiftUI

struct EnvelopesView: View {
    @EnvironmentObject private var store: WalletStore
    @State private var adding = false
    @State private var editing: Envelope?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("قسّم الموجود، وخطّط للقادم.").font(.title2.bold())
                    Text("خصّص مبالغ للمصاريف والمهام والادخار حسب الرصيد المتوفر. اربط كل عملية بمخصصها من صفحة التفاصيل، أو أضف قاعدة تصنيف تلقائي.").font(.subheadline).foregroundStyle(.secondary)
                    ForEach(store.data?.snapshot.accounts ?? []) { a in
                        Card {
                            HStack {
                                VStack(alignment: .leading, spacing: 6) { Text(a.shortName).font(.caption).foregroundStyle(.secondary); Text("متاح للتوزيع").font(.subheadline) }
                                Spacer(); MoneyLabel(amount: a.available)
                            }
                        }
                    }
                    if (store.data?.snapshot.envelopes ?? []).isEmpty { Card { EmptyWallet(symbol: "leaf", title: "أعطِ مالك وجهة", message: "ابدأ بمخصص للمصروف اليومي وآخر للادخار.") } }
                    ForEach(store.data?.snapshot.envelopes ?? []) { e in
                        Button {
                            editing = store.data?.state.envelopes.first { $0.id == e.id }
                        } label: { Card { EnvelopeRow(envelope: e) } }.buttonStyle(.plain)
                    }
                    Button { adding = true } label: { Label("مخصص جديد", systemImage: "plus") }.buttonStyle(PrimaryButton())
                    Text("المخصصات مستمرة حتى تعدّلها أو تحذفها. إعادة تعبئتها تكون بزيادة إجمالي المبلغ المخصص. لا يُحوّل التطبيق الأموال إلى حساب ادخار.").font(.caption).foregroundStyle(.secondary)
                }.padding(20)
            }.background(Theme.background).navigationTitle("خطتي")
                .sheet(isPresented: $adding) { EnvelopeEditor(envelope: nil).modifier(WalletErrorBanner()) }
                .sheet(item: $editing) { EnvelopeEditor(envelope: $0).modifier(WalletErrorBanner()) }
        }
    }
}

struct EnvelopeEditor: View {
    var envelope: Envelope?
    @EnvironmentObject private var store: WalletStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var amount = ""
    @State private var account = ""
    @State private var kind = "spending"
    @State private var deleting = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("الاسم: طوارئ، سيارة، مصروف…", text: $name)
                    AccountPicker(account: $account).disabled(envelope != nil)
                    Picker("الغرض", selection: $kind) { Text("مصاريف أو مهمة").tag("spending"); Text("ادخار").tag("saving") }
                    AmountField(title: "إجمالي المبلغ المخصص", text: $amount)
                } footer: { Text("يُحجز المتبقي من هذا المخصص ضمن خطتك. عند ربط مصروف به ينخفض المتبقي؛ لا يُخصم المصروف مرة ثانية من رصيد الرسالة البنكية.") }
                Button("حفظ المخصص") {
                    var p: [String: Any] = ["name": name, "account": account, "kind": kind, "amount": amount]
                    if let envelope { p["id"] = envelope.id }
                    if store.save("envelope", p) { dismiss() }
                }.disabled(name.isEmpty || account.isEmpty || amount.isEmpty)
                if envelope != nil { Button("حذف المخصص", role: .destructive) { deleting = true } }
            }.navigationTitle(envelope == nil ? "مخصص جديد" : "تعديل المخصص").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } } }
                .onAppear {
                    name = envelope?.name ?? ""; amount = envelope.map { Amount.text($0.allocated) } ?? ""
                    account = envelope?.account ?? store.data?.snapshot.accounts.first?.account ?? ""; kind = envelope?.kind ?? "spending"
                }
                .confirmationDialog("سيُحذف المخصص وتبقى عملياته في السجل.", isPresented: $deleting, titleVisibility: .visible) {
                    Button("حذف", role: .destructive) { if let envelope, store.save("deleteEnvelope", ["id": envelope.id]) { dismiss() } }
                }
        }
    }
}
