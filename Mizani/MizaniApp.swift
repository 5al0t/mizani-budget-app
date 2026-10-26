import SwiftUI
import LocalAuthentication

@main
struct MizaniApp: App {
    @StateObject private var store = WalletStore.shared
    var body: some Scene {
        WindowGroup {
            AppRoot().environmentObject(store)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "ar_OM"))
                .tint(Theme.teal)
        }
    }
}

struct AppRoot: View {
    @EnvironmentObject private var store: WalletStore
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appLockEnabled") private var appLockEnabled = false
    @State private var unlocked = false
    @State private var authenticating = false
    @State private var lockMessage = ""
    var body: some View {
        ZStack {
            if !appLockEnabled || unlocked { MainTabs() }
            if appLockEnabled && !unlocked {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 24) {
                    Image(systemName: "lock.shield.fill").font(.system(size: 58)).foregroundStyle(Theme.teal)
                    Text("أموالك، بخصوصية").font(.title2.bold())
                    Text(lockMessage).font(.footnote).foregroundStyle(.secondary)
                    Button("فتح ميزاني", action: authenticate).buttonStyle(PrimaryButton()).disabled(authenticating)
                }.padding(32)
            }
            if scenePhase != .active { Theme.background.ignoresSafeArea().overlay(Image(systemName: "lock.fill").font(.largeTitle).foregroundStyle(Theme.teal)) }
        }
        .task { if appLockEnabled { authenticate() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { unlocked = false }
            if phase == .active { store.reload(); if appLockEnabled && !unlocked { authenticate() } }
        }
        .modifier(WalletErrorBanner())
    }
    private func authenticate() {
        guard !authenticating else { return }
        authenticating = true
        Task { @MainActor in
            defer { authenticating = false }
            do { unlocked = try await LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "افتح بيانات ميزانيتك") }
            catch { lockMessage = "استخدم Face ID أو رمز قفل الجهاز للمتابعة." }
        }
    }
}

struct MainTabs: View {
    var body: some View {
        TabView {
            DashboardView().tabItem { Label("نظرة عامة", systemImage: "square.grid.2x2") }
            TransactionsView().tabItem { Label("العمليات", systemImage: "arrow.left.arrow.right") }
            EnvelopesView().tabItem { Label("خطتي", systemImage: "tray.full") }
            SettingsView().tabItem { Label("الإعدادات", systemImage: "slider.horizontal.3") }
        }
    }
}
