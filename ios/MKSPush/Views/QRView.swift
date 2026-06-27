//
//  QRView.swift
//  MKSPush
//

import SwiftUI

/// Pairing screen: shows an auto-refreshing QR code and polls for connection.
struct QRView: View {
    @EnvironmentObject private var appState: AppState

    @State private var qrImage: UIImage?
    @State private var isLoadingQR = true
    @State private var loadFailed = false
    @State private var firstLoadStarted: Date?

    @State private var qrRefreshTask: Task<Void, Never>?
    @State private var statusPollTask: Task<Void, Never>?

    private let api = APIService.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("Подключите ваше приложение")
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 12)

                instructions

                qrCard

                if !loadFailed {
                    VStack(spacing: 14) {
                        HStack(spacing: 8) {
                            Text("Ожидание подключения")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                            AnimatedDots()
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .background(Color(.systemBackground))
        .onAppear {
            startQRRefresh()
            startStatusPolling()
        }
        .onDisappear {
            qrRefreshTask?.cancel()
            statusPollTask?.cancel()
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
        .background(Color(.secondarySystemBackground))
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
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
    }

    private var qrCard: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.08), radius: 16, y: 8)

                if let qrImage {
                    Image(uiImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .padding(20)
                } else if loadFailed {
                    failureContent
                        .padding(24)
                } else {
                    loadingContent
                        .padding(24)
                }
            }
            .frame(width: 260, height: 260)

            if !loadFailed {
                Text("QR обновляется каждые 20 секунд")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var loadingContent: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
                .tint(Theme.green)
            Text("Генерируем QR-код…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var failureContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 34))
                .foregroundStyle(Theme.red)
            Text("Не удалось получить QR-код")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
            Button("Начать заново") {
                Task { await restart() }
            }
            .buttonStyle(SecondaryButtonStyle(color: Theme.blue))
        }
    }

    // MARK: - Loading

    private func startQRRefresh() {
        guard let userId = appState.userId else { return }
        firstLoadStarted = Date()
        qrRefreshTask?.cancel()
        qrRefreshTask = Task {
            await loadQR(userId: userId)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                if Task.isCancelled { break }
                await loadQR(userId: userId)
            }
        }
    }

    private func loadQR(userId: String) async {
        if qrImage == nil { isLoadingQR = true }
        do {
            let data = try await api.qrImageData(userId: userId)
            if let image = UIImage(data: data) {
                qrImage = image
                isLoadingQR = false
                loadFailed = false
            } else {
                handleLoadFailure()
            }
        } catch {
            handleLoadFailure()
        }
    }

    private func handleLoadFailure() {
        isLoadingQR = false
        // Only show the error state if we never got a QR and 15s elapsed.
        if qrImage == nil, let started = firstLoadStarted, Date().timeIntervalSince(started) >= 15 {
            loadFailed = true
        }
    }

    private func startStatusPolling() {
        guard let userId = appState.userId else { return }
        statusPollTask?.cancel()
        statusPollTask = Task {
            while !Task.isCancelled {
                if let status = try? await api.status(userId: userId), status == .active {
                    appState.markConnected()
                    break
                }
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private func restart() async {
        qrRefreshTask?.cancel()
        statusPollTask?.cancel()
        await appState.disconnect()
    }
}
