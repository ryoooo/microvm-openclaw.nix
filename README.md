# microvm-openclaw.nix

NixOS + [microvm.nix](https://github.com/microvm-nix/microvm.nix) で AI エージェント ([OpenClaw](https://openclaw.dev)) をカーネルレベル隔離する宣言的構成。

## アーキテクチャ

```
┌─ NixOS ホスト ──────────────────────────────────────┐
│  Unbound (DNS ログ)  nftables (egress ログ)  auditd │
│                                                      │
│  ┌─ OpenClaw VM (4GB) ───────────┐                   │
│  │  Gateway + Discord             │                   │
│  │  openclaw-defender (3層防御)   │                   │
│  │    Layer 1: regex              │   ┌─ gogcli VM ─┐│
│  │    Layer 2: Prompt Guard 2     │──→│  Google API  ││
│  │            + DeBERTa v3        │SSH│  OAuth 隔離  ││
│  │    Layer 3: Cerebras LLM      │   └──────────────┘│
│  └────────────────────────────────┘                   │
│        virtiofs /run/secrets (buduroiu パターン)      │
└──────────────────────────────────────────────────────┘
```

## ファイル構成

| ファイル | 役割 |
|---|---|
| `flake.nix` | Flake inputs (nixpkgs, home-manager, microvm, nix-openclaw, nix-openclaw-defender 等) |
| `configuration.nix` | ホスト設定: microVM ネットワーク (bridge + NAT), nftables, Unbound, auditd, secrets サービス |
| `vms/openclaw.nix` | OpenClaw VM: Gateway, defender プラグイン, ML サーバー, Docker, HM 設定 |
| `vms/gogcli.nix` | gogcli VM: Google Workspace CLI 隔離, SSH command= 制限, 監査ログ |
| `docs/SOUL.md` | エージェントのキャラクター定義 |
| `docs/AGENTS.md` | ツール実行ポリシー (読み取り自動/書き込み要承認) |
| `docs/TOOLS.md` | 利用可能ツール一覧 |

## セキュリティ多層防御

- **KVM 隔離**: microvm.nix (Cloud Hypervisor) でカーネル分離。Docker コンテナのカーネル共有リスクを排除
- **ネットワーク監視**: Unbound DNS ログ + nftables egress ログで全通信を記録
- **VM 間通信制限**: OpenClaw → gogcli は SSH のみ許可、逆方向 drop
- **シークレット管理**: virtiofs で `/run/secrets/` にマウント、gateway-token は起動ごとに再生成
- **プロンプトインジェクション防御**: [openclaw-defender](https://github.com/nyosegawa/openclaw-defender) 3 層 (regex → ML 分類器 → LLM 判定)
- **OAuth 隔離**: Google OAuth トークンは gogcli VM 内のみ保持、SSH `command=` でサブコマンド制限
- **監査**: auditd で secrets ディレクトリへのアクセスを記録

## 依存 flake

- [microvm.nix](https://github.com/microvm-nix/microvm.nix) — Cloud Hypervisor ベースの NixOS microVM
- [nix-openclaw](https://github.com/openclaw/nix-openclaw) — OpenClaw Home Manager モジュール + overlay
- [nix-openclaw-defender](https://github.com/ryoooo/nix-openclaw-defender) — 3 層防御プラグインの Nix パッケージ + ML サーバー NixOS モジュール
- [nix-steipete-tools/gogcli](https://github.com/openclaw/nix-steipete-tools) — Google Workspace CLI スキル

## 注意

このリポジトリは技術記事用の公開コードベースです。デスクトップ環境 (Hyprland, WezTerm 等) の設定は省略しています。`hardware-configuration.nix` は各自の環境で `nixos-generate-config` により生成してください。
