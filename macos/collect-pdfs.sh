#!/usr/bin/env bash
set -euo pipefail

PROGRAM=${0##*/}
readonly PROGRAM

usage() {
  cat <<EOF_USAGE
Usage: $PROGRAM [OPTIONS]

Collect PDF files from one or more source roots and write them into a zip
archive while preserving their folder structure below each chosen root.

Options:
  -o, --output PATH   Write the zip archive to PATH
  -r, --root DIR      Add a root directory to scan (repeatable)
  -h, --help          Show this help

If no roots are supplied, the script scans \$HOME/Documents when it exists.
When one root is scanned, paths inside the archive are relative to that root.
When multiple roots are scanned, each root's basename is used as a prefix to
avoid collisions.
EOF_USAGE
}

die() {
  printf '%s: error: %s\n' "$PROGRAM" "$*" >&2
  exit 1
}

usage_error() {
  printf '%s: error: %s\n\n' "$PROGRAM" "$*" >&2
  usage >&2
  exit 2
}

canonical_dir() {
  local dir=$1

  [[ -d $dir ]] || return 1
  (cd -P -- "$dir" && pwd -P)
}

output=''
roots=()
tmpdir=''
archive_tmp=''
home_dir=${HOME:-}

cleanup() {
  local status=$?

  trap - EXIT

  if [[ -n ${archive_tmp:-} && -e $archive_tmp ]]; then
    rm -f -- "$archive_tmp" || {
      printf '%s: warning: failed to remove temporary archive: %s\n' \
        "$PROGRAM" "$archive_tmp" >&2
      ((status == 0)) && status=1
    }
  fi

  if [[ -n ${tmpdir:-} && -d $tmpdir ]]; then
    rm -rf -- "$tmpdir" || {
      printf '%s: warning: failed to remove temporary directory: %s\n' \
        "$PROGRAM" "$tmpdir" >&2
      ((status == 0)) && status=1
    }
  fi

  exit "$status"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

while (($#)); do
  case $1 in
    -o|--output)
      (($# >= 2)) || usage_error "missing value for $1"
      output=$2
      shift 2
      ;;
    --output=*)
      output=${1#*=}
      [[ -n $output ]] || usage_error "--output requires a value"
      shift
      ;;
    -r|--root)
      (($# >= 2)) || usage_error "missing value for $1"
      roots+=("$2")
      shift 2
      ;;
    --root=*)
      root_value=${1#*=}
      [[ -n $root_value ]] || usage_error "--root requires a value"
      roots+=("$root_value")
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      usage_error "unknown option: $1"
      ;;
    *)
      usage_error "unexpected positional argument: $1"
      ;;
  esac
done

if (($# > 0)); then
  usage_error "unexpected positional arguments: $*"
fi

if ((${#roots[@]} == 0)); then
  [[ -n $home_dir ]] || die "HOME is not set"

  if [[ -d $home_dir/Documents ]]; then
    roots=("$home_dir/Documents")
  else
    die "no roots supplied and $home_dir/Documents does not exist"
  fi
fi

if [[ -z $output ]]; then
  output="college-pdfs-$(date +%Y%m%d-%H%M%S).zip"
fi

output_dir=$(dirname -- "$output")
output_base=$(basename -- "$output")

[[ -n $output_base ]] || usage_error "output path is invalid: $output"

if output_dir_abs=$(canonical_dir "$output_dir" 2>/dev/null); then
  :
else
  mkdir -p -- "$output_dir" || die "failed to create output directory: $output_dir"
  output_dir_abs=$(canonical_dir "$output_dir") || die "failed to resolve output directory: $output_dir"
fi

output_abs=$output_dir_abs/$output_base

archive_tmp=$(mktemp "$output_dir_abs/.${output_base}.XXXXXX") ||
  die "failed to create temporary archive placeholder"

tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/${PROGRAM}.XXXXXXXX") ||
  die "failed to create temporary directory"

command -v zip >/dev/null 2>&1 || die "zip command not found"

if [[ $output_abs == / || $output_abs == . || $output_abs == .. ]]; then
  die "refusing unsafe output path: $output_abs"
fi

staging="$tmpdir/staging"
mkdir -p -- "$staging"

single_root=0
if ((${#roots[@]} == 1)); then
  single_root=1
fi

found=0
copied=0

for root in "${roots[@]}"; do
  root_real=$(canonical_dir "$root") || {
    printf '%s: warning: skipping missing root: %s\n' "$PROGRAM" "$root" >&2
    continue
  }

  found=1
  root_label=$(basename -- "$root_real")

  while IFS= read -r -d '' file; do
    rel=${file#"$root_real"/}
    if ((single_root == 0)); then
      rel=$root_label/$rel
    fi

    dest=$staging/$rel
    mkdir -p -- "$(dirname -- "$dest")"
    cp -p -- "$file" "$dest"
    ((copied++))
  done < <(find "$root_real" -type f -iname '*.pdf' -print0)
done

if ((found == 0)); then
  die "none of the requested roots exist"
fi

if ((copied == 0)); then
  die "no PDF files found"
fi

(
  cd -- "$staging"
  find . -type f -exec zip -q -X "$archive_tmp" {} +
)

mv -f -- "$archive_tmp" "$output_abs"
archive_tmp=''

if ((copied == 1)); then
  printf '%s: wrote %s (%d PDF file)\n' "$PROGRAM" "$output_abs" "$copied"
else
  printf '%s: wrote %s (%d PDF files)\n' "$PROGRAM" "$output_abs" "$copied"
fi
