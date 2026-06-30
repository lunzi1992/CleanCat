import SwiftUI

struct ScanErrorView: View {
    let message: String
    @ObservedObject var scanner: PhotoScanner

    var body: some View {
        ZStack {
            Color.cream.ignoresSafeArea()

            VStack(spacing: Design.spaceXL) {
                Spacer()

                ZStack {
                    Circle().fill(Color.peachL).frame(width: 120, height: 120)
                    Image(systemName: "cat.fill").font(.system(size: 36)).foregroundStyle(Color.grayW.opacity(0.6))
                }

                VStack(spacing: Design.spaceSM) {
                    Text("扫描中断").font(Design.headlineFont).foregroundColor(Color.sageD)
                    Text(message).font(Design.bodyFont).foregroundColor(Color.grayW)
                        .multilineTextAlignment(.center)
                }

                Button(action: { scanner.cancelScan() }) {
                    Text("返回重试")
                }
                .brandButton()
                .padding(.horizontal, Design.space2XL)

                Spacer()
            }
        }
    }
}
