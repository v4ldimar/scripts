#!/usr/bin/env bash
# Description: Generate pronounceable passwords containing three six-character groups, one uppercase letter, and one digit.
# Requirements: Bash 3.2+, od, and /dev/urandom (Linux or macOS)
set -euo pipefail

readonly PROGRAM=${0##*/}
readonly CONSONANTS='bcdfghjklmnpqrstvwxz'
readonly UPPERCASE_CONSONANTS='BCDFGHJKLMNPQRSTVWXZ'
readonly VOWELS='aeiouy'
readonly UPPERCASE_VOWELS='AEIOUY'
readonly GROUP_LENGTH=6
readonly GROUP_COUNT=3
readonly PASSWORD_LENGTH=$((GROUP_LENGTH * GROUP_COUNT))
readonly LETTER_COUNT=$((PASSWORD_LENGTH - 1))

RANDOM_BYTES=()
RANDOM_BYTE_INDEX=0
RANDOM_VALUE=0

usage() {
  cat <<EOF_USAGE
Usage: $PROGRAM [OPTIONS]

Generate a pronounceable password such as: tedSo2-fasnut-sewmaw

Options:
  -n, --count COUNT  Generate COUNT passwords (default: 1)
  -h, --help         Show this help

Each password has three groups of six characters, alternating consonants and
vowels, and contains exactly one uppercase letter and one digit. Randomness is
read from /dev/urandom.
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

refill_random_bytes() {
  local random_text=''

  if ! random_text=$(LC_ALL=C od -An -N 128 -tu1 /dev/urandom); then
    die 'could not read random data from /dev/urandom'
  fi

  # od wraps its output across lines. Flatten the text before splitting it
  # into an array of decimal byte values.
  random_text=${random_text//$'\n'/ }
  read -r -a RANDOM_BYTES <<< "$random_text"
  ((${#RANDOM_BYTES[@]} > 0)) || die 'no random data was returned'
  RANDOM_BYTE_INDEX=0
}

random_below() {
  local limit=$1
  local cutoff=$((256 - (256 % limit)))
  local byte=0

  while true; do
    if ((RANDOM_BYTE_INDEX >= ${#RANDOM_BYTES[@]})); then
      refill_random_bytes
    fi

    byte=${RANDOM_BYTES[$RANDOM_BYTE_INDEX]}
    ((RANDOM_BYTE_INDEX += 1))

    # Reject the incomplete range at the top of the byte domain so every
    # possible result has exactly the same probability.
    if ((byte < cutoff)); then
      RANDOM_VALUE=$((byte % limit))
      return 0
    fi
  done
}

generate_password() {
  local password=''
  local uppercase_letter=0
  local digit_group=0
  local digit_position=0
  local digit=0
  local letter_number=0
  local letter_in_group=0
  local alphabet=''
  local uppercase_alphabet=''
  local alphabet_index=0
  local group=0
  local position=0

  random_below "$LETTER_COUNT"
  uppercase_letter=$RANDOM_VALUE

  random_below "$GROUP_COUNT"
  digit_group=$RANDOM_VALUE

  random_below "$GROUP_LENGTH"
  digit_position=$RANDOM_VALUE

  random_below 10
  digit=$RANDOM_VALUE

  for ((group = 0; group < GROUP_COUNT; group += 1)); do
    if ((group > 0)); then
      password+='-'
    fi

    letter_in_group=0
    for ((position = 0; position < GROUP_LENGTH; position += 1)); do
      if ((group == digit_group && position == digit_position)); then
        password+=$digit
        continue
      fi

      if ((letter_in_group % 2 == 0)); then
        alphabet=$CONSONANTS
        uppercase_alphabet=$UPPERCASE_CONSONANTS
      else
        alphabet=$VOWELS
        uppercase_alphabet=$UPPERCASE_VOWELS
      fi

      random_below "${#alphabet}"
      alphabet_index=$RANDOM_VALUE
      if ((letter_number == uppercase_letter)); then
        password+=${uppercase_alphabet:alphabet_index:1}
      else
        password+=${alphabet:alphabet_index:1}
      fi

      ((letter_in_group += 1))
      ((letter_number += 1))
    done
  done

  printf '%s\n' "$password"
}

main() {
  local count=1
  local i=0

  while (($#)); do
    case $1 in
      -n|--count)
        (($# >= 2)) || usage_error "missing value for $1"
        [[ -n $2 ]] || usage_error "$1 requires a value"
        count=$2
        shift 2
        ;;
      --count=*)
        count=${1#*=}
        [[ -n $count ]] || usage_error '--count requires a value'
        shift
        ;;
      -h|--help)
        usage
        return 0
        ;;
      --)
        shift
        break
        ;;
      -*)
        usage_error "unknown option: $1"
        ;;
      *)
        usage_error "unexpected argument: $1"
        ;;
    esac
  done

  (($# == 0)) || usage_error "unexpected argument: $1"
  [[ $count =~ ^[1-9][0-9]*$ ]] || usage_error 'count must be a positive integer'

  command -v od >/dev/null 2>&1 || die 'od is not installed or not on PATH'
  [[ -r /dev/urandom ]] || die '/dev/urandom is not readable'

  for ((i = 0; i < count; i += 1)); do
    generate_password
  done
}

main "$@"
