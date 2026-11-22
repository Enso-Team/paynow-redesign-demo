import SwiftUI

struct PayTransferView: View {
    @Environment(AppModel.self) private var app
    @State private var segment = 0

    private struct Recipient: Identifiable {
        var id: String { name }
        var initials: String
        var name: String
        var detail: String
        var tint: Color
    }

    private let recents = [
        Recipient(initials: "KC", name: "KOPI CORNER PTE. LTD.", detail: "UEN •••••449W", tint: Color(hex: 0x1E8E5A)),
        Recipient(initials: "TN", name: "TAN ** **NG", detail: "MOBILE •••• 4567", tint: Color(hex: 0x6A4FC9)),
        Recipient(initials: "LA", name: "LIM ** **AH", detail: "MOBILE •••• 5432", tint: Color(hex: 0xC2410C)),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ShellTopBar()
            ScrollView {
                VStack(spacing: 0) {
                    grid
                    recipients
                }
            }
            .scrollIndicators(.hidden)
        }
        .background(Color.canvas)
    }

    private var grid: some View {
        VStack(spacing: 0) {
            Grid(horizontalSpacing: 4, verticalSpacing: 22) {
                GridRow {
                    QuickTile(title: "PayNow", image: "pay-paynow", id: "pay.paynow") { app.send(.payNow, from: .shell) }
                    QuickTile(title: "Local\ntransfer", image: "pay-local", id: "pay.local") {
                        app.report("Local transfer isn't in the demo")
                    }
                    QuickTile(title: "Scan & Pay", image: "pay-scan", id: "pay.scanAndPay") { app.send(.scanAndPay, from: .shell) }
                    QuickTile(title: "Overseas\ntransfer", image: "pay-overseas", id: "pay.overseas") {
                        app.send(.overseas, from: .shell)
                    }
                }
                GridRow {
                    QuickTile(title: "Bills, Cards\n& GIRO", image: "pay-bills", id: "pay.bills") {
                        app.report("Bills isn't in the demo")
                    }
                    QuickTile(title: "Scheduled\ntransfer", image: "pay-scheduled", id: "pay.scheduled") {
                        app.report("Scheduled transfer isn't in the demo")
                    }
                    QuickTile(title: "EDP", image: "pay-edp", id: "pay.edp") { app.report("EDP isn't in the demo") }
                        .overlay(alignment: .top) {
                            Text("New")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Color(hex: 0xD9261C), in: Capsule())
                                .offset(x: 18, y: -10)
                        }
                    QuickTile(title: "Exchange\ncurrency", image: "pay-fx", id: "pay.fx") {
                        app.report("Exchange currency isn't in the demo")
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 24)
            .padding(.bottom, 20)

            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.brandBlue)
                .frame(width: 24, height: 24)
                .background(.white, in: Circle())
                .overlay(Circle().stroke(Color.hairline))
                .offset(y: 12)
        }
        .frame(maxWidth: .infinity)
        .background(.white)
        .padding(.bottom, 26)
    }

    private var recipients: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Your Recipients & Billers")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.ink)
                Spacer()
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.inkSecondary)
                    .frame(width: 36, height: 36)
                    .background(.white, in: Circle())
                    .shadow(color: .black.opacity(0.1), radius: 3, y: 1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            HStack(spacing: 0) {
                ForEach(Array([("Recent", 5), ("All", 8), ("Favourites", 0)].enumerated()), id: \.offset) { index, item in
                    Button {
                        withAnimation(.snappy) { segment = index }
                    } label: {
                        VStack(spacing: 10) {
                            HStack(spacing: 6) {
                                Text(item.0).font(.system(size: 16, weight: segment == index ? .semibold : .regular))
                                Text("\(item.1)")
                                    .font(.system(size: 10, weight: .medium))
                                    .frame(width: 16, height: 16)
                                    .background(Color.hairline, in: Circle())
                            }
                            .foregroundStyle(segment == index ? Color.ink : Color.inkSecondary)
                            Rectangle()
                                .fill(segment == index ? Color.brandBlue : .clear)
                                .frame(height: 2.5)
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 8)
            Divider()

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 14) {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(Color.inkSecondary)
                        .frame(width: 40, height: 40)
                        .overlay(Circle().stroke(Color.hairline))
                    Text("Add a recipient or bill").font(.system(size: 16, weight: .medium)).foregroundStyle(Color.ink)
                }
                .padding(.vertical, 16)
                Text("Recent transfers")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.inkSecondary)
                    .padding(.bottom, 10)
                ForEach(recents) { recipient in
                    HStack(spacing: 14) {
                        Text(recipient.initials)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(recipient.tint)
                            .frame(width: 40, height: 40)
                            .background(recipient.tint.opacity(0.15), in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(recipient.name).font(.system(size: 15)).foregroundStyle(Color.ink)
                            Text(recipient.detail).font(.system(size: 13)).foregroundStyle(Color.inkSecondary)
                        }
                        Spacer()
                        Text("PAYNOW")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.paynowTag)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.paynowTag.opacity(0.6)))
                    }
                    .padding(.vertical, 12)
                    Divider().padding(.leading, 54)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 120)
        }
        .background(.white)
    }
}

struct WealthView: View {
    @Environment(AppModel.self) private var app
    @AppStorage("balanceHidden") private var balanceHidden = true

