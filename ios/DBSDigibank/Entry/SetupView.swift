import SwiftUI

/// First run: bind this iPhone to Alex Tan with a fresh device key.
struct SetupView: View {
    @Environment(AppModel.self) private var app
    @State private var username = "alextan"
    @State private var otp = "123456"
    @State private var working = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                BankMark(color: Color(hex: 0x0B2384)).frame(width: 34, height: 40)
                Text("Demo Bank")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: 0x0B2384))
            }
            .padding(.top, 36)

            Text("Set up this iPhone")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Color.ink)
                .padding(.top, 36)
            Text("Bind this iPhone to your Demo Bank account. You'll use Face ID to log in and pay from now on.")
                .font(.system(size: 15))
                .foregroundStyle(Color.inkSecondary)
                .padding(.top, 8)

            VStack(spacing: 0) {
                field("Name", value: .constant("Alex Tan"), editable: false)
                Divider()
                field("Username", value: $username, editable: true)
                Divider()
                field("OTP sent to +65 •••• 4567", value: $otp, editable: true, keyboard: .numberPad)
            }
            .background(.white, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.hairline))
            .padding(.top, 28)

            if let error {
                Text(error)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.dbsRed)
                    .padding(.top, 12)
                    .accessibilityIdentifier("setup.error")
            }

            Spacer()

            Button {
                Task { await setUp() }
            } label: {
                if working { ProgressView().tint(.white) } else { Text("SET UP THIS IPHONE") }
            }
            .buttonStyle(PrimaryButtonStyle(enabled: !working))
            .disabled(working)
            .accessibilityIdentifier("setup.submit")
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 20)
        .background(Color.canvas.ignoresSafeArea())
    }

    private func field(_ label: String, value: Binding<String>, editable: Bool,
                       keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Color.inkSecondary)
            TextField(label, text: value)
                .font(.system(size: 17))
                .foregroundStyle(Color.ink)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .disabled(!editable)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func setUp() async {
        working = true
        error = nil
        defer { working = false }
        do {
            try await app.bindDevice(username: username, otp: otp)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
