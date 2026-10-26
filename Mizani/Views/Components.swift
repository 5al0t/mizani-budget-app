import SwiftUI

enum Theme {
    static let teal = Color(red: 0.04, green: 0.52, blue: 0.44)
    static let ink = Color(red: 0.04, green: 0.17, blue: 0.16)
    static let background = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let amber = Color(red: 0.80, green: 0.43, blue: 0.10)
}
struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).frame(maxWidth: .infinity).padding(.vertical, 15)
            .foregroundStyle(.white).background(Theme.teal.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 16))
    }
}
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { content.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Theme.card, in: RoundedRectangle(cornerRadius: 22)) }
}
struct MoneyLabel: View {
    var amount: Int64?
    var large = false
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(amount.map(Amount.text) ?? "—").font(large ? .system(size: 38, weight: .semibold, design: .rounded) : .headline)
                .monospacedDigit().environment(\.layoutDirection, .leftToRight).minimumScaleFactor(0.6)
            Text("ر.ع").font(.caption)
        }.accessibilityElement(children: .ignore).accessibilityLabel(Amount.currency(amount))
    }
}
struct EmptyWallet: View {
    var symbol = "tray"
    var title: String
    var message: String
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 42, weight: .light)).foregroundStyle(Theme.teal)
            Text(title).font(.title3.bold())
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(28)
    }
}
struct TransactionRow: View {
    var transaction: Transaction
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: transaction.symbol).font(.headline).foregroundStyle(transaction.isDebit ? Theme.ink : Theme.teal)
                .frame(width: 43, height: 43).background(Theme.teal.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 5) {
                Text(transaction.party).font(.subheadline.weight(.medium)).lineLimit(1)
                Text(transaction.dateEstimated ? "يحتاج تأكيد التاريخ" : transaction.category).font(.caption)
                    .foregroundStyle(transaction.dateEstimated ? Theme.amber : .secondary)
            }
            Spacer(minLength: 2)
            VStack(alignment: .trailing, spacing: 4) {
                Text((transaction.isDebit ? "−" : "+") + Amount.text(transaction.amount))
                    .font(.subheadline.weight(.semibold)).monospacedDigit().environment(\.layoutDirection, .leftToRight)
                    .foregroundStyle(transaction.isDebit ? Color.primary : Theme.teal)
                Text("ر.ع").font(.caption2).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 5)
    }
}
struct EnvelopeRow: View {
    var envelope: EnvelopeSummary
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Label(envelope.name, systemImage: envelope.kind == "saving" ? "leaf" : "tray").font(.headline)
                Spacer()
                Text(envelope.kind == "saving" ? "ادخار" : "مصروف").font(.caption).foregroundStyle(Theme.teal)
            }
            HStack {
                VStack(alignment: .leading, spacing: 4) { Text("المتبقي").font(.caption).foregroundStyle(.secondary); MoneyLabel(amount: envelope.remaining) }
                Spacer()
                Text("من " + Amount.currency(envelope.allocated)).font(.caption).foregroundStyle(.secondary)
            }
            ProgressView(value: min(Double(envelope.percent), 100), total: 100).tint(envelope.percent >= 100 ? .orange : Theme.teal)
            if envelope.overspent > 0 { Text("تجاوز بمقدار " + Amount.currency(envelope.overspent)).font(.caption).foregroundStyle(.orange) }
        }
    }
}

struct AccountPicker: View {
    @EnvironmentObject private var store: WalletStore
    @Binding var account: String
    var body: some View {
        Picker("الحساب", selection: $account) {
            Text("اختر الحساب").tag("")
            ForEach(store.data?.snapshot.accounts ?? []) { a in Text(a.shortName).tag(a.account) }
        }
    }
}
struct EnvelopePicker: View {
    @EnvironmentObject private var store: WalletStore
    @Binding var selection: String
    var account: String
    var body: some View {
        Picker("المخصص", selection: $selection) {
            Text("دون مخصص").tag("")
            ForEach((store.data?.state.envelopes ?? []).filter { $0.account == account }) { e in Text(e.name).tag(e.id) }
        }
    }
}
struct AmountField: View {
    var title: String
    @Binding var text: String
    var body: some View {
        HStack { Text(title); Spacer(); TextField("0.000", text: $text).keyboardType(.decimalPad).multilineTextAlignment(.trailing).environment(\.layoutDirection, .leftToRight); Text("ر.ع").foregroundStyle(.secondary) }
    }
}

struct WalletErrorBanner: ViewModifier {
    @EnvironmentObject private var store: WalletStore
    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom) {
            if let message = store.errorMessage {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                    Text(message).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                    Button { store.errorMessage = nil } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("إغلاق التنبيه")
                }.padding().background(.regularMaterial).accessibilityElement(children: .contain)
            }
        }
    }
}
