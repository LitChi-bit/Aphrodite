# Aphrodite

> [English](#english) | 中文

移动端优先的端到端加密即时通讯应用，基于 Flutter + Go + Rust/OpenMLS 构建。

---

## 当前状态

| 组件 | 状态 |
|------|------|
| Flutter 前端 | 认证流程、聊天 UI（Telegram 风格）、Drift 本地数据库、Riverpod 状态管理 — UI 完整 |
| Go 后端 | REST API（Ed25519 JWT 认证、设备管理、MLS KeyPackage/群组状态）、PostgreSQL — 已测试通过 |
| Rust 原生层 | MLS 1.0 引擎（RFC 9420）— 设备身份、KeyPackage、群组加解密 — 已编译、已 FFI 集成 |

## 功能

| 功能 | 状态 |
|------|------|
| 文字消息（MLS 端到端加密） | MLS 引擎已完成，Flutter 联调中 |
| 语音消息 | 计划中 |
| 实时语音/视频通话 | 计划中 |
| 端到端加密（消息/文件/通话媒体） | MLS 核心已完成 |

## 平台支持

| 平台 | 状态 |
|------|------|
| Android | 开发中 |
| iOS | 开发中 |
| Windows / Linux | 暂缓 |
| Web | 仅调试用 |

## 项目结构

```
Aphrodite/
├── lib/                      # Flutter 前端（70 文件）
│   ├── app/                  # 路由、主题
│   ├── auth/                 # 认证（登录、设备管理）
│   ├── chat/                 # 聊天（消息、会话、通话）
│   │   └── e2ee/             # MLS FFI 绑定
│   ├── core/                 # 网络、存储、异常
│   └── plugins/              # 插件系统（预留）
├── backend/                  # Go 后端（63 文件）
│   ├── internal/
│   │   ├── auth/             # 认证服务
│   │   ├── chat/             # 会话与消息
│   │   ├── httpapi/          # HTTP 传输层
│   │   ├── keypackage/       # MLS KeyPackage
│   │   ├── mlsstate/         # MLS 群组状态
│   │   └── migrations/       # 迁移引擎
│   └── migrations/           # SQL 迁移（7 次）
├── native/                   # Rust 原生层
│   └── aphrodite_openmls/    # MLS 1.0 引擎
└── test/                     # Dart 测试（21 文件）
```

## 安全模型

客户端加密，服务器仅保存密文：

- **消息加密**：MLS 1.0 (RFC 9420) — DHKEM X25519 + AES-128-GCM + Ed25519
- **文件加密**：AES-256-GCM + HKDF，每文件独立密钥（计划中）
- **通话媒体**：LiveKit E2EE Frame Cryptor 帧级加密（计划中）
- **密钥存储**：OS Keychain / Keystore，私钥不离开设备

## 技术栈

| 层 | 选型 | 状态 |
|---|---|---|
| Flutter UI | Flutter 3.44 / Dart 3.12 | ✅ |
| 状态管理 | Riverpod | ✅ |
| HTTP | Dio | ✅ |
| 实时通信 | WebSocket | ✅ (客户端) |
| 本地数据库 | Drift / SQLite | ✅ |
| 安全存储 | flutter_secure_storage | ✅ |
| E2EE 引擎 | Rust / OpenMLS 0.8 | ✅ |
| 后端 | Go 1.22 + net/http | ✅ |
| 数据库 | PostgreSQL 16 + pgx | ✅ |
| [计划中] | Redis、NATS、LiveKit | 📋 |

## 快速开始

```bash
# Flutter 前端
flutter pub get
flutter analyze
flutter test
flutter run -d chrome

# Go 后端
cd backend
go build ./cmd/api/
go test ./...

# Rust 原生层
cd native/aphrodite_openmls
cargo build
cargo test
```

## 更多信息

- [项目 Wiki](https://github.com/LitChi-bit/Aphrodite/wiki) — 架构设计、安全模型、API 文档、开发路线
- [开发指南](https://github.com/LitChi-bit/Aphrodite/wiki/开发指南)

## 开源协议

MIT License. 详见 [LICENSE](LICENSE)。

---

# English <a id="english"></a>

Mobile-first end-to-end encrypted messenger built with Flutter + Go + Rust/OpenMLS.

## Status

| Component | Status |
|-----------|--------|
| Flutter frontend | Auth flow, chat UI (Telegram-style), Drift local DB, Riverpod — UI complete |
| Go backend | REST API (Ed25519 JWT auth, devices, MLS KeyPackage/group state), PostgreSQL — tested |
| Rust native | MLS 1.0 engine (RFC 9420) — device identity, encrypt/decrypt, group management — FFI-integrated |

## Features

| Feature | Status |
|---------|--------|
| Text messages (MLS E2EE) | Engine complete, Flutter integration in progress |
| Voice messages | Planned |
| Audio/video calls | Planned |
| End-to-end encryption | MLS core complete |

## Platform Support

| Platform | Status |
|----------|--------|
| Android | In development |
| iOS | In development |
| Windows / Linux | Deferred |
| Web | Debug only |

## Security

Client-side encryption. Server stores only ciphertext.

- **Messages**: MLS 1.0 (RFC 9420) — DHKEM X25519 + AES-128-GCM + Ed25519
- **Files**: AES-256-GCM + HKDF (planned)
- **Calls**: LiveKit E2EE Frame Cryptor (planned)
- **Keys**: OS Keychain / Keystore

## Tech Stack

Flutter 3.44 · Riverpod · Dio · WebSocket · Drift · flutter_secure_storage · Rust/OpenMLS 0.8 · Go 1.22 · PostgreSQL 16 · pgx

## Quick Start

```bash
# Flutter
flutter pub get && flutter analyze && flutter test

# Go backend
cd backend && go build ./cmd/api/ && go test ./...

# Rust native
cd native/aphrodite_openmls && cargo build && cargo test
```

## More Info

- [Project Wiki](https://github.com/LitChi-bit/Aphrodite/wiki) — Architecture, Security Model, API Docs, Roadmap
- [Getting Started](https://github.com/LitChi-bit/Aphrodite/wiki/Getting-Started)

## License

MIT. See [LICENSE](LICENSE).
