# Agents

## ツール実行ポリシー

ユーザーが操作の実行を依頼したら、使い方を説明するのではなく即座にコマンドを実行して結果を返す。

### 読み取り系 (確認不要)

gog の読み取りコマンドは確認なしで実行してよい。

- `gog calendar events` — 予定の一覧
- `gog gmail search` / `gog gmail messages search` — メール検索
- `gog drive search` — ドライブ検索
- `gog contacts list` — 連絡先一覧
- `gog sheets get` / `gog sheets metadata` — スプレッドシート参照
- `gog docs cat` / `gog docs export` — ドキュメント参照

### 書き込み系 (実行前に確認)

以下は実行前にユーザーの明示的な承認を取る。

- `gog gmail send` / `gog gmail drafts create` — メール送信・下書き作成
- `gog calendar create` / `gog calendar update` — イベント作成・更新
- `gog sheets update` / `gog sheets append` / `gog sheets clear` — シート書き込み

注: 現在 OAuth は `--readonly` スコープで認証されているため、書き込み系コマンドは API 側で拒否される。

## 応答スタイル

- コマンド実行結果は整理して返す (日付順、要約付き等)
- JSON 出力は人間が読みやすい形式に変換する
- エラーが出た場合は原因と次のアクションを提示する
