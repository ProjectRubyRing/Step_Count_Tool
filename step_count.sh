#!/usr/bin/env bash
#===============================================================================
#  step_count.sh
#    Terraform (*.tf) / シェルスクリプト (*.sh) ステップ数計測ツール
#
#    対象環境 : Red Hat Enterprise Linux 9.8
#               bash 5.1 / gawk 5.1 / coreutils / findutils
#               Excel(.xlsx) 生成には zip もしくは python3 のいずれかを使用
#
#    出力     : Excel (.xlsx)  Meiryo UI フォント / モノトーンデザイン
#               CSV  (UTF-8, 既定で BOM 付与)
#===============================================================================
set -u
set -o pipefail
umask 022

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_VERSION="1.0.0"
readonly SCRIPT_NAME SCRIPT_DIR SCRIPT_VERSION

#-------------------------------------------------------------------------------
# 既定値
#-------------------------------------------------------------------------------
OPT_ROOT=""
OPT_OUTDIR="./stepcount_out"
OPT_PREFIX="step_count"
OPT_EXTS="tf,sh"
OPT_EXCLUDE_DIRS=".git,.terraform,.svn,node_modules,vendor,.idea,.vscode"
OPT_EXCLUDE_BLANK=1
OPT_EXCLUDE_COMMENT=1
OPT_SHEBANG_COMMENT=0
OPT_ATTACH_COMMENT=1
OPT_RESOURCE=0
OPT_ESTIMATE=0
OPT_ENVS="j1,j2,j3,st,pr"
OPT_EST_DIR="terraform/stacks"
OPT_EST_DIR_SET=0
OPT_EST_REF="j1"
OPT_EST_EXCLUDE="containers"
OPT_SUMMARY_EXT=1
OPT_SUMMARY_ALL=1
OPT_EXCEL=1
OPT_CSV=1
OPT_BOM=1
OPT_TIMESTAMP=0
OPT_VERBOSE=0
OPT_QUIET=0

RUN_AT="$(date '+%Y-%m-%d %H:%M:%S')"
RUN_STAMP="$(date '+%Y%m%d_%H%M%S')"

#-------------------------------------------------------------------------------
# メッセージ出力
#-------------------------------------------------------------------------------
if [ -t 2 ]; then
  C_RST=$'\033[0m'; C_DIM=$'\033[2m'; C_BLD=$'\033[1m'
  C_RED=$'\033[31m'; C_YLW=$'\033[33m'; C_GRN=$'\033[32m'
else
  C_RST=""; C_DIM=""; C_BLD=""; C_RED=""; C_YLW=""; C_GRN=""
fi

log_info()  { [ "$OPT_QUIET" -eq 1 ] && return 0; printf '%s[INFO ]%s %s\n' "$C_DIM" "$C_RST" "$*" >&2; }
log_step()  { [ "$OPT_QUIET" -eq 1 ] && return 0; printf '%s[STEP ]%s %s\n' "$C_BLD" "$C_RST" "$*" >&2; }
log_ok()    { [ "$OPT_QUIET" -eq 1 ] && return 0; printf '%s[ OK  ]%s %s\n' "$C_GRN" "$C_RST" "$*" >&2; }
log_warn()  { printf '%s[WARN ]%s %s\n' "$C_YLW" "$C_RST" "$*" >&2; }
log_error() { printf '%s[ERROR]%s %s\n' "$C_RED" "$C_RST" "$*" >&2; }
log_debug() { [ "$OPT_VERBOSE" -eq 1 ] || return 0; printf '%s[DEBUG]%s %s\n' "$C_DIM" "$C_RST" "$*" >&2; }
die()       { log_error "$*"; exit 1; }

#-------------------------------------------------------------------------------
# 使い方
#-------------------------------------------------------------------------------
usage() {
  cat <<'__USAGE_EOF__'
--------------------------------------------------------------------------------
 step_count.sh - Terraform / シェルスクリプト ステップ数計測ツール
--------------------------------------------------------------------------------
 使い方:
   step_count.sh -d <対象ディレクトリ> [オプション]

 [必須]
   -d, --dir DIR              計測対象のルートディレクトリ

 [出力]
   -o, --outdir DIR           出力先ディレクトリ             (既定: ./stepcount_out)
   -p, --prefix NAME          出力ファイル名のプレフィックス (既定: step_count)
       --excel | --no-excel   Excel(.xlsx) 出力の ON/OFF     (既定: ON)
       --csv   | --no-csv     CSV 出力の ON/OFF              (既定: ON)
       --bom   | --no-bom     CSV へ UTF-8 BOM を付与        (既定: 付与)
       --timestamp            出力ファイル名に日時を付与

 [計測対象]
   -e, --ext LIST             対象拡張子 (カンマ区切り)      (既定: tf,sh)
   -x, --exclude-dir LIST     除外ディレクトリ名 (カンマ区切り)
                              (既定: .git,.terraform,.svn,node_modules,vendor,.idea,.vscode)

 [計測ルール]
   -b, --exclude-blank        空白行を除外して計測           (既定)
       --include-blank        空白行を含めて計測
   -c, --exclude-comment      コメント行を除外して計測       (既定)
       --include-comment      コメント行を含めて計測
       --shebang-as-comment   1行目のシェバンをコメント行として扱う (既定: コード行)
       --no-attach-comment    ブロック直前の連続コメントをリソースに含めない

 [Terraform リソース単位計測]
   -r, --resource             リソース(ブロック)単位でも計測する
       --no-resource          リソース単位計測を行わない     (既定)

 [推測計測]
   -E, --estimate             基準環境の実測値から未配置ファイルを推測計測する
       --envs LIST            環境ディレクトリ名 (カンマ区切り / auto で自動検出)
                              (既定: j1,j2,j3,st,pr)
       --estimate-dir DIR     推測対象の環境ディレクトリが並ぶディレクトリ
                              (-d からの相対パス, 既定: terraform/stacks)
       --estimate-ref ENV     推測の基準環境                 (既定: j1)
       --estimate-exclude LIST
                              推測対象から外すディレクトリ名 (既定: containers)

 [集計]
       --summary-ext | --no-summary-ext   拡張子ごとの集計   (既定: ON)
       --summary-all | --no-summary-all   全ファイルの集計   (既定: ON)

 [その他]
   -v, --verbose              詳細ログを出力
   -q, --quiet                エラー以外のログを抑止
   -h, --help                 このヘルプを表示
   -V, --version              バージョンを表示

 [使用例]
   ./step_count.sh -d /opt/terraform
   ./step_count.sh -d /opt/terraform -r -E -o /var/tmp/report -p tf_steps
   ./step_count.sh -d /opt/repo -E --envs auto
   ./step_count.sh -d /opt/terraform --include-blank --include-comment --no-excel
--------------------------------------------------------------------------------
__USAGE_EOF__
}

#-------------------------------------------------------------------------------
# 引数解析
#-------------------------------------------------------------------------------
need_value() { [ "$#" -ge 2 ] || die "オプション $1 には値が必要です"; }

parse_args() {
  local _k _v
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --*=*)
        _k="${1%%=*}"; _v="${1#*=}"
        shift
        set -- "$_k" "$_v" "$@"
        continue
        ;;
    esac
    case "$1" in
      -d|--dir)               need_value "$@"; OPT_ROOT="$2";          shift 2 ;;
      -o|--outdir)            need_value "$@"; OPT_OUTDIR="$2";        shift 2 ;;
      -p|--prefix)            need_value "$@"; OPT_PREFIX="$2";        shift 2 ;;
      -e|--ext)               need_value "$@"; OPT_EXTS="$2";          shift 2 ;;
      -x|--exclude-dir)       need_value "$@"; OPT_EXCLUDE_DIRS="$2";  shift 2 ;;
      --envs)                 need_value "$@"; OPT_ENVS="$2";          shift 2 ;;
      --estimate-dir)         need_value "$@"; OPT_EST_DIR="$2"; OPT_EST_DIR_SET=1; shift 2 ;;
      --estimate-ref)         need_value "$@"; OPT_EST_REF="$2";       shift 2 ;;
      --estimate-exclude)     need_value "$@"; OPT_EST_EXCLUDE="$2";   shift 2 ;;
      --estimate-method)      need_value "$@"
                              log_warn "--estimate-method は廃止しました (推測は基準環境の実測値を使用します)"
                              shift 2 ;;
      -b|--exclude-blank)     OPT_EXCLUDE_BLANK=1;    shift ;;
      --include-blank)        OPT_EXCLUDE_BLANK=0;    shift ;;
      -c|--exclude-comment)   OPT_EXCLUDE_COMMENT=1;  shift ;;
      --include-comment)      OPT_EXCLUDE_COMMENT=0;  shift ;;
      --shebang-as-comment)   OPT_SHEBANG_COMMENT=1;  shift ;;
      --no-attach-comment)    OPT_ATTACH_COMMENT=0;   shift ;;
      -r|--resource)          OPT_RESOURCE=1;         shift ;;
      --no-resource)          OPT_RESOURCE=0;         shift ;;
      -E|--estimate)          OPT_ESTIMATE=1;         shift ;;
      --no-estimate)          OPT_ESTIMATE=0;         shift ;;
      --summary-ext)          OPT_SUMMARY_EXT=1;      shift ;;
      --no-summary-ext)       OPT_SUMMARY_EXT=0;      shift ;;
      --summary-all)          OPT_SUMMARY_ALL=1;      shift ;;
      --no-summary-all)       OPT_SUMMARY_ALL=0;      shift ;;
      --excel)                OPT_EXCEL=1;            shift ;;
      --no-excel)             OPT_EXCEL=0;            shift ;;
      --csv)                  OPT_CSV=1;              shift ;;
      --no-csv)               OPT_CSV=0;              shift ;;
      --bom)                  OPT_BOM=1;              shift ;;
      --no-bom)               OPT_BOM=0;              shift ;;
      --timestamp)            OPT_TIMESTAMP=1;        shift ;;
      -v|--verbose)           OPT_VERBOSE=1;          shift ;;
      -q|--quiet)             OPT_QUIET=1;            shift ;;
      -h|--help)              usage; exit 0 ;;
      -V|--version)           printf '%s %s\n' "$SCRIPT_NAME" "$SCRIPT_VERSION"; exit 0 ;;
      --)                     shift; break ;;
      -*)                     die "不明なオプション: $1  (--help で使い方を表示)" ;;
      *)                      if [ -z "$OPT_ROOT" ]; then OPT_ROOT="$1"; shift; else die "余分な引数: $1"; fi ;;
    esac
  done
}

