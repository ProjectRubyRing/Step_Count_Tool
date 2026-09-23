# step_count.sh — Terraform / シェルスクリプト ステップ数計測ツール

指定したディレクトリ配下の **Terraform (`*.tf`)** と **シェルスクリプト (`*.sh`)** の
ステップ数をファイル単位で計測し、**Excel (Meiryo UI / モノトーン)** と **CSV** に出力する
シェルスクリプトです。

- 対象 OS : **Red Hat Enterprise Linux 9.8**（bash 5.x / gawk / coreutils / findutils）
- 依存    : `bash` `awk` `find` `sort` `sed` `date` `mktemp` + `zip` **または** `python3`
  （Excel 出力に使用。どちらか一方があれば動作します。CSV のみなら不要）
- 外部ライブラリのインストールは不要です（xlsx は OOXML を直接生成します）

---

## 1. 設置

```bash
cp step_count.sh /usr/local/bin/
chmod +x /usr/local/bin/step_count.sh
```

改行コードは LF です。Windows 経由で転送した場合は `dos2unix step_count.sh` を実行してください。

---

## 2. 使い方

```bash
./step_count.sh -d <対象ディレクトリ> [オプション]
```

### 実行例

```bash
# 既定（空白行・コメント行を除外して計測し、Excel と CSV を出力）
./step_count.sh -d /opt/terraform

# Terraform をリソース単位でも計測し、未配置ファイルを他環境から推測
./step_count.sh -d /opt/terraform -r -E -o /var/tmp/report -p tf_steps

# 配置先（terraform/stacks/*/env など）直下の環境ディレクトリを自動検出して推測
./step_count.sh -d /opt/repo -E --envs auto

# 空白行・コメント行も含めた総行数で計測し、CSV のみ出力
./step_count.sh -d /opt/terraform --include-blank --include-comment --no-excel
```

---

## 3. パラメータ一覧

すべての機能はパラメータで ON / OFF できます。

### 必須

| オプション | 説明 |
|---|---|
| `-d`, `--dir DIR` | 計測対象のルートディレクトリ |

### 出力

| オプション | 既定 | 説明 |
|---|---|---|
| `-o`, `--outdir DIR` | `./stepcount_out` | 出力先ディレクトリ（自動作成） |
| `-p`, `--prefix NAME` | `step_count` | 出力ファイル名のプレフィックス |
| `--excel` / `--no-excel` | ON | Excel (.xlsx) 出力 |
| `--csv` / `--no-csv` | ON | CSV 出力 |
| `--bom` / `--no-bom` | 付与 | CSV へ UTF-8 BOM を付与（Excel の文字化け防止） |
| `--timestamp` | OFF | 出力ファイル名へ `_YYYYMMDD_HHMMSS` を付与 |

### 計測対象

| オプション | 既定 | 説明 |
|---|---|---|
| `-e`, `--ext LIST` | `tf,sh` | 対象拡張子（カンマ区切り） |
| `-x`, `--exclude-dir LIST` | `.git,.terraform,.svn,node_modules,vendor,.idea,.vscode` | 除外ディレクトリ名 |

### 計測ルール

| オプション | 既定 | 説明 |
|---|---|---|
| `-b`, `--exclude-blank` / `--include-blank` | 除外 | **空白行を除外する機能** |
| `-c`, `--exclude-comment` / `--include-comment` | 除外 | **コメント行を除外する機能** |
| `--shebang-as-comment` | OFF | 1 行目のシェバン（`#!` 行）をコメント行として扱う |
| `--no-attach-comment` | OFF | ブロック直前の連続コメントをリソースに含めない |

### Terraform リソース単位計測

| オプション | 既定 | 説明 |
|---|---|---|
| `-r`, `--resource` / `--no-resource` | OFF | **リソース（ブロック）単位で計測する機能** |

### 環境ディレクトリ

| オプション | 既定 | 説明 |
|---|---|---|
| `--envs LIST` | `j1,j2,j3,st,pr` | 環境ディレクトリ名。`auto` で配置先直下のディレクトリを自動検出 |
| `--env-base LIST` | `terraform/stacks/*/env,`<br>`scripts/cicd/*/build_stage,`<br>`scripts/cicd/*/merge_stage` | 環境ディレクトリの配置先（`-d` からの相対パス、カンマ区切り、`*` などのワイルドカード可） |

### 推測計測

