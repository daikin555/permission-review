# permission-review

Claude Code のパーミッション設定を自動分析・整理するスキルです。

ツール呼び出しのログを蓄積し、頻出パターンを特定して `~/.claude/settings.json` への追加提案や `settings.local.json` の不要ルール削除を支援します。

## 概要

### できること

- ツール呼び出しログを日次JSONLファイルに蓄積
- 頻出パターン（3回以上）をグローバル永続許可の推奨候補として提示
- `settings.local.json` 内の不要ルール（シェル制御構文の断片、フルパス指定など）を削除候補として提示
- ローカルルールをグローバルに昇格する提案

### 対応ツール

Bash / Read / Write / Edit / Glob / Grep / WebFetch / WebSearch / Skill

## セットアップ

### 1. スクリプトの配置

```bash
cp scripts/permission-logger.sh ~/.claude/scripts/permission-logger.sh
chmod +x ~/.claude/scripts/permission-logger.sh
```

### 2. スキルの配置

```bash
cp -r skills/permission-review ~/.claude/skills/
```

### 3. フックの登録

`~/.claude/settings.json` の `hooks.PreToolUse` に以下を追加します（`settings.json.example` 参照）:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/scripts/permission-logger.sh"
          }
        ]
      }
    ]
  }
}
```

既存の `settings.json` に `hooks` キーが既にある場合は、`PreToolUse` 配列にマージしてください。

## 使い方

Claude Code で以下のコマンドを実行するだけです:

```
/permission-review
```

分析結果が表示され、対話形式でどの変更を適用するか選択できます。

## ログの保存場所

ツール呼び出しログは以下に保存されます:

```
~/.claude/logs/permissions/YYYY-MM-DD.jsonl
```

## ファイル構成

```
permission-review/
├── README.md
├── settings.json.example        # フック登録サンプル
├── skills/
│   └── permission-review/
│       └── SKILL.md             # スキル定義
└── scripts/
    └── permission-logger.sh     # ログ収集フックスクリプト
```

## ライセンス

MIT
