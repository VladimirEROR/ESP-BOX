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
// MARK: - ACTIVATION SCREEN
// ============================================================
struct ActivationView: View {
    @Binding var isActivated: Bool
    @State private var key = ""
    @State private var errorMessage = ""
    @State private var showError = false
    @State private var attempts = 0
    @State private var glow = false

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

                if showError {
                    Text(errorMessage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(red: 1, green: 0.35, blue: 0.35))
                        .transition(.opacity)
                }

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
                    .padding(.bottom, 30)
            }
        }
        .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: glow)
        .onAppear { glow = true }
    }

    private func activate() {
        let cleaned = key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if validKeys.contains(cleaned) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                isActivated = true
            }
        } else {
            errorMessage = cleaned.isEmpty
                ? "Please enter a key"
                : "Invalid key. Please check and try again"
            withAnimation(.default) {
                showError = true
                attempts += 1
            }
        }
    }
}

struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        let position = CGFloat(sin(animatableData * .pi * 8) * 10 * (1 - animatableData))
        return ProjectionTransform(CGAffineTransform(translationX: position, y: 0))
    }
}

// ============================================================
// MARK: - MAIN SCREEN
// ============================================================
struct MainView: View {
    @StateObject private var hackState = HackState.shared
    @State private var showLoading = false

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

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    HeaderView()
                        .padding(.top, 50)

                    StatsGrid()
                        .padding(.top, 40)

                    if hackState.isConnected {
                        LiveStatusCard()
                            .padding(.top, 20)
                            .transition(.opacity.combined(with: .move(edge: .top)))

                        SettingsPanel()
                            .padding(.top, 16)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    Text("Preview")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.top, 40)
                        .padding(.horizontal, 10)

                    PreviewCarousel()
                        .padding(.top, 20)

                    InfoCard()
                        .padding(.top, 20)

                    StartButton(
                        isConnected: hackState.isConnected,
                        isTransitioning: hackState.isTransitioning
                    ) {
                        if hackState.isConnected {
                            hackState.stopHack()
                        } else {
                            showLoading = true
                        }
                    }
                    .padding(.top, 10)
                    .padding(.bottom, 30)
                }
                .padding(.horizontal, 20)
            }

            if showLoading {
                RealLoadingView(
                    showLoading: $showLoading,
                    hackState: hackState
                )
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: hackState.isConnected)
        .animation(.easeInOut(duration: 0.3), value: showLoading)
    }
}

// MARK: - Header
struct HeaderView: View {
    var body: some View {
        HStack(spacing: 18) {
            AnimatedLogo()

            VStack(alignment: .leading, spacing: 6) {
                Text("ESP - BOX")
                    .font(.system(size: 32, weight: .heavy))
                    .foregroundColor(.white)

                HStack(spacing: 4) {
                    Text("MLBB ESP")
                        .foregroundColor(Color(red: 1, green: 0.3, blue: 0.3))
                    Text("· @Vladimir")
                        .foregroundColor(Color(red: 0.72, green: 0.44, blue: 0.44))
                }
                .font(.system(size: 15, weight: .semibold))
            }
            Spacer()
        }
        .padding(.horizontal, 10)
    }
}

struct AnimatedLogo: View {
    @State private var rotate = false
    @State private var glow = false
    @State private var floatUp = false
    @State private var shimmerX: CGFloat = -90
    @State private var orbit: Double = 0

