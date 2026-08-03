#!/usr/bin/env bash
set -euo pipefail

readonly PROGRAM=${0##*/}
readonly SUDOERS_DIR='/etc/sudoers.d'

die() {
  printf '%s: error: %s\n' "$PROGRAM" "$*" >&2
  exit 1
}

if (($# != 0)); then
  printf 'Usage: %s\n' "$PROGRAM" >&2
  exit 2
fi

((EUID != 0)) || die 'run this script as your normal user, not with sudo'

for command_name in id install mktemp rm sudo; do
  command -v "$command_name" >/dev/null 2>&1 ||
    die "required command not found: $command_name"
done

username=$(id -un) || die 'could not determine the current user'
[[ $username =~ ^[a-zA-Z_][a-zA-Z0-9_.-]*$ ]] ||
  die "unsupported user name: $username"

readonly username
readonly sudoers_file="$SUDOERS_DIR/$username"
readonly sudoers_rule="$username ALL=(ALL:ALL) NOPASSWD: ALL"

tmp_file=''
cleanup() {
  local status=$?
  trap - EXIT

  if [[ -n ${tmp_file:-} && -f $tmp_file ]]; then
    if ! rm -f -- "$tmp_file"; then
      printf '%s: warning: could not remove temporary file: %s\n' \
        "$PROGRAM" "$tmp_file" >&2
      ((status == 0)) && status=1
    fi
  fi

  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Authenticate before inspecting or changing the root-owned sudoers directory.
sudo -v || die 'sudo authentication failed'

if sudo test -e "$sudoers_file"; then
  existing_rule=$(sudo cat -- "$sudoers_file") ||
    die "could not read existing file: $sudoers_file"

  if [[ $existing_rule == "$sudoers_rule" ]]; then
    printf 'Passwordless sudo is already enabled for %s.\n' "$username"
    exit 0
  fi

  die "refusing to overwrite an existing sudoers file: $sudoers_file"
fi

tmp_file=$(mktemp "${TMPDIR:-/tmp}/${PROGRAM}.XXXXXXXXXX") ||
  die 'could not create a temporary file'
printf '%s\n' "$sudoers_rule" >"$tmp_file"
chmod 0600 -- "$tmp_file"

sudo visudo -cf "$tmp_file" >/dev/null || die 'generated sudoers rule is invalid'
sudo install -o root -g root -m 0440 -- "$tmp_file" "$sudoers_file" ||
  die "could not install sudoers file: $sudoers_file"

printf 'Enabled passwordless sudo for %s.\n' "$username"
