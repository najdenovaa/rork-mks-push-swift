//
//  QRView.swift
//  MKSPush
//
//  Pairing screen: QR code + 2FA mode.
//  Ported from React Native build 23 QRScreen.tsx.
//

import Combine
import SwiftUI

struct QRView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.themeColors) private var c

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

    private enum QRPhase { case loading, ready, error }

    var body: some View {
        VStack(spacing: 0) {
            // Back button
            HStack {
                BackButton { Task { await restart() } }
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
                qrPhase = .ready  // Skip QR loading in 2FA mode
            } else {
                startQRRefresh()
            }
            appState.startStatusPolling(interval: 5)
        }
        .onDisappear {
            qrRefreshTask?.cancel()
            appState.stopStatusPolling()
        }
    }

    // MARK: - QR section

    private var qrSection: some View {
        VStack(spacing: 24) {
            Text("Подключите ваше приложение")
                .font(.title2.bold())
                .foregroundStyle(c.text)
                .multilineTextAlignment(.center)

            instructions

            qrCard
        }
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 14) {
            instructionRow(1, "Откройте ваше приложение")
            instructionRow(2, "Профиль → Устройства → Сканировать QR")
            instructionRow(3, "Наведите камеру на QR-код ниже")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(c.card)
        .clipShape(.rect(cornerRadius: 18))
    }

    private func instructionRow(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Text("\(number)")
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Theme.green)
                .clipShape(Circle())
            Text(text)
                .font(.subheadline)
                .foregroundStyle(c.text)
            Spacer(minLength: 0)
        }
    }

    private var qrCard: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(c.surface)
                    .shadow(color: .black.opacity(0.06), radius: 16, y: 8)

                switch qrPhase {
                case .loading:
                    loadingContent
                case .ready:
                    if let qrImage {
                        Image(uiImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .padding(20)
                    }
                case .error:
                    errorContent
                }
            }
            .frame(width: 260, height: 260)

            if qrPhase != .error {
                Text("QR обновляется каждые 20 секунд")
                    .font(.caption)
                    .foregroundStyle(c.textFaint)
            }
        }
    }

    private var loadingContent: some View {
        VStack(spacing: 14) {
            SpinnerRow(color: c.textSecondary)
            Text("Генерируем QR-код…")
                .font(.subheadline)
                .foregroundStyle(c.textSecondary)
        }
    }

    private var errorContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 34))
                .foregroundStyle(Theme.amber)
            Text("Не удалось получить QR-код")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(c.text)
                .multilineTextAlignment(.center)
            Button("Начать заново") {
                Task { await restart() }
            }
            .buttonStyle(SecondaryButtonStyle(color: Theme.primary))
        }
        .padding(24)
    }

    // MARK: - Waiting

    private var waitingSection: some View {
        HStack(spacing: 8) {
            Text("Ожидание подключения")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(c.textSecondary)
            AnimatedDots(color: c.textSecondary)
        }
    }

    // MARK: - 2FA section

    private var twoFASection: some View {
        VStack(spacing: 20) {
            Text("Подтвердите вход")
                .font(.title2.bold())
                .foregroundStyle(c.text)

            if let hint = appState.pairingHint, !hint.isEmpty {
                Text(hint)
                    .font(.subheadline)
                    .foregroundStyle(c.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }

            SecureField("Пароль", text: $twoFAPassword)
                .textFieldStyle(.plain)
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .background(c.card)
                .clipShape(.rect(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(c.border, lineWidth: 1)
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
                try? await Task.sleep(for: .seconds(20))
                if Task.isCancelled { break }
                qrVersion += 1
                await loadQR(userId: userId)
            }
        }
    }

    /// First load: try for up to 15 seconds then show error.
    private func validateQR(userId: String) async {
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if Task.isCancelled { return }
            if let data = try? await api.qrImageData(userId: userId),
               let image = UIImage(data: data) {
                qrImage = image
                qrPhase = .ready
                return
            }
            try? await Task.sleep(for: .seconds(1))
        }
        qrPhase = .error
    }

    private func loadQR(userId: String) async {
        if let data = try? await api.qrImageData(userId: userId),
           let image = UIImage(data: data) {
            qrImage = image
            qrPhase = .ready
        }
    }

    // MARK: - 2FA submit

    private func submit2FA() async {
        isSubmitting2FA = true
        twoFAError = nil
        let error = await appState.submit2FA(password: twoFAPassword)
        isSubmitting2FA = false
        if let err = error {
            twoFAError = err
        }
    }

    // MARK: - Restart

    private func restart() async {
        qrRefreshTask?.cancel()
        appState.stopStatusPolling()
        await appState.disconnect()
    }
}

// MARK: - Spinner row (matching RN spinnerRow)

private struct SpinnerRow: View {
    let color: Color
    @State private var phase = 0

    private let timer = Timer.publish(every: 0.3, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                    .opacity(phase == index ? 1 : 0.25)
            }
        }
        .onReceive(timer) { _ in
            withAnimation(.easeInOut(duration: 0.25)) {
                phase = (phase + 1) % 3
            }
        }
    }
}

#Preview {
    QRView()
        .environmentObject(AppState())
}
