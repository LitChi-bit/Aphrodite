# Aphrodite

> [English](#english) | 中文

一个移动端优先的端到端加密即时通讯应用，支持文字消息、语音消息及实时语音/视频通话。基于 Flutter 构建。

> 当前状态：早期开发阶段（Sprint 0）— 工程基础已搭建，核心加密能力开发中。

---

## 功能

- 文字消息（MLS 端到端加密）
- 语音消息（录制、加密上传、波形播放）
- 实时语音通话
- 实时视频通话
- 端到端加密（消息、文件、通话媒体）

## 平台支持

| 平台 | 状态 |
|------|------|
| Android | 开发中 |
| iOS | 开发中 |
| Windows | 暂缓 |
| Linux | 暂缓 |
| Web | 仅调试用 |

## 安全模型

Aphrodite 采用客户端加密，服务器仅保存密文和最少路由元数据：

- **消息加密**：MLS 1.0 (RFC 9420)
- **文件加密**：AES-256-GCM + HKDF，每文件独立密钥
- **通话媒体**：LiveKit E2EE Frame Cryptor（帧级加密）
- **密钥存储**：OS Keychain / Keystore

> 重要：传输加密（TLS/DTLS）不等于端到端加密。

## 快速开始

```bash
flutter pub get
flutter run -d chrome    # Chrome 调试
flutter analyze          # 代码检查
```

## 技术栈

| 层 | 选型 |
|---|---|
| UI | Flutter 3.x |
| 状态管理 | Riverpod |
| HTTP | Dio |
| 实时通信 | WebSocket |
| 本地数据库 | Drift / SQLite |
| E2EE | OpenMLS (RFC 9420) |
| 通话媒体 | LiveKit + WebRTC |
| 后端 | Go + PostgreSQL + Redis + NATS |

## 开源协议

MIT License. 详见 [LICENSE](LICENSE)。

---

# English <a id="english"></a>

A mobile-first end-to-end encrypted messenger built with Flutter, supporting text messaging, voice messages, and real-time audio/video communication.

> Status: Early development (Sprint 0).

## Features

- Text messages (MLS E2EE)
- Voice messages (record, encrypt, waveform playback)
- Real-time audio/video calls
- End-to-end encryption (messages, files, call media)

## Platform Support

| Platform | Status |
|------|------|
| Android | In development |
| iOS | In development |
| Windows/Linux | Deferred |
| Web | Debug only |

## Security

Client-side encryption. Server stores only ciphertext.

- **Messages**: MLS 1.0 (RFC 9420)
- **Files**: AES-256-GCM + HKDF
- **Calls**: LiveKit E2EE Frame Cryptor
- **Keys**: OS Keychain / Keystore

## Quick Start

```bash
flutter pub get
flutter run -d chrome
flutter analyze
```

## Tech Stack

Flutter · Riverpod · Dio · WebSocket · Drift · OpenMLS · LiveKit · Go + PostgreSQL backend

## License

MIT. See [LICENSE](LICENSE).
