import SwiftUI

struct ScanningView: View {
    @ObservedObject var scanner: PhotoScanner
    @State private var rotation = 0.0

    var progressFraction: Double {
        guard scanner.progress.total > 0 else { return 0 }
        return Double(scanner.progress.current) / Double(scanner.progress.total)
    }

    var body: some View {
        ZStack {
            Color.cream.ignoresSafeArea()

            VStack(spacing: Design.spaceXL) {
                Spacer()

                // 旋转猫爪
                ZStack {
                    Circle()
                        .stroke(Color.sageL, lineWidth: 6)
                        .frame(width: 140, height: 140)

                    Circle()
                        .trim(from: 0, to: progressFraction)
                        .stroke(Color.brandGradient, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .frame(width: 140, height: 140)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.3), value: progressFraction)

                    Image(systemName: "cat.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.brandGradient)
                        .rotationEffect(.degrees(rotation))
                }
                .onAppear {
                    withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                        rotation = 360
                    }
                }

                VStack(spacing: Design.spaceSM) {
                    Text(scanner.scanStatusText)
                        .font(Design.headlineFont).foregroundColor(Color.sageD)
                        .multilineTextAlignment(.center)

                    Text("\(scanner.progress.current) / \(scanner.progress.total)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(Color.sageD)

                    if scanner.progress.total > 0 && scanner.progress.current >= scanner.progress.total {
                        Text("照片读取完成，正在生成结果，请稍候")
                            .font(Design.captionFont)
                            .foregroundColor(Color.grayW)
                    }
                }

                Button(action: { scanner.cancelScan() }) {
                    Text("取消").font(.subheadline).foregroundColor(Color.grayW)
                }
                .padding(.top, Design.spaceSM)

                Spacer()
            }
        }
    }
}
