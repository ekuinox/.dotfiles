#!/usr/bin/env bash
# Dynamically load Windows user PATH into the bash environment.
# Called automatically by bash via BASH_ENV for non-interactive shells.
_win_path=$(powershell.exe -NoProfile -Command \
  "[Environment]::GetEnvironmentVariable('PATH','User') + ';' + [Environment]::GetEnvironmentVariable('PATH','Machine')" \
  2>/dev/null | tr -d '\r\n')

if [ -n "$_win_path" ]; then
  # Convert Windows path format (C:\foo\bar) to Git Bash format (/c/foo/bar)
  _bash_path=$(printf '%s' "$_win_path" \
    | tr '\\' '/' \
    | tr ';' '\n' \
    | sed 's|^\([A-Za-z]\):|/\l\1|' \
    | tr '\n' ':' \
    | sed 's/:$//')
  export PATH="${_bash_path}:${PATH}"
fi
