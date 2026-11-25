import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var app
    @AppStorage("balanceHidden") private var balanceHidden = true
    @State private var showAllAccounts = false

    private var home: HomeModel { app.home }
    private var name: String { home.summary?.displayName ?? "ALEX TAN" }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                VStack(alignment: .leading, spacing: 0) {
                    quickActions
                    accounts
                    discover
                }
                .background(Color.canvas)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18))
                .offset(y: -18)
            }
        }
        .scrollIndicators(.hidden)
        .background(alignment: .top) {
            VStack(spacing: 0) {
                headerGradient.frame(height: 400)
                Color.canvas
            }
            .ignoresSafeArea()
        }
        .background(AppearProbe { app.homeAppeared() })
        .refreshable { await home.refresh() }
    }

    private var headerGradient: some View {
        LinearGradient(colors: [Color(hex: 0x00609C), Color(hex: 0x0088E6), Color(hex: 0x0093FE)],
                       startPoint: .top, endPoint: .bottom)
            .overlay(alignment: .topTrailing) {
                Circle().fill(Color.white.opacity(0.07)).frame(width: 260).offset(x: 150, y: 10)
            }
            .overlay(alignment: .bottomTrailing) {
                Circle().fill(Color(hex: 0x0A7FDB)).frame(width: 110).offset(x: -60, y: 20)
            }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 18) {
                BellBadge(count: 51, tint: .white, badge: Color(hex: 0x10212B))
                    .accessibilityIdentifier("home.notifications")
                Spacer()
                ChatBubbleIcon(tint: .white)
                Button("LOG OUT") { app.logOut() }
                    .font(.system(size: 12, weight: .medium))
                    .tracking(0.8)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 22)
                    .overlay(Capsule().stroke(.white, lineWidth: 1.2))
                    .accessibilityIdentifier("home.logout")
            }
            .padding(.top, 8)

            Text("Hi, \(name)!")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .padding(.top, 34)
                .accessibilityIdentifier("home.greeting")
            HStack(spacing: 10) {
                Text("View your net worth and more")
                    .font(.system(size: 15.5))
                    .foregroundStyle(.white)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 25, height: 25)
                    .background(Color(hex: 0x0B4F86), in: Circle())
            }
            .padding(.top, 18)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 64)
    }

    private var quickActions: some View {
        HStack(alignment: .top, spacing: 2) {
            QuickTile(title: "Security\nHub", image: "home-security", id: "home.securityHub") {
                app.report("Security Hub isn't in the demo")
            }
            QuickTile(title: "PayNow", image: "home-paynow", id: "home.paynow") { app.send(.payNow, from: .shell) }
            QuickTile(title: "Bills, Cards\n& GIRO", image: "home-bills", id: "home.bills") {
                app.report("Bills isn't in the demo")
            }
            QuickTile(title: "Overseas\ntransfer", image: "home-overseas", id: "home.overseas") {
                app.send(.overseas, from: .shell)
            }
            QuickTile(title: "Scan & Pay", image: "pay-scan", id: "home.scanAndPay") { app.send(.scanAndPay, from: .shell) }
        }
        .padding(.horizontal, 8)
        .padding(.top, 20)
        .padding(.bottom, 22)
        .background(Color(hex: 0xFBFBFB))
    }

    private var accounts: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 18) {
                Text("Your accounts")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.ink)
                Spacer()
                Button {
                    balanceHidden.toggle()
                } label: {
                    Image(systemName: balanceHidden ? "eye.slash" : "eye")
                        .font(.system(size: 17))
                        .foregroundStyle(Color.inkSecondary)
                        .frame(width: 30, height: 30)
                }
                .accessibilityLabel(balanceHidden ? "Show balances" : "Hide balances")
                .accessibilityIdentifier("home.balanceToggle")
                Image(systemName: "gearshape")
                    .font(.system(size: 17))
                    .foregroundStyle(Color.inkSecondary)
            }
            .padding(.top, 26)

            if home.refreshFailed, let updated = home.lastUpdated {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    let minutes = max(1, Int(context.date.timeIntervalSince(updated) / 60))
                    Text("Updated \(minutes) min ago")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.inkSecondary)
                }
            }

            card {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Deposits").font(.system(size: 17, weight: .semibold)).foregroundStyle(Color.ink)
                    Spacer(minLength: 24)
                    HStack {
                        Spacer()
                        VStack(alignment: .trailing, spacing: 6) {
                            Text("Available balance").font(.system(size: 14)).foregroundStyle(Color.inkSecondary)
                            amount(home.summary.map { "SGD " + Money.format($0.totalAvailable) }, size: 19)
                        }
                    }
                }
                .frame(height: 86)
            }
            .padding(.top, 8)

            HStack(spacing: 8) {
                card {
                    VStack(alignment: .leading) {
                        Text("Wallet").font(.system(size: 17, weight: .semibold)).foregroundStyle(Color.ink)
                        Spacer(minLength: 22)
                        Text("Link a wallet\nto see it here")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.inkSecondary)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .frame(height: 86)
                }
                card {
                    VStack(alignment: .leading) {
                        Text("Wealth").font(.system(size: 17, weight: .semibold)).foregroundStyle(Color.ink)
                        Spacer(minLength: 22)
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Your net worth").font(.system(size: 14)).foregroundStyle(Color.inkSecondary)
                            amount(home.summary.map { "SGD " + Money.format($0.totalAvailable) }, size: 15)
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .frame(height: 86)
                }
            }

            if showAllAccounts, let summary = home.summary {
                card {
                    VStack(spacing: 0) {
                        ForEach(summary.accounts) { account in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(account.name).font(.system(size: 15)).foregroundStyle(Color.ink)
                                    Text(account.numberMasked).font(.system(size: 13)).foregroundStyle(Color.inkSecondary)
                                }
                                Spacer()
                                amount("\(account.currency) \(account.balance)", size: 15)
                            }
                            .padding(.vertical, 10)
                            if account.id != summary.accounts.last?.id { Divider() }
                        }
                    }
                }
            }

            Button {
                withAnimation(.snappy) { showAllAccounts.toggle() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: showAllAccounts ? "minus.circle.fill" : "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white, Color.brandBlue)
                    Text(showAllAccounts ? "Hide accounts" : "Show all accounts")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.ink)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func amount(_ text: String?, size: CGFloat) -> some View {
        if balanceHidden || text == nil {
            Text("••••••").font(.system(size: size + 3, weight: .bold)).tracking(1).foregroundStyle(Color.ink)
                .redacted(reason: text == nil && !balanceHidden ? .placeholder : [])
        } else if let text {
            Text(text).font(.system(size: size, weight: .semibold)).foregroundStyle(Color.ink)
                .contentTransition(.numericText())
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.hairline))
            .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
    }

    private var discover: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Discover more")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.ink)
                .padding(.horizontal, 16)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    promo("Keep your account safe", "Turn on extra checks for large transfers.")
                    promo("Insights", "See where your money went this month.")
                }
                .padding(.horizontal, 12)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.top, 18)
        .padding(.bottom, 120)
    }

    private func promo(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 19, weight: .semibold)).foregroundStyle(Color.ink)
            Text(body).font(.system(size: 14)).foregroundStyle(Color.inkSecondary)
            Spacer()
        }
        .padding(16)
        .frame(width: 290, height: 150, alignment: .topLeading)
        .background(.white, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.hairline))
    }
}
