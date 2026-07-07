import SwiftUI

struct ScanStartView: View {
    @ObservedObject var scanner: PhotoScanner

    var body: some View {
        ZStack {
            Color.cream.ignoresSafeArea()
            ScrollView {
                VStack(spacing: Design.spaceLG) {
                    heroSection
                    yearSelector
                    scanButton
                    privacyNote
                }
                .contentWrapper()
                .padding(.top, 40)
                .padding(.bottom, 60)
            }
        }
        .onAppear {
            if scanner.availableYears.isEmpty {
                scanner.detectAvailableYears()
            }
        }
    }

    // MARK: Hero

    var heroSection: some View {
        VStack(spacing: Design.spaceMD) {
            ZStack {
                Circle().fill(Color.sageL).frame(width: 100, height: 100)
                Image(systemName: "cat.fill").font(.system(size: 40)).foregroundStyle(Color.brandGradient)
            }

            VStack(spacing: Design.spaceXS) {
                Text("涂涂已就绪")
                    .font(Design.headlineFont).foregroundColor(Color.sageD)
                Text("选中一个年份，剩下的交给轻猫")
                    .font(Design.bodyFont).foregroundColor(Color.grayW)
            }
        }
    }

    // MARK: 年份选择器

    var yearSelector: some View {
        VStack(alignment: .leading, spacing: Design.spaceSM) {
            Text("选择年份").font(Design.captionFont).foregroundColor(Color.grayW)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Design.spaceSM) {
                    ForEach(scanner.availableYears.sorted(by: >), id: \.self) { year in
                        yearChip(YearBucket.year(year))
                    }
                    yearChip(.all)
                }
                .padding(.horizontal, 2)
            }
        }
    }

    func yearChip(_ bucket: YearBucket) -> some View {
        let isSelected = scanner.selectedBucket == bucket

        return Button(action: {
            catImpact(.light)
            scanner.selectedBucket = bucket
        }) {
            Text(bucket.displayName)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(isSelected ? .white : Color.sageD)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: 62)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(
                    Group {
                        if isSelected {
                            Color.brandGradient
                        } else {
                            Color(.systemBackground)
                        }
                    }
                )
                .clipShape(Capsule())
                .if(!isSelected) {
                    $0.shadow(color: Design.shadowColor, radius: 4, y: 2)
                }
        }
    }

    // MARK: 扫描按钮

    var scanButton: some View {
        Button(action: {
            catImpact(.medium)
            scanner.cancelScan()
            scanner.selectBucket(scanner.selectedBucket ?? .all, forceRescan: true)
        }) {
            Label("开始分析", systemImage: "sparkle.magnifyingglass")
        }
        .brandButton()
        .padding(.top, Design.spaceSM)
    }

    // MARK: 隐私说明

    var privacyNote: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.shield").font(.caption2)
            Text("100% 本地处理 · 照片不会离开你的 iPhone")
        }
        .font(Design.captionFont)
        .foregroundColor(Color.grayW)
    }
}
