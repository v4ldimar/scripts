# Shared Windows tzutil helpers. Safe to source without performing work.

windows_timezone_require_tzutil() {
  command -v tzutil.exe >/dev/null 2>&1
}

windows_timezone_get() {
  local timezone_id=''

  timezone_id=$(MSYS_NO_PATHCONV=1 tzutil.exe /g) || return 1
  timezone_id=${timezone_id//$'\r'/}
  [[ -n $timezone_id ]] || return 1
  printf '%s' "$timezone_id"
}

windows_timezone_set() {
  local timezone_id=$1

  MSYS_NO_PATHCONV=1 tzutil.exe /s "$timezone_id"
}
