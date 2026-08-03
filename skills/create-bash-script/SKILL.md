---
name: create-bash-script
description: Write, review, debug, harden, and refactor Bash scripts for both personal use and reliable unattended automation. Use for .sh files, shell snippets, CI/CD steps, cron jobs, deployment or maintenance scripts, command-line parsing, safe file processing, portability checks, ShellCheck fixes, and destructive-operation reviews. Favor explicit failure, secure quoting, predictable cleanup, guarded side effects, and readable code. Use POSIX sh instead only when the user explicitly requires POSIX portability.
---

# Create Bash Script

Produce Bash that can run unattended, fail loudly, handle hostile edge cases, and remain readable months later.

## Workflow

1. Identify the execution contract: Bash version, Linux or macOS, inputs, outputs, side effects, and allowed dependencies. Ask only when the answer materially changes the implementation; otherwise state a narrow assumption.
2. Classify risk. Treat deletion, privilege changes, remote execution, credential handling, package changes, and writes outside a temporary or work directory as high risk.
3. Write or revise the script using the rules and patterns below.
4. Validate before presenting or running:
   - `bash -n script.sh`
   - `shellcheck script.sh` when available
   - focused tests for success, invalid usage, missing input, empty values, pathnames with spaces or leading dashes, failed pipelines, and interrupted cleanup
5. Report assumptions, dependencies, validation performed, and remaining platform-specific behavior.

## Baseline

Start full Bash scripts with:

```bash
#!/usr/bin/env bash
# Description: Process input files and write the transformed output.
set -euo pipefail
```

Document every full script directly below the shebang:

- Add `# Description: <description>` as a single comment line containing a concise one-to-three-sentence description of what the script does.
- If the script depends on externally installed tools, add `# Requirements: <requirements>` immediately below the description. List requirements as comma-separated names, including versions when required or known, for example `# Requirements: Node v24.18.0, jq`.
- Omit `# Requirements:` when the script needs no externally installed tools.

Treat `set -e` as a backstop, not exception handling. It is suppressed in conditional contexts and has edge cases in functions, subshells, command substitutions, and boolean lists. Handle expected failures explicitly:

```bash
if ! output=$(command); then
  die "command failed"
fi
```

Do not hide failures with unexplained `|| true`. Check and document the exact statuses that are safe to ignore.

Avoid global `IFS=$'\n\t'` by default. Careful quoting plus local `IFS=` on reads is easier to reason about.

## Required Defaults

- Quote expansions: `"$var"`, `"${array[@]}"`. Leave an expansion unquoted only for intentional, explained splitting or pattern matching.
- Use `[[ ... ]]` for Bash tests and `(( ... ))` for arithmetic.
- Declare function variables with `local`; declare fixed configuration with `readonly`.
- Use `printf`, not `echo`, for diagnostics and data whose content is not fully controlled.
- Send errors to stderr. Use exit code `2` for invalid usage, `1` for runtime failure, and `0` for success.
- Validate option values before reading `$2`; reject unknown flags and unexpected positional arguments.
- Read text with `while IFS= read -r`; process arbitrary pathnames with NUL delimiters.
- Never parse `ls`. Use globs, `find -print0`, arrays, or process substitution.
- Create temporary resources with `mktemp`; install cleanup immediately; preserve the original exit status during cleanup.
- Put `--` before user-controlled path operands when the command supports it.
- Reject empty, root-like, or out-of-scope targets before destructive operations.
- Never use `eval` or build shell source from untrusted data. Pass data as arguments, stdin, or files.
- Keep secrets out of command lines and traces. Disable tracing around secret handling.
- Prefer built-ins and parameter expansion when clearer, but do not trade readability for avoiding a small external command.

## Core Helpers

Use consistent diagnostics:

```bash
PROGRAM=${0##*/}

usage() {
  cat <<EOF_USAGE
Usage: $PROGRAM [OPTIONS] INPUT

Options:
  -o, --output PATH  Write output to PATH
  -v, --verbose      Enable verbose logging
  -h, --help         Show this help
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
```

Use `${value:-default}` for optional values. Use `${value:?message}` when unset or blank is invalid.

## Repository Organization

When adding a script to a mixed-purpose toolbox repository, organize by tool or domain rather than by implementation language. Keep repository metadata at the root and place each script with related commands:

```text
tool-name/
├── command.sh
├── lib/             # sourced implementation shared by this tool
└── tests/           # Bats or other behavior tests
```

