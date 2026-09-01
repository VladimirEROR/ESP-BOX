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

// Shake effect for wrong key
struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        let position = CGFloat(sin(animatableData * .pi * 8) * 10 * (1 - animatableData))
        return ProjectionTransform(CGAffineTransform(translationX: position, y: 0))
    }
}

// ============================================================
// MARK: - MAIN SCREEN (ESP-BOX UI)
// ============================================================
struct MainView: View {
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

                    Text("Preview")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.top, 40)
                        .padding(.horizontal, 10)

                    PreviewCarousel()
                        .padding(.top, 20)

                    InfoCard()
                        .padding(.top, 20)

                    StartButton(action: { showLoading = true })
                        .padding(.top, 10)
                        .padding(.bottom, 30)
                }
                .padding(.horizontal, 20)
            }

            if showLoading {
                LoadingView(showLoading: $showLoading)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showLoading)
    }
}

// MARK: - Header + Animated Logo
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
    let action: () -> Void
    @State private var glow = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text("START HACK")
                    .font(.system(size: 20, weight: .heavy))
                    .tracking(1)
                Image(systemName: "bolt.fill")
                    .font(.system(size: 22))
                    .opacity(glow ? 1 : 0.7)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(
                LinearGradient(gradient: Gradient(colors: [
                    Color(red: 1, green: 0.1, blue: 0.1),
                    Color(red: 1, green: 0.3, blue: 0.3),
                    Color(red: 1, green: 0.1, blue: 0.1)]),
                    startPoint: .leading, endPoint: .trailing)
            )
            .cornerRadius(16)
            .shadow(color: .red.opacity(glow ? 0.6 : 0.35), radius: glow ? 25 : 12)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) { glow = true }
        }
        .padding(.horizontal, 10)
    }
}

// ============================================================
// MARK: - LOADING SCREEN (after START HACK pressed)
// ============================================================
struct LoadingView: View {
    @Binding var showLoading: Bool
    @State private var progress: Double = 0
    @State private var spin = false
    @State private var done = false
    @State private var statusText = "Connecting to server..."

    let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.black.opacity(0.88)
                .ignoresSafeArea()
                .onTapGesture { }

            VStack(spacing: 0) {
                Spacer()

                if done {
                    // Success checkmark
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
                } else {
                    // Spinning ring + progress
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
                            .animation(.linear(duration: 0.05), value: progress)

                        Circle()
                            .trim(from: 0, to: 0.25)
                            .stroke(Color.red, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .frame(width: 150, height: 150)
                            .rotationEffect(.degrees(spin ? 360 : 0))
                            .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: spin)

                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 32, weight: .heavy, design: .monospaced))
                            .foregroundColor(.white)
                    }
                    .shadow(color: .red.opacity(0.4), radius: 15)
                }

                Text(done ? "INJECTION COMPLETE" : statusText)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(done ? .green : Color(red: 1, green: 0.35, blue: 0.35))
                    .padding(.top, 35)

                // Progress bar
                if !done {
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
                                .animation(.linear(duration: 0.05), value: progress)
                        }
                    }
                    .frame(width: 250, height: 8)
                    .padding(.top, 20)
                }

                // Close button (only when done)
                if done {
                    Button(action: { showLoading = false }) {
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
                }

                Spacer()
            }
        }
        .onReceive(timer) { _ in
            if progress < 1.0 {
                progress = min(progress + Double.random(in: 0.008...0.02), 1.0)
                statusText = statusMessage(for: progress)
            } else if !done {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    done = true
                }
            }
        }
        .onAppear { spin = true }
    }

    private func statusMessage(for p: Double) -> String {
        switch p {
        case 0..<0.2:  return "Connecting to server..."
        case 0.2..<0.4: return "Bypassing anti-cheat..."
        case 0.4..<0.6: return "Reading game memory..."
        case 0.6..<0.85: return "Attaching ESP modules..."
        case 0.85..<1.0: return "Finalizing injection..."
        default: return "Injection complete!"
        }
    }
}
