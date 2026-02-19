---
name: permission-review
description: Analyzes ~/.claude/logs/permissions/ JSONL logs to identify frequently used tool patterns and propose permission rule cleanup. Use when user says "permission review", "パーミッション整理", "パーミッションレビュー", "権限整理", "許可設定の見直し", "review permissions", or "/permission-review". Also use PROACTIVELY when the Stop hook outputs a permission review reminder (e.g. "📋 パーミッションログが〇件溜まっています").
author: daichi
category: productivity
---

# パーミッションレビュースキル

`~/.claude/logs/permissions/` に蓄積されたJSONLログを分析し、頻出パターンを特定してパーミッション設定を整理・最適化します。

## 使用方法

```
/permission-review
```

手動起動のみ対応。引数は不要。

## 処理フロー

### Step 1: ログ読み込みと集計

`~/.claude/logs/permissions/` ディレクトリ内の全JSONLファイルを読み込む。

各行はJSON形式で、以下の構造を持つ:

```json
{"ts":"2026-02-18T20:59:07Z","tool":"Bash","summary":{"command":"git add foo.md"}}
{"ts":"2026-02-18T20:59:07Z","tool":"Read","summary":{"file_path":"~/.claude/settings.json"}}
{"ts":"2026-02-18T20:59:07Z","tool":"WebFetch","summary":{"url":"https://example.com/page"}}
```

全ファイルの全行を読み込み、`tool` フィールドを基にツール呼び出しを集計する。

**実装方針**:
- Globツールで `~/.claude/logs/permissions/*.jsonl` を列挙
- 各ファイルをReadツールで読み込む
- 各行をJSONとしてパースしてツール呼び出しを収集

### Step 2: パターン正規化

収集したツール呼び出しを、settings.jsonで使われる許可パターン形式に変換する。

#### Bash コマンドの正規化

`summary.command` から先頭の実行ファイル名（サブコマンド含む）を抽出し `Bash(コマンド:*)` 形式に変換する。

**変換ルール**:
- コマンド全体から最初のスペースで区切られたトークンを取り出す
- gitなど典型的なサブコマンドを持つコマンドはサブコマンドまで含める

**変換例**:

| 実際のコマンド | 正規化パターン |
|--------------|--------------|
| `git add foo.md` | `Bash(git add:*)` |
| `git commit -m "..."` | `Bash(git commit:*)` |
| `git push` | `Bash(git push:*)` |
| `ls /path/to/dir` | `Bash(ls:*)` |
| `grep -r pattern .` | `Bash(grep:*)` |
| `cat /etc/hosts` | `Bash(cat:*)` |
| `python3 script.py` | `Bash(python3:*)` |
| `npm install express` | `Bash(npm install:*)` |
| `/usr/local/bin/tool arg` | `Bash(/usr/local/bin/tool:*)` |

**サブコマンドまで含めるコマンド一覧**:

以下のコマンドはサブコマンドまで含めてパターン化する:

- **git**: `git add`, `git commit`, `git push`, `git pull`, `git checkout`, `git merge`, `git diff`, `git fetch`, `git mv`, `git remote`, `git log`, `git status`, `git stash`, `git rebase`, `git tag`, `git branch` など
- **npm**: `npm install`, `npm run`, `npm test`, `npm build`, `npm publish` など
- **docker**: `docker build`, `docker run`, `docker push`, `docker pull`, `docker compose` など
- **cargo**: `cargo build`, `cargo run`, `cargo test`, `cargo add` など
- **kubectl**: `kubectl apply`, `kubectl get`, `kubectl delete`, `kubectl describe` など
- **gh**: `gh pr`, `gh issue`, `gh repo`, `gh release` など

その他のコマンドは先頭トークンのみでパターン化する（例: `ls`, `grep`, `cat`, `python3` など）。

#### Read / Write / Edit / Glob / Grep

ツール名をそのまま使用する。`summary` の内容は無視する。

| ツール | 正規化パターン |
|--------|--------------|
| Read | `Read` |
| Write | `Write` |
| Edit | `Edit` |
| Glob | `Glob` |
| Grep | `Grep` |

#### WebFetch

`summary.url` からドメインを抽出し `WebFetch(domain:ドメイン名)` 形式に変換する。

**変換例**:

