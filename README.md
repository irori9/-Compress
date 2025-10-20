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
- ArchiveAdapters/ — ZIP/RAR/7Z 适配器骨架（待实现）
- Utilities/ — CancellationToken 等工具
- Tests/
  - ArchiveManagerTests — 示例单测
  - ArchiveManagerSnapshotTests — 快照测试占位（未引入快照库）

## 能力与占位

- UIDocumentPicker 导入文件，生成待处理任务（暂不实际解压）。
- 任务模型：包含 id、状态、进度、速度、剩余时间、可取消等字段。
- ArchiveService 协议：`extract(inputURL:destination:password:progress:cancellationToken:)`、`probe()`；
  适配器（ZIP/RAR/7Z）仅占位，未来接入 ZIPFoundation / UnrarKit / LzmaSDK-ObjC。
- UI：主页采用 SwiftUI Material（ultraThinMaterial）实现“liquid glass”视觉基底。

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

## 依赖（占位）

- ZIPFoundation（建议通过 SPM 集成，待后续任务对接）
- UnrarKit、LzmaSDK-ObjC（ObjC 库，可能需要桥接头 Bridging Header：`Bridging/ArchiveManager-Bridging-Header.h`）

> 当前未引入三方依赖，避免 CI 拉取失败；后续任务按需接入。

## 路线图

- [ ] ZIP/RAR/7Z 适配器实现与探测
- [ ] 分卷与密码流程（UI 与解密回调）
- [ ] 大文件与后台优化、错误恢复
- [ ] 快照测试框架与可视化回归