    var body: some View {
        ZStack {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Color(red: 1, green: 0.2, blue: 0.2))
                    .frame(width: 5, height: 5)
                    .shadow(color: .red, radius: 6)
                    .offset(x: 52)
                    .rotationEffect(.degrees(orbit + Double(i) * 120))
            }

            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            .clear, .red,
                            Color(red: 1, green: 0.4, blue: 0.4),
                            .clear, .red, .clear
                        ]),
                        center: .center,
                        startAngle: .zero, endAngle: .degrees(360)
                    ),
                    lineWidth: 3
                )
                .frame(width: 96, height: 96)
                .shadow(color: .red.opacity(0.5), radius: 8)
                .rotationEffect(.degrees(rotate ? 360 : 0))

            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.2, green: 0.05, blue: 0.05),
                        Color(red: 0.1, green: 0.02, blue: 0.02)
                    ]),
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .frame(width: 90, height: 90)
                .overlay(
                    Rectangle()
                        .fill(LinearGradient(
                            gradient: Gradient(colors: [.clear, .white.opacity(0.35), .clear]),
                            startPoint: .leading, endPoint: .trailing))
                        .frame(width: 24)
                        .offset(x: shimmerX)
                )
                .mask(RoundedRectangle(cornerRadius: 22, style: .continuous).frame(width: 90, height: 90))
                .overlay(
                    Text("E")
                        .font(.system(size: 48, weight: .black))
                        .foregroundColor(Color(red: 1, green: 0.2, blue: 0.2))
                        .shadow(color: .red, radius: glow ? 20 : 8)
                        .shadow(color: .red.opacity(0.6), radius: glow ? 35 : 15)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.red.opacity(0.6), lineWidth: 2)
                )
                .shadow(color: .red.opacity(0.45), radius: glow ? 30 : 15)
                .offset(y: floatUp ? -5 : 0)
        }
        .frame(width: 110, height: 110)
        .onAppear {
            withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) { rotate = true }
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) { glow = true }
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) { floatUp = true }
            withAnimation(.linear(duration: 2.5).repeatForever(autoreverses: false)) { shimmerX = 90 }
            withAnimation(.linear(duration: 5).repeatForever(autoreverses: false)) { orbit = 360 }
        }
    }
}

// MARK: - Stats Grid
struct StatsGrid: View {
    let stats: [(String, String)] = [
        ("EDITION", "READONLY"),
        ("TYPE", "EXT"),
        ("TARGET", "MLBB"),
        ("VERSION", "0.1")
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(stats, id: \.0) { stat in
                VStack(spacing: 8) {
                    Text(stat.0)
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1)
                        .foregroundColor(Color(red: 0.72, green: 0.44, blue: 0.44))
                    Text(stat.1)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 20)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.red.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.red.opacity(0.15), lineWidth: 1))
        .padding(.horizontal, 10)
    }
}

// MARK: - Live Status
struct LiveStatusCard: View {
    @ObservedObject var hackState = HackState.shared

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 10, height: 10)
                        .shadow(color: .green, radius: 6)

                    Circle()
                        .stroke(Color.green.opacity(0.4), lineWidth: 1)
                        .frame(width: 18, height: 18)
                        .scaleEffect(hackState.isConnected ? 1.4 : 1.0)
                        .animation(
                            .easeInOut(duration: 1).repeatForever(autoreverses: true),
                            value: hackState.isConnected
                        )
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("CONNECTED")
                        .font(.system(size: 14, weight: .heavy, design: .monospaced))
                        .foregroundColor(.green)

                    Text("PID: \(hackState.mlbbPID) • Base: 0x\(String(hackState.baseAddress, radix: 16).uppercased())")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Color(red: 0.72, green: 0.44, blue: 0.44))
                }

                Spacer()

                VStack(spacing: 2) {
                    Text("\(hackState.currentFPS)")
                        .font(.system(size: 22, weight: .heavy, design: .monospaced))
                        .foregroundColor(Color(red: 1, green: 0.55, blue: 0.3))
                    Text("FPS")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(Color(red: 1, green: 0.55, blue: 0.3).opacity(0.6))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(red: 1, green: 0.55, blue: 0.3).opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(red: 1, green: 0.55, blue: 0.3).opacity(0.3), lineWidth: 1)
                        )
                )
            }

            HStack {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 12))
                    .foregroundColor(Color(red: 1, green: 0.3, blue: 0.3))

                Text("Players: \(hackState.entityCount)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Color(red: 1, green: 0.3, blue: 0.3))

                Spacer()

                Text("READONLY")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.green.opacity(0.7))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.green.opacity(0.3), lineWidth: 1)
                    )
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.red.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.red.opacity(0.15), lineWidth: 1))
        .padding(.horizontal, 10)
    }
}

