import SwiftUI

struct ConfidenceBadge: View {
    let confidence: RecommendationConfidence

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: confidence.systemImage)
                .font(.system(size: 8, weight: .bold))
            Text(confidence.title)
                .font(.system(size: 10, weight: .bold))
        }
        .foregroundColor(foregroundColor)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(backgroundColor)
        .clipShape(Capsule())
    }

    private var foregroundColor: Color {
        switch confidence {
        case .high: return .sageDark
        case .cautious: return .orange
        }
    }

    private var backgroundColor: Color {
        switch confidence {
        case .high: return Color.sage.opacity(0.14)
        case .cautious: return Color.orange.opacity(0.12)
        }
    }
}

struct ReasonTagRow: View {
    let tags: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tags.prefix(3), id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.warmGray)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.warmGray.opacity(0.08))
                        .clipShape(Capsule())
                }
            }
        }
    }
}
