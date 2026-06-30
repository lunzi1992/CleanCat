<p align="center">
  <img src="Resources/cleancat-app-icon.png" width="128" alt="轻猫 CleanCat App Icon">
</p>

<h1 align="center">轻猫 CleanCat</h1>

<p align="center">
  像猫一样，轻快整理你的相册。
</p>

CleanCat 是一款 100% 本地处理的 iOS 相册整理助手。它帮助用户按年份扫描相册，找出重复照片、相似照片、截图和录屏，再由用户自己确认要保留或删除的内容。

照片不会上传到服务器，扫描和判断都在设备本地完成。

---

## 产品故事

轻猫的灵感来自一只叫“涂涂”的虎斑美短。

相册里总会有很多舍不得删、又确实需要整理的照片：连拍、截图、聊天记录、表情包、网页截屏、模糊照片，还有为了拍好猫咪而留下的一整串相似照片。

轻猫想做的不是替用户决定，而是像一只聪明的电子猫一样，把需要注意的照片轻轻扒拉到面前：

- 哪些照片完全重复
- 哪些照片看起来很相似
- 哪些截图和录屏已经堆积太久
- 哪些照片可以先预览、再决定是否删除

整理相册不应该是一件沉重的家务活。它应该轻一点、慢一点、放心一点。

---

## 当前 MVP 能力

- 按年份扫描相册，避免一次性处理几万张照片
- 自动识别截图和录屏
- 检测完全重复照片
- 检测相似照片并分组展示
- 展示小图列表，并支持点击预览大图
- 支持用户手动选择、取消选择
- 调用系统删除确认页，删除用户确认的照片
- 扫描过程支持取消，避免旧扫描结果覆盖新状态
- 本地记录基础使用事件，便于后续调试和体验优化
- 内置轻猫 App 图标与品牌视觉资源

当前版本更适合作为 TestFlight/MVP 验证版本。隐私政策、正式付费、StoreKit、iCloud 照片提示、公开上架配置等会放在下个阶段完善。

---

## 技术栈

- 语言：Swift
- UI：SwiftUI
- 平台：iOS
- 当前工程最低系统：iOS 17.0
- 核心框架：Photos、UIKit、CommonCrypto
- 依赖策略：以 Apple 原生能力为主，当前无第三方运行时依赖

---

## 核心实现

| 能力 | 实现方式 | 说明 |
| --- | --- | --- |
| 年份扫描 | Photos fetch + 日期过滤 | 支持按年分桶处理 |
| 截图/录屏识别 | PHAsset 元数据 | 使用系统媒体类型和子类型 |
| 重复照片检测 | 文件大小/尺寸预筛 + MD5 | 保守匹配，降低误删风险 |
| 相似照片检测 | pHash 感知哈希 | 控制比较窗口，优先保证性能 |
| 照片预览 | PHImageManager | 小图列表 + 全屏预览 |
| 删除照片 | PHPhotoLibrary.performChanges | 使用系统确认页完成删除 |
| 状态保护 | scanID + Task cancel | 避免取消后旧任务回写界面 |

---

## 项目结构

```text
CleanCat/
├── App/                          # 应用入口与全局状态
├── Core/
│   ├── Analytics/                # 本地事件记录
│   ├── Detector/                 # 重复/相似/质量相关检测
│   ├── Models/                   # 扫描结果数据模型
│   └── Scanner/                  # 相册扫描与删除管理
├── Extensions/                   # SwiftUI 辅助扩展
├── Resources/
│   ├── Assets.xcassets/          # AppIcon 资源
│   ├── Info.plist                # 权限与启动配置
│   └── cleancat-app-icon.png     # README 图标预览
└── UI/
    ├── Components/               # 通用组件
    ├── Delete/                   # 删除确认
    ├── Onboarding/               # 权限引导
    ├── Paywall/                  # 付费入口占位
    ├── Results/                  # 扫描结果
    ├── Scan/                     # 扫描首页与进度页
    └── Settings/                 # 设置页
```

---

## 构建与运行

1. 用 Xcode 打开 `CleanCat.xcodeproj`
2. 选择 iPhone 模拟器或真机
3. 配置 Signing Team
4. 运行 `CleanCat` scheme

真机测试需要授权相册访问。模拟器测试前需要先向模拟器相册导入照片。

---

## License

MIT License

---

**轻猫 CleanCat**

> 你的每一张照片，都值得被认真对待。它们只是需要被整理好。