// MARK: - Settings Panel
struct SettingsPanel: View {
    @ObservedObject var hackState = HackState.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("FEATURES")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(Color(red: 0.72, green: 0.44, blue: 0.44))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            ESPToggleRow(title: "Box ESP", icon: "square.dashed", isOn: $hackState.showBoxESP)
            ESPToggleRow(title: "Health Bar", icon: "heart.fill", isOn: $hackState.showHealthBar)
            ESPToggleRow(title: "Distance", icon: "ruler.fill", isOn: $hackState.showDistance)
            ESPToggleRow(title: "Player Names", icon: "textformat", isOn: $hackState.showNames)
            ESPToggleRow(title: "Level", icon: "chart.bar.fill", isOn: $hackState.showLevel)

            Divider()
                .background(Color.red.opacity(0.1))
                .padding(.vertical, 10)

            ESPColorRow(title: "Enemy Color", color: $hackState.enemyColor)
            ESPColorRow(title: "Ally Color", color: $hackState.allyColor)

            VStack(spacing: 8) {
                HStack {
                    Text("Box Thickness")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(Color(red: 0.72, green: 0.44, blue: 0.44))
                    Spacer()
                    Text(String(format: "%.1f", hackState.boxThickness))
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(Color(red: 1, green: 0.3, blue: 0.3))
                }

                Slider(
                    value: $hackState.boxThickness,
                    in: 0.5...4.0,
                    step: 0.5
                )
                .tint(Color(red: 1, green: 0.3, blue: 0.3))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .padding(.bottom, 14)
        }
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.red.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.red.opacity(0.15), lineWidth: 1))
        .padding(.horizontal, 10)
    }
}

// MARK: - Toggle Row
struct ESPToggleRow: View {
    let title: String
    let icon: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(isOn ? Color(red: 1, green: 0.3, blue: 0.3) : Color(red: 0.5, green: 0.3, blue: 0.3))
                .font(.system(size: 14))
                .frame(width: 24)

            Text(title)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(isOn ? .white : Color(red: 0.72, green: 0.44, blue: 0.44))

            Spacer()

            Toggle("", isOn: $isOn)
                .toggleStyle(SwitchToggleStyle(tint: Color(red: 1, green: 0.3, blue: 0.3)))
                .labelsHidden()
                .scaleEffect(0.75)
                .frame(width: 50)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
    }
}

// MARK: - Color Row
struct ESPColorRow: View {
    let title: String
    @Binding var color: UIColor

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(Color(red: 0.72, green: 0.44, blue: 0.44))

            Spacer()

            RoundedRectangle(cornerRadius: 4)
                .fill(Color(color))
                .frame(width: 28, height: 16)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )

            HStack(spacing: 5) {
                ForEach(ColorPreset.allCases, id: \.self) { preset in
                    Button(action: {
                        color = preset.color
                    }) {
                        Circle()
                            .fill(preset.swiftUIColor)
                            .frame(width: 18, height: 18)
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
    }
}

// MARK: - Color Presets
enum ColorPreset: CaseIterable {
    case red, green, blue, yellow, purple, cyan, white, pink

    var color: UIColor {
        switch self {
        case .red:    return UIColor(red: 1.0, green: 0.25, blue: 0.25, alpha: 0.9)
        case .green:  return UIColor(red: 0.25, green: 1.0, blue: 0.25, alpha: 0.9)
        case .blue:   return UIColor(red: 0.25, green: 0.5, blue: 1.0, alpha: 0.9)
        case .yellow: return UIColor(red: 1.0, green: 0.9, blue: 0.2, alpha: 0.9)
        case .purple: return UIColor(red: 0.7, green: 0.3, blue: 1.0, alpha: 0.9)
        case .cyan:   return UIColor(red: 0.2, green: 0.9, blue: 1.0, alpha: 0.9)
        case .white:  return UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.9)
        case .pink:   return UIColor(red: 1.0, green: 0.4, blue: 0.8, alpha: 0.9)
        }
    }

    var swiftUIColor: Color {
        Color(color)
    }
}