    var body: some View {
        VStack(spacing: 0) {
            ShellTopBar(title: "Wealth")
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your net worth").font(.system(size: 14)).foregroundStyle(Color.inkSecondary)
                        Text(balanceHidden ? "••••••" : app.home.summary.map { "SGD " + Money.format($0.totalAvailable) } ?? "—")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(Color.ink)
                        Text("Assets less liabilities across your accounts")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.inkSecondary)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.hairline))
                    ForEach(["Investments", "Insurance", "CPF", "Retirement planning"], id: \.self) { row in
                        HStack {
                            Text(row).font(.system(size: 16)).foregroundStyle(Color.ink)
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(Color.inkSecondary)
                        }
                        .padding(18)
                        .background(.white, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.hairline))
                    }
                }
                .padding(16)
                .padding(.bottom, 100)
            }
        }
        .background(Color.canvas)
    }
}

struct ApplyView: View {
    private let sections: [(String, Color, [(String, String)])] = [
        ("Bank", Color(hex: 0xA3410F), [("Deposits", "Start saving with us"), ("Fixed Deposits", "Maximise your savings"),
                                         ("Supplementary Retirement Scheme", "Enjoy tax savings")]),
        ("Cards", Color(hex: 0xA51C30), [("Credit Cards", "For rebates, miles, rewards"), ("Debit Cards", "For everyday banking"),
                                          ("Card Services", "Payment plans and more")]),
        ("Loans", Color(hex: 0x1D5FA8), [("Personal Loan", "Funds when you need them"), ("Home Loans", "Rates for your new home")]),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ShellTopBar(title: "Apply")
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Discover more with us")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.ink)
                        .padding(.top, 26)
                    Text("Explore a category")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.inkSecondary)
                        .padding(.top, 10)
                        .padding(.bottom, 22)
                    ForEach(sections, id: \.0) { section in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(section.0)
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(section.1)
                                .padding(.horizontal, 16)
                                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                                .background(LinearGradient(colors: [.white, section.1.opacity(0.08)], startPoint: .leading, endPoint: .trailing))
                            ForEach(section.2, id: \.0) { item in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.0).font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.ink)
                                    Text(item.1).font(.system(size: 15)).foregroundStyle(Color.inkSecondary)
                                }
                                .padding(.vertical, 14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .overlay(alignment: .bottom) { Divider() }
                                .padding(.horizontal, 16)
                            }
                            HStack {
                                Spacer()
                                Text("View all").font(.system(size: 15)).foregroundStyle(Color.ink)
                                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(Color.inkSecondary)
                            }
                            .padding(16)
                        }
                        .background(.white, in: RoundedRectangle(cornerRadius: 6))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.hairline))
                        .padding(.bottom, 14)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 100)
            }
        }
        .background(Color.canvas)
    }
}

struct MoreView: View {
    @Environment(AppModel.self) private var app

    private let quickAccess: [(String, String)] = [
        ("eDocuments", "doc.text"), ("Replace/Block Card", "creditcard.trianglebadge.exclamationmark"),
        ("Personalise Your App", "circle.grid.3x3"), ("Rewards", "leaf"),
        ("Update Particulars", "person.crop.circle.badge"), ("Lock Your Account", "lock"),
    ]
    private let apply: [(String, String)] = [
        ("Starter Packs", "building.columns"), ("Cards", "creditcard"), ("Deposit Accounts", "banknote"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                BellBadge(count: 51, tint: Color.inkSecondary)
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                    Text("Search 'more'")
                }
                .font(.system(size: 17))
                .foregroundStyle(Color.inkSecondary)
                Spacer()
                ChatBubbleIcon(tint: Color.inkSecondary)
            }
            .padding(.horizontal, 22)
            .frame(height: 56)
            .background(.white)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 18) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(Color(hex: 0x2E3A44), Color.brandBlue.opacity(0.15))
                            .frame(width: 70, height: 70)
                            .background(.white, in: Circle())
                            .shadow(color: .black.opacity(0.1), radius: 4)
                        VStack(alignment: .leading, spacing: 10) {
                            Text(app.home.summary?.displayName ?? "ALEX TAN")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Color.ink)
                            Button {
                                app.logOut()
                            } label: {
                                Label("LOG OUT", systemImage: "rectangle.portrait.and.arrow.right")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 14)
                                    .frame(height: 30)
                                    .background(Color.brandBlue, in: Capsule())
                            }
                            .accessibilityIdentifier("more.logout")
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.canvas)

                    HStack(spacing: 16) {
                        Image("home-security")
                            .resizable()
                            .frame(width: 39, height: 39)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("SECURITY HUB").font(.system(size: 11)).foregroundStyle(Color.inkSecondary)
                            Text("Security settings and tips")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(Color.ink)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Color.inkSecondary)
                    }
                    .padding(16)
                    .background(.white)

                    section("QUICK ACCESS", quickAccess)
                    section("APPLY", apply)
                }
                .padding(.bottom, 100)
            }
        }
        .background(Color.canvas)
    }

    private func section(_ title: String, _ items: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 13))
                .tracking(0.6)
                .foregroundStyle(Color.inkSecondary)
                .padding(.horizontal, 16)
                .padding(.top, 28)
                .padding(.bottom, 12)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 22) {
                ForEach(items, id: \.0) { item in
                    VStack(spacing: 10) {
                        Image(systemName: item.1)
                            .font(.system(size: 20, weight: .light))
                            .foregroundStyle(Color.inkSecondary)
                            .frame(width: 48, height: 48)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.hairline))
                        Text(item.0)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Color.ink)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .padding(.vertical, 18)
            .background(.white)
        }
    }
}
