import SwiftUI

/// DBS Sequential's loading screens, in order. Each stays up only while its own work runs.
enum LoadingStage: String, Sendable {
    case entrySpinner = "Entry grid spinner"
    case splash = "Splash"
    case splashSpinner = "Splash with spinner"
    case login = "In-app login screen"
    case homeSkeleton = "Home skeleton"
    case paySkeleton = "Pay & Transfer skeleton"
}

struct LoadingStageView: View {
    let stage: LoadingStage

    var body: some View {
        Group {
            switch stage {
            case .entrySpinner:
                Color.black.opacity(0.6).overlay { SpinnerTile() }
            case .splash:
                splash
            case .splashSpinner:
                splash.overlay { Color.black.opacity(0.6).overlay { SpinnerTile() } }
            case .login:
                LoginWaitView()
            case .homeSkeleton:
                HomeSkeleton()
            case .paySkeleton:
                PaySkeleton()
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .accessibilityElement()
        .accessibilityLabel(stage.rawValue)
        .accessibilityIdentifier("stage")
    }

    private var splash: some View {
        Color.white.overlay { Image("splash-logo").resizable().scaledToFit().frame(width: 193) }
    }
}

private struct SpinnerTile: View {
    @State private var dim = false

    var body: some View {
        Image("splash-spinner")
            .resizable()
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .opacity(dim ? 0.55 : 1)
            .onAppear { withAnimation(.easeInOut(duration: 0.45).repeatForever()) { dim = true } }
    }
}

/// Looks like a login form and takes no input. It waits for the session.
private struct LoginWaitView: View {
    var body: some View {
        VStack(spacing: 0) {
            Color(hex: 0x0077CC).frame(height: 106)
                .overlay(alignment: .bottom) {
                    ZStack {
                        Image(systemName: "xmark").font(.system(size: 22, weight: .light))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        BankMark(color: .white).frame(width: 26, height: 30)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                }
            VStack(spacing: 0) {
                Image(systemName: "person.crop.circle.fill").font(.system(size: 66)).foregroundStyle(.white)
                Text("ALEX TAN").font(.system(size: 17, weight: .semibold)).padding(.top, 8)
                Text("Not you?").font(.system(size: 13)).underline().padding(.top, 4)
                Text("PIN").foregroundStyle(Color.gray)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .background(.white, in: RoundedRectangle(cornerRadius: 4))
                    .padding(.top, 30)
                Text("Forgot your PIN?").font(.system(size: 14))
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12)
                Text("LOGIN").font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .background(Color(hex: 0x0077CC), in: RoundedRectangle(cornerRadius: 4))
                    .padding(.top, 28)
                Image(systemName: "faceid").font(.system(size: 28, weight: .light))
                    .symbolEffect(.pulse, options: .repeating).padding(.top, 40)
                Spacer()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.top, 10)
        }
        .background(LinearGradient(colors: [Color(hex: 0x4A4038), Color(hex: 0x111111)], startPoint: .top, endPoint: .center))
    }
}

private struct HomeSkeleton: View {
    private let bone = Color(hex: 0xECF0F3)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule().fill(Color(hex: 0xD1D6DA)).frame(width: 132, height: 13).padding(.top, 84)
            Capsule().fill(Color(hex: 0xD1D6DA)).frame(width: 230, height: 13).padding(.top, 27)
            VStack(spacing: 9) {
                HStack { ForEach(0..<5, id: \.self) { index in
                    Circle().fill(bone).frame(width: 45, height: 45)
                    if index < 4 { Spacer() }
                } }
                .padding(.bottom, 18)
                RoundedRectangle(cornerRadius: 8).fill(bone).frame(height: 111)
                HStack(spacing: 9) { ForEach(0..<2, id: \.self) { _ in RoundedRectangle(cornerRadius: 8).fill(bone).frame(height: 111) } }
                Spacer()
            }
            .padding(18)
            .frame(maxWidth: .infinity)
            .background(.white, in: UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18))
            .padding(.horizontal, -18)
            .padding(.top, 38)
        }
        .padding(.horizontal, 18)
        .background(Color(hex: 0xDDE2E6))
    }
}

private struct PaySkeleton: View {
    private let bone = Color(hex: 0xECEDF1)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            RoundedRectangle(cornerRadius: 4).fill(bone).frame(width: 258, height: 32)
                .frame(maxWidth: .infinity)
                .padding(.top, 78).padding(.bottom, 16)
                .background(.white)
            VStack(alignment: .leading, spacing: 32) {
                ForEach([295.0, 240, 277], id: \.self) { width in
                    RoundedRectangle(cornerRadius: 4).fill(bone).frame(width: width, height: 32)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white)
            Spacer()
        }
        .background(Color(hex: 0xF5F6F9))
    }
}