// MARK: - Preview Carousel
struct PreviewCarousel: View {
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                PreviewCard(type: .building)
                PreviewCard(type: .snow)
                PreviewCard(type: .dark)
            }
            .padding(.horizontal, 10)
        }
    }
}

struct PreviewCard: View {
    enum CardType { case building, snow, dark }
    let type: CardType

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(bgGradient)

            if type == .building {
                HStack(spacing: 20) {
                    ForEach(0..<3) { _ in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.black.opacity(0.3))
                            .frame(width: 44, height: 90)
                            .overlay(RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.red.opacity(0.8), lineWidth: 2))
                            .shadow(color: .red.opacity(0.3), radius: 6)
                    }
                }
            }

            VStack {
                Spacer()
                LinearGradient(gradient: Gradient(colors: [.clear, .black.opacity(0.6)]),
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 90)
            }
        }
        .frame(width: 310, height: 240)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.red.opacity(0.2), lineWidth: 1))
    }

    var bgGradient: LinearGradient {
        switch type {
        case .building:
            return LinearGradient(gradient: Gradient(colors: [
                Color(red: 0.27, green: 0.08, blue: 0.08),
                Color(red: 0.16, green: 0.04, blue: 0.04)]),
                startPoint: .topLeading, endPoint: .bottomTrailing)
        case .snow:
            return LinearGradient(gradient: Gradient(colors: [
                Color(red: 1, green: 0.88, blue: 0.88),
                Color(red: 1, green: 0.72, blue: 0.72)]),
                startPoint: .top, endPoint: .bottom)
        case .dark:
            return LinearGradient(gradient: Gradient(colors: [
                Color(red: 0.35, green: 0.2, blue: 0.15),
                Color(red: 0.2, green: 0.1, blue: 0.08)]),
                startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

// MARK: - Info Card
struct InfoCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(gradient: Gradient(colors: [
                    Color(red: 1, green: 0.1, blue: 0.1),
                    Color(red: 1, green: 0.3, blue: 0.3)]),
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 32, height: 32)
                .shadow(color: .red.opacity(0.6), radius: 8)
                .overlay(
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.system(size: 15))
                        .foregroundColor(.white)
                )

            VStack(alignment: .leading, spacing: 10) {
                Text("Play safe | READONLY")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                Text("ESP-BOX ISN'T DETECTED by the AC. But MLBB has moderators who can spectate you.")
                    .font(.system(size: 15))
                    .foregroundColor(Color(red: 0.79, green: 0.6, blue: 0.6))
                    .lineSpacing(4)
            }
            Spacer()
        }
        .padding(22)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.red.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.red.opacity(0.3), lineWidth: 1))
        .shadow(color: .red.opacity(0.08), radius: 15)
        .padding(.horizontal, 10)
    }
}

// MARK: - Start Button
struct StartButton: View {
    let isConnected: Bool
    let isTransitioning: Bool
    let action: () -> Void
    @State private var glow = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if isTransitioning {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.9)
                } else {
                    Text(isConnected ? "STOP HACK" : "START HACK")
                        .font(.system(size: 20, weight: .heavy))
                        .tracking(1)
                    Image(systemName: isConnected ? "stop.fill" : "bolt.fill")
                        .font(.system(size: 22))
                        .opacity(glow ? 1 : 0.7)
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: isConnected
                        ? [Color(red: 0.3, green: 0.1, blue: 0.1),
                           Color(red: 0.5, green: 0.15, blue: 0.15),
                           Color(red: 0.3, green: 0.1, blue: 0.1)]
                        : [Color(red: 1, green: 0.1, blue: 0.1),
                           Color(red: 1, green: 0.3, blue: 0.3),
                           Color(red: 1, green: 0.1, blue: 0.1)]),
                    startPoint: .leading, endPoint: .trailing
                )
            )
            .cornerRadius(16)
            .shadow(
                color: isConnected
                    ? Color.gray.opacity(0.3)
                    : Color.red.opacity(glow ? 0.6 : 0.35),
                radius: isConnected ? 0 : (glow ? 25 : 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.red.opacity(0.5), lineWidth: 1)
            )
        }
        .disabled(isTransitioning)
        .opacity(isTransitioning ? 0.6 : 1.0)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) { glow = true }
        }
        .padding(.horizontal, 10)
    }
}

