import SwiftUI

/// One journey's screens in a NavigationStack: scanner or PayNow menu, then form, then sent.
struct JourneyView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        if let journey = app.journey {
            NavigationStack(path: Binding(
                get: { app.journey?.path ?? [] },
                set: { app.journey?.path = $0 }
            )) {
                screen(journey.root)
                    .navigationDestination(for: Destination.self) { screen($0) }
            }
            .overlay(alignment: .top) {
                if let toast = app.toast {
                    ToastView(text: toast).padding(.top, 8).transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.3), value: app.toast)
        }
    }

    @ViewBuilder
    private func screen(_ destination: Destination) -> some View {
        Group {
            switch destination {
            case .scanner:
                ScannerView()
            case .paynowMenu:
                PayNowMenuView()
            case .form(let initial):
                PayNowFormView(initial: initial)
            case .sent(let result):
                SentView(result: result)
            case .placeholder(let title):
                PlaceholderScreen(title: title) { app.endJourney() }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

struct PayNowMenuView: View {
    @Environment(AppModel.self) private var app
    @State private var tab = 0

    var body: some View {
        VStack(spacing: 0) {
            ModalHeader("PayNow") { app.endJourney() }
            HStack(spacing: 0) {
                ForEach(Array(["Transfer", "Recipients"].enumerated()), id: \.offset) { index, title in
                    Button {
                        withAnimation(.snappy) { tab = index }
                    } label: {
                        VStack(spacing: 12) {
                            Text(title)
                                .font(.system(size: 16, weight: tab == index ? .medium : .regular))
                                .foregroundStyle(tab == index ? Color.ink : Color.inkSecondary)
                            Rectangle().fill(tab == index ? Color.brandBlue : .clear).frame(height: 2.5)
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                }
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PayNowProfileBanner()
                        .padding(16)
                        .background(Color.canvas)
                    section("Local transfer") {
                        row("Scan a QR", id: "menu.scan") {
                            Image(systemName: "qrcode")
                                .font(.system(size: 15))
                                .foregroundStyle(.white.opacity(0.9))
                                .frame(width: 26, height: 26)
                                .background(Color(hex: 0x9A9A9A), in: RoundedRectangle(cornerRadius: 2))
                        } action: {
                            app.journey?.path.append(.scanner)
                        }
                        row("PayNow to mobile", id: "menu.mobile", symbol: "iphone") {
                            app.journey?.path.append(.form(.menu(.mobile)))
                        }
                        row("PayNow to NRIC", id: "menu.nric", symbol: "person.text.rectangle") {
                            app.journey?.path.append(.placeholder("PayNow to NRIC"))
                        }
                        row("PayNow to UEN", id: "menu.uen", symbol: "storefront") {
                            app.journey?.path.append(.form(.menu(.uen)))
                        }
                        row("PayNow to VPA", id: "menu.vpa", symbol: "envelope.open", last: true) {
                            app.journey?.path.append(.placeholder("PayNow to VPA"))
                        }
                    }
                    Color.canvas.frame(height: 26)
                    section("Overseas transfer") {
                        ForEach(["DuitNow (Malaysia)", "PromptPay (Thailand)", "UPI (India)"], id: \.self) { title in
                            row(title, id: "menu.\(title)", symbol: "globe", last: title.hasPrefix("UPI")) {
                                app.journey?.path.append(.placeholder(title))
                            }
                        }
                    }
                    Color.canvas.frame(height: 60)
                }
            }
            .background(Color.canvas)
        }
        .background(.white)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 14.5))
                .foregroundStyle(Color(hex: 0x4F6475))
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
            Divider()
            content()
        }
        .background(.white)
    }

    private func row(_ title: String, id: String, symbol: String, last: Bool = false,
                     action: @escaping () -> Void) -> some View {
        row(title, id: id, last: last, icon: {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(Color.inkSecondary)
                .frame(width: 28)
        }, action: action)
    }

    private func row<Icon: View>(_ title: String, id: String, last: Bool = false,
                                 @ViewBuilder icon: () -> Icon, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 18) {
                icon()
                Text(title).font(.system(size: 17)).foregroundStyle(Color.ink)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(Color.inkSecondary)
            }
            .padding(.vertical, 18)
            .padding(.trailing, 6)
            .overlay(alignment: .bottom) { if !last { Divider() } }
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

struct SentView: View {
    @Environment(AppModel.self) private var app
    let result: PaymentResult
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            ModalHeader("PayNow Transfer") { app.endJourney() }
            Spacer().frame(height: 90)
            Circle()
                .fill(result.settled ? Color.sentGreen : Color.dbsRed)
                .frame(width: 98, height: 98)
                .overlay {
                    Image(systemName: result.settled ? "checkmark" : "xmark")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(.white)
                        .symbolEffect(.bounce, value: appeared)
                }
                .scaleEffect(appeared ? 1 : 0.6)
                .opacity(appeared ? 1 : 0)
            if result.settled {
                Text("Sent")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.inkSecondary)
                    .padding(.top, 28)
                Text("SGD \(Money.format(result.amount))")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(Color(hex: 0x1C1C1E))
                    .padding(.top, 8)
                    .accessibilityIdentifier("sent.amount")
                Text("to \(result.maskedName) · PayNow")
                    .font(.system(size: 16))
                    .foregroundStyle(Color(hex: 0x1C1C1E))
                    .padding(.top, 14)
                Text("Reference \(reference)")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.inkSecondary)
                    .padding(.top, 8)
            } else {
                Text("Payment didn't go through")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x1C1C1E))
                    .padding(.top, 28)
                Text("No money left your account.")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.inkSecondary)
                    .padding(.top, 8)
            }
            Spacer()
            Button("Done") { app.endJourney() }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("sent.done")
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .background(.white)
        .navigationBarBackButtonHidden()
        .onAppear { withAnimation(.spring(duration: 0.4, bounce: 0.35)) { appeared = true } }
    }

    private var reference: String {
        String(result.paymentId.replacingOccurrences(of: "-", with: "").prefix(8)).uppercased()
    }
}
