# Aphrodite

A mobile-first end-to-end encrypted messenger built with Flutter, supporting text messaging, voice messages, and real-time audio/video communication.

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

- **消息加密**：MLS 1.0 (RFC 9420)，密码套件 `MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519`
- **文件加密**：AES-256-GCM + HKDF，每文件独立密钥
- **通话媒体**：LiveKit E2EE Frame Cryptor（帧级加密）
- **密钥存储**：OS Keychain / Keystore / Credential Manager

> 重要：传输加密（TLS/DTLS）不等于端到端加密。未完成客户端帧级加密验证的平台，不能宣称通话"端到端加密"。

## 快速开始

```bash
# 安装依赖
flutter pub get

# Chrome 调试运行
flutter run -d chrome

# 代码检查
flutter analyze
```

## 项目结构

```
lib/
├── app/            # 应用配置（路由、主题）
├── auth/           # 认证模块
├── chat/           # 聊天核心
│   ├── models/     # 领域模型
│   ├── data/       # 数据层
│   ├── application/# 业务逻辑
│   ├── e2ee/       # 端到端加密
│   ├── providers/  # 状态管理
│   └── widgets/    # UI 组件
├── core/           # 基础设施
└── plugins/        # 插件系统
```

## 技术栈

| 层 | 选型 |
|---|---|
| UI | Flutter 3.x |
| 状态管理 | Riverpod |
| HTTP | Dio |
| 实时通信 | WebSocket |
| E2EE | OpenMLS (RFC 9420) |
| 通话媒体 | LiveKit + WebRTC |
| 后端 | Go + PostgreSQL + Redis + NATS |

## 开源协议

MIT License. 详见 [LICENSE](LICENSE)。