// ============================================================
// MARK: - LOADING SCREEN (spawns overlay immediately)
// ============================================================
struct RealLoadingView: View {
    @Binding var showLoading: Bool
    @ObservedObject var hackState: HackState

    @State private var progress: Double = 0
    @State private var spin = false
    @State private var done = false
    @State private var failed = false
    @State private var statusText = "Starting..."
    @State private var errorDetail = ""

    var body: some View {
        ZStack {
            Color.black.opacity(0.88)
                .ignoresSafeArea()
                .onTapGesture { }

            VStack(spacing: 0) {
                Spacer()

                if done {
                    ZStack {
                        Circle()
                            .fill(Color.green.opacity(0.15))
                            .frame(width: 150, height: 150)
                        Circle()
                            .stroke(Color.green, lineWidth: 4)
                            .frame(width: 130, height: 130)
                        Image(systemName: "checkmark")
                            .font(.system(size: 60, weight: .heavy))
                            .foregroundColor(.green)
                    }
                    .shadow(color: .green.opacity(0.6), radius: 25)
                    .transition(.scale.combined(with: .opacity))
                } else if failed {
                    ZStack {
                        Circle()
                            .fill(Color.red.opacity(0.15))
                            .frame(width: 150, height: 150)
                        Circle()
                            .stroke(Color.red, lineWidth: 4)
                            .frame(width: 130, height: 130)
                        Image(systemName: "xmark")
                            .font(.system(size: 55, weight: .heavy))
                            .foregroundColor(.red)
                    }
                    .shadow(color: .red.opacity(0.6), radius: 25)
                    .transition(.scale.combined(with: .opacity))
                } else {
                    ZStack {
                        Circle()
                            .stroke(Color.red.opacity(0.15), lineWidth: 8)
                            .frame(width: 150, height: 150)

                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(
                                LinearGradient(gradient: Gradient(colors: [
                                    Color(red: 1, green: 0.1, blue: 0.1),
                                    Color(red: 1, green: 0.4, blue: 0.4)
                                ]), startPoint: .top, endPoint: .bottom),
                                style: StrokeStyle(lineWidth: 8, lineCap: .round)
                            )
                            .frame(width: 150, height: 150)
                            .rotationEffect(.degrees(-90))

                        Circle()
                            .trim(from: 0, to: 0.25)
                            .stroke(Color.red, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .frame(width: 150, height: 150)
                            .rotationEffect(.degrees(spin ? 360 : 0))

                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 32, weight: .heavy, design: .monospaced))
                            .foregroundColor(.white)
                    }
                    .shadow(color: .red.opacity(0.4), radius: 15)
                }

                Group {
                    if done {
                        Text("OVERLAY ACTIVE")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.green)
                    } else if failed {
                        VStack(spacing: 6) {
                            Text("FAILED")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(.red)
                            Text(errorDetail)
                                .font(.system(size: 13))
                                .foregroundColor(Color(red: 0.79, green: 0.6, blue: 0.6))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 30)
                        }
                    } else {
                        Text(statusText)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(Color(red: 1, green: 0.35, blue: 0.35))
                    }
                }
                .padding(.top, 35)

