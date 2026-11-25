import SwiftUI

/// The signed-out entry screen, laid out on a 1170 px design grid so it scales with width.
struct EntryView: View {
    @Environment(AppModel.self) private var app
    @State private var showToken = false
    @State private var hold: PeekHold

    init(hold: PeekHold = PeekHold()) {
        _hold = State(initialValue: hold)
    }

    private static let alert = "Notice: This is a concept demo. No real money moves. Never share your OTP or password with anyone."

    /// The live page, plus Peek on top: a blurred snapshot of the page, the white card and a sharp hint.
    /// Everything shares the screen's coordinates, so the card sits exactly above the hint.
    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width / 1170
            ZStack(alignment: .topLeading) {
                ScrollView {
                    VStack(spacing: 0) {
                        hero(s: s, width: geo.size.width)
                        promos(s: s)
                    }
                }
                .scrollIndicators(.hidden)
                .scrollDisabled(hold.active)
                .background(alignment: .top) {
                    ZStack(alignment: .top) {
                        Color(hex: 0x05080C)
                        Image("entry-bg").resizable().scaledToFit()
                    }
                }
                .ignoresSafeArea(edges: .top)

                if hold.active {
                    PeekOverlay(hold: hold, hint: hold.hint, safeTop: geo.safeAreaInsets.top, contentWidth: geo.size.width) { peekHint }
                        .zIndex(1)
                }
            }
            .coordinateSpace(.named("entry"))
            .onPreferenceChange(HintFrameKey.self) { [hold] frame in
                MainActor.assumeIsolated { hold.hint = frame }
            }
            .ignoresSafeArea(edges: .top)
        }
        .background(Color.black)
        .fullScreenCover(isPresented: $showToken) { DigitalTokenView { showToken = false } }
    }

    private func hero(s: CGFloat, width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            BellBadge(count: 45, tint: .white.opacity(0.9), badge: Color(hex: 0xE5352B))
                .accessibilityIdentifier("entry.notifications")
                .position(x: 80 * s, y: 250 * s)
            ChatBubbleIcon(tint: .white.opacity(0.9))
                .position(x: 1078 * s, y: 243 * s)

            ZStack(alignment: .topTrailing) {
                Text(Self.alert)
                    .font(.system(size: 39.6 * s))
                    .tracking(0.3 * s)
                    .lineSpacing(1.5 * s)
                    .lineLimit(4, reservesSpace: true)
                    .truncationMode(.tail)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 33 * s)
                    .padding(.trailing, 66 * s)
                    .padding(.top, 27 * s)
                Capsule()
                    .fill(Color.white.opacity(0.55))
                    .frame(width: 9 * s, height: 150 * s)
                    .padding(.top, 39 * s)
                    .padding(.trailing, 27 * s)
            }
            .frame(width: 1074 * s, height: 258 * s, alignment: .top)
            .clipped()
            .background(Color(hex: 0x1C1E22, opacity: 0.78), in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.22), lineWidth: 1))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("entry.alert")
            .position(x: 585 * s, y: 489 * s)

            ABControlBar()
                .position(x: 585 * s, y: 700 * s)

            peekBalance
                .position(x: 585 * s, y: 1078 * s)

            tile("Log In", image: "entry-login", id: "entry.login", x: 199, y: 1223, s: s) { app.send(.login, from: .entry) }
            tile("Digital Token", image: "entry-token", id: "entry.token", x: 585, y: 1223, s: s) { showToken = true }
            tile("PayNow", image: "entry-paynow", id: "entry.paynow", x: 969, y: 1223, s: s) { app.send(.payNow, from: .entry) }
            tile("Overseas\nTransfer", image: "entry-overseas", id: "entry.overseas", x: 199, y: 1522, s: s) {
                app.send(.overseas, from: .entry)
            }
            tile("Scan & Pay", image: "entry-scan", id: "entry.scanAndPay", x: 585, y: 1522, s: s) { app.send(.scanAndPay, from: .entry) }
            tile("Apply & More\nServices", image: "entry-apply", id: "entry.apply", x: 969, y: 1522, s: s) {
                app.send(.apply, from: .entry)
            }
        }
        .frame(width: width, height: 1742 * s, alignment: .topLeading)
    }

    private var peekHint: some View {
        HStack(spacing: 22) {
            PeekChevron(systemName: "chevron.right", inward: 1)
            VStack(spacing: 4) {
                Text("Tap and hold to").font(.system(size: 13))
                Text("PEEK BALANCE").font(.system(size: 16)).tracking(0.6)
            }
            PeekChevron(systemName: "chevron.left", inward: -1)
        }
        .foregroundStyle(.white.opacity(0.92))
    }

    /// Press and hold shows Peek. Release ends it. VoiceOver's action shows it for a few seconds.
    private var peekBalance: some View {
        peekHint
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 600, maximumDistance: 400, perform: {}) { pressing in
                if pressing { hold.start(app) } else { hold.end() }
            }
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: HintFrameKey.self, value: proxy.frame(in: .named("entry")))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Tap and hold to peek balance")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                hold.start(app)
                Task {
                    try? await Task.sleep(for: .seconds(4))
                    hold.end()
                }
            }
            .accessibilityIdentifier("entry.peek")
    }

    private func tile(_ title: String, image: String, id: String, x: CGFloat, y: CGFloat, s: CGFloat,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Image(image)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 90 * s)
                    .frame(height: 36)
                Text(title)
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(-1)
                    .frame(height: 44, alignment: .top)
                    .padding(.top, 12)
            }
            .frame(width: 380 * s)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title.replacingOccurrences(of: "\n", with: " "))
        .accessibilityIdentifier(id)
        .position(x: x * s, y: y * s + 30)
    }

    private func promos(s: CGFloat) -> some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.white.opacity(0.35))
                .frame(width: 38, height: 4)
                .padding(.top, 14)
                .padding(.bottom, 28)
            VStack(alignment: .leading, spacing: 0) {
                Image("promo-child")
                    .resizable()
                    .scaledToFill()
                    .frame(height: 155)
                    .clipped()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Save for What's Next")
                        .font(.system(size: 19))
                        .foregroundStyle(Color(hex: 0x1C1C1E))
                    Text("Set a goal and watch your savings grow.")
                        .font(.system(size: 14.5))
                        .foregroundStyle(Color(hex: 0x8A8F96))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 14)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity)
        .background(Color.black)
    }
}

