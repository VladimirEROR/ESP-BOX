import SwiftUI

// MARK: - ROOT (switches between Activation and Main)
struct ContentView: View {
    @AppStorage("isActivated") private var isActivated = false

    var body: some View {
        Group {
            if isActivated {
                MainView()
            } else {
                ActivationView(isActivated: $isActivated)
            }
        }
        .preferredColorScheme(.dark)
    }
}

// ============================================================
// MARK: - ACTIVATION SCREEN (Key Input)
// ============================================================
struct ActivationView: View {
    @Binding var isActivated: Bool
    @State private var key = ""
    @State private var errorMessage = ""
    @State private var showError = false
    @State private var attempts = 0
    @State private var glow = false

    // 🔑 CHANGE YOUR VALID KEYS HERE
    let validKeys = [
        "VLADIMIR-MLBB-2024",
        "ESP-BOX-PREMIUM",
        "ADMIN-KEY-001"
    ]

    var body: some View {
        ZStack {
            RadialGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.18, green: 0.04, blue: 0.04),
                    Color(red: 0.08, green: 0.015, blue: 0.015),
                    Color(red: 0.05, green: 0.01, blue: 0.01)
                ]),
                center: .top, startRadius: 0, endRadius: 700
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                AnimatedLogo()

                Text("ESP - BOX")
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundColor(.white)
                    .padding(.top, 20)

                Text("Activation Required")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color(red: 1, green: 0.3, blue: 0.3))
                    .padding(.top, 6)

                // Key input
                HStack {
                    Image(systemName: "key.fill")
                        .foregroundColor(Color(red: 0.72, green: 0.44, blue: 0.44))
                    TextField("ENTER LICENSE KEY", text: $key)
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                    if !key.isEmpty {
                        Button(action: { key = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(Color(red: 0.72, green: 0.44, blue: 0.44))
                        }
                    }
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.red.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            showError ? Color.red : Color.red.opacity(0.35),
                            lineWidth: showError ? 2 : 1.5
                        )
                )
                .shadow(color: .red.opacity(glow ? 0.35 : 0.1), radius: glow ? 18 : 8)
                .padding(.horizontal, 30)
                .padding(.top, 40)
                .modifier(ShakeEffect(animatableData: CGFloat(attempts)))

                // Error message
                if showError {
                    Text(errorMessage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(red: 1, green: 0.35, blue: 0.35))
                        .transition(.opacity)
                }

                // Activate button
                Button(action: activate) {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.seal.fill")
                        Text("ACTIVATE")
                            .font(.system(size: 18, weight: .heavy))
                            .tracking(1)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 1, green: 0.1, blue: 0.1),
                                Color(red: 1, green: 0.3, blue: 0.3)
                            ]),
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .cornerRadius(16)
                    .shadow(color: .red.opacity(glow ? 0.55 : 0.3), radius: glow ? 22 : 12)
                }
                .padding(.horizontal, 30)
                .padding(.top, 24)

                Spacer()

                Text("Don't have a key? Contact @Vladimir")
                    .font(.system(size: 13))
                    .foregroundColor(Color(red: 0.72, green: 0.44, blue: 0.44))
                    .padding(.bottom