                if !done && !failed {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.red.opacity(0.15))
                            Capsule()
                                .fill(LinearGradient(gradient: Gradient(colors: [
                                    Color(red: 1, green: 0.1, blue: 0.1),
                                    Color(red: 1, green: 0.4, blue: 0.4)
                                ]), startPoint: .leading, endPoint: .trailing))
                                .frame(width: geo.size.width * progress)
                        }
                    }
                    .frame(width: 250, height: 8)
                    .padding(.top, 20)
                }

                if done {
                    Button(action: {
                        withAnimation(.easeOut(duration: 0.3)) {
                            showLoading = false
                        }
                    }) {
                        Text("CLOSE")
                            .font(.system(size: 16, weight: .heavy))
                            .tracking(1)
                            .foregroundColor(.white)
                            .frame(width: 180, height: 50)
                            .background(
                                LinearGradient(gradient: Gradient(colors: [
                                    Color(red: 0.2, green: 0.75, blue: 0.3),
                                    Color(red: 0.15, green: 0.6, blue: 0.25)
                                ]), startPoint: .leading, endPoint: .trailing)
                            )
                            .cornerRadius(14)
                            .shadow(color: .green.opacity(0.4), radius: 15)
                    }
                    .padding(.top, 30)
                    .transition(.opacity)
                } else if failed {
                    Button(action: {
                        hackState.resetState()
                        withAnimation(.easeOut(duration: 0.3)) {
                            showLoading = false
                        }
                    }) {
                        Text("RETRY")
                            .font(.system(size: 16, weight: .heavy))
                            .tracking(1)
                            .foregroundColor(.white)
                            .frame(width: 180, height: 50)
                            .background(
                                LinearGradient(gradient: Gradient(colors: [
                                    Color(red: 1, green: 0.1, blue: 0.1),
                                    Color(red: 1, green: 0.3, blue: 0.3)
                                ]), startPoint: .leading, endPoint: .trailing)
                            )
                            .cornerRadius(14)
                            .shadow(color: .red.opacity(0.4), radius: 15)
                    }
                    .padding(.top, 30)
                    .transition(.opacity)
                }

                Spacer()
            }
        }
        .onAppear {
            spin = true
            startOverlay()
        }
    }

    // MARK: - Just spawn overlay — no MLBB check
    private func startOverlay() {
        setStatus("Starting...", 0.2)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            setStatus("Spawning overlay...", 0.5)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            setStatus("Activating ESP...", 0.8)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            hackState.spawnOverlay()
            setStatus("Done", 1.0)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    done = true
                }
            }
        }
    }

    private func setStatus(_ text: String, _ p: Double) {
        withAnimation(.easeInOut(duration: 0.2)) {
            statusText = text
            progress = p
        }
    }
}

// ============================================================
// MARK: - HACK STATE
// ============================================================
class HackState: ObservableObject {
    static let shared = HackState()

    let version = "0.1"

    @Published var isConnected = false
    @Published var isTransitioning = false
    @Published var statusText = "Not Connected"
    @Published var mlbbPID: Int32 = 0
    @Published var baseAddress: UInt64 = 0
    @Published var currentFPS: Int = 0
    @Published var entityCount: Int = 0

    @Published var showBoxESP = true
    @Published var showHealthBar = true
    @Published var showDistance = true
    @Published var showNames = false
    @Published var showLevel = true
    @Published var showHealthText = false

    @Published var enemyColor = UIColor(red: 1.0, green: 0.25, blue: 0.25, alpha: 0.9)
    @Published var allyColor = UIColor(red: 0.25, green: 1.0, blue: 0.25, alpha: 0.9)
    @Published var boxThickness: Double = 1.5
    @Published var boxGlow: Double = 4.0

    let memoryManager = MemoryManager()
    private var overlayController: OverlayController?

    // MARK: - Spawn overlay immediately
    func spawnOverlay() {
        overlayController = OverlayController(
            memoryManager: memoryManager,
            baseAddress: 0,
            settings: self
        )
        overlayController?.start()
        statusText = "Waiting for MLBB..."
    }

    // MARK: - Stop
    func stopHack() {
        guard !isTransitioning else { return }
        isTransitioning = true

        overlayController?.stop()
        overlayController = nil
        memoryManager.detach()

        withAnimation(.easeInOut(duration: 0.3)) {
            isConnected = false
            isTransitioning = false
            statusText = "Not Connected"
            mlbbPID = 0
            baseAddress = 0
            entityCount = 0
            currentFPS = 0
        }
    }

    // MARK: - Reset
    func resetState() {
        overlayController?.stop()
        overlayController = nil
        memoryManager.detach()
        isConnected = false
        isTransitioning = false
        mlbbPID = 0
        baseAddress = 0
        entityCount = 0
        currentFPS = 0
        statusText = "Not Connected"
    }
}