| URL | 正規化パターン |
|-----|--------------|
| `https://example.com/path/to/page` | `WebFetch(domain:example.com)` |
| `https://docs.anthropic.com/api` | `WebFetch(domain:docs.anthropic.com)` |
| `https://raw.githubusercontent.com/...` | `WebFetch(domain:raw.githubusercontent.com)` |

#### WebSearch

`WebSearch` そのままで使用する。

#### Skill

`summary.skill` フィールドが存在する場合は `Skill(スキル名)` 形式に変換する。存在しない場合は `Skill` そのまま。

### Step 3: 既存グローバル設定との比較

`~/.claude/settings.json` を読み込み、`permissions.allow` 配列に含まれているパターンを確認する。

**既存パターンに完全一致するものはスキップする**。重複提案を避けるため。

比較は文字列の完全一致で行う。

### Step 4: 頻度による分類

正規化後のパターンごとに登場回数を集計し、以下の2グループに分類する:

- **グループA（頻出: 3回以上）**: グローバル永続許可の推奨候補
- **グループB（低頻度: 2回以下）**: 参考情報として表示

グループA・Bともに、既存グローバル設定に存在するパターンは除外する。

登場回数の多い順にソートして表示する。

### Step 5: settings.local.json 分析

現在のプロジェクトの `.claude/settings.local.json` を読み込み（存在する場合）、`permissions.allow` 配列の各エントリを以下の基準で分類する:

#### 削除候補（不要な具体的ルール）

以下のいずれかに該当するルールを「削除候補」とする:

1. **フルパスを含む具体的なBashコマンド**:
   - `Bash(/Users/<username>/project/.../ファイル名.md )`
   - 特定のファイルパスや長いコマンド文字列を含むもの

2. **シェル制御構文の断片**:
   - `Bash(then)`, `Bash(else)`, `Bash(fi)`, `Bash(done)`, `Bash(do)` など
   - `Bash(do if [ -f "$file" ])` のような断片的な制御構文
   - これらは実際の許可ではなく、誤ってログに記録されたシェルスクリプトの断片

3. **冗長な重複パターン**:
   - グローバルsettings.jsonに既に同じルールが存在するもの

#### グローバル昇格候補

以下の条件を満たすルールを「グローバル昇格候補」とする:

1. 汎用パターン形式である（`Bash(コマンド名:*)` 形式）
2. かつグローバルsettings.jsonに存在しない
3. かつ複数プロジェクトで利用する可能性が高い（汎用的なコマンド）

**昇格候補の例**:
- `Bash(git add:*)` - 汎用gitコマンド
- `Bash(ls:*)` - 汎用コマンド
- `Write`, `Edit` - 汎用ツール
- `WebSearch` - 汎用検索

**昇格しない例**（プロジェクト固有のため）:
- `Skill(project-specific-skill)` - プロジェクト専用スキル
- `WebFetch(domain:specific-site.com)` - 特定サイト（プロジェクト次第）

### Step 6: ユーザーへの提案表示

分析結果をまとめて表示し、ユーザーに確認を求める。以下の形式で表示する:

---

**パーミッションレビュー結果**

**分析済みログファイル**: N個 / 総ツール呼び出し数: M回

---

**[1] グローバルに追加を推奨するルール（3回以上使用）**

以下のルールを `~/.claude/settings.json` の `permissions.allow` に追加することを推奨します。

```
[ ] Bash(git add:*)           (12回)
[ ] Bash(git commit:*)        (8回)
[ ] Read                      (47回)
[ ] Bash(ls:*)                (6回)
...
```

**[2] 参考情報（1〜2回のみ使用）**

```
Bash(brew install:*)          (1回)
WebFetch(domain:example.com)  (2回)
...
```

---

**[3] settings.local.json の削除候補**

以下のルールは不要・冗長なため、`settings.local.json` から削除することを推奨します。

```
[ ] Bash(then)                               ← シェル制御構文の断片
[ ] Bash(else)                               ← シェル制御構文の断片
[ ] Bash(fi)                                 ← シェル制御構文の断片
[ ] Bash(do if [ -f "$file" ])               ← 断片的な制御構文
[ ] Bash(/Users/<username>/.../file.md)      ← フルパスのファイル指定
...
```

**[4] settings.local.json のグローバル昇格候補**

以下のルールはグローバル設定に移動することで、全プロジェクトで再利用できます。

