import SwiftUI
import UtataneCore

struct ShioriStatusView: View {
    var body: some View {
        Section("対応SHIORI") {
            ForEach(ShioriCatalog.descriptors) { descriptor in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(LocalizedStringKey(descriptor.displayName))
                        Text(executionLabel(descriptor))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(statusLabel(descriptor))
                        .foregroundStyle(statusColor(descriptor))
                }
            }
        }

        Section {
            Text("実行方式と追加ランタイムの要否を表示する。SHIORIのダウンロードや更新は行わない。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func statusLabel(_ descriptor: ShioriDescriptor) -> LocalizedStringKey {
        if descriptor.provisioning == .included {
            return "内蔵"
        }
        return switch descriptor.runtimeRequirement {
        case .configuredExecutable: "外部ランタイムが必要"
        case .wine: "Wineが必要"
        case .none:
            switch descriptor.provisioning {
            case .included: "内蔵"
            case .ghost: "ゴースト同梱"
            case .user: "手動導入"
            case .unavailable: "未対応"
            }
        }
    }

    private func statusColor(_ descriptor: ShioriDescriptor) -> Color {
        descriptor.runtimeRequirement == .none ? .secondary : .orange
    }

    private func executionLabel(_ descriptor: ShioriDescriptor) -> LocalizedStringKey {
        switch descriptor.execution {
        case .builtIn: "ネイティブ実装"
        case .bundledNativeModule: "macOSネイティブモジュール"
        case .externalProcess: "外部プロセス"
        case .dynamicLibrary: "標準SHIORI dylib"
        case .windowsDLL: "Windows DLL互換経路"
        }
    }
}
