import SwiftUI

struct TranscriptionModelDownloadProgressView: View {
    let progress: ModelDownloadProgress?
    let totalBytes: Int64
    let identifier: String

    private var phase: ModelDownloadProgress.Phase { progress?.phase ?? .connecting }
    private var receivedBytes: Int64 { max(0, progress?.receivedBytes ?? 0) }
    private var expectedBytes: Int64 {
        let reported = progress?.totalBytes ?? 0
        return reported > 0 ? reported : totalBytes
    }
    private var fraction: Double {
        guard expectedBytes > 0 else { return 0 }
        return min(1, max(0, Double(receivedBytes) / Double(expectedBytes)))
    }
    private var amount: String {
        L(.trans_model_download_bytes, formatBytes(receivedBytes), formatBytes(expectedBytes))
    }
    private var speed: String? {
        guard phase == .downloading, receivedBytes > 0,
              let rate = progress?.bytesPerSecond,
              rate.isFinite, rate >= 1, rate < Double(Int64.max) else { return nil }
        return L(.trans_model_download_rate, formatBytes(Int64(rate)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if phase == .downloading {
                Text(Self.phaseLabel(phase))
                    .font(.subheadline)
                    .accessibilityIdentifier(identifier + "_phase")
                ProgressView(value: fraction)
                    .accessibilityLabel(Self.phaseLabel(phase))
                    .accessibilityValue(amount)
            } else {
                ProgressView(Self.phaseLabel(phase))
                    .font(.subheadline)
                    .accessibilityIdentifier(identifier + "_phase")
            }

            if phase != .connecting || receivedBytes > 0 {
                transferDetails
            }

            if let host = progress?.sourceHost, !host.isEmpty {
                Text(L(.trans_model_download_source, host))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(identifier + "_source")
            }

            Text(L(.trans_model_download_foreground))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(identifier + "_foreground")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder
    private var transferDetails: some View {
        if let speed {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    amountText
                    speedText(speed)
                }
                .fixedSize(horizontal: true, vertical: false)

                VStack(alignment: .leading, spacing: 4) {
                    amountText
                    speedText(speed)
                }
            }
        } else {
            amountText
        }
    }

    private var amountText: some View {
        Text(amount)
            .font(.subheadline.monospacedDigit())
            .accessibilityIdentifier(identifier + "_amount")
    }

    private func speedText(_ value: String) -> some View {
        Text(value)
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .accessibilityIdentifier(identifier + "_speed")
    }

    private func formatBytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, value), countStyle: .file)
    }

    static func phaseLabel(_ phase: ModelDownloadProgress.Phase) -> String {
        switch phase {
        case .connecting: return L(.trans_model_connecting)
        case .downloading: return L(.trans_model_downloading)
        case .verifying: return L(.trans_model_verifying)
        }
    }
}