```
[ ] Bash(git push:*)          ← 汎用gitコマンド
[ ] Write                     ← 汎用ツール
...
```

---

どの変更を適用しますか？

1. グローバル追加ルール（[1]）を全て適用
2. グローバル追加ルール（[1]）を選択して適用
3. settings.local.json の削除候補（[3]）を全て適用
4. settings.local.json の削除候補（[3]）を選択して適用
5. グローバル昇格候補（[4]）を適用
6. 全て適用
7. キャンセル（変更しない）

---

AskUserQuestionツールを使って上記を表示し、選択を求める。

### Step 7: 実行

ユーザーの選択に基づいて変更を適用する。

#### グローバルへの追加（settings.json）

1. `~/.claude/settings.json` を読み込む
2. 現在の `permissions.allow` 配列を取得
3. 選択されたルールを配列に追加（重複チェック必須）
4. Editツールで該当箇所を更新する

**重要**: JSONの整合性を保つこと。配列の末尾にカンマなどの構文エラーが生じないよう注意。

#### settings.local.json からの削除

1. プロジェクトの `.claude/settings.local.json` を読み込む
2. 選択されたルールを `permissions.allow` 配列から除去
3. Editツールで該当箇所を更新する

**重要**: 削除後のJSONが有効な形式であることを確認する（末尾カンマの除去など）。

#### 実行後の確認

変更適用後、以下を確認して報告する:

- `~/.claude/settings.json` の更新後の `permissions.allow` 件数
- `.claude/settings.local.json` の更新後の `permissions.allow` 件数
- 追加されたルール一覧
- 削除されたルール一覧

## エラーハンドリング

| エラーケース | 対応 |
|------------|------|
| ログディレクトリが存在しない | 「ログが見つかりません。`~/.claude/logs/permissions/` にJSONLファイルが必要です」と表示して終了 |
| JSONLの行が不正 | その行をスキップしてカウントし、最後に「N行スキップ（パースエラー）」と報告 |
| settings.jsonが読み込めない | エラーを報告し、グローバル比較なしで分析のみ実施 |
| settings.local.jsonが存在しない | Step 5をスキップし、その旨を表示 |
| JSON編集後に構文エラー | 変更を適用せず、手動編集が必要である旨を報告 |

## 注意事項

- **バックアップ**: settings.jsonとsettings.local.jsonを変更する前に、現在の内容を表示してユーザーに確認を取ること
- **JSON整合性**: ファイル編集後は必ずReadで読み直して、JSONとして有効であることを確認する
- **settings.local.jsonはgitignore対象**: プロジェクトローカルの設定であり、git管理されていない可能性がある。削除は慎重に行う
- **グローバル設定の影響範囲**: settings.jsonへの変更は全プロジェクトに影響する。不要に広範な許可（例: `Bash(*:*)` のようなワイルドカード全許可）は追加しない
- **冪等性**: 同じルールが既に存在する場合は重複追加しない

## 実行チェックリスト

- [ ] ログファイルを全て読み込めた
- [ ] 正規化パターンの集計が完了した
- [ ] 既存グローバル設定との重複を除外した
- [ ] 頻度によるグループA/B分類が完了した
- [ ] settings.local.jsonの分析が完了した
- [ ] ユーザーへの提案表示を行い承認を得た
- [ ] 承認されたルールをsettings.jsonに追加した
- [ ] 承認された削除対象をsettings.local.jsonから削除した
- [ ] 変更後のファイルの整合性を確認した
- [ ] 変更結果をユーザーに報告した

## テストケース

### Test 1: 正常系 - ログがある場合
- 前提: `~/.claude/logs/permissions/` に1件以上のJSONLファイルが存在する
- 期待: ログを集計し、パターン正規化後の提案リストを表示する
- 確認: グループA（3回以上）とグループBが正しく分類されている

### Test 2: ログなし
- 前提: `~/.claude/logs/permissions/` が存在しない or 空
- 期待: 「ログが見つかりません」メッセージを表示してスキル終了
- 確認: エラーで落ちずに適切なメッセージが返る

### Test 3: 重複チェック
- 前提: `~/.claude/settings.json` の `permissions.allow` に `Bash(cat:*)` が既に存在する
- 期待: `Bash(cat:*)` はグローバル追加候補に含まれない
- 確認: 既存ルールは提案から除外されている
