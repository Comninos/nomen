#!/usr/bin/env bash
# nomen: bring filenames into nomenclature. Form, not meaning.
# No config, no flag farm. Edit this file; prompts on a tty.
#
# APPLY=1  also rename when stdout is not a tty (default: print plan only)

APPLY="${APPLY:-0}"
BATCH_PAD=3
# Colour: auto | always | never  (also respects NO_COLOR)
COLOR="${COLOR:-auto}"

set -euo pipefail

die() { printf 'nomen: %s\n' "$*" >&2; exit 1; }
warn() { printf 'nomen: %s\n' "$*" >&2; }

# --- colour (zero deps; ANSI only when the terminal can use it) ------------
use_color=0
case "$COLOR" in
    always) use_color=1 ;;
    never) use_color=0 ;;
    *)
        if [[ -z "${NO_COLOR:-}" && -t 1 && "${TERM:-}" != "dumb" ]]; then
            use_color=1
        fi
        ;;
esac

if ((use_color)); then
    C_RESET=$'\033[0m'
    C_DIM=$'\033[2m'
    C_BOLD=$'\033[1m'
    C_RED=$'\033[31m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_CYAN=$'\033[36m'
    C_FRAME=$'\033[2m'   # dim chrome
else
    C_RESET="" C_DIM="" C_BOLD="" C_RED="" C_GREEN="" C_YELLOW="" C_CYAN="" C_FRAME=""
fi


# Interactive when we can talk on /dev/tty and stdout is a terminal.
# Stdin may be redirected; prompts always read /dev/tty.
can_prompt() { [[ -r /dev/tty && -w /dev/tty ]]; }
is_interactive() { can_prompt && [[ -t 1 ]]; }

ask_yn() {
    local q="$1" default="${2:-n}" ans prompt
    if [[ "$default" == "y" ]]; then prompt="[Y/n]"; else prompt="[y/N]"; fi
    if ! can_prompt; then
        [[ "$default" == "y" ]]
        return
    fi
    printf '%s %s ' "$q" "$prompt" >/dev/tty
    # shellcheck disable=SC2162
    read -r ans </dev/tty || ans=""
    ans="${ans:-$default}"
    case "$ans" in
        y|Y|yes|YES) return 0 ;;
        *) return 1 ;;
    esac
}

# --- grammar helpers -------------------------------------------------------

# Strip diacritics to ASCII before kebab cleanup (iconv when available).
ascii_fold() {
    local s="$1" out
    if command -v iconv >/dev/null 2>&1; then
        out=$(printf '%s' "$s" | iconv -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null) || out="$s"
        out=$(printf '%s' "$out" | sed "s/[']//g")
        s="$out"
    fi
    printf '%s' "$s"
}