| オプション | 既定 | 説明 |
|---|---|---|
| `-E`, `--estimate` / `--no-estimate` | OFF | **未配置ファイルを基準環境（j1）から推測する機能**（配置先ごとに比較） |
| `--estimate-ref ENV` | `j1` | 推測の基準環境 |
| `--estimate-exclude LIST` | `containers` | 推測対象から外すディレクトリ名（カンマ区切り） |

> `--estimate-dir` は `--env-base` の旧名です（同じ意味で引き続き使用できます）。
> `--estimate-method` は廃止しました（指定しても警告を出して無視します）。

### 集計

| オプション | 既定 | 説明 |
|---|---|---|
| `--summary-ext` / `--no-summary-ext` | ON | **ファイル拡張子ごとの集計** |
| `--summary-all` / `--no-summary-all` | ON | **全ファイルの集計** |

### その他

| オプション | 説明 |
|---|---|
| `-v`, `--verbose` / `-q`, `--quiet` | ログレベル |
| `-h`, `--help` / `-V`, `--version` | ヘルプ / バージョン |

---

## 4. 計測ルールの詳細

各ファイルの行は **空白行 / コメント行 / コード行** のいずれか 1 つに分類され、
`有効ステップ数` は次の式で算出されます。

```
有効ステップ数 = 総行数 −（空白行を除外する場合は空白行数）−（コメント行を除外する場合はコメント行数）
```

### 空白行

タブ・半角スペースのみの行を空白行とします。

### コメント行

| 対象 | コメントと判定する行 |
|---|---|
| `*.tf` (HCL) | 行頭（インデント除く）が `#` / `//` で始まる行、`/* … */` のブロックコメント行 |
| `*.sh` | 行頭（インデント除く）が `#` で始まる行 |
| その他の拡張子 | 行頭が `#` で始まる行 |

- **行末コメント**（例: `version = "1.0"  # 備考`）は**コード行**として計上します。
- `/* … */` が終わった後に有効なコードが続く行は**コード行**として計上します。
- **1 行目のシェバン**（`#!/bin/bash`）は既定で**コード行**です。
  `--shebang-as-comment` を付けるとコメント行として計上します。

### ヒアドキュメント

`<<EOF` `<<-EOF` `<<"EOF"` `<<'EOF'`（HCL は `<<EOT` / `<<-EOT`）を検出し、
**終端行までの内容はコメントとみなしません**（文字列データとしてコード行に計上）。
1 行に複数のヒアドキュメントが現れる場合にも対応しています。
`<<<`（ヒアストリング）および `$(( a << b ))`（シフト演算）は除外しています。

### 文字コード / 改行コード

UTF-8 を前提としています。CRLF 改行は自動的に除去して判定します。
ファイル末尾に改行が無い場合も 1 行として計上します。

---

## 5. Terraform リソース単位計測（`-r`）

`{ }` の対応をトラッキングして、トップレベルブロックごとに行数を集計します。

- 対象ブロック: `resource` / `data` / `module` / `variable` / `output` / `locals` /
  `provider` / `terraform` など、ルート階層で `{` を開くすべてのブロック
- ラベル（`resource "aws_vpc" "main"` の `aws_vpc` と `main`）を別列に出力します
- 文字列リテラル・コメント・ヒアドキュメント中の `{` `}` は括弧の対応から除外します
- **ブロック直前の連続コメント行は、そのブロックの行数に含めます**
  （`--no-attach-comment` で無効化）
- ブロックに属さない行（ファイル冒頭のコメントや空行など）は
  `(ブロック外)` という擬似ブロックとして出力します

そのため **「ブロックの行数の合計 ＝ ファイルの総行数」** が常に一致し、検算できます。

---

## 6. 環境ディレクトリと推測計測（`-E`）

### 環境ディレクトリの配置先

環境ディレクトリ（`j1` `j2` `j3` `st` `pr`）は、次の**配置先**の直下にあるものとして判定します
（`--env-base` で変更可、`*` は任意の 1 階層）。

| 配置先（既定） | 該当するディレクトリの例 |
|---|---|
| `terraform/stacks/*/env` | `terraform/stacks/01-workload/env/j1`<br>`terraform/stacks/02-apprelease/env/j1`<br>`terraform/stacks/03-dbrelease/env/j1` |
| `scripts/cicd/*/build_stage` | `scripts/cicd/app_release/build_stage/j1` |
| `scripts/cicd/*/merge_stage` | `scripts/cicd/app_release/merge_stage/j1` |

