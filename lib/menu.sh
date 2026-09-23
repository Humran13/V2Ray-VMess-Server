#!/usr/bin/env bash
# menu.sh - generic terminal UI helpers shared by install.sh's wizard and bin/vmess.
# All input goes through tty_read (lib/common.sh) so it works under `curl | sudo bash`.

if [[ -n "${VMESS_MENU_LOADED:-}" ]]; then return 0 2>/dev/null || exit 0; fi
VMESS_MENU_LOADED=1

print_banner() {
  printf '\n%s%s================================================%s\n' "$C_BLD" "$C_CYN" "$C_RST"
  printf '%s%s %s%s\n' "$C_BLD" "$C_CYN" "$*" "$C_RST"
  printf '%s%s================================================%s\n\n' "$C_BLD" "$C_CYN" "$C_RST"
}

print_kv() { printf '  %-14s %s\n' "$1:" "$2"; }

# menu_choose <var_name> <prompt> <opt1> [opt2...] -> sets var_name to the 1-based index chosen.
menu_choose() {
  local __var=$1 prompt=$2; shift 2
  local -a opts=("$@")
  local i choice
  echo "$prompt" >&2
  for i in "${!opts[@]}"; do
    printf '  %d) %s\n' "$((i+1))" "${opts[$i]}" >&2
  done
  while true; do
    tty_read choice "Enter choice [1-${#opts[@]}]: "
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#opts[@]} )); then
      printf -v "$__var" '%s' "$choice"
      return 0
    fi
    echo "Invalid choice. Try again." >&2
  done
}

menu_input() { # menu_input <var_name> <prompt> [default]
  local __var=$1 prompt=$2 default=${3:-} val
  if [[ -n "$default" ]]; then
    tty_read val "${prompt} [${default}]: "
    val=${val:-$default}
  else
    tty_read val "${prompt}: "
  fi
  printf -v "$__var" '%s' "$val"
}

pause_for_user() {
  [[ "${VMESS_ASSUME_YES:-0}" == "1" ]] && return 0
  is_interactive || return 0
  local _x
  tty_read _x "Press Enter to continue..."
}
