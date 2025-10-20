# iOS 解压缩文件管理器 — 项目脚手架（SwiftUI + Liquid Glass）

最低系统：iOS 17+
语言/框架：Swift 5、SwiftUI、并发（async/await）

## 项目结构

- App/ — 应用入口（SwiftUI App）与资源（Assets）
- UI/ — 主页与任务单元（“液态玻璃”毛玻璃风格）
- Core/
  - Models/ — ArchiveFormat / ArchiveTask / ArchiveProgress
  - TaskQueue.swift — 内存任务队列（添加/更新/取消占位）
- Services/ — ArchiveService 协议、服务注册表
- ArchiveAdapters/ — ZIP/RAR/7Z 适配器（ZIP: 模拟实现；RAR/7Z: 已集成基础适配器，包含探测、分卷/密码识别、进度与取消的最小可用路径）
- Utilities/ — CancellationToken、ZipUtils / RarUtils / SevenZUtils 等工具
- Tests/
  - ArchiveManagerTests — 单元测试（覆盖 ZIP/RAR/7Z 的基础流程与错误分支）
  - ArchiveManagerSnapshotTests — 快照测试占位（未引入快照库）

## 能力（当前阶段）

- UIDocumentPicker 导入文件；任务执行时自动探测格式并选择相应适配器。
- 任务模型：包含 id、状态、进度、速度、剩余时间、可取消等字段。
- ArchiveService 协议：`extract(inputURL:destination:password:progress:cancellationToken:)`、`probe()`；
  - ZIP：模拟读取并上报进度/取消；能够识别密码需求与错误密码（测试注入）。
  - RAR（基于未来 UnrarKit 接入预留）：已实现基础探测（扩展名/签名）、分卷识别（.r00/.partNN.rar）、密码提示流程、进度与取消（当前为模拟解压管线）。
  - 7Z（基于未来 LzmaSDK-ObjC 接入预留）：已实现基础探测（扩展名/签名）、分卷识别（.7z.001/002…）、密码提示流程、进度与取消（当前为模拟解压管线）。
- UI：主页采用 SwiftUI Material（ultraThinMaterial）实现“liquid glass”视觉基底；错误与密码提示复用现有组件。

> 说明：目前未实际链接第三方库，适配器通过可注入的 inspector 闭包与模拟数据驱动测试，确保流程与错误分支就绪。后续任务可无缝替换为真实库调用。

## 构建与 CI

- Xcode 工程：`ArchiveManager.xcodeproj`
- Scheme：`ArchiveManager`（已共享）
- GitHub Actions：`.github/workflows/ios-ci.yml` 使用 macOS runner 构建并运行单测。

本地构建示例：

```bash
xcodebuild -project ArchiveManager.xcodeproj \
  -scheme ArchiveManager \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,OS=latest,name=iPhone 15 Pro' \
  build test
```

## 依赖与桥接（预留）

- ZIPFoundation（建议通过 SPM 集成，待后续任务对接）。
- UnrarKit、LzmaSDK-ObjC（ObjC 库；桥接头：`Bridging/ArchiveManager-Bridging-Header.h`）。
  - 后续集成时，在 Bridging Header 中加入：
    - `#import <UnrarKit/UnrarKit.h>`
    - `#import <LzmaSDK_ObjC/LzmaSDKObjCReader.h>`

> 当前未引入三方依赖，避免 CI 拉取失败；后续任务按需接入。

## 开源许可与第三方声明

- UnRAR License：仅允许用于解压 RAR，不得用于创建 RAR；具体条款详见 THIRD_PARTY_NOTICES.md 与 UnrarKit 所附许可。
- LZMA SDK：7-Zip 的 LZMA SDK 以公共领域/宽松许可发布；LzmaSDK-ObjC 遵循其上游许可，详见其仓库与 THIRD_PARTY_NOTICES.md。

更多第三方与许可信息参见：`THIRD_PARTY_NOTICES.md`。

## 路线图

- [x] ZIP/RAR/7Z 基础适配器与探测（模拟解压，流程打通）
- [x] 分卷与密码流程（UI 与解密回调）
- [ ] 接入真实库（ZIPFoundation / UnrarKit / LzmaSDK-ObjC）
- [ ] 大文件与后台优化、错误恢复
- [ ] 快照测试框架与可视化回归