is_date_seg() {
    local s="$1" y m d
    case "$s" in
        ''|*[!0-9]*) return 1 ;;
    esac
    case ${#s} in
        2) return 0 ;;
        4)
            m="${s:2:2}"
            ((10#$m >= 1 && 10#$m <= 12))
            ;;
        6)
            m="${s:2:2}"
            d="${s:4:2}"
            ((10#$m >= 1 && 10#$m <= 12 && 10#$d >= 1 && 10#$d <= 31))
            ;;
        *) return 1 ;;
    esac
}

is_yyyymmdd_glued() {
    local s="$1" m d
    [[ ${#s} -eq 8 && "$s" =~ ^[0-9]{8}$ ]] || return 1
    m="${s:4:2}"
    d="${s:6:2}"
    ((10#$m >= 1 && 10#$m <= 12 && 10#$d >= 1 && 10#$d <= 31))
}

compact_from_yyyymmdd() {
    local s="$1"
    printf '%s%s%s' "${s:2:2}" "${s:4:2}" "${s:6:2}"
}

# Split glued date prefix (260812taxes, 20240101notes) or version suffix (reportv01).
split_glued_date_prefix() {
    local seg="$1" len rest prefix compact
    for len in 8 6 4 2; do
        ((${#seg} <= len)) && continue
        prefix="${seg:0:len}"
        rest="${seg:len}"
        [[ "$rest" =~ ^[a-z] ]] || continue
        case "$len" in
            8)
                if is_yyyymmdd_glued "$prefix"; then
                    compact=$(compact_from_yyyymmdd "$prefix")
                    printf '%s-%s' "$compact" "$rest"
                    return
                fi
                ;;
            *)
                if is_date_seg "$prefix"; then
                    printf '%s-%s' "$prefix" "$rest"
                    return
                fi
                ;;
        esac
    done
    printf '%s' "$seg"
}

split_glued_version_suffix() {
    local seg="$1" body ver
    if [[ "$seg" =~ ^(.+)(v[0-9]+([.][0-9]+)*)$ ]]; then
        body="${BASH_REMATCH[1]}"
        ver="${BASH_REMATCH[2]}"
        if [[ -n "$body" ]] && is_version_seg "$ver"; then
            printf '%s-%s' "$body" "$ver"
            return
        fi
    fi
    printf '%s' "$seg"
}

is_version_seg() {
    local s="$1"
    [[ "$s" =~ ^v[0-9]+([.][0-9]+)*$ ]]
}

is_batch_seg() {
    local s="$1"
    [[ "$s" =~ ^[0-9]+$ ]]
}

pad_batch() {
    local s="$1" n
    # Keep width when already >= BATCH_PAD digits; only pad shorter runs.
    if ((${#s} >= BATCH_PAD)); then
        printf '%s' "$s"
        return
    fi
    n=$((10#$s))
    printf "%0${BATCH_PAD}d" "$n"
}

# Split basename into stem + extension (compound .tar.* kept; else last .ext).
split_base() {
    local base="$1" lower len
    lower=$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')
    case "$lower" in
        *.tar.gz) len=7 ;;
        *.tar.bz2) len=8 ;;
        *.tar.xz) len=7 ;;
        *)
            if [[ "$base" =~ ^(.+)\.([^.]+)$ ]]; then
                _stem="${BASH_REMATCH[1]}"
                _ext="${BASH_REMATCH[2]}"
            else
                _stem="$base"
                _ext=""
            fi
            return
            ;;
    esac
    _stem="${base:0:$((${#base} - len))}"
    _ext="${base:$((${#base} - len + 1))}"
}

# Camel/digit boundaries → hyphens, then kebab cleanup.
kebab_raw() {
    local s="$1"
    s=$(ascii_fold "$s")
    # fooBar → foo-Bar; foo2Bar kept simple via later lower+strip
    s=$(printf '%s' "$s" | sed -E \
        -e 's/([a-z])([A-Z])/\1-\2/g' \
        -e 's/([A-Z]+)([A-Z][a-z])/\1-\2/g')
    s="${s// /_}"
    s="${s//_/-}"
    s=$(printf '%s' "$s" | tr '[:upper:]' '[:lower:]')
    # keep letters, digits, hyphens, dots (dots for version tokens)
    s=$(printf '%s' "$s" | sed -E 's/[^a-z0-9.-]+/-/g')
    # dots that are not part of a version get flattened later; collapse hyphens
    s=$(printf '%s' "$s" | sed -E 's/-+/-/g; s/^\-//; s/\-$//')
    printf '%s' "$s"
}

# Normalize stem to canonical nomenclature (no extension).
normalize_stem() {
    local raw="$1" keb date="" suffix="" n seg out _b iso_y iso_m iso_d split
    local -a parts=() clean=() terms=() _bits=() unglued=()

    keb=$(kebab_raw "$raw")
    [[ -n "$keb" ]] || { printf ''; return; }

    IFS='-' read -r -a parts <<<"$keb"

    for seg in "${parts[@]}"; do
        [[ -n "$seg" ]] || continue
        seg=$(split_glued_date_prefix "$seg")
        seg=$(split_glued_version_suffix "$seg")
        IFS='-' read -r -a _bits <<<"$seg"
        for _b in "${_bits[@]}"; do
            [[ -n "$_b" ]] && unglued+=("$_b")
        done
    done
    parts=("${unglued[@]}")
    n=${#parts[@]}
    (( n > 0 )) || { printf ''; return; }

    # ISO date at front: YYYY-MM-DD or YYYY-MM (needs at least one term after)
    if (( n >= 4 )) \
        && [[ "${parts[0]}" =~ ^[0-9]{4}$ && "${parts[1]}" =~ ^[0-9]{2}$ && "${parts[2]}" =~ ^[0-9]{2}$ ]]; then
        iso_y="${parts[0]}"
        iso_m="${parts[1]}"
        iso_d="${parts[2]}"
        if ((10#$iso_m >= 1 && 10#$iso_m <= 12 && 10#$iso_d >= 1 && 10#$iso_d <= 31)); then
            date="${iso_y: -2}${iso_m}${iso_d}"
            parts=("${parts[@]:3}")
            n=${#parts[@]}
        fi
    elif (( n >= 3 )) \
        && [[ "${parts[0]}" =~ ^[0-9]{4}$ && "${parts[1]}" =~ ^[0-9]{2}$ ]]; then
        iso_y="${parts[0]}"
        iso_m="${parts[1]}"
        if ((10#$iso_m >= 1 && 10#$iso_m <= 12)); then
            date="${iso_y: -2}${iso_m}"
            parts=("${parts[@]:2}")
            n=${#parts[@]}
        fi
    fi

    # Compact date token (YY / YYMM / YYMMDD / glued YYYYMMDD → compact)
    if (( n >= 2 )); then
        seg="${parts[0]}"
        if [[ ${#seg} -eq 8 && "$seg" =~ ^[0-9]{8}$ ]] && is_yyyymmdd_glued "$seg"; then
            date=$(compact_from_yyyymmdd "$seg")
            parts=("${parts[@]:1}")
            n=${#parts[@]}
        elif is_date_seg "$seg"; then
            date="$seg"
            parts=("${parts[@]:1}")
            n=${#parts[@]}
        fi
    fi

    # Trailing suffix only if at least one term remains before it
    if (( n >= 2 )); then
        seg="${parts[n-1]}"
        if is_version_seg "$seg"; then
            suffix="$seg"
            parts=("${parts[@]:0:n-1}")
        elif is_batch_seg "$seg"; then
            suffix=$(pad_batch "$seg")
            parts=("${parts[@]:0:n-1}")
        fi
    fi

    # Remaining parts are terms; flatten internal dots unless version-shaped
    for seg in "${parts[@]}"; do
        if ! is_version_seg "$seg"; then
            seg="${seg//./-}"
        fi
        seg=$(printf '%s' "$seg" | sed -E 's/-+/-/g; s/^\-//; s/\-$//')
        if [[ -n "$seg" ]]; then
            IFS='-' read -r -a _bits <<<"$seg"
            for _b in "${_bits[@]}"; do
                [[ -n "$_b" ]] && terms+=("$_b")
            done
        fi
    done

    if ((${#terms[@]} == 0)); then
        # Nothing left to be a term; fall back to kebab without suffix/date peel
        printf '%s' "$keb"
        return
    fi

    out=""
    [[ -n "$date" ]] && out="$date"
    for seg in "${terms[@]}"; do
        if [[ -n "$out" ]]; then out+="-"; fi
        out+="$seg"
    done
    [[ -n "$suffix" ]] && out+="-$suffix"
    printf '%s' "$out"
}

normalize_basename() {
    local base="$1"
    split_base "$base"
    local ns
    ns=$(normalize_stem "$_stem")
    if [[ -z "$ns" ]]; then
        printf '%s' "$base"
        return
    fi
    if [[ -n "$_ext" ]]; then
        printf '%s.%s' "$ns" "$_ext"
    else
        printf '%s' "$ns"
    fi
}

is_conforming() {
    local base="$1" norm
    norm=$(normalize_basename "$base")
    [[ "$base" == "$norm" ]]
}

# --- collect paths ---------------------------------------------------------

declare -a FILES=()
declare -A SEEN=()

add_file() {
    local f="$1" abs
    [[ -f "$f" ]] || return 0
    if command -v realpath >/dev/null 2>&1; then
        abs=$(realpath "$f")
    else
        abs=$(readlink -f "$f" 2>/dev/null || true)
        if [[ -z "$abs" ]]; then
            abs="$(cd "$(dirname "$f")" && pwd)/$(basename "$f")"
        fi
    fi
    [[ -n "${SEEN[$abs]:-}" ]] && return 0
    SEEN[$abs]=1
    FILES+=("$abs")
}

collect_dir() {
    local dir="$1" recursive="$2" f
    if [[ "$recursive" == "1" ]]; then
        while IFS= read -r -d '' f; do
            add_file "$f"
        done < <(find "$dir" -type f -print0 2>/dev/null)
    else
        for f in "$dir"/* "$dir"/.[!.]* "$dir"/..?*; do
            [[ -e "$f" ]] || continue
            [[ -f "$f" ]] && add_file "$f"
        done
    fi
}

usage() {
    cat <<'EOF'
Usage: nomen [path...]

Bring filenames into nomenclature (kebab form). Does not invent better names.

  [date-]term(-term)*[-vN|NNN].ext

Date is optional (YY / YYMM / YYMMDD). Version or batch suffix normalized when
present. Already-good names are skipped. Directories: one recurse prompt.

No flags. On a tty: print plan, confirm, rename. Non-tty: print plan only
(unless APPLY=1). Colour: COLOR=auto|always|never (respects NO_COLOR).
EOF
}

# --- main ------------------------------------------------------------------

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

if [[ $# -eq 0 ]]; then
    set -- .
fi

declare -a DIR_ARGS=()
declare -a FILE_ARGS=()

for arg in "$@"; do
    if [[ -d "$arg" ]]; then
        DIR_ARGS+=("$arg")
    elif [[ -f "$arg" ]]; then
        FILE_ARGS+=("$arg")
    else
        die "not a file or directory: $arg"
    fi
done

RECURSIVE=0
if ((${#DIR_ARGS[@]} > 0)); then
    if is_interactive; then
        if ask_yn "Recurse into directories?" n; then
            RECURSIVE=1
        fi
    fi
fi

for f in "${FILE_ARGS[@]+"${FILE_ARGS[@]}"}"; do
    add_file "$f"
done
for d in "${DIR_ARGS[@]+"${DIR_ARGS[@]}"}"; do
    collect_dir "$d" "$RECURSIVE"
done

if ((${#FILES[@]} == 0)); then
    die "no files found"
fi

# Build plan
declare -a PLAN_FROM=()
declare -a PLAN_TO=()
declare -a PLAN_DIR=()
SKIP=0
FAIL=0
declare -a FAIL_MSG=()

# Track targets within this run to catch collisions
declare -A TARGET_OWNER=()

for abs in "${FILES[@]}"; do
    dir=$(dirname "$abs")
    base=$(basename "$abs")
    if is_conforming "$base"; then
        SKIP=$((SKIP + 1))
        continue
    fi
    new=$(normalize_basename "$base")
    if [[ -z "$new" || "$new" == "$base" ]]; then
        SKIP=$((SKIP + 1))
        continue
    fi
    target="$dir/$new"

    if [[ -e "$target" && "$target" != "$abs" ]]; then
        FAIL=$((FAIL + 1))
        FAIL_MSG+=("$base → $new (target exists)")
        continue
    fi
    if [[ -n "${TARGET_OWNER[$target]:-}" ]]; then
        FAIL=$((FAIL + 1))
        FAIL_MSG+=("$base → $new (collides with ${TARGET_OWNER[$target]})")
        continue
    fi
    TARGET_OWNER[$target]="$base"
    PLAN_FROM+=("$base")
    PLAN_TO+=("$new")
    PLAN_DIR+=("$dir")
done

N=${#PLAN_FROM[@]}

# --- print (the product) ---------------------------------------------------

# Row body between box walls: " %-*s → %-*s " → width w_from+w_to+5
w_from=4
w_to=2
for ((i = 0; i < N; i++)); do
    ((${#PLAN_FROM[i]} > w_from)) && w_from=${#PLAN_FROM[i]}
    ((${#PLAN_TO[i]} > w_to)) && w_to=${#PLAN_TO[i]}
done
((w_from > 48)) && w_from=48
((w_to > 48)) && w_to=48

inner=$((w_from + w_to + 5))
# Visible (no ANSI) summary for width math
summary_plain=$(printf '%d rename | %d skip | %d fail' "$N" "$SKIP" "$FAIL")
((${#summary_plain} + 2 > inner)) && inner=$((${#summary_plain} + 2))
((inner < 36)) && inner=36

extra=$((inner - 5 - w_from - w_to))
if ((extra > 0)); then
    w_to=$((w_to + extra))
fi

# Coloured summary; pad to inner-2 using plain length
summary_color=$(printf '%s%d%s rename | %s%d%s skip | %s%d%s fail' \
    "$C_GREEN" "$N" "$C_RESET" \
    "$C_DIM" "$SKIP" "$C_RESET" \
    "$C_RED" "$FAIL" "$C_RESET")
sum_pad=$((inner - 2 - ${#summary_plain}))
((sum_pad < 0)) && sum_pad=0
summary_line="${summary_color}$(printf '%*s' "$sum_pad" '')"

hrule() {
    local i
    printf '%s%s' "$C_FRAME" "$1"
    for ((i = 0; i < inner; i++)); do printf '─'; done
    printf '%s%s\n' "$2" "$C_RESET"
}

title=" nomen "
tlen=${#title}
if ((tlen >= inner)); then
    hrule "┌" "┐"
else
    left=$(( (inner - tlen) / 2 ))
    right=$((inner - tlen - left))
    printf '%s┌' "$C_FRAME"
    for ((i = 0; i < left; i++)); do printf '─'; done
    printf '%s%s%s%s' "$C_RESET" "$C_BOLD" "$title" "$C_RESET"
    printf '%s' "$C_FRAME"
    for ((i = 0; i < right; i++)); do printf '─'; done
    printf '┐%s\n' "$C_RESET"
fi

if ((N == 0)); then
    printf '%s│%s %s%-*s%s %s│%s\n' \
        "$C_FRAME" "$C_RESET" "$C_DIM" "$((inner - 2))" "(nothing to rename)" "$C_RESET" "$C_FRAME" "$C_RESET"
else
    for ((i = 0; i < N; i++)); do
        from="${PLAN_FROM[i]}"
        to="${PLAN_TO[i]}"
        ((${#from} > w_from)) && from="${from:0:$((w_from - 3))}..."
        ((${#to} > w_to)) && to="${to:0:$((w_to - 3))}..."
        printf '%s│%s %s%-*s%s %s→%s %s%-*s%s %s│%s\n' \
            "$C_FRAME" "$C_RESET" \
            "$C_DIM" "$w_from" "$from" "$C_RESET" \
            "$C_FRAME" "$C_RESET" \
            "$C_CYAN" "$w_to" "$to" "$C_RESET" \
            "$C_FRAME" "$C_RESET"
    done
fi

hrule "├" "┤"
printf '%s│%s %s %s│%s\n' "$C_FRAME" "$C_RESET" "$summary_line" "$C_FRAME" "$C_RESET"
hrule "└" "┘"

if ((FAIL > 0)); then
    for m in "${FAIL_MSG[@]}"; do
        printf '%snomen: %s%s\n' "$C_RED" "$m" "$C_RESET" >&2
    done
fi

if ((N == 0)); then
    ((FAIL > 0)) && exit 1
    exit 0
fi

do_apply=0
if is_interactive; then
    if ask_yn "Apply renames?" n; then
        do_apply=1
    fi
elif [[ "$APPLY" == "1" ]]; then
    do_apply=1
fi

if ((do_apply == 0)); then
    exit 0
fi

renamed=0
for ((i = 0; i < N; i++)); do
    src="${PLAN_DIR[i]}/${PLAN_FROM[i]}"
    dst="${PLAN_DIR[i]}/${PLAN_TO[i]}"
    if [[ -e "$dst" && "$dst" != "$src" ]]; then
        warn "skip (exists): ${PLAN_FROM[i]} → ${PLAN_TO[i]}"
        FAIL=$((FAIL + 1))
        continue
    fi
    if ! mv -- "$src" "$dst"; then
        warn "failed: ${PLAN_FROM[i]} → ${PLAN_TO[i]}"
        FAIL=$((FAIL + 1))
        continue
    fi
    renamed=$((renamed + 1))
done

printf 'nomen: applied %d rename(s)\n' "$renamed"
((FAIL > 0)) && exit 1
exit 0