### 推測計測

推測は**配置先ごと**に行います。各配置先の **`j1` を基準環境**とし、
同じ配置先の他の環境に不足しているファイルを、その配置先の `j1` の実測値で補います。

```
<ルート>/
  ├ terraform/stacks/
  │   ├ 01-workload/env/            ← 配置先
  │   │   ├ j1/…   6 ファイル       ← 基準環境
  │   │   ├ j2/…   6 ファイル       → j1 以上あるので推測しない
  │   │   ├ j3/…   4 ファイル       → j1 より少ないので、j1 にだけあるファイル 2 件を推測
  │   │   └ st/    (空)             → j1 のファイル 6 件をすべて推測
  │   │                               pr はディレクトリが無いので推測しない
  │   ├ 02-apprelease/env/          ← 配置先（01-workload とは独立して j1 と比較）
  │   │   ├ j1/…   2 ファイル
  │   │   ├ j2/…   2 ファイル       → 推測しない
  │   │   └ st/…   1 ファイル       → 1 件を推測
  │   └ 03-dbrelease/env/           ← 配置先
  │       ├ j1/…   2 ファイル
  │       └ j2/    (空)             → 2 件を推測
  ├ scripts/cicd/app_release/
  │   ├ build_stage/                ← 配置先
  │   │   ├ j1/…   2 ファイル
  │   │   └ j2/…   1 ファイル       → 1 件を推測
  │   └ merge_stage/                ← 配置先
  │       ├ j1/…   1 ファイル
  │       └ j2/…   1 ファイル       → 推測しない
  └ containers/
      ├ j1/…                        ← 配置先の外なので推測の対象外（環境別集計には含む）
      └ j2/…
```

推測の条件は次のとおりです（配置先ごとに判定）。

| 環境ディレクトリの状態 | 推測 |
|---|---|
| 配置先に `j1` が存在しない | **行わない** |
| ディレクトリが存在しない | **行わない** |
| 存在するが空（対象ファイル 0 件） | `j1` のファイルをすべて推測 |
| 存在し、ファイル数が `j1` より少ない | `j1` にあって当該環境に無いファイル（同じ相対パス）を推測 |
| 存在し、ファイル数が `j1` 以上 | 行わない |

- ファイル数は対象拡張子（`--ext`）のファイルで数えます。`.gitkeep` などは数えません
- 推測したファイルの空白行数・コメント行数・コード行数は、同じ配置先の `j1` の同じ相対パスのファイルの実測値です
- **`containers` 配下は推測の対象外**です。ルート直下の `containers/` はもちろん、
  `terraform/stacks/01-workload/env/j1/containers/` のように環境ディレクトリ内にあっても、
  ファイル数にも推測元にも含めません（`--estimate-exclude` で変更可）
- 推測した行は区分 `推測` として、**拡張子別集計・環境別集計・全体集計にも合算**されます
- 判定の内容は「推測根拠」列（例: `j3 のファイル数 4 < j1 のファイル数 6 (参照: terraform/stacks/01-workload/env/j1/compute/ec2.tf)`）と、
  サマリシートの「推測の判定」（配置先ごとに 1 行）に出力されます
- `-d` に `terraform` や `terraform/stacks`、`terraform/stacks/01-workload` などの途中の階層を指定した場合も、
  `--env-base` を省略していれば既定の配置先をそこからの相対パスに読み替えます
  （例: `-d terraform/stacks` → `*/env`）

### 環境別集計での環境の判定

1. 配置先の直下にある環境ディレクトリ配下のファイルは、その環境として集計します
   （例: `terraform/stacks/02-apprelease/env/j2/main.tf` は `j2`）
2. 配置先の外にあるファイルは、パスの途中に環境ディレクトリ名（`--envs`）が現れれば、その環境として集計します
   （例: `containers/j1/app/run.sh` は `j1`）
3. どちらにも当てはまらないファイルは `(環境外)` として集計します

環境別集計は、配置先をまたいで環境ごとに合算した値です（配置先ごとの内訳は「ファイル別」シートのパスで絞り込めます）。

> リソース単位の明細は実測ファイルのみが対象です（推測はファイル単位で行います）。

---

## 7. 出力

### Excel（`<prefix>.xlsx`）

