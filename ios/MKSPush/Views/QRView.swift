//
//  QRView.swift
//  MKSPush
//
//  Pairing screen: QR code + 2FA mode.
//  Pixel-parity with React Native QRScreen.tsx.
//

import Combine
import SwiftUI

struct QRView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.themeColors) private var c
    @Environment(\.scenePhase) private var scenePhase

    // QR state
    @State private var qrImage: UIImage?
    @State private var qrPhase: QRPhase = .loading
    @State private var qrRefreshTask: Task<Void, Never>?

    // 2FA state
    @State private var twoFAPassword = ""
    @State private var isSubmitting2FA = false
    @State private var twoFAError: String?

    // QR refresh counter (for cache busting)
    @State private var qrVersion = 0

    private let api = APIService.shared

    // RN parity constants
    private let pollInterval: TimeInterval = 1.5
    private let qrRefreshInterval: TimeInterval = 20
    private let validateTimeout: TimeInterval = 45

    private enum QRPhase { case loading, ready, error }

    var body: some View {
        VStack(spacing: 0) {
            // Back button
            HStack {
                if appState.pairing == .needs2FA {
                    BackButton { Task { await disconnect() } }
                } else {
                    BackButton { Task { await restart() } }
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            ScrollView {
                VStack(spacing: 24) {
                    if appState.pairing == .needs2FA {
                        twoFASection
                    } else {
                        qrSection
                    }

                    if appState.pairing != .needs2FA && qrPhase != .error {
                        waitingSection
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
            }
        }
        .background(c.bg)
        .onAppear {
            if appState.pairing == .needs2FA {
                qrPhase = .ready
            } else {
                startQRRefresh()
            }
            appState.startStatusPolling(interval: pollInterval)
        }
        .onDisappear {
            qrRefreshTask?.cancel()
            appState.stopStatusPolling()
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                Task { await appState.checkStatus() }
            }
        }
    }

    // MARK: - QR section

    private var qrSection: some View {
        VStack(spacing: 24) {
            // Title
            Text("Подключите ваше приложение")
                .font(.title2.bold())
                .foregroundStyle(c.text)
                .multilineTextAlignment(.center)

            // Steps — centered plain text, no numbered circles
            stepsView

            // QR image
            qrCard
        }
    }

    // MARK: - Steps (centered, no card)

    private var stepsView: some View {
        VStack(spacing: 14) {
            Text("1. Откройте ваше приложение")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(c.text)
                .multilineTextAlignment(.center)
            Text("2. Профиль → Устройства → Сканировать QR")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(c.text)
                .multilineTextAlignment(.center)
            Text("3. Наведите камеру на QR-код ниже")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(c.text)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - QR card

    private var qrCard: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.white)

                switch qrPhase {
                case .loading:
                    loadingContent
                case .ready:
                    if let qrImage {
                        Image(uiImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .padding(12)
                    }
                case .error:
                    errorContent
                }
            }
            .frame(width: 250, height: 250)

            if qrPhase != .error {
                Text("QR обновляется каждые 20 секунд")
                    .font(.caption)
                    .foregroundStyle(c.textFaint)
            }
        }
    }

    private var loadingContent: some View {
        VStack(spacing: 18) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Генерируем QR-код…")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(c.textSecondary)
        }
    }

    private var errorContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 34))
                .foregroundStyle(Theme.amber)
            Text("Не удалось получить QR-код. Нажмите, чтобы начать заново.")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(c.text)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
            Button("Начать заново") {
                Task { await restart() }
            }
            .buttonStyle(SecondaryButtonStyle(color: Theme.primary))
        }
        .padding(24)
    }

    // MARK: - Waiting

    private var waitingSection: some View {
        VStack(spacing: 12) {
            // Animated dots — 12x12, gap 10, active = Theme.primary
            AnimatedDotsLarge(color: Theme.primary)
            Text("Ожидание подключения...")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(c.textSecondary)
        }
    }

    // MARK: - 2FA section

    private var twoFASection: some View {
        VStack(spacing: 20) {
            Text("Подтвердите вход")
                .font(.title2.bold())
                .foregroundStyle(c.text)

            Text("QR отсканирован. Введите пароль двухфакторной аутентификации вашего аккаунта.")
                .font(.subheadline)
                .foregroundStyle(c.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            if let hint = appState.pairingHint, !hint.isEmpty {
                Text("Подсказка: \(hint)")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }

            SecureField("Пароль", text: $twoFAPassword)
                .textFieldStyle(.plain)
                .frame(height: 56)
                .padding(.horizontal, 16)
                .background(c.card)
                .clipShape(.rect(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(c.border, lineWidth: 1.5)
                }
                .disabled(isSubmitting2FA)

            if let error = twoFAError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Theme.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await submit2FA() }
            } label: {
                HStack(spacing: 8) {
                    if isSubmitting2FA {
                        ProgressView().tint(.white)
                    }
                    Text(isSubmitting2FA ? "Отправка…" : "Подтвердить")
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
            }
            .buttonStyle(PrimaryButtonStyle(color: Theme.green))
            .disabled(isSubmitting2FA || twoFAPassword.isEmpty)
        }
        .padding(.top, 12)
    }

    // MARK: - QR polling

    private func startQRRefresh() {
        guard let userId = appState.userId else { return }
        qrPhase = .loading
        qrRefreshTask?.cancel()
        qrRefreshTask = Task {
            await validateQR(userId: userId)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(qrRefreshInterval))
                if Task.isCancelled { break }
                qrVersion += 1
                await loadQR(userId: userId)
            }
        }
    }

    /// First load: try for up to validateTimeout seconds, then show error.
    private func validateQR(userId: String) async {
        let deadline = Date().addingTimeInterval(validateTimeout)
        while Date() < deadline {
            if Task.isCancelled { return }
            if let data = try? await qrFetch(userId: userId),
               let image = UIImage(data: data) {
                qrImage = image
                qrPhase = .ready
                return
            }
            // On 503 → retry every 1s; on 404 → reconnect
            try? await Task.sleep(for: .seconds(1))
        }
        qrPhase = .error
    }

    private func loadQR(userId: String) async {
        if let data = try? await qrFetch(userId: userId),
           let image = UIImage(data: data) {
            qrImage = image
            qrPhase = .ready
        }
    }

    /// Fetch QR with 8s timeout, handle 404 → reconnect, 503 → silent retry
    private func qrFetch(userId: String) async throws -> Data {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.waitsForConnectivity = false
        let s = URLSession(configuration: config)

        var url = api.baseURL.appendingPathComponent("api/max-qr/\(userId)")
        if var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            comps.queryItems = [URLQueryItem(name: "v", value: String(qrVersion))]
            if let u = comps.url { url = u }
        }

        let (data, response) = try await s.data(from: url)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 404 {
                // Session expired — trigger reconnect
                await MainActor.run {
                    Task { await appState.disconnect() }
                }
                throw URLError(.badServerResponse, userInfo: ["status": 404])
            }
            if http.statusCode == 503 {
                throw URLError(.badServerResponse, userInfo: ["status": 503])
            }
            if !(200...299).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
        }
        return data
    }

    // MARK: - 2FA submit

    private func submit2FA() async {
        isSubmitting2FA = true
        twoFAError = nil
        let error = await appState.submit2FA(password: twoFAPassword)
        isSubmitting2FA = false
        if let err = error {
            twoFAError = "Неверный пароль или время истекло. Попробуйте снова."
            _ = err // suppress unused
        }
    }

    // MARK: - Restart / Disconnect

    private func restart() async {
        qrRefreshTask?.cancel()
        appState.stopStatusPolling()
        await appState.disconnect()
    }

    private func disconnect() async {
        qrRefreshTask?.cancel()
        appState.stopStatusPolling()
        await appState.disconnect()
    }
}

// MARK: - Animated dots (large — 12×12, gap 10, DOT_INTERVAL 800ms)

private struct AnimatedDotsLarge: View {
    let color: Color
    @State private var phase = 0

    private let timer = Timer.publish(every: 0.8, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)
                    .opacity(phase == index ? 1 : 0.3)
            }
        }
        .onReceive(timer) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                phase = (phase + 1) % 3
            }
        }
    }
}

#Preview {
    QRView()
        .environmentObject(AppState())
}
