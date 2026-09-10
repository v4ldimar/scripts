#!/usr/bin/env bash
# Description: Restore the selected Windows applications from Git Bash using WinGet and official installers.
# Requirements: Bash 4+, Windows 10/11, WinGet
set -euo pipefail

PROGRAM=${0##*/}
readonly SCRIPT_DIR=$(cd -P -- "$(dirname -- "$0")" && pwd -P)
LOG_FILE=${SETUP_LOG_FILE:-"$SCRIPT_DIR/setup-apps.log"}

dry_run=0
only=''
winget_cmd=''
declare -a successes=() skipped=() failures=()

usage() {
  cat <<EOF_USAGE
Usage: $PROGRAM [OPTIONS]

Install the workstation application set. Run from Git Bash after Windows setup.

Options:
  --dry-run       Show commands without installing anything
  --only NAME     Install one item (repeat with comma-separated names)
  -h, --help      Show this help

Names: teams, chrome, dbeaver, notepadpp, git, vscode-insiders, azure-storage,
       postman, xrmtoolbox, docker, nvm, visual-studio
EOF_USAGE
}

usage_error() {
  printf '%s: error: %s\n\n' "$PROGRAM" "$*" >&2
  usage >&2
  exit 2
}

die() {
  printf '%s: error: %s\n' "$PROGRAM" "$*" >&2
  exit 1
}

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG_FILE"
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

selected() {
  [[ -z $only ]] && return 0
  local item
  IFS=',' read -r -a requested <<< "$only"
  for item in "${requested[@]}"; do
    [[ $item == "$1" ]] && return 0
  done
  return 1
}

record_skip() { skipped+=("$1"); log "SKIP  $1: $2"; }
record_success() { successes+=("$1"); log "OK    $1"; }
record_failure() { failures+=("$1"); log "FAIL  $1: $2"; }

run_command() {
  if ((dry_run)); then
    printf '+ '
    printf '%q ' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

install_winget() {
  local name=$1 id=$2
  selected "$name" || return 0
  if [[ -z $winget_cmd ]]; then
    record_failure "$name" 'winget.exe was not found; install App Installer from Microsoft Store first'
    return 0
  fi
  log "Installing $name ($id)"
  if run_command "$winget_cmd" install --id "$id" --exact --source winget --scope user \
      --silent --accept-source-agreements --accept-package-agreements; then
    record_success "$name"
  else
    record_failure "$name" 'WinGet returned a failure (the installer may require elevation or a different scope)'
  fi
}

install_docker() {
  local name=docker
  selected "$name" || return 0
  log 'Installing Docker Desktop in per-user mode'
  if run_command "$winget_cmd" install --id Docker.DockerDesktop --exact --source winget \
      --scope user --silent --accept-source-agreements --accept-package-agreements; then
    record_success "$name"
  else
    record_failure "$name" 'Docker installation failed; WSL 2 and virtualization may need to be enabled by an administrator'
  fi
}

install_visual_studio() {
  local name=visual-studio
  selected "$name" || return 0
  log 'Installing Visual Studio 2026 Professional stable (administrator elevation is expected)'
  if [[ -n $winget_cmd ]]; then
    if run_command "$winget_cmd" install --id Microsoft.VisualStudio.Professional --exact --source winget \
        --silent --accept-source-agreements --accept-package-agreements; then
      record_success "$name"
      return 0
    fi
  fi
  record_failure "$name" 'Visual Studio requires elevation; WinGet could not install Microsoft.VisualStudio.Professional'
}

main() {
  local arg
  while (($#)); do
    case $1 in
      --dry-run) dry_run=1; shift ;;
      --only)
        (($# >= 2)) || usage_error '--only requires a value'
        only=$2; shift 2 ;;
      --only=*) only=${1#*=}; [[ -n $only ]] || usage_error '--only requires a value'; shift ;;
      -h|--help) usage; return 0 ;;
      --) shift; (($# == 0)) || usage_error 'unexpected positional arguments'; break ;;
      -*) usage_error "unknown option: $1" ;;
      *) usage_error "unexpected positional argument: $1" ;;
    esac
  done

  if ((dry_run)); then
    LOG_FILE=/dev/null
  else
    mkdir -p -- "$(dirname -- "$LOG_FILE")"
    : > "$LOG_FILE"
  fi
  log "Starting Windows application restore (dry-run=$dry_run)"

  if ! command_exists winget.exe && ! command_exists winget; then
    die 'WinGet is unavailable. Sign in to Windows once so App Installer can register, then retry.'
  fi
  if command_exists winget.exe; then
    winget_cmd=winget.exe
  else
    winget_cmd=winget
  fi

  install_winget teams Microsoft.Teams
  install_winget chrome Google.Chrome
  install_winget dbeaver DBeaver.DBeaver.Community
  install_winget notepadpp Notepad++.Notepad++
  install_winget git Git.Git
  install_winget vscode-insiders Microsoft.VisualStudioCode
  install_winget azure-storage Microsoft.Azure.StorageExplorer
  install_winget postman Postman.Postman
  install_winget xrmtoolbox "MscrmTools.XrmToolBox"
  install_winget nvm CoreyButler.NVMforWindows
  install_docker
  install_visual_studio

  log "Completed: ${#successes[@]} installed, ${#skipped[@]} skipped, ${#failures[@]} failed"
  if ((${#failures[@]})); then
    printf '%s: failed items: %s\n' "$PROGRAM" "${failures[*]}" >&2
    return 1
  fi
}

main "$@"