validate_args() {
  if [ -z "$OPT_ROOT" ]; then usage; echo; die "計測対象ディレクトリ (-d) を指定してください"; fi
  [ -d "$OPT_ROOT" ] || die "ディレクトリが存在しません: $OPT_ROOT"
  [ -r "$OPT_ROOT" ] || die "ディレクトリを読み取れません: $OPT_ROOT"
  [ -n "$OPT_EST_REF" ] || die "--estimate-ref に基準環境を指定してください"
  case "$OPT_EST_REF" in */*) die "--estimate-ref には環境ディレクトリ名を指定してください: $OPT_EST_REF" ;; esac
  [ -n "$OPT_EXTS" ]   || die "--ext に対象拡張子を指定してください"
  [ -n "$OPT_PREFIX" ] || die "--prefix に出力名を指定してください"
  if [ "$OPT_EXCEL" -eq 0 ] && [ "$OPT_CSV" -eq 0 ]; then
    die "--no-excel と --no-csv を同時に指定することはできません"
  fi
  ROOT_ABS="$(cd "$OPT_ROOT" && pwd)" || die "ディレクトリへ移動できません: $OPT_ROOT"
  mkdir -p "$OPT_OUTDIR" || die "出力先ディレクトリを作成できません: $OPT_OUTDIR"
  OUT_ABS="$(cd "$OPT_OUTDIR" && pwd)"
}

#-------------------------------------------------------------------------------
# 前提コマンド確認
#-------------------------------------------------------------------------------
ZIP_MODE=""
check_prereq() {
  local c
  for c in awk find sort date mktemp; do
    command -v "$c" >/dev/null 2>&1 || die "必須コマンドが見つかりません: $c"
  done
  if [ "$OPT_EXCEL" -eq 1 ]; then
    if command -v zip >/dev/null 2>&1; then
      ZIP_MODE="zip"
    elif command -v python3 >/dev/null 2>&1; then
      ZIP_MODE="python3"
    elif command -v python >/dev/null 2>&1; then
      ZIP_MODE="python"
    else
      log_warn "zip / python3 のいずれも見つからないため Excel 出力を無効化します"
      OPT_EXCEL=0
    fi
    [ -n "$ZIP_MODE" ] && log_debug "xlsx 圧縮方式: $ZIP_MODE"
  fi
  return 0
}

#-------------------------------------------------------------------------------
# 作業ディレクトリ
#-------------------------------------------------------------------------------
WORK=""
cleanup() { if [ -n "$WORK" ] && [ -d "$WORK" ]; then rm -rf "$WORK"; fi; }
trap cleanup EXIT INT TERM

#===============================================================================
# AWK プログラム生成
#===============================================================================

#-------------------------------------------------------------------------------
# 行種別判定 (空白行 / コメント行 / コード行) と Terraform ブロック単位計測
#-------------------------------------------------------------------------------
write_awk_counter() {
  cat > "$1" <<'__AWK_COUNTER_EOF__'
#-------------------------------------------------------------------------------
# 入力  : 対象ファイル群 (ルートディレクトリからの相対パス)
# 変数  : ENVS            環境ディレクトリ名 (カンマ区切り)
#                         パス中で最初に現れた環境ディレクトリ名をそのファイルの環境とする
#         WANT_RES        1 なら Terraform ブロック単位レコードも出力
#         SHEBANG_COMMENT 1 なら 1行目のシェバンをコメント行として扱う
#         ATTACH_COMMENT  1 ならブロック直前の連続コメントをブロックへ含める
#         FOUT            ファイル単位レコードの出力先
#         ROUT            ブロック単位レコードの出力先
# 出力  : FOUT 環境/相対パス/パス/拡張子/区分/総行/空白/コメント/コード/根拠
#         ROUT 環境/パス/拡張子/種別/ラベル1/ラベル2/開始/終了/総行/空白/コメント/コード
#-------------------------------------------------------------------------------
function trim(s) { gsub(/^[ \t\r]+|[ \t\r]+$/, "", s); return s }

# 文字列リテラル・コメント・ヒアドキュメント開始以降を取り除いた行を返す
function strip_code(s,   t, p, q) {
    t = s
    gsub(RE_STR, "\"\"", t)
    while ((p = index(t, "/*")) > 0) {
        q = index(substr(t, p + 2), "*/")
        if (q > 0) t = substr(t, 1, p - 1) " " substr(t, p + q + 3)
        else { t = substr(t, 1, p - 1); break }
    }
    p = index(t, "<<"); if (p > 0) t = substr(t, 1, p - 1)
    sub(/#.*$/, "", t)
    sub(/\/\/.*$/, "", t)
    return t
}

