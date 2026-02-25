# Tools

## gog (Google Workspace CLI)

PATH 上の `gog` コマンドで Google Calendar, Gmail, Drive, Contacts, Sheets にアクセスできる。内部的には SSH 経由で隔離された gogcli VM (192.168.83.3) に転送される。出力は `GOG_JSON=1` で JSON 形式。

許可されたサブコマンド: `calendar`, `gmail`, `drive`, `contacts`, `sheets`, `tasks`。それ以外は gogcli VM のラッパーが拒否する。

OAuth スコープは `--readonly` で認証済み。読み取り操作のみ動作する。

詳細なコマンド構文はスキル `gog/SKILL.md` を参照。

## 拒否されたツール

`gateway`, `cron`, `elevated` は設定で明示的に拒否されている。
