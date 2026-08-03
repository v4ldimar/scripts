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

for command_name in id sudo; do
  command -v "$command_name" >/dev/null 2>&1 ||
    die "required command not found: $command_name"
done

username=$(id -un) || die 'could not determine the current user'
[[ $username =~ ^[a-zA-Z_][a-zA-Z0-9_.-]*$ ]] ||
  die "unsupported user name: $username"

readonly username
readonly sudoers_file="$SUDOERS_DIR/$username"
readonly expected_rule="$username ALL=(ALL:ALL) NOPASSWD: ALL"

# Authenticate before inspecting or changing the root-owned sudoers directory.
sudo -v || die 'sudo authentication failed'

if ! sudo test -e "$sudoers_file"; then
  printf 'Passwordless sudo is already disabled for %s.\n' "$username"
  exit 0
fi

existing_rule=$(sudo cat -- "$sudoers_file") ||
  die "could not read existing file: $sudoers_file"
[[ $existing_rule == "$expected_rule" ]] ||
  die "refusing to remove an unrecognized sudoers file: $sudoers_file"

sudo rm -- "$sudoers_file" || die "could not remove sudoers file: $sudoers_file"

printf 'Disabled passwordless sudo for %s.\n' "$username"