# ヒアドキュメント開始の検出 (複数個/行にも対応)
function detect_hd(   t, w, ind) {
    if (ftype != "sh" && ftype != "tf") return
    if (ftype == "sh" && line ~ /\$\(\(/) return
    t = line
    gsub(/<<</, "   ", t)
    while (match(t, /<<-?[ \t]*("[^"]*"|'[^']*'|[A-Za-z_][A-Za-z0-9_]*)/)) {
        w = substr(t, RSTART, RLENGTH)
        t = substr(t, RSTART + RLENGTH)
        ind = (w ~ /^<<-/) ? 1 : 0
        sub(/^<<-?[ \t]*/, "", w)
        gsub(/["']/, "", w)
        if (w == "") continue
        hd_n++
        hd_term[hd_n] = w
        hd_indent[hd_n] = ind
    }
}

# ブロック宣言行からラベル (resource "type" "name") を取り出す
function set_labels(s,   t, p, m, n) {
    r_lab1 = ""; r_lab2 = ""
    t = s
    p = index(t, "{"); if (p > 0) t = substr(t, 1, p - 1)
    n = 0
    while (match(t, /"[^"]*"/)) {
        m = substr(t, RSTART + 1, RLENGTH - 2)
        n++
        if (n == 1) r_lab1 = m
        else if (n == 2) r_lab2 = m
        t = substr(t, RSTART + RLENGTH)
    }
}

# パス中で最初に現れる環境ディレクトリ名を環境、それ以降を相対パスとする (ファイル名は除く)
function classify(p,   n, a, i, off) {
    env = "-"; rel = p
    n = split(p, a, "/")
    off = 0
    for (i = 1; i < n; i++) {
        off += length(a[i]) + 1
        if (a[i] in envset) { env = a[i]; rel = substr(p, off + 1); return }
    }
}

function flush_pend() {
    if (pend_c > 0) { o_t += pend_c; o_c += pend_c }
    pend_c = 0; pend_start = 0; pend_end = 0
}

function emit_res(endline) {
    printf "%s\t%s\t%s\t%s\t%s\t%s\t%d\t%d\t%d\t%d\t%d\t%d\n", \
        env, curfile, ext, r_type, r_lab1, r_lab2, r_start, endline, r_t, r_b, r_c, r_x >> ROUT
    inres = 0
    nres++
}

function emit_other() {
    printf "%s\t%s\t%s\t%s\t%s\t%s\t%d\t%d\t%d\t%d\t%d\t%d\n", \
        env, curfile, ext, "(ブロック外)", "", "", 0, 0, o_t, o_b, o_c, o_x >> ROUT
}

function tf_block(cls, scan,   sl, no, nc, w) {
    if (inres) {
        r_t++
        if (cls == "B") r_b++
        else if (cls == "C") r_c++
        else r_x++
        if (scan == 1) {
            sl = strip_code(line)
            no = gsub(/\{/, "{", sl)
            nc = gsub(/\}/, "}", sl)
            depth += no - nc
            if (depth <= 0) { depth = 0; emit_res(FNR) }
        }
        return
    }
    if (cls == "C") {
        if (pend_c > 0 && pend_end == FNR - 1) { pend_c++; pend_end = FNR }
        else { flush_pend(); pend_start = FNR; pend_c = 1; pend_end = FNR }
        return
    }
    if (cls == "B") { flush_pend(); o_t++; o_b++; return }
    no = 0; nc = 0
    if (scan == 1) {
        sl = strip_code(line)
        no = gsub(/\{/, "{", sl)
        nc = gsub(/\}/, "}", sl)
    }
    if (no > 0 && tl ~ /^[A-Za-z_]/) {
        w = tl
        sub(/[ \t{"].*$/, "", w)
        r_type = w
        set_labels(line)
        if (ATTACH_COMMENT == 1 && pend_c > 0 && pend_end == FNR - 1) {
            r_start = pend_start
            r_t = pend_c; r_b = 0; r_c = pend_c; r_x = 0
            pend_c = 0; pend_start = 0; pend_end = 0
        } else {
            flush_pend()
            r_start = FNR; r_t = 0; r_b = 0; r_c = 0; r_x = 0
        }
        inres = 1
        r_t++; r_x++
        depth = no - nc
        if (depth <= 0) { depth = 0; emit_res(FNR) }
        return
    }
    flush_pend()
    o_t++; o_x++
    depth += no - nc
    if (depth < 0) depth = 0
}

function record(cls, scan) {
    if (cls == "B") b_all++
    else if (cls == "C") c_all++
    else x_all++
    if (WANT_RES == 1 && ftype == "tf") tf_block(cls, scan)
    if (scan == 1 && cls == "X") detect_hd()
}

function start_file() {
    curfile = FILENAME
    sub(/^\.\//, "", curfile)
    ext = curfile
    if (ext ~ /\./) sub(/^.*\./, "", ext); else ext = ""
    ftype = (ext == "tf") ? "tf" : ((ext == "sh") ? "sh" : "other")
    classify(curfile)
    t_all = 0; b_all = 0; c_all = 0; x_all = 0
    hd_i = 1; hd_n = 0
    delete hd_term; delete hd_indent
    inblk = 0; depth = 0; inres = 0
    pend_c = 0; pend_start = 0; pend_end = 0
    o_t = 0; o_b = 0; o_c = 0; o_x = 0
    r_t = 0; r_b = 0; r_c = 0; r_x = 0
    lastfnr = 0
}

function finish_file() {
    if (WANT_RES == 1 && ftype == "tf") {
        if (inres) emit_res(lastfnr)
        flush_pend()
        if (o_t > 0) emit_other()
    }
    printf "%s\t%s\t%s\t%s\t%s\t%d\t%d\t%d\t%d\t%s\n", \
        env, rel, curfile, ext, "実測", t_all, b_all, c_all, x_all, "" >> FOUT
}

BEGIN {
    BS = sprintf("%c", 92)
    RE_STR = "\"(" BS BS ".|[^\"" BS BS "])*\""
    n = split(ENVS, ea, ",")
    for (i = 1; i <= n; i++) if (ea[i] != "") envset[ea[i]] = 1
    curfile = ""
    nres = 0
}

FNR == 1 {
    if (curfile != "") finish_file()
    start_file()
}

{
    lastfnr = FNR
    line = $0
    sub(/\r$/, "", line)
    tl = line
    gsub(/^[ \t]+|[ \t]+$/, "", tl)
    t_all++

    if (hd_i <= hd_n) {
        hterm = hd_term[hd_i]
        if (hd_indent[hd_i]) hcand = tl
        else { hcand = line; sub(/[ \t]+$/, "", hcand) }
        if (hcand == hterm) { hd_i++; record("X", 0); next }
        record((tl == "") ? "B" : "X", 0)
        next
    }

    if (inblk) {
        p = index(line, "*/")
        if (p > 0) {
            inblk = 0
            rest = trim(substr(line, p + 2))
            if (rest != "" && rest !~ /^(#|\/\/)/) { record("X", 1); next }
        }
        record("C", 0)
        next
    }

    if (tl == "") { record("B", 0); next }

    if (ftype == "tf") {
        if (tl ~ /^#/ || tl ~ /^\/\//) { record("C", 0); next }
        if (tl ~ /^\/\*/) {
            p = index(tl, "*/")
            if (p > 0) {
                rest = trim(substr(tl, p + 2))
                if (rest != "" && rest !~ /^(#|\/\/)/) { record("X", 1); next }
                record("C", 0); next
            }
            inblk = 1
            record("C", 0); next
        }
    } else if (ftype == "sh") {
        if (tl ~ /^#/) {
            if (FNR == 1 && tl ~ /^#!/ && SHEBANG_COMMENT != 1) { record("X", 1); next }
            record("C", 0); next
        }
    } else {
        if (tl ~ /^#/) { record("C", 0); next }
    }

    record("X", 1)
}

END {
    if (curfile != "") finish_file()
    close(FOUT)
    if (WANT_RES == 1) close(ROUT)
}
__AWK_COUNTER_EOF__
}

#-------------------------------------------------------------------------------
# 未配置ファイルのステップ数推測
#   <推測対象ディレクトリ>/<基準環境> (既定 terraform/stacks/j1) を基準とし、
#   同じ階層に実在する他の環境ディレクトリのうち、ファイル数が基準環境より
#   少ないもの (空を含む) について、基準環境にだけ存在するファイルを
#   基準環境の実測値で補う
#-------------------------------------------------------------------------------
write_awk_estimate() {
  cat > "$1" <<'__AWK_EST_EOF__'
#-------------------------------------------------------------------------------
# 入力 : ファイル単位レコード (実測)
# 変数 : BASEDIR  推測対象の環境ディレクトリが並ぶディレクトリ ("." はルート直下)
#        REF      基準環境
#        ENVS     BASEDIR 直下に実在する環境ディレクトリ (カンマ区切り / REF を含む)
#        EXCLUDE  推測対象から外すディレクトリ名 (カンマ区切り)
#        STATF    環境ごとの判定結果の出力先 (環境/実ファイル数/基準ファイル数/推測件数)
# 出力 : 推測レコード (区分 = 推測)
#-------------------------------------------------------------------------------
BEGIN {
    FS = "\t"
    pre = (BASEDIR == "" || BASEDIR == ".") ? "" : BASEDIR "/"
    ne = split(ENVS, E, ",")
    for (i = 1; i <= ne; i++) if (E[i] != "") eset[E[i]] = 1
    n = split(EXCLUDE, a, ",")
    for (i = 1; i <= n; i++) if (a[i] != "") xset[a[i]] = 1
    nref = 0
}

$5 == "実測" {
    p = $3
    if (pre != "") {
        if (substr(p, 1, length(pre)) != pre) next
        p = substr(p, length(pre) + 1)
    }
    n = split(p, a, "/")
    if (n < 2 || !(a[1] in eset)) next
    for (i = 2; i < n; i++) if (a[i] in xset) next
    env = a[1]
    rel = substr(p, length(env) + 2)
    cnt[env]++
    have[env, rel] = 1
    if (env == REF) {
        nref++; R[nref] = rel
        RE[rel] = $4; RB[rel] = $7 + 0; RC[rel] = $8 + 0; RX[rel] = $9 + 0
    }
}

END {
    for (i = 1; i <= ne; i++) {
        e = E[i]
        if (e == "" || e == REF) continue
        c = cnt[e] + 0
        k = 0
        if (c < nref) {
            basis = sprintf("%s のファイル数 %d < %s のファイル数 %d", e, c, REF, nref)
            for (j = 1; j <= nref; j++) {
                rel = R[j]
                if ((e SUBSEP rel) in have) continue
                k++
                printf "%s\t%s\t%s%s/%s\t%s\t%s\t%d\t%d\t%d\t%d\t%s (参照: %s%s/%s)\n", \
                    e, rel, pre, e, rel, RE[rel], "推測", \
                    RB[rel] + RC[rel] + RX[rel], RB[rel], RC[rel], RX[rel], \
                    basis, pre, REF, rel
            }
        }
        printf "%s\t%d\t%d\t%d\n", e, c, nref, k > STATF
    }
    close(STATF)
}
__AWK_EST_EOF__
}

#-------------------------------------------------------------------------------
# 集計 (拡張子別 / 環境別 / 環境 x 拡張子 / 全体)
#-------------------------------------------------------------------------------
write_awk_aggregate() {
  cat > "$1" <<'__AWK_AGG_EOF__'
#-------------------------------------------------------------------------------
# 入力 : ファイル単位レコード (実測 + 推測)
# 変数 : EB EC       空白行 / コメント行を除外するか (1/0)
#        ENVORDER    環境の表示順 (カンマ区切り)
#        NRES        Terraform ブロック数
#        OUT_EXT OUT_ENV OUT_TOTAL OUT_MATRIX  出力先
#-------------------------------------------------------------------------------
function envname(e) { return (e == "-") ? "(環境ディレクトリ外)" : e }

BEGIN { FS = "\t"; no = split(ENVORDER, EO, ",") }

{
    env = $1; ext = ($4 == "" ? "(拡張子なし)" : $4); kind = $5
    t = $6 + 0; b = $7 + 0; c = $8 + 0; x = $9 + 0
    e = t - (EB == 1 ? b : 0) - (EC == 1 ? c : 0)
    if (e < 0) e = 0

    extseen[ext] = 1
    envseen[env] = 1

    xf[ext]++; xt[ext] += t; xb[ext] += b; xc[ext] += c; xx[ext] += x; xe[ext] += e
    vf[env]++; vt[env] += t; vb[env] += b; vc[env] += c; vx[env] += x; ve[env] += e
    m[env, ext] += e
    mrow[env] += e; mcol[ext] += e

    gf++; gt += t; gb += b; gc += c; gx += x; ge += e
    if (kind == "推測") {
        xef[ext]++; xee[ext] += e
        vef[env]++; vee[env] += e
        gef++; gee += e
    } else {
        grf++; gre += e
    }
}

END {
    # ---- 拡張子の並び (昇順) ----
    ne = 0
    for (k in extseen) { ne++; EX[ne] = k }
    for (i = 2; i <= ne; i++) { tv = EX[i]; j = i - 1; while (j >= 1 && EX[j] > tv) { EX[j+1] = EX[j]; j-- } EX[j+1] = tv }

    # ---- 環境の並び (指定順 -> 未指定分を昇順) ----
    nv = 0
    for (i = 1; i <= no; i++) {
        k = EO[i]
        if (k != "" && (k in envseen) && !(k in envdone)) { nv++; VE[nv] = k; envdone[k] = 1 }
    }
    nr = 0
    for (k in envseen) if (!(k in envdone)) { nr++; RE[nr] = k }
    for (i = 2; i <= nr; i++) { tv = RE[i]; j = i - 1; while (j >= 1 && RE[j] > tv) { RE[j+1] = RE[j]; j-- } RE[j+1] = tv }
    for (i = 1; i <= nr; i++) { nv++; VE[nv] = RE[i] }

    # ---- 拡張子別集計 ----
    for (i = 1; i <= ne; i++) {
        k = EX[i]
        printf "%s\t%d\t%d\t%d\t%d\t%d\t%d\t%.6f\t%d\t%d\n", \
            k, xf[k], xt[k], xb[k], xc[k], xx[k], xe[k], (ge > 0 ? xe[k] / ge : 0), xef[k] + 0, xee[k] + 0 > OUT_EXT
    }
    printf "%s\t%d\t%d\t%d\t%d\t%d\t%d\t%.6f\t%d\t%d\n", \
        "合計", gf, gt, gb, gc, gx, ge, (ge > 0 ? 1 : 0), gef + 0, gee + 0 > OUT_EXT

    # ---- 環境別集計 ----
    for (i = 1; i <= nv; i++) {
        k = VE[i]
        printf "%s\t%d\t%d\t%d\t%d\t%d\t%d\t%.6f\t%d\t%d\n", \
            envname(k), vf[k], vt[k], vb[k], vc[k], vx[k], ve[k], (ge > 0 ? ve[k] / ge : 0), vef[k] + 0, vee[k] + 0 > OUT_ENV
    }
    printf "%s\t%d\t%d\t%d\t%d\t%d\t%d\t%.6f\t%d\t%d\n", \
        "合計", gf, gt, gb, gc, gx, ge, (ge > 0 ? 1 : 0), gef + 0, gee + 0 > OUT_ENV

    # ---- 環境 x 拡張子 (有効ステップ数) ----
    hdr = "環境"
    for (i = 1; i <= ne; i++) hdr = hdr "\t" EX[i]
    hdr = hdr "\t合計"
    print hdr > OUT_MATRIX
    for (i = 1; i <= nv; i++) {
        k = VE[i]
        row = envname(k)
        for (j = 1; j <= ne; j++) row = row "\t" (m[k, EX[j]] + 0)
        row = row "\t" (mrow[k] + 0)
        print row > OUT_MATRIX
    }
    row = "合計"
    for (j = 1; j <= ne; j++) row = row "\t" (mcol[EX[j]] + 0)
    row = row "\t" ge
    print row > OUT_MATRIX

    # ---- 全体集計 ----
    printf "対象ファイル数\t%d\n", gf                      > OUT_TOTAL
    printf "実測ファイル数\t%d\n", grf + 0                 > OUT_TOTAL
    printf "推測ファイル数\t%d\n", gef + 0                 > OUT_TOTAL
    printf "総行数\t%d\n", gt                              > OUT_TOTAL
    printf "空白行数\t%d\n", gb                            > OUT_TOTAL
    printf "コメント行数\t%d\n", gc                        > OUT_TOTAL
    printf "コード行数\t%d\n", gx                          > OUT_TOTAL
    printf "有効ステップ数\t%d\n", ge                      > OUT_TOTAL
    printf "有効ステップ数(実測)\t%d\n", gre + 0           > OUT_TOTAL
    printf "有効ステップ数(推測)\t%d\n", gee + 0           > OUT_TOTAL
    printf "Terraformブロック数\t%d\n", NRES + 0           > OUT_TOTAL

    close(OUT_EXT); close(OUT_ENV); close(OUT_MATRIX); close(OUT_TOTAL)
}
__AWK_AGG_EOF__
}

#===============================================================================
# Excel (.xlsx) 生成
#   OOXML (SpreadsheetML) を直接組み立てて zip 圧縮する
#   デザイン : Meiryo UI / モノトーン / 細罫線 / 縞模様 / グレーのデータバー
#===============================================================================

#-------------------------------------------------------------------------------
# xl/styles.xml
#   cellXfs のインデックスは以下で固定 (シート生成 awk と対応)
#     0 既定           1 タイトル       2 キャプション   3 セクション見出し
#     4 見出し(中央)   5 見出し(左)     6 文字           7 文字(縞)
#     8 数値           9 数値(縞)      10 中央          11 中央(縞)
#    12 率            13 率(縞)        14 合計(文字)    15 合計(数値)
#    16 合計(中央)    17 合計(率)      18 推測(文字)    19 推測(数値)
#    20 推測(文字/縞) 21 推測(数値/縞) 22 項目名        23 項目値
#    24 KPIラベル     25 KPI値         26 推測(中央)    27 推測(中央/縞)
#    28 アクセント    29 数値(枠なし)  30 文字(枠なし)  31 小見出し
#-------------------------------------------------------------------------------
xlsx_styles() {
  cat <<'__STYLES_EOF__'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<numFmts count="1"><numFmt numFmtId="164" formatCode="0.0%"/></numFmts>
<fonts count="10">
<font><sz val="9"/><color rgb="FF3A3A3A"/><name val="Meiryo UI"/><family val="3"/><charset val="128"/></font>
<font><b/><sz val="9"/><color rgb="FFFFFFFF"/><name val="Meiryo UI"/><family val="3"/><charset val="128"/></font>
<font><b/><sz val="18"/><color rgb="FF1A1A1A"/><name val="Meiryo UI"/><family val="3"/><charset val="128"/></font>
<font><i/><sz val="9"/><color rgb="FF8C8C8C"/><name val="Meiryo UI"/><family val="3"/><charset val="128"/></font>
<font><b/><sz val="11"/><color rgb="FF1A1A1A"/><name val="Meiryo UI"/><family val="3"/><charset val="128"/></font>
<font><b/><sz val="9"/><color rgb="FF1A1A1A"/><name val="Meiryo UI"/><family val="3"/><charset val="128"/></font>
<font><sz val="8"/><color rgb="FF8C8C8C"/><name val="Meiryo UI"/><family val="3"/><charset val="128"/></font>
<font><b/><sz val="10"/><color rgb="FFFFFFFF"/><name val="Meiryo UI"/><family val="3"/><charset val="128"/></font>
<font><b/><sz val="18"/><color rgb="FF1A1A1A"/><name val="Meiryo UI"/><family val="3"/><charset val="128"/></font>
<font><b/><sz val="8"/><color rgb="FF6E6E6E"/><name val="Meiryo UI"/><family val="3"/><charset val="128"/></font>
</fonts>
<fills count="8">
<fill><patternFill patternType="none"/></fill>
<fill><patternFill patternType="gray125"/></fill>
<fill><patternFill patternType="solid"><fgColor rgb="FF3F3F3F"/><bgColor indexed="64"/></patternFill></fill>
<fill><patternFill patternType="solid"><fgColor rgb="FFF5F5F5"/><bgColor indexed="64"/></patternFill></fill>
<fill><patternFill patternType="solid"><fgColor rgb="FFE9E9E9"/><bgColor indexed="64"/></patternFill></fill>
<fill><patternFill patternType="solid"><fgColor rgb="FFFAFAFA"/><bgColor indexed="64"/></patternFill></fill>
<fill><patternFill patternType="solid"><fgColor rgb="FF1A1A1A"/><bgColor indexed="64"/></patternFill></fill>
<fill><patternFill patternType="solid"><fgColor rgb="FFEFEFEF"/><bgColor indexed="64"/></patternFill></fill>
</fills>
<borders count="5">
<border><left/><right/><top/><bottom/><diagonal/></border>
<border><left style="thin"><color rgb="FFDCDCDC"/></left><right style="thin"><color rgb="FFDCDCDC"/></right><top style="thin"><color rgb="FFDCDCDC"/></top><bottom style="thin"><color rgb="FFDCDCDC"/></bottom><diagonal/></border>
<border><left/><right/><top/><bottom style="thin"><color rgb="FF3F3F3F"/></bottom><diagonal/></border>
<border><left style="thin"><color rgb="FFDCDCDC"/></left><right style="thin"><color rgb="FFDCDCDC"/></right><top style="thin"><color rgb="FF9A9A9A"/></top><bottom style="thin"><color rgb="FFDCDCDC"/></bottom><diagonal/></border>
<border><left style="thin"><color rgb="FFCFCFCF"/></left><right style="thin"><color rgb="FFCFCFCF"/></right><top style="thin"><color rgb="FFCFCFCF"/></top><bottom style="thin"><color rgb="FFCFCFCF"/></bottom><diagonal/></border>
</borders>
<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
<cellXfs count="32">
<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
<xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1" applyAlignment="1"><alignment horizontal="left" vertical="center"/></xf>
<xf numFmtId="0" fontId="6" fillId="0" borderId="0" xfId="0" applyFont="1" applyAlignment="1"><alignment horizontal="left" vertical="center"/></xf>
<xf numFmtId="0" fontId="4" fillId="0" borderId="2" xfId="0" applyFont="1" applyBorder="1" applyAlignment="1"><alignment horizontal="left" vertical="center"/></xf>
<xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>
<xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="left" vertical="center" wrapText="1"/></xf>
<xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1" applyAlignment="1"><alignment horizontal="left" vertical="center"/></xf>
<xf numFmtId="0" fontId="0" fillId="3" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="left" vertical="center"/></xf>
<xf numFmtId="3" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyFont="1" applyBorder="1" applyAlignment="1"><alignment horizontal="right" vertical="center"/></xf>
<xf numFmtId="3" fontId="0" fillId="3" borderId="1" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="right" vertical="center"/></xf>
<xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>
<xf numFmtId="0" fontId="0" fillId="3" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>
<xf numFmtId="164" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyFont="1" applyBorder="1" applyAlignment="1"><alignment horizontal="right" vertical="center"/></xf>
<xf numFmtId="164" fontId="0" fillId="3" borderId="1" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="right" vertical="center"/></xf>
<xf numFmtId="0" fontId="5" fillId="4" borderId="3" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="left" vertical="center"/></xf>
<xf numFmtId="3" fontId="5" fillId="4" borderId="3" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="right" vertical="center"/></xf>
<xf numFmtId="0" fontId="5" fillId="4" borderId="3" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>
<xf numFmtId="164" fontId="5" fillId="4" borderId="3" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="right" vertical="center"/></xf>
<xf numFmtId="0" fontId="3" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1" applyAlignment="1"><alignment horizontal="left" vertical="center"/></xf>
<xf numFmtId="3" fontId="3" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyFont="1" applyBorder="1" applyAlignment="1"><alignment horizontal="right" vertical="center"/></xf>
<xf numFmtId="0" fontId="3" fillId="3" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="left" vertical="center"/></xf>
<xf numFmtId="3" fontId="3" fillId="3" borderId="1" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="right" vertical="center"/></xf>
<xf numFmtId="0" fontId="5" fillId="7" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="left" vertical="center"/></xf>
<xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1" applyAlignment="1"><alignment horizontal="left" vertical="center" wrapText="1"/></xf>
<xf numFmtId="0" fontId="9" fillId="5" borderId="4" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="left" vertical="center"/></xf>
<xf numFmtId="3" fontId="8" fillId="5" borderId="4" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="right" vertical="center"/></xf>
<xf numFmtId="0" fontId="3" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>
<xf numFmtId="0" fontId="3" fillId="3" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>
<xf numFmtId="0" fontId="0" fillId="6" borderId="0" xfId="0" applyFill="1"/>
<xf numFmtId="3" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1" applyAlignment="1"><alignment horizontal="right" vertical="center"/></xf>
<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyFont="1" applyAlignment="1"><alignment horizontal="left" vertical="center"/></xf>
<xf numFmtId="0" fontId="7" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="left" vertical="center"/></xf>
</cellXfs>
<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
<dxfs count="0"/>
<tableStyles count="0" defaultTableStyle="TableStyleMedium2" defaultPivotStyle="PivotStyleLight16"/>
</styleSheet>
__STYLES_EOF__
}

#-------------------------------------------------------------------------------
# 明細シート (ファイル別 / リソース別 / 推測明細) 生成 awk
#-------------------------------------------------------------------------------
write_awk_sheet() {
  cat > "$1" <<'__AWK_SHEET_EOF__'
#-------------------------------------------------------------------------------
# 入力 : TSV レコード
# 変数 : TITLE SUBTITLE HEADERS(TAB区切り) CLASSES(列種別 s/n/c/p)
#        WIDTHS(カンマ区切り) ESTCOL(推測判定列) ALLEST(全行推測)
#        TOTALCOLS(合計対象列) TOTALLABEL BARCOL(データバー列)
#-------------------------------------------------------------------------------
function colref(n,   s, r) {
    s = ""
    while (n > 0) { r = (n - 1) % 26; s = sprintf("%c", 65 + r) s; n = int((n - 1) / 26) }
    return s
}
function xe(s) {
    gsub(/&/, R_AMP, s); gsub(/</, R_LT, s)
    gsub(/>/, R_GT, s); gsub(/"/, R_QT, s)
    return s
}
function sc(r, c, st, v) {
    if (v == "") { printf "<c r=\"%s%d\" s=\"%d\"/>", colref(c), r, st; return }
    printf "<c r=\"%s%d\" s=\"%d\" t=\"inlineStr\"><is><t xml:space=\"preserve\">%s</t></is></c>", colref(c), r, st, xe(v)
}
function nu(r, c, st, v) {
    if (v == "") { printf "<c r=\"%s%d\" s=\"%d\"/>", colref(c), r, st; return }
    printf "<c r=\"%s%d\" s=\"%d\"><v>%s</v></c>", colref(c), r, st, v
}
function stylefor(cl, band, est) {
    if (est == 1) {
        if (cl == "n") return band ? 21 : 19
        if (cl == "c") return band ? 27 : 26
        if (cl == "p") return band ? 13 : 12
        return band ? 20 : 18
    }
    if (cl == "n") return band ? 9 : 8
    if (cl == "c") return band ? 11 : 10
    if (cl == "p") return band ? 13 : 12
    return band ? 7 : 6
}
function totalstyle(cl) {
    if (cl == "n") return 15
    if (cl == "c") return 16
    if (cl == "p") return 17
    return 14
}

BEGIN {
    BS = sprintf("%c", 92)
    R_AMP = BS "&amp;"; R_LT = BS "&lt;"; R_GT = BS "&gt;"; R_QT = BS "&quot;"
    FS = "\t"
    HROW = 4
    ncol = split(HEADERS, H, "\t")
    nw = split(WIDTHS, W, ",")
    ntc = split(TOTALCOLS, TC, ",")
    for (i = 1; i <= ntc; i++) if (TC[i] != "") istotal[TC[i] + 0] = 1
    last = colref(ncol)

    print "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
    printf "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">"
    printf "<sheetPr><tabColor rgb=\"FFA6A6A6\"/><pageSetUpPr fitToPage=\"1\"/></sheetPr>"
    printf "<sheetViews><sheetView showGridLines=\"0\" workbookViewId=\"0\">"
    printf "<pane ySplit=\"%d\" topLeftCell=\"A%d\" activePane=\"bottomLeft\" state=\"frozen\"/>", HROW, HROW + 1
    printf "<selection pane=\"bottomLeft\" activeCell=\"A%d\" sqref=\"A%d\"/>", HROW + 1, HROW + 1
    printf "</sheetView></sheetViews>"
    printf "<sheetFormatPr defaultRowHeight=\"16.5\"/>"
    printf "<cols>"
    for (i = 1; i <= ncol; i++) {
        w = (i <= nw && W[i] != "") ? W[i] : 12
        printf "<col min=\"%d\" max=\"%d\" width=\"%s\" customWidth=\"1\"/>", i, i, w
    }
    printf "</cols><sheetData>"

    # 1行目 : タイトル
    printf "<row r=\"1\" ht=\"32\" customHeight=\"1\">"
    sc(1, 1, 1, TITLE)
    for (i = 2; i <= ncol; i++) sc(1, i, 1, "")
    printf "</row>"
    # 2行目 : キャプション
    printf "<row r=\"2\" ht=\"15\" customHeight=\"1\">"
    sc(2, 1, 2, SUBTITLE)
    for (i = 2; i <= ncol; i++) sc(2, i, 2, "")
    printf "</row>"
    # 3行目 : 余白
    printf "<row r=\"3\" ht=\"6\" customHeight=\"1\"/>"
    # 4行目 : 見出し
    printf "<row r=\"4\" ht=\"30\" customHeight=\"1\">"
    for (i = 1; i <= ncol; i++) sc(HROW, i, (i == 1 ? 5 : 4), H[i])
    printf "</row>"
    nrow = 0
}

{
    nrow++
    r = HROW + nrow
    band = (nrow % 2 == 0) ? 1 : 0
    est = (ALLEST == 1) ? 1 : 0
    if (est == 0 && ESTCOL + 0 > 0 && $(ESTCOL + 0) == "推測") est = 1
    printf "<row r=\"%d\">", r
    for (i = 1; i <= ncol; i++) {
        cl = substr(CLASSES, i, 1)
        st = stylefor(cl, band, est)
        v = (i <= NF) ? $i : ""
        if (cl == "n" || cl == "p") {
            nu(r, i, st, v)
            if (istotal[i]) sum[i] += v + 0
        } else {
            sc(r, i, st, v)
        }
    }
    printf "</row>"
}

END {
    lastdata = HROW + nrow
    if (ntc > 0 && TOTALCOLS != "" && nrow > 0) {
        r = lastdata + 1
        printf "<row r=\"%d\" ht=\"20\" customHeight=\"1\">", r
        for (i = 1; i <= ncol; i++) {
            cl = substr(CLASSES, i, 1)
            if (i == 1) { sc(r, i, totalstyle(cl), TOTALLABEL) }
            else if (istotal[i]) { nu(r, i, totalstyle(cl), sum[i] + 0) }
            else if (i == 2) { sc(r, i, totalstyle(cl), sprintf("%d 件", nrow)) }
            else { sc(r, i, totalstyle(cl), "") }
        }
        printf "</row>"
    }
    printf "</sheetData>"
    if (nrow > 0) printf "<autoFilter ref=\"A%d:%s%d\"/>", HROW, last, lastdata
    printf "<mergeCells count=\"2\"><mergeCell ref=\"A1:%s1\"/><mergeCell ref=\"A2:%s2\"/></mergeCells>", last, last
    if (BARCOL + 0 > 0 && nrow > 0) {
        bc = colref(BARCOL + 0)
        printf "<conditionalFormatting sqref=\"%s%d:%s%d\">", bc, HROW + 1, bc, lastdata
        printf "<cfRule type=\"dataBar\" priority=\"1\"><dataBar showValue=\"1\">"
        printf "<cfvo type=\"num\" val=\"0\"/><cfvo type=\"max\"/><color rgb=\"FFC9C9C9\"/>"
        printf "</dataBar></cfRule></conditionalFormatting>"
    }
    printf "<printOptions horizontalCentered=\"1\"/>"
    printf "<pageMargins left=\"0.4\" right=\"0.4\" top=\"0.6\" bottom=\"0.5\" header=\"0.3\" footer=\"0.3\"/>"
    printf "<pageSetup paperSize=\"9\" orientation=\"landscape\" fitToWidth=\"1\" fitToHeight=\"0\"/>"
    printf "</worksheet>\n"
}
__AWK_SHEET_EOF__
}

#-------------------------------------------------------------------------------
# サマリシート生成 awk
#-------------------------------------------------------------------------------
write_awk_dashboard() {
  cat > "$1" <<'__AWK_DASH_EOF__'
#-------------------------------------------------------------------------------
# 変数 : TITLE SUBTITLE METAF KPIF EXTF ENVF MATF
#        EXTHDR ENVHDR MATHDR SHOWEXT SHOWENV SHOWMAT
#-------------------------------------------------------------------------------
function colref(n,   s, r) {
    s = ""
    while (n > 0) { r = (n - 1) % 26; s = sprintf("%c", 65 + r) s; n = int((n - 1) / 26) }
    return s
}
function xe(s) {
    gsub(/&/, R_AMP, s); gsub(/</, R_LT, s)
    gsub(/>/, R_GT, s); gsub(/"/, R_QT, s)
    return s
}
function sc(r, c, st, v) {
    if (v == "") { printf "<c r=\"%s%d\" s=\"%d\"/>", colref(c), r, st; return }
    printf "<c r=\"%s%d\" s=\"%d\" t=\"inlineStr\"><is><t xml:space=\"preserve\">%s</t></is></c>", colref(c), r, st, xe(v)
}
function nu(r, c, st, v) {
    if (v == "") { printf "<c r=\"%s%d\" s=\"%d\"/>", colref(c), r, st; return }
    printf "<c r=\"%s%d\" s=\"%d\"><v>%s</v></c>", colref(c), r, st, v
}
function orow(r, h) {
    if (h > 0) printf "<row r=\"%d\" ht=\"%.1f\" customHeight=\"1\">", r, h
    else printf "<row r=\"%d\">", r
}
function addmerge(ref) { nmg++; MG[nmg] = ref }
function addbar(ref)   { nbar++; BAR[nbar] = ref }
function spacer(r)     { printf "<row r=\"%d\" ht=\"8\" customHeight=\"1\"/>", r }
function section(r, txt,   c) {
    orow(r, 26)
    sc(r, 2, 3, txt)
    for (c = 3; c <= LASTC; c++) sc(r, c, 3, "")
    printf "</row>"
    addmerge(sprintf("B%d:%s%d", r, colref(LASTC), r))
}

#-- TSV を表として描画 (ファイルの最終行は合計行として扱う) ----------------------
function table(r, file, hdr, classes, barcol,   nh, HH, ln, a, i, j, n, lines, band, cl, st, first)
{
    nh = split(hdr, HH, "\t")
    orow(r, 30)
    for (i = 1; i <= nh; i++) sc(r, 1 + i, (i == 1 ? 5 : 4), HH[i])
    printf "</row>"
    r++
    first = r
    n = 0
    while ((getline ln < file) > 0) { n++; lines[n] = ln }
    close(file)
    for (i = 1; i <= n; i++) {
        split(lines[i], a, "\t")
        band = (i % 2 == 0) ? 1 : 0
        orow(r, (i == n) ? 20 : 0)
        for (j = 1; j <= nh; j++) {
            cl = substr(classes, j, 1)
            if (i == n)        st = (cl == "n" ? 15 : (cl == "p" ? 17 : (cl == "c" ? 16 : 14)))
            else if (cl == "n") st = (band ? 9 : 8)
            else if (cl == "p") st = (band ? 13 : 12)
            else if (cl == "c") st = (band ? 11 : 10)
            else                st = (band ? 7 : 6)
            if (cl == "n" || cl == "p") nu(r, 1 + j, st, a[j])
            else sc(r, 1 + j, st, a[j])
        }
        printf "</row>"
        r++
    }
    if (barcol > 0 && n > 1) addbar(sprintf("%s%d:%s%d", colref(1 + barcol), first, colref(1 + barcol), r - 2))
    return r
}

BEGIN {
    BS = sprintf("%c", 92)
    R_AMP = BS "&amp;"; R_LT = BS "&lt;"; R_GT = BS "&gt;"; R_QT = BS "&quot;"
    nmc = split(MATHDR, MH, "\t")
    LASTC = 11
    if (1 + nmc > LASTC) LASTC = 1 + nmc
    LC = colref(LASTC)
    nmg = 0; nbar = 0

    print "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
    printf "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">"
    printf "<sheetPr><tabColor rgb=\"FF3F3F3F\"/><pageSetUpPr fitToPage=\"1\"/></sheetPr>"
    printf "<sheetViews><sheetView showGridLines=\"0\" tabSelected=\"1\" workbookViewId=\"0\">"
    printf "<pane ySplit=\"2\" topLeftCell=\"A3\" activePane=\"bottomLeft\" state=\"frozen\"/>"
    printf "<selection pane=\"bottomLeft\" activeCell=\"B4\" sqref=\"B4\"/>"
    printf "</sheetView></sheetViews>"
    printf "<sheetFormatPr defaultRowHeight=\"16.5\"/>"
    printf "<cols>"
    printf "<col min=\"1\" max=\"1\" width=\"3\" customWidth=\"1\"/>"
    printf "<col min=\"2\" max=\"2\" width=\"26\" customWidth=\"1\"/>"
    printf "<col min=\"3\" max=\"4\" width=\"12.5\" customWidth=\"1\"/>"
    printf "<col min=\"5\" max=\"7\" width=\"13\" customWidth=\"1\"/>"
    printf "<col min=\"8\" max=\"8\" width=\"15\" customWidth=\"1\"/>"
    printf "<col min=\"9\" max=\"9\" width=\"11\" customWidth=\"1\"/>"
    printf "<col min=\"10\" max=\"10\" width=\"14\" customWidth=\"1\"/>"
    printf "<col min=\"11\" max=\"11\" width=\"15\" customWidth=\"1\"/>"
    if (LASTC > 11) printf "<col min=\"12\" max=\"%d\" width=\"13\" customWidth=\"1\"/>", LASTC
    printf "<col min=\"%d\" max=\"%d\" width=\"3\" customWidth=\"1\"/>", LASTC + 1, LASTC + 1
    printf "</cols><sheetData>"

    #---- タイトル ----
    orow(1, 38)
    sc(1, 2, 1, TITLE)
    for (i = 3; i <= LASTC; i++) sc(1, i, 1, "")
    printf "</row>"
    addmerge(sprintf("B1:%s1", LC))
    orow(2, 16)
    sc(2, 2, 2, SUBTITLE)
    for (i = 3; i <= LASTC; i++) sc(2, i, 2, "")
    printf "</row>"
    addmerge(sprintf("B2:%s2", LC))

    r = 3
    spacer(r); r++

    sec = 1
    #---- 計測結果サマリ (KPI) ----
    nk = 0
    while ((getline ln < KPIF) > 0) { split(ln, a, "\t"); nk++; KL[nk] = a[1]; KV[nk] = a[2] }
    close(KPIF)
    if (nk > 5) nk = 5
    if (nk > 0) {
    section(r, sprintf("%d.  計測結果サマリ", sec)); sec++; r++
    spacer(r); r++
    CS[1] = 2; CE[1] = 2; CS[2] = 3; CE[2] = 4; CS[3] = 5; CE[3] = 6
    CS[4] = 7; CE[4] = 8; CS[5] = 9; CE[5] = 10
    for (i = 2; i <= LASTC; i++) { kcard[i] = 0 }
    for (k = 1; k <= nk; k++) for (i = CS[k]; i <= CE[k]; i++) kcard[i] = k
    orow(r, 20)
    for (i = 2; i <= LASTC; i++) {
        if (kcard[i] > 0) sc(r, i, 24, (i == CS[kcard[i]]) ? KL[kcard[i]] : "")
        else sc(r, i, 0, "")
    }
    printf "</row>"
    for (k = 1; k <= nk; k++) if (CE[k] > CS[k]) addmerge(sprintf("%s%d:%s%d", colref(CS[k]), r, colref(CE[k]), r))
    r++
    orow(r, 34)
    for (i = 2; i <= LASTC; i++) {
        if (kcard[i] > 0) nu(r, i, 25, (i == CS[kcard[i]]) ? KV[kcard[i]] : "")
        else sc(r, i, 0, "")
    }
    printf "</row>"
    for (k = 1; k <= nk; k++) if (CE[k] > CS[k]) addmerge(sprintf("%s%d:%s%d", colref(CS[k]), r, colref(CE[k]), r))
    r++
    spacer(r); r++
    }

    #---- 計測条件 ----
    section(r, sprintf("%d.  計測条件", sec)); sec++; r++
    while ((getline ln < METAF) > 0) {
        split(ln, a, "\t")
        orow(r, 18)
        sc(r, 2, 22, a[1])
        sc(r, 3, 23, a[2])
        for (i = 4; i <= LASTC; i++) sc(r, i, 23, "")
        printf "</row>"
        addmerge(sprintf("C%d:%s%d", r, LC, r))
        r++
    }
    close(METAF)
    spacer(r); r++

    #---- 3. 拡張子別集計 ----
    if (SHOWEXT == 1) {
        section(r, sprintf("%d.  拡張子別 集計", sec)); sec++; r++
        r = table(r, EXTF, EXTHDR, "snnnnnnpnn", 7)
        spacer(r); r++
    }
    #---- 4. 環境別集計 ----
    if (SHOWENV == 1) {
        section(r, sprintf("%d.  環境別 集計", sec)); sec++; r++
        r = table(r, ENVF, ENVHDR, "snnnnnnpnn", 7)
        spacer(r); r++
    }
    #---- 5. 環境 x 拡張子 ----
    if (SHOWMAT == 1) {
        section(r, sprintf("%d.  環境 x 拡張子 別 有効ステップ数", sec)); sec++; r++
        mcls = "s"
        for (i = 2; i <= nmc; i++) mcls = mcls "n"
        r = table(r, MATF, MATHDR, mcls, nmc)
        spacer(r); r++
    }

    printf "</sheetData>"
    printf "<mergeCells count=\"%d\">", nmg
    for (i = 1; i <= nmg; i++) printf "<mergeCell ref=\"%s\"/>", MG[i]
    printf "</mergeCells>"
    for (i = 1; i <= nbar; i++) {
        printf "<conditionalFormatting sqref=\"%s\">", BAR[i]
        printf "<cfRule type=\"dataBar\" priority=\"%d\"><dataBar showValue=\"1\">", i
        printf "<cfvo type=\"num\" val=\"0\"/><cfvo type=\"max\"/><color rgb=\"FFC9C9C9\"/>"
        printf "</dataBar></cfRule></conditionalFormatting>"
    }
    printf "<printOptions horizontalCentered=\"1\"/>"
    printf "<pageMargins left=\"0.4\" right=\"0.4\" top=\"0.6\" bottom=\"0.5\" header=\"0.3\" footer=\"0.3\"/>"
    printf "<pageSetup paperSize=\"9\" orientation=\"landscape\" fitToWidth=\"1\" fitToHeight=\"0\"/>"
    printf "</worksheet>\n"
}
__AWK_DASH_EOF__
}

#-------------------------------------------------------------------------------
# xlsx パッケージ組み立て
#   使い方: xlsx_package <出力ファイル> <シート名1> <シートXML1> [<シート名2> ...]
#-------------------------------------------------------------------------------
xlsx_package() {
  local out="$1"; shift
  local pkg="$WORK/xlsx"
  local -a names=() files=()
  while [ "$#" -ge 2 ]; do
    names+=("$1"); files+=("$2"); shift 2
  done
  local n="${#names[@]}"
  [ "$n" -ge 1 ] || die "xlsx: シートがありません"

  rm -rf "$pkg"
  mkdir -p "$pkg/_rels" "$pkg/docProps" "$pkg/xl/_rels" "$pkg/xl/worksheets"

  # ---- [Content_Types].xml ----
  {
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    printf '%s' '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    printf '%s' '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    printf '%s' '<Default Extension="xml" ContentType="application/xml"/>'
    printf '%s' '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
    local i
    for i in $(seq 1 "$n"); do
      printf '<Override PartName="/xl/worksheets/sheet%d.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>' "$i"
    done
    printf '%s' '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
    printf '%s' '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
    printf '%s' '<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>'
    printf '%s\n' '</Types>'
  } > "$pkg/[Content_Types].xml"

  # ---- _rels/.rels ----
  {
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    printf '%s' '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    printf '%s' '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
    printf '%s' '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>'
    printf '%s' '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>'
    printf '%s\n' '</Relationships>'
  } > "$pkg/_rels/.rels"

  # ---- docProps ----
  {
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    printf '%s' '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
    printf '<dc:title>%s</dc:title>' "ステップ数計測レポート"
    printf '<dc:creator>%s</dc:creator>' "$SCRIPT_NAME"
    printf '<cp:lastModifiedBy>%s</cp:lastModifiedBy>' "$SCRIPT_NAME"
    printf '<dcterms:created xsi:type="dcterms:W3CDTF">%s</dcterms:created>' "$(date '+%Y-%m-%dT%H:%M:%SZ')"
    printf '<dcterms:modified xsi:type="dcterms:W3CDTF">%s</dcterms:modified>' "$(date '+%Y-%m-%dT%H:%M:%SZ')"
    printf '%s\n' '</cp:coreProperties>'
  } > "$pkg/docProps/core.xml"
  {
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    printf '%s' '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">'
    printf '<Application>%s %s</Application>' "$SCRIPT_NAME" "$SCRIPT_VERSION"
    printf '%s\n' '</Properties>'
  } > "$pkg/docProps/app.xml"

  # ---- xl/workbook.xml ----
  {
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    printf '%s' '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
    printf '%s' '<workbookPr/>'
    printf '%s' '<bookViews><workbookView xWindow="0" yWindow="0" windowWidth="30000" windowHeight="18000" activeTab="0"/></bookViews>'
    printf '%s' '<sheets>'
    local i
    for i in $(seq 1 "$n"); do
      printf '<sheet name="%s" sheetId="%d" r:id="rId%d"/>' "${names[$((i-1))]}" "$i" "$i"
    done
    printf '%s' '</sheets>'
    if [ "$n" -ge 2 ]; then
      printf '%s' '<definedNames>'
      for i in $(seq 2 "$n"); do
        printf '<definedName name="_xlnm.Print_Titles" localSheetId="%d">%s</definedName>' \
          "$((i-1))" "'${names[$((i-1))]}'!\$4:\$4"
      done
      printf '%s' '</definedNames>'
    fi
    printf '%s' '<calcPr calcId="0"/>'
    printf '%s\n' '</workbook>'
  } > "$pkg/xl/workbook.xml"

  # ---- xl/_rels/workbook.xml.rels ----
  {
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    printf '%s' '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    local i
    for i in $(seq 1 "$n"); do
      printf '<Relationship Id="rId%d" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet%d.xml"/>' "$i" "$i"
    done
    printf '<Relationship Id="rId%d" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>' "$((n+1))"
    printf '%s\n' '</Relationships>'
  } > "$pkg/xl/_rels/workbook.xml.rels"

  # ---- xl/styles.xml / シート ----
  xlsx_styles > "$pkg/xl/styles.xml"
  local i
  for i in $(seq 1 "$n"); do
    cp "${files[$((i-1))]}" "$pkg/xl/worksheets/sheet${i}.xml" || die "シート XML をコピーできません"
  done

  # ---- zip ----
  rm -f "$out"
  local mode="${STEPCOUNT_ZIP_MODE:-$ZIP_MODE}"
  case "$mode" in
    zip)
      ( cd "$pkg" && zip -q -X -D -r "$out" "[Content_Types].xml" _rels docProps xl ) \
        || die "zip による xlsx 生成に失敗しました"
      ;;
    python3|python)
      "$mode" - "$out" "$pkg" <<'__PYZIP_EOF__'
import os, sys, zipfile
out, root = sys.argv[1], sys.argv[2]
order = []
for dirpath, dirnames, filenames in os.walk(root):
    dirnames.sort()
    for fn in sorted(filenames):
        full = os.path.join(dirpath, fn)
        rel = os.path.relpath(full, root).replace(os.sep, '/')
        order.append((rel, full))
order.sort(key=lambda x: (x[0] != '[Content_Types].xml', x[0]))
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    for rel, full in order:
        z.write(full, rel)
__PYZIP_EOF__
      [ -f "$out" ] || die "python による xlsx 生成に失敗しました"
      ;;
    *)
      die "xlsx を圧縮する手段がありません (zip / python3)"
      ;;
  esac
  return 0
}

#===============================================================================
# 計測処理
#===============================================================================

#-------------------------------------------------------------------------------
# 環境ディレクトリの決定
#   ENV_LIST : 環境ディレクトリ名 (集計用)。パス中のどの階層に現れても環境として扱う
#   EST_DIR  : 推測対象の環境ディレクトリが並ぶディレクトリ (ルートからの相対パス)
#   EST_ENVS : EST_DIR 直下に実在する環境ディレクトリ (推測はこの範囲でのみ行う)
#-------------------------------------------------------------------------------
ENV_LIST=""
ENV_FOUND=""
EST_DIR=""
EST_REF_PATH=""
EST_ENVS=""

# カンマ区切りリストに含まれるか
in_csv() { case ",$2," in *",$1,"*) return 0 ;; esac; return 1; }

resolve_est_dir() {
  local d="${OPT_EST_DIR%/}"
  d="${d#./}"
  [ -z "$d" ] && d="."
  # 既定値のままで見つからない場合は、-d に terraform / terraform/stacks を指定したものとみなす
  if [ ! -d "$ROOT_ABS/$d" ] && [ "$OPT_EST_DIR_SET" -eq 0 ]; then
    case "$ROOT_ABS" in
      */terraform/stacks) d="." ;;
      */terraform)        [ -d "$ROOT_ABS/stacks" ] && d="stacks" ;;
    esac
  fi
  EST_DIR="$d"
  if [ "$d" = "." ]; then EST_REF_PATH="$OPT_EST_REF"; else EST_REF_PATH="$d/$OPT_EST_REF"; fi
}

detect_envs() {
  local d out="" est=""
  local -a arr=()
  resolve_est_dir
  if [ "$OPT_ENVS" = "auto" ]; then
    # 推測対象ディレクトリ直下のディレクトリを環境とみなす
    if [ -d "$ROOT_ABS/$EST_DIR" ]; then
      while IFS= read -r d; do
        [ -z "$d" ] && continue
        in_csv "$d" "$OPT_EXCLUDE_DIRS" && continue
        in_csv "$d" "$OPT_EST_EXCLUDE" && continue
        out="${out:+$out,}$d"
      done < <( cd "$ROOT_ABS/$EST_DIR" && find . -mindepth 1 -maxdepth 1 -type d -print | sed 's|^\./||' | LC_ALL=C sort )
    fi
  else
    IFS=',' read -r -a arr <<< "$OPT_ENVS"
    for d in "${arr[@]+"${arr[@]}"}"; do
      [ -z "$d" ] && continue
      in_csv "$d" "$out" || out="${out:+$out,}$d"
    done
  fi
  ENV_LIST="$out"

  IFS=',' read -r -a arr <<< "$ENV_LIST"
  for d in "${arr[@]+"${arr[@]}"}"; do
    [ -d "$ROOT_ABS/$EST_DIR/$d" ] && est="${est:+$est,}$d"
  done
  EST_ENVS="$est"

  log_info "環境ディレクトリ: ${ENV_LIST:-(該当なし)}"
  if [ "$OPT_ESTIMATE" -eq 1 ]; then
    log_info "推測対象ディレクトリ: ${EST_DIR} (実在する環境: ${EST_ENVS:-なし} / 対象外: ${OPT_EST_EXCLUDE:-なし})"
  fi
}

#-------------------------------------------------------------------------------
# 対象ファイルの探索
#-------------------------------------------------------------------------------
discover_files() {
  local d first
  local -a prune=() nameargs=() exdirs=() exts=()
  IFS=',' read -r -a exdirs <<< "$OPT_EXCLUDE_DIRS"
  first=1
  for d in "${exdirs[@]+"${exdirs[@]}"}"; do
    [ -z "$d" ] && continue
    if [ "$first" -eq 1 ]; then prune+=( "(" -name "$d" ); first=0
    else prune+=( -o -name "$d" ); fi
  done
  [ "$first" -eq 0 ] && prune+=( ")" -prune -o )

  IFS=',' read -r -a exts <<< "$OPT_EXTS"
  first=1
  for d in "${exts[@]+"${exts[@]}"}"; do
    [ -z "$d" ] && continue
    d="${d#.}"
    if [ "$first" -eq 1 ]; then nameargs+=( "(" -name "*.$d" ); first=0
    else nameargs+=( -o -name "*.$d" ); fi
  done
  [ "$first" -eq 0 ] || die "対象拡張子の指定が不正です: $OPT_EXTS"
  nameargs+=( ")" )

  ( cd "$ROOT_ABS" && find . "${prune[@]+"${prune[@]}"}" -type f "${nameargs[@]}" -print ) \
    | sed 's|^\./||' | LC_ALL=C sort > "$WORK/filelist.txt"
  FILE_COUNT=$(grep -c . "$WORK/filelist.txt" 2>/dev/null || true)
  [ -z "$FILE_COUNT" ] && FILE_COUNT=0
  log_info "対象ファイル数: $FILE_COUNT"
  [ "$FILE_COUNT" -gt 0 ] || die "対象ファイルが 1 件も見つかりません (--ext / --exclude-dir を確認してください)"
}

#-------------------------------------------------------------------------------
# ステップ数計測
#-------------------------------------------------------------------------------
run_counter() {
  ( cd "$ROOT_ABS" && awk \
      -v ENVS="$ENV_LIST" \
      -v WANT_RES="$OPT_RESOURCE" \
      -v SHEBANG_COMMENT="$OPT_SHEBANG_COMMENT" \
      -v ATTACH_COMMENT="$OPT_ATTACH_COMMENT" \
      -v FOUT="$F_FILES" \
      -v ROUT="$F_RES" \
      -f "$AWK_COUNTER" "$@" )
}

count_files() {
  : > "$F_FILES"
  : > "$F_RES"
  local -a chunk=()
  local line cnt=0
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    chunk+=( "$line" )
    cnt=$((cnt + 1))
    if [ "$cnt" -ge 300 ]; then
      run_counter "${chunk[@]}" || die "計測処理に失敗しました"
      chunk=(); cnt=0
    fi
  done < "$WORK/filelist.txt"
  if [ "${#chunk[@]}" -gt 0 ]; then
    run_counter "${chunk[@]}" || die "計測処理に失敗しました"
  fi

  # 空ファイル (0 バイト) は awk のレコードが生成されないため補完する
  awk -F'\t' -v ENVS="$ENV_LIST" '
    BEGIN { n = split(ENVS, ea, ","); for (i = 1; i <= n; i++) if (ea[i] != "") es[ea[i]] = 1 }
    NR == FNR { seen[$3] = 1; next }
    {
      if ($0 in seen) next
      p = $0
      ext = p; if (ext ~ /\./) sub(/^.*\./, "", ext); else ext = ""
      env = "-"; rel = p
      m = split(p, a, "/"); off = 0
      for (i = 1; i < m; i++) {
        off += length(a[i]) + 1
        if (a[i] in es) { env = a[i]; rel = substr(p, off + 1); break }
      }
      printf "%s\t%s\t%s\t%s\t%s\t0\t0\t0\t0\t\n", env, rel, p, ext, "実測"
    }' "$F_FILES" "$WORK/filelist.txt" >> "$F_FILES"
}

#-------------------------------------------------------------------------------
# 未配置ファイルの推測計測
#-------------------------------------------------------------------------------
EST_COUNT=0
EST_SKIP=""
EST_DETAIL=""
estimate_files() {
  EST_COUNT=0; EST_SKIP=""; EST_DETAIL=""
  [ "$OPT_ESTIMATE" -eq 1 ] || return 0
  if [ ! -d "$ROOT_ABS/$EST_DIR" ]; then
    EST_SKIP="推測対象ディレクトリ ${EST_DIR} が存在しない"
  elif ! in_csv "$OPT_EST_REF" "$ENV_LIST"; then
    EST_SKIP="基準環境 ${OPT_EST_REF} が環境ディレクトリ (--envs) に含まれていない"
  elif ! in_csv "$OPT_EST_REF" "$EST_ENVS"; then
    EST_SKIP="基準環境 ${EST_REF_PATH} が存在しない"
  fi
  if [ -n "$EST_SKIP" ]; then
    log_warn "${EST_SKIP}ため推測計測をスキップします"
    return 0
  fi

  : > "$WORK/est_stat.tsv"
  awk -v BASEDIR="$EST_DIR" -v REF="$OPT_EST_REF" -v ENVS="$EST_ENVS" \
      -v EXCLUDE="$OPT_EST_EXCLUDE" -v STATF="$WORK/est_stat.tsv" \
      -f "$AWK_EST" "$F_FILES" > "$WORK/est.tsv" || die "推測計測に失敗しました"
  EST_COUNT=$(grep -c . "$WORK/est.tsv" 2>/dev/null || true)
  [ -z "$EST_COUNT" ] && EST_COUNT=0
  [ "$EST_COUNT" -gt 0 ] && cat "$WORK/est.tsv" >> "$F_FILES"

  # 環境ごとの判定結果 (ログ / 計測条件シート用)
  local e note n_act n_ref n_est
  local -a arr=()
  IFS=',' read -r -a arr <<< "$ENV_LIST"
  for e in "${arr[@]+"${arr[@]}"}"; do
    [ "$e" = "$OPT_EST_REF" ] && continue
    if ! in_csv "$e" "$EST_ENVS"; then
      note="${e}: ディレクトリなし (推測しない)"
    else
      IFS=$'\t' read -r _ n_act n_ref n_est < <(awk -F'\t' -v e="$e" '$1 == e { print; exit }' "$WORK/est_stat.tsv")
      if [ "${n_est:-0}" -gt 0 ]; then
        note="${e}: ${n_est} 件推測 (${n_act} ファイル / ${OPT_EST_REF}: ${n_ref} ファイル)"
      else
        note="${e}: 推測なし (${n_act} ファイル / ${OPT_EST_REF}: ${n_ref} ファイル)"
      fi
    fi
    log_info "推測計測  ${note}"
    EST_DETAIL="${EST_DETAIL:+$EST_DETAIL    }${note}"
  done
  log_info "推測計測: ${EST_COUNT} 件 (基準環境 ${EST_REF_PATH} の実測値)"
}

#-------------------------------------------------------------------------------
# ファイルが 1 件以上ある環境 (表示順は ENV_LIST 順)
#-------------------------------------------------------------------------------
collect_envs_found() {
  ENV_FOUND="$(awk -F'\t' -v ORDER="$ENV_LIST" '
    $1 != "-" { s[$1] = 1 }
    END {
      n = split(ORDER, E, ","); o = ""
      for (i = 1; i <= n; i++) if (E[i] in s) o = o (o == "" ? "" : ",") E[i]
      print o
    }' "$F_FILES")"
}

#-------------------------------------------------------------------------------
# 並べ替え (環境の指定順 -> パス順)
#-------------------------------------------------------------------------------
sort_records() {
  local tmp="$WORK/sort.tmp"
  awk -F'\t' -v OFS='\t' -v ENVORDER="$ENV_LIST" '
    BEGIN { n = split(ENVORDER, E, ","); for (i = 1; i <= n; i++) idx[E[i]] = i }
    { k = ($1 == "-") ? 9999 : (($1 in idx) ? idx[$1] : 5000); print k, $0 }' "$F_FILES" \
    | LC_ALL=C sort -t "$(printf '\t')" -k1,1n -k3,3 -k2,2 | cut -f2- > "$tmp" && mv "$tmp" "$F_FILES"
  if [ -s "$F_RES" ]; then
    awk -F'\t' -v OFS='\t' -v ENVORDER="$ENV_LIST" '
      BEGIN { n = split(ENVORDER, E, ","); for (i = 1; i <= n; i++) idx[E[i]] = i }
      { k = ($1 == "-") ? 9999 : (($1 in idx) ? idx[$1] : 5000); print k, $0 }' "$F_RES" \
      | LC_ALL=C sort -t "$(printf '\t')" -k1,1n -k3,3 -k8,8n | cut -f2- > "$tmp" && mv "$tmp" "$F_RES"
  fi
}

#-------------------------------------------------------------------------------
# 集計
#-------------------------------------------------------------------------------
RES_COUNT=0
aggregate() {
  RES_COUNT=0
  if [ -s "$F_RES" ]; then
    RES_COUNT=$(awk -F'\t' '$4 != "(ブロック外)"' "$F_RES" | grep -c . || true)
    [ -z "$RES_COUNT" ] && RES_COUNT=0
  fi
  awk -v EB="$OPT_EXCLUDE_BLANK" -v EC="$OPT_EXCLUDE_COMMENT" \
      -v ENVORDER="$ENV_LIST" -v NRES="$RES_COUNT" \
      -v OUT_EXT="$F_SUM_EXT" -v OUT_ENV="$F_SUM_ENV" \
      -v OUT_TOTAL="$F_SUM_TOTAL" -v OUT_MATRIX="$F_MATRIX" \
      -f "$AWK_AGG" "$F_FILES" || die "集計処理に失敗しました"
}

get_total() { awk -F'\t' -v k="$1" '$1 == k { print $2; exit }' "$F_SUM_TOTAL"; }

#===============================================================================
# 出力用ビュー (有効ステップ数を付与した表)
#===============================================================================
build_views() {
  # ---- ファイル別 ----
  awk -F'\t' -v OFS='\t' -v EB="$OPT_EXCLUDE_BLANK" -v EC="$OPT_EXCLUDE_COMMENT" '
    {
      t = $6 + 0; b = $7 + 0; c = $8 + 0; x = $9 + 0
      e = t - (EB == 1 ? b : 0) - (EC == 1 ? c : 0); if (e < 0) e = 0
      env = ($1 == "-") ? "(環境外)" : $1
      print env, $3, ($4 == "" ? "(なし)" : $4), $5, t, b, c, x, e, $10
    }' "$F_FILES" > "$V_FILES"

  # ---- Terraform リソース別 ----
  if [ -s "$F_RES" ]; then
    awk -F'\t' -v OFS='\t' -v EB="$OPT_EXCLUDE_BLANK" -v EC="$OPT_EXCLUDE_COMMENT" '
      {
        t = $9 + 0; b = $10 + 0; c = $11 + 0; x = $12 + 0
        e = t - (EB == 1 ? b : 0) - (EC == 1 ? c : 0); if (e < 0) e = 0
        env = ($1 == "-") ? "(環境外)" : $1
        s = ($7 + 0 == 0) ? "" : $7
        d = ($8 + 0 == 0) ? "" : $8
        print env, $2, $4, ($5 == "" ? "-" : $5), ($6 == "" ? "-" : $6), s, d, t, b, c, x, e
      }' "$F_RES" > "$V_RES"
  else
    : > "$V_RES"
  fi

  # ---- 推測明細 ----
  awk -F'\t' -v OFS='\t' -v EB="$OPT_EXCLUDE_BLANK" -v EC="$OPT_EXCLUDE_COMMENT" -v M="$EST_METHOD_LABEL" '
    $5 == "推測" {
      t = $6 + 0; b = $7 + 0; c = $8 + 0; x = $9 + 0
      e = t - (EB == 1 ? b : 0) - (EC == 1 ? c : 0); if (e < 0) e = 0
      print $1, $3, ($4 == "" ? "(なし)" : $4), t, b, c, x, e, M, $10
    }' "$F_FILES" > "$V_EST"
}

#===============================================================================
# CSV 出力
#===============================================================================
tsv_to_csv() {
  local src="$1" hdr="$2" out="$3"
  {
    [ "$OPT_BOM" -eq 1 ] && printf '\xEF\xBB\xBF'
    awk -F'\t' -v HDR="$hdr" '
      function q(s) {
        if (s ~ /^-?[0-9]+(\.[0-9]+)?$/) return s
        gsub(/"/, "\"\"", s)
        return "\"" s "\""
      }
      BEGIN { ORS = "\r\n"; n = split(HDR, h, "\t"); o = ""
              for (i = 1; i <= n; i++) o = o (i > 1 ? "," : "") q(h[i]); print o }
      { o = ""; for (i = 1; i <= NF; i++) o = o (i > 1 ? "," : "") q($i); print o }
    ' "$src"
  } > "$out"
}

output_csv() {
  [ "$OPT_CSV" -eq 1 ] || return 0
  log_step "CSV を出力しています"
  tsv_to_csv "$V_FILES" "$HDR_FILES" "${OUT_BASE}_files.csv"
  OUT_LIST="${OUT_LIST}${OUT_BASE}_files.csv"$'\n'
  if [ -s "$V_RES" ]; then
    tsv_to_csv "$V_RES" "$HDR_RES" "${OUT_BASE}_resources.csv"
    OUT_LIST="${OUT_LIST}${OUT_BASE}_resources.csv"$'\n'
  fi
  if [ -s "$V_EST" ]; then
    tsv_to_csv "$V_EST" "$HDR_EST" "${OUT_BASE}_estimated.csv"
    OUT_LIST="${OUT_LIST}${OUT_BASE}_estimated.csv"$'\n'
  fi
  if [ "$OPT_SUMMARY_EXT" -eq 1 ]; then
    tsv_to_csv "$F_SUM_EXT" "$HDR_SUM" "${OUT_BASE}_summary_ext.csv"
    OUT_LIST="${OUT_LIST}${OUT_BASE}_summary_ext.csv"$'\n'
  fi
  if [ -n "$ENV_FOUND" ]; then
    tsv_to_csv "$F_SUM_ENV" "$HDR_SUMENV" "${OUT_BASE}_summary_env.csv"
    OUT_LIST="${OUT_LIST}${OUT_BASE}_summary_env.csv"$'\n'
    tsv_to_csv "$F_MAT_BODY" "$MAT_HDR" "${OUT_BASE}_summary_matrix.csv"
    OUT_LIST="${OUT_LIST}${OUT_BASE}_summary_matrix.csv"$'\n'
  fi
  if [ "$OPT_SUMMARY_ALL" -eq 1 ]; then
    tsv_to_csv "$F_SUM_TOTAL" "項目	値" "${OUT_BASE}_summary_total.csv"
    OUT_LIST="${OUT_LIST}${OUT_BASE}_summary_total.csv"$'\n'
  fi
}

#===============================================================================
# Excel 出力
#===============================================================================
build_meta_kpi() {
  local yn_blank yn_comment yn_sheb yn_res yn_est
  [ "$OPT_EXCLUDE_BLANK" -eq 1 ]   && yn_blank="除外して計測する"       || yn_blank="計測に含める"
  [ "$OPT_EXCLUDE_COMMENT" -eq 1 ] && yn_comment="除外して計測する"     || yn_comment="計測に含める"
  [ "$OPT_SHEBANG_COMMENT" -eq 1 ] && yn_sheb="コメント行として扱う"    || yn_sheb="コード行として扱う"
  if [ "$OPT_RESOURCE" -eq 1 ]; then yn_res="実施 (検出ブロック数: ${RES_COUNT})"; else yn_res="未実施"; fi
  if [ "$OPT_ESTIMATE" -eq 1 ]; then
    if [ -z "$EST_SKIP" ]; then yn_est="実施 / 基準環境 ${EST_REF_PATH} の実測値 (推測ファイル数: ${EST_COUNT})"
    else yn_est="実施を指定 (${EST_SKIP}ためスキップ)"; fi
  else
    yn_est="未実施"
  fi

  {
    printf '計測対象ディレクトリ\t%s\n' "$ROOT_ABS"
    printf '計測日時\t%s\n' "$RUN_AT"
    printf '対象拡張子\t%s\n' "$OPT_EXTS"
    printf '除外ディレクトリ\t%s\n' "$OPT_EXCLUDE_DIRS"
    printf '空白行の扱い\t%s\n' "$yn_blank"
    printf 'コメント行の扱い\t%s\n' "$yn_comment"
    printf 'シェバン行の扱い\t%s\n' "$yn_sheb"
    printf 'Terraform リソース単位計測\t%s\n' "$yn_res"
    printf '推測計測\t%s\n' "$yn_est"
    if [ "$OPT_ESTIMATE" -eq 1 ] && [ -z "$EST_SKIP" ]; then
      printf '推測の判定\t%s\n' "${EST_DETAIL:-(比較する環境なし)}"
      printf '推測の対象外\t%s\n' "${OPT_EST_EXCLUDE:+${OPT_EST_EXCLUDE} 配下 / }${EST_DIR} 以外の環境ディレクトリ"
    fi
    printf '環境ディレクトリ\t%s\n' "${ENV_FOUND:-(該当なし)}"
    printf '有効ステップ数の定義\t%s\n' "$EFF_DEF"
    printf '生成ツール\t%s\n' "$SCRIPT_NAME $SCRIPT_VERSION"
  } > "$F_META"

  : > "$F_KPI"
  if [ "$OPT_SUMMARY_ALL" -eq 1 ]; then
    {
      printf '有効ステップ数\t%s\n'        "$(get_total '有効ステップ数')"
      printf '対象ファイル数\t%s\n'        "$(get_total '対象ファイル数')"
      printf '総行数\t%s\n'                "$(get_total '総行数')"
      printf '推測ファイル数\t%s\n'        "$(get_total '推測ファイル数')"
      printf 'Terraformブロック数\t%s\n'   "$(get_total 'Terraformブロック数')"
    } >> "$F_KPI"
  fi
}

output_xlsx() {
  [ "$OPT_EXCEL" -eq 1 ] || return 0
  log_step "Excel (.xlsx) を出力しています"
  build_meta_kpi

  local showmat=0
  head -n 1 "$F_MATRIX" > "$WORK/mat_hdr.txt"
  tail -n +2 "$F_MATRIX" > "$F_MAT_BODY"
  [ -s "$F_MAT_BODY" ] && [ -n "$ENV_FOUND" ] && showmat=1
  MAT_HDR="$(cat "$WORK/mat_hdr.txt")"

  local -a sheets=()

  awk -v TITLE="ステップ数 計測レポート" \
      -v SUBTITLE="対象: ${ROOT_ABS}    計測日時: ${RUN_AT}    ${EFF_DEF}" \
      -v METAF="$F_META" -v KPIF="$F_KPI" \
      -v EXTF="$F_SUM_EXT" -v ENVF="$F_SUM_ENV" -v MATF="$F_MAT_BODY" \
      -v EXTHDR="$HDR_SUM" -v ENVHDR="$HDR_SUMENV" -v MATHDR="$MAT_HDR" \
      -v SHOWEXT="$OPT_SUMMARY_EXT" \
      -v SHOWENV="$( [ -n "$ENV_FOUND" ] && echo 1 || echo 0 )" \
      -v SHOWMAT="$showmat" \
      -f "$AWK_DASH" < /dev/null > "$WORK/sheet1.xml" || die "サマリシートの生成に失敗しました"
  sheets+=( "サマリ" "$WORK/sheet1.xml" )

  awk -v TITLE="ファイル別 ステップ数" \
      -v SUBTITLE="${EFF_DEF}    斜体グレーの行は他環境からの推測値です" \
      -v HEADERS="$HDR_FILES" -v CLASSES="ssccnnnnns" \
      -v WIDTHS="10,58,9,9,11,11,12,11,14,70" \
      -v ESTCOL=4 -v ALLEST=0 \
      -v TOTALCOLS="5,6,7,8,9" -v TOTALLABEL="合計" -v BARCOL=9 \
      -f "$AWK_SHEET" "$V_FILES" > "$WORK/sheet2.xml" || die "ファイル別シートの生成に失敗しました"
  sheets+=( "ファイル別" "$WORK/sheet2.xml" )

  if [ -s "$V_RES" ]; then
    awk -v TITLE="Terraform リソース(ブロック)別 ステップ数" \
        -v SUBTITLE="${EFF_DEF}    ブロック直前の連続コメントは当該ブロックに含めています" \
        -v HEADERS="$HDR_RES" -v CLASSES="sscssnnnnnnn" \
        -v WIDTHS="10,46,14,26,22,9,9,10,11,12,11,14" \
        -v ESTCOL=0 -v ALLEST=0 \
        -v TOTALCOLS="8,9,10,11,12" -v TOTALLABEL="合計" -v BARCOL=12 \
        -f "$AWK_SHEET" "$V_RES" > "$WORK/sheet3.xml" || die "リソース別シートの生成に失敗しました"
    sheets+=( "Terraformリソース別" "$WORK/sheet3.xml" )
  fi

  if [ -s "$V_EST" ]; then
    awk -v TITLE="推測計測 明細 (未配置ファイル)" \
        -v SUBTITLE="${EST_DIR} 配下でファイル数が ${OPT_EST_REF} より少ない環境について、${OPT_EST_REF} にのみ存在するファイルを ${OPT_EST_REF} の実測値で推測しています" \
        -v HEADERS="$HDR_EST" -v CLASSES="sscnnnnncs" \
        -v WIDTHS="10,58,9,11,11,12,11,14,14,70" \
        -v ESTCOL=0 -v ALLEST=1 \
        -v TOTALCOLS="4,5,6,7,8" -v TOTALLABEL="合計" -v BARCOL=8 \
        -f "$AWK_SHEET" "$V_EST" > "$WORK/sheet4.xml" || die "推測明細シートの生成に失敗しました"
    sheets+=( "推測明細" "$WORK/sheet4.xml" )
  fi

  xlsx_package "${OUT_BASE}.xlsx" "${sheets[@]}"
  OUT_LIST="${OUT_LIST}${OUT_BASE}.xlsx"$'\n'
}

#===============================================================================
# 結果表示
#===============================================================================
print_summary() {
  [ "$OPT_QUIET" -eq 1 ] && return 0
  local bar="--------------------------------------------------------------------------"
  printf '\n%s\n' "$bar"
  printf ' ステップ数 計測結果\n'
  printf '%s\n' "$bar"
  printf ' 対象ディレクトリ : %s\n' "$ROOT_ABS"
  printf ' 計測条件         : %s\n' "$EFF_DEF"
  printf ' 環境ディレクトリ : %s\n' "${ENV_FOUND:-(該当なし)}"
  printf '%s\n' "$bar"
  awk -F'\t' '{ printf " %-24s : %12s\n", $1, $2 }' "$F_SUM_TOTAL"
  if [ "$OPT_SUMMARY_EXT" -eq 1 ]; then
    printf '%s\n' "$bar"
    printf ' [拡張子別]\n'
    awk -F'\t' '{ printf " %-14s  ファイル %6s   総行 %9s   有効ステップ %9s\n", $1, $2, $3, $7 }' "$F_SUM_EXT"
  fi
  if [ -n "$ENV_FOUND" ]; then
    printf '%s\n' "$bar"
    printf ' [環境別]\n'
    awk -F'\t' '{ printf " %-14s  ファイル %6s   総行 %9s   有効ステップ %9s\n", $1, $2, $3, $7 }' "$F_SUM_ENV"
  fi
  printf '%s\n' "$bar"
  printf ' [出力ファイル]\n'
  printf '%s' "$OUT_LIST" | while IFS= read -r f; do [ -n "$f" ] && printf '   %s\n' "$f"; done
  printf '%s\n\n' "$bar"
}

#===============================================================================
# メイン
#===============================================================================
setup_workspace() {
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/step_count.XXXXXXXX")" || die "作業ディレクトリを作成できません"
  log_debug "作業ディレクトリ: $WORK"

  AWK_COUNTER="$WORK/counter.awk"
  AWK_EST="$WORK/estimate.awk"
  AWK_AGG="$WORK/aggregate.awk"
  AWK_SHEET="$WORK/sheet.awk"
  AWK_DASH="$WORK/dashboard.awk"
  write_awk_counter   "$AWK_COUNTER"
  write_awk_estimate  "$AWK_EST"
  write_awk_aggregate "$AWK_AGG"
  write_awk_sheet     "$AWK_SHEET"
  write_awk_dashboard "$AWK_DASH"

  F_FILES="$WORK/files.tsv"
  F_RES="$WORK/resources.tsv"
  F_SUM_EXT="$WORK/sum_ext.tsv"
  F_SUM_ENV="$WORK/sum_env.tsv"
  F_SUM_TOTAL="$WORK/sum_total.tsv"
  F_MATRIX="$WORK/matrix.tsv"
  F_MAT_BODY="$WORK/matrix_body.tsv"
  F_META="$WORK/meta.tsv"
  F_KPI="$WORK/kpi.tsv"
  V_FILES="$WORK/view_files.tsv"
  V_RES="$WORK/view_res.tsv"
  V_EST="$WORK/view_est.tsv"
  MAT_HDR=""

  HDR_FILES=$'環境\tファイルパス\t拡張子\t区分\t総行数\t空白行数\tコメント行数\tコード行数\t有効ステップ数\t推測根拠'
  HDR_RES=$'環境\tファイルパス\tブロック種別\tラベル1\tラベル2\t開始行\t終了行\t総行数\t空白行数\tコメント行数\tコード行数\t有効ステップ数'
  HDR_EST=$'環境\tファイルパス\t拡張子\t総行数\t空白行数\tコメント行数\tコード行数\t有効ステップ数\t推測方法\t推測根拠'
  HDR_SUM=$'拡張子\tファイル数\t総行数\t空白行数\tコメント行数\tコード行数\t有効ステップ数\t構成比\t推測ファイル数\t推測ステップ数'
  HDR_SUMENV=$'環境\tファイル数\t総行数\t空白行数\tコメント行数\tコード行数\t有効ステップ数\t構成比\t推測ファイル数\t推測ステップ数'

  EST_METHOD_LABEL="${OPT_EST_REF} の実測値"

  if   [ "$OPT_EXCLUDE_BLANK" -eq 1 ] && [ "$OPT_EXCLUDE_COMMENT" -eq 1 ]; then
    EFF_DEF="有効ステップ = 総行数 - 空白行 - コメント行"
  elif [ "$OPT_EXCLUDE_BLANK" -eq 1 ]; then
    EFF_DEF="有効ステップ = 総行数 - 空白行"
  elif [ "$OPT_EXCLUDE_COMMENT" -eq 1 ]; then
    EFF_DEF="有効ステップ = 総行数 - コメント行"
  else
    EFF_DEF="有効ステップ = 総行数 (空白行・コメント行を含む)"
  fi

  if [ "$OPT_TIMESTAMP" -eq 1 ]; then
    OUT_BASE="${OUT_ABS}/${OPT_PREFIX}_${RUN_STAMP}"
  else
    OUT_BASE="${OUT_ABS}/${OPT_PREFIX}"
  fi
  OUT_LIST=""
  FILE_COUNT=0
}

split_matrix() {
  head -n 1 "$F_MATRIX" > "$WORK/mat_hdr.txt"
  tail -n +2 "$F_MATRIX" > "$F_MAT_BODY"
  MAT_HDR="$(cat "$WORK/mat_hdr.txt")"
}

main() {
  parse_args "$@"
  validate_args
  check_prereq
  setup_workspace

  log_step "対象ディレクトリを走査しています: $ROOT_ABS"
  detect_envs
  discover_files

  log_step "ステップ数を計測しています"
  count_files
  estimate_files
  collect_envs_found
  sort_records

  log_step "集計しています"
  aggregate
  split_matrix
  build_views

  output_csv
  output_xlsx

  log_ok "完了しました"
  print_summary
}

main "$@"