- Use lowercase kebab-case for directories and executable script names.
- Keep a single self-contained command directly in its tool directory. Add `lib/` only when the tool has substantial internal logic or two real consumers need the same behavior; add `tests/` when repeatable behavior tests exist.
- Keep executable entry points thin: parse arguments, validate inputs, call domain functions, and translate failures into diagnostics and exit codes.
- Put sourced files under the nearest tool's `lib/`, not beside unrelated entry points. Make libraries safe to source: avoid top-level side effects, namespace public functions when collisions are plausible, use `return` instead of `exit`, and do not change caller shell options unexpectedly.
- Keep dependencies directed from entry points to libraries. Do not source entry points, create circular imports, or reach into another tool's private `lib/` directory.
- Create a repository-level shared library only after stable behavior is genuinely shared across tools. Give shared modules narrow purpose-based names; avoid catch-all files such as `utils.sh` or `common.sh`.
- Resolve paths relative to the script's own location when loading adjacent libraries; do not assume the caller's working directory.
- Keep configuration outside implementation logic. Accept it through explicit flags, documented environment variables, or tool-local configuration files, with precedence and defaults defined in one place.
- Follow the repository's established structure when it is already consistent. Do not reorganize unrelated scripts as a side effect of adding one command.

Prefer one readable script over premature decomposition. Split code when it creates a stable boundary, independent test surface, or real reuse—not merely to shorten the entry-point file.

## Safe Argument Parsing

Validate an option value before accessing it under `set -u`:

```bash
verbose=0
output=''

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
    -v|--verbose)
      verbose=1
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
      break
      ;;
  esac
done

(($# == 1)) || usage_error "expected exactly one INPUT"
input=$1
```

For a large or deeply nested CLI, recommend a language with a mature argument parser instead of extending an ad hoc Bash parser indefinitely.

## Input and Pathname Safety

Read lines exactly, including a final line without a newline:

```bash
while IFS= read -r line || [[ -n $line ]]; do
  process_line "$line"
done < "$file"
```

Use NUL delimiters for arbitrary pathnames:

```bash
files=()
while IFS= read -r -d '' path; do
  files+=("$path")
done < <(find "$root" -type f -print0)
```

Prefer process substitution over `find ... | while ...` when loop variables must survive, because a pipeline commonly runs the loop in a subshell.

Choose one glob policy per script:

```bash
shopt -s nullglob
for file in "$dir"/*.log; do
  process_file "$file"
done
```

Without `nullglob`, guard unmatched patterns with `[[ -e $file ]] || continue`.

Forward argument arrays with `"${args[@]}"`, never `$*`.

## Temporary Resources and Cleanup

Create temporary resources safely and install cleanup immediately:

```bash
tmpdir=''

tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/${PROGRAM}.XXXXXXXXXX")

cleanup() {
  local status=$?
  trap - EXIT

  if [[ -n ${tmpdir:-} && -d $tmpdir ]]; then
    if ! rm -rf -- "$tmpdir"; then
      printf '%s: warning: cleanup failed: %s\n' "$PROGRAM" "$tmpdir" >&2
      ((status == 0)) && status=1
    fi
  fi

  exit "$status"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
```

Make cleanup idempotent and safe after partial initialization. Do not attach the same cleanup function directly to `EXIT INT TERM`; that can run cleanup multiple times and obscure the signal-derived status.

## Destructive Operations

Before deletion, truncation, overwrite, permission change, or recursive copy:

1. Constrain or canonicalize the target when practical.
2. Reject empty values, `/`, `.`, `..`, and targets outside the permitted root.
3. Use `--` before path operands.
4. Prefer operating only inside a directory created or explicitly allowlisted by the script.
5. Add `--dry-run` for broad or user-selected changes.
6. Log the resolved target before mutation when appropriate for unattended operation.

Use resolved paths rather than a textual prefix check, which can be bypassed by `..` components or symlinks:

```bash
canonical_dir() {
  local dir=$1
  [[ -d $dir ]] || return 1
  (cd -P -- "$dir" && pwd -P)
}

safe_remove_tree() {
  local target=$1
  local allowed_root=$2
  local target_real
  local root_real

  [[ -n $target && $target != / && $target != . && $target != .. ]] ||
    die "refusing unsafe removal target"

  root_real=$(canonical_dir "$allowed_root") ||
    die "allowed root not found: $allowed_root"
  [[ $root_real != / ]] || die "refusing allowed root: /"

  target_real=$(canonical_dir "$target") ||
    die "directory not found: $target"

  [[ $target_real != / && $target_real != "$root_real" ]] ||
    die "refusing to remove root directory: $target_real"
  [[ $target_real == "$root_real"/* ]] ||
    die "target is outside allowed root: $target_real"

  rm -rf -- "$target_real"
}
```

