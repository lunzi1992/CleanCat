import SwiftUI

/// 空状态视图
struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: icon)
                .font(.system(size: 56))
                .foregroundColor(.warmGray.opacity(0.5))

            VStack(spacing: 8) {
                Text(title)
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundColor(.warmGray)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.warmGray.opacity(0.7))
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

/// 全选按钮(带回调)
struct SelectAllButton: View {
    let title: String
    let itemCount: Int
    let spaceToFree: Int64
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.sage)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text("\(itemCount) 项 · \(formatBytes(spaceToFree))")
                    .font(.caption)
                    .foregroundColor(.sage)
            }
            .padding(12)
            .background(Color.sageLight.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .foregroundColor(.sageDark)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter().string(fromByteCount: bytes)
    }
}