/// Digital Token is a placeholder in the demo and never asks for Face ID.
struct DigitalTokenView: View {
    var onClose: () -> Void

    static let lifetime: TimeInterval = 60

    @State private var otp: String?
    @State private var expires = Date.distantPast

    var body: some View {
        VStack(spacing: 0) {
            ModalHeader("Digital Token", onClose: onClose)
            ZStack {
                LinearGradient(colors: [.white, Color(hex: 0xF4F5F7)], startPoint: .top, endPoint: .center)
                VStack(spacing: 0) {
                    Image("token-lock")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 140, height: 140)
                        .padding(.top, 90)
                    Text(otp == nil ? "One-time PIN (OTP)" : "Secure PIN")
                        .font(.system(size: 21))
                        .foregroundStyle(Color(hex: 0x1F2A30))
                        .padding(.top, 36)
                    if otp == nil {
                        Button { generate() } label: {
                            Text("GENERATE OTP")
                                .font(.system(size: 19))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 26)
                                .frame(height: 54)
                                .background(.black, in: Capsule())
                        }
                        .padding(.top, 34)
                        .accessibilityIdentifier("token.generate")
                    }
                    Spacer()
                    if let otp {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let left = max(0, Int(expires.timeIntervalSince(context.date).rounded(.up)))
                            VStack(spacing: 14) {
                                Text("\(otp.prefix(3)) \(otp.suffix(3))")
                                    .font(.system(size: 44, weight: .medium, design: .rounded))
                                    .monospacedDigit()
                                    .tracking(4)
                                    .foregroundStyle(Color(hex: 0x1F2A30))
                                    .contentTransition(.numericText())
                                    .accessibilityIdentifier("token.otp")
                                ProgressView(value: Double(left), total: Self.lifetime)
                                    .tint(Color(hex: 0xE1251B))
                                    .frame(width: 200)
                                Text("New PIN in \(left)s")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color(hex: 0x6B747A))
                                    .monospacedDigit()
                                    .accessibilityIdentifier("token.timer")
                            }
                            .onChange(of: left) { _, now in
                                if now == 0 { generate() }
                            }
                        }
                        .padding(.bottom, 70)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
        }
        .background(Color(hex: 0xF4F5F7))
        .preferredColorScheme(.light)
    }

    private func generate() {
        withAnimation(.snappy) {
            otp = String(format: "%06d", Int.random(in: 0..<1_000_000))
            expires = .now.addingTimeInterval(Self.lifetime)
        }
    }
}

/// Where the Peek hint sits on screen, so the card and the sharp hint line up with it.
private struct HintFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

/// The Peek hint: each chevron fades in at the outer edge, slides toward the text, and fades out as it arrives, on a loop.
struct PeekChevron: View {
    let systemName: String
    let inward: CGFloat

    static let period: Double = 2.4
    static let travel: CGFloat = 14

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let phase = reduceMotion ? 0.5 : context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: Self.period) / Self.period
            Image(systemName: systemName)
                .font(.system(size: 20, weight: .ultraLight))
                .offset(x: inward * Self.travel * (CGFloat(phase) - 0.5))
                .opacity(Self.opacity(at: phase))
        }
    }

    static func opacity(at phase: Double) -> Double {
        if phase < 0.3 { return phase / 0.3 }
        if phase > 0.65 { return max(0, (1 - phase) / 0.35) }
        return 1
    }
}