This resolves ordinary traversal and symlink escapes, but Bash cannot eliminate every time-of-check/time-of-use race in a hostile, concurrently modified directory tree. For that threat model, use a language or helper with directory-file-descriptor APIs such as `openat`/`unlinkat`.

Do not rely on quoting alone to make destructive paths safe. Quoting prevents splitting and globbing; it does not validate intent.

## Security Boundaries

Never evaluate external data as code:

```bash
# Unsafe:
# eval "$user_text"
# bash -c "command $user_text"

# Safe: pass data to a fixed command; do not treat it as the command name.
printf '%s\n' "$user_text"
```

For remote execution, avoid interpolating data into a remote command string. Pass arguments to a fixed script or send a fixed script over stdin:

```bash
ssh -- "$host" bash -s -- "$arg" <<'REMOTE'
set -euo pipefail
arg=$1
printf '%s\n' "$arg"
REMOTE
```

Validate external values before using them as paths, option names, regular expressions, globs, hosts, or identifiers. Prefer allowlists over blacklists.

Treat environment variables as convenient transport, not perfect secrecy. Prefer stdin, a dedicated file descriptor, a secret manager, or a mode-600 file. Never enable `set -x` around secrets.

## Portability

- Do not claim POSIX compatibility for Bash syntax.
- macOS system Bash is 3.2. Avoid associative arrays, `${var,,}`, `${var^^}`, `mapfile`, `readarray`, `coproc`, `globstar`, and `wait -n` unless Bash 4+ is explicit.
- GNU and BSD utilities differ, notably `date`, `sed -i`, `readlink -f`, `stat`, `find`, `xargs`, and `mktemp`.
- For cross-platform scripts, use a portable subset, feature-detect, branch deliberately, or document required GNU tools.
- Avoid relying on `#!/usr/bin/env bash` to select a newer Bash unless the deployment environment controls `PATH`.

## Validation and Testing

Run at minimum:

```bash
bash -n script.sh
shellcheck script.sh
```

Treat ShellCheck warnings as defects unless a narrowly scoped `# shellcheck disable=SC...` comment explains why the code is correct.

Test relevant cases:

- normal success
- missing required arguments
- unknown options
- options missing values
- missing or unreadable input
- empty values and empty files
- final input line without a newline
- pathnames containing spaces, tabs, leading dashes, glob characters, newlines, or Unicode
- a failed pipeline stage
- interrupted execution and cleanup
- destructive mode in dry-run and guarded-failure states

Use `bats-core` for repeatable behavior tests. Assert exit status, stdout, stderr, and side effects.

For tracing, include source location and disable tracing around secrets:

```bash
PS4='+ ${BASH_SOURCE}:${LINENO}:${FUNCNAME[0]:-main}: '
set -x
```

## Review Priorities

When reviewing an existing script, prioritize:

1. Data loss, injection, privilege, secret, and path-traversal risks
2. Silent failure or incorrect exit status
3. Quoting, globbing, subshell, pipeline, and cleanup defects
4. Portability and dependency mismatches
5. Readability, duplication, and maintainability

Give precise fixes with corrected snippets. Do not rewrite merely for style when behavior is already safe and clear.

## Completion Checklist

- Correct Bash or POSIX dialect and documented minimum version
- `#!/usr/bin/env bash` plus justified strict-mode behavior
- One-line `# Description:` and, when needed, comma-separated `# Requirements:` comments below the shebang
- Domain-based placement with thin entry points and narrowly scoped libraries when decomposition is warranted
- Quoted expansions and safe array forwarding
- Explicit expected-failure handling
- Validated option values before `$2` access
- stderr diagnostics and meaningful exit codes
- NUL-safe pathname handling where required
- No `ls` parsing, `eval`, or untrusted `bash -c`
- Safe temporary creation and status-preserving cleanup
- Guarded destructive targets and `--` path separators
- Documented GNU or BSD dependencies
- `bash -n`, ShellCheck, and relevant edge-case tests completed