| シート | 内容 |
|---|---|
| **サマリ** | KPI カード（有効ステップ数 / 対象ファイル数 / 総行数 / 推測ファイル数 / ブロック数）、計測条件、拡張子別集計、環境別集計、環境 × 拡張子マトリクス |
| **ファイル別** | 全ファイルの総行数・空白行数・コメント行数・コード行数・有効ステップ数 |
| **Terraformリソース別** | `-r` 指定時。ブロック種別・ラベル・開始行・終了行・各行数 |
| **推測明細** | `-E` 指定時。推測したファイルと推測方法・根拠 |

デザイン:

- フォントは全セル **Meiryo UI**
- **モノトーン（無彩色）** — 見出し `#3F3F3F` / 縞模様 `#F5F5F5` / 罫線 `#DCDCDC` / 合計行 `#E9E9E9`
- グリッド線は非表示、細罫線と余白で区切る構成
- 見出し行の**ウィンドウ枠固定**・**オートフィルタ**・**印刷タイトル行**を設定済み
- 数値は 3 桁区切り、構成比は小数 1 桁のパーセント表示
- 有効ステップ数の列にグレーの**データバー**（0 起点）
- 推測行は**斜体グレー**で実測と区別
- 印刷設定: A4 横 / 横方向 1 ページに収める

### CSV（UTF-8、既定で BOM 付き、改行は CRLF）

| ファイル | 内容 | 出力条件 |
|---|---|---|
| `<prefix>_files.csv` | ファイル別 | 常時 |
| `<prefix>_resources.csv` | Terraform リソース別 | `-r` |
| `<prefix>_estimated.csv` | 推測明細 | `-E` かつ推測対象あり |
| `<prefix>_summary_ext.csv` | 拡張子別集計 | `--summary-ext` |
| `<prefix>_summary_env.csv` | 環境別集計 | 環境ディレクトリ検出時 |
| `<prefix>_summary_matrix.csv` | 環境 × 拡張子 マトリクス | 環境ディレクトリ検出時 |
| `<prefix>_summary_total.csv` | 全体集計 | `--summary-all` |

### 標準出力

計測条件・全体集計・拡張子別・環境別のサマリと出力ファイル一覧を表示します（`-q` で抑止）。

---

## 8. 動作確認用サンプル

`sample/` に検証用のディレクトリツリーを同梱しています。

| パス | 内容 |
|---|---|
| `terraform/stacks/01-workload/env/j1` | 基準環境（6 ファイル） |
| `terraform/stacks/01-workload/env/j2` | 6 ファイル（推測しない） |
| `terraform/stacks/01-workload/env/j3` | 4 ファイル（2 件を推測） |
| `terraform/stacks/01-workload/env/st` | 空ディレクトリ（6 件を推測） |
| `terraform/stacks/01-workload/env/pr` | 存在しない（推測しない） |
| `terraform/stacks/02-apprelease/env/{j1,j2,st}` | j1・j2 は 2 ファイル、st は 1 ファイル（1 件を推測） |
| `terraform/stacks/03-dbrelease/env/{j1,j2}` | j1 は 2 ファイル、j2 は空ディレクトリ（2 件を推測） |
| `scripts/cicd/app_release/build_stage/{j1,j2}` | j1 は 2 ファイル、j2 は 1 ファイル（1 件を推測） |
| `scripts/cicd/app_release/merge_stage/{j1,j2}` | 各 1 ファイル（推測しない） |
| `containers/j1` `containers/j2` | 推測の対象外 |
| `common` | 環境外 |

```bash
./step_count.sh -d sample -o out -r -E
```

`out/` に Excel と CSV 一式が生成されます。

---

## 9. 終了ステータス

| 値 | 意味 |
|---|---|
| `0` | 正常終了 |
| `1` | 引数不正、対象ディレクトリ不正、対象ファイル 0 件、出力失敗 など |

---

## 10. 制限事項

- 行の分類は「行頭で判定する」方式です。文字列リテラル内に単独で現れる `#` で始まる行など、
  構文解析器と完全に同じ結果にはならない場合があります。
- Terraform のブロック判定は括弧の対応に基づく簡易解析です。
  文字列・コメント・ヒアドキュメント内の括弧は除外していますが、
  極端に特殊な記述では想定と異なる区切りになる可能性があります。
- シンボリックリンクは追跡しません。
- Excel 生成は `zip` を優先し、無い場合は `python3`（標準ライブラリのみ）を使用します。
  環境変数 `STEPCOUNT_ZIP_MODE=zip|python3|python` で明示指定できます。
