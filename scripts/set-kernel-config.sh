#!/usr/bin/env bash
# Apply CONFIG lines from a file to gki_defconfig with the kernel's own scripts/config.
# Lines: CONFIG_X=y|m|n|<value>; '#' comments and blanks ignored. Verifies each one.
# usage: set-kernel-config.sh <config-file>
set -euo pipefail
. "$(dirname "$0")/common.sh"

FILE="${1:?config file}"
[ -f "$FILE" ] || die "$FILE not found"
cd "$COMMON"
DEFCONFIG="arch/arm64/configs/gki_defconfig"
[ -f "$DEFCONFIG" ] || die "$DEFCONFIG not found"
[ -f scripts/config ] || die "scripts/config not found"

# scripts/config is bash (uses [[ ]]), and some trees ship it non-executable.
kc() { bash scripts/config "$@"; }

while IFS= read -r line || [ -n "$line" ]; do
  line="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  [[ -z "$line" || "$line" == \#* ]] && continue
  key="${line%%=*}"
  value="${line#*=}"
  [[ "$line" == *"="* ]] || value=y
  case "$value" in
    y) kc --file "$DEFCONFIG" --enable  "$key" ;;
    m) kc --file "$DEFCONFIG" --module  "$key" ;;
    n) kc --file "$DEFCONFIG" --disable "$key" ;;
    *) kc --file "$DEFCONFIG" --set-val "$key" "$value" ;;
  esac
  case "$value" in
    y|m) grep -qE "^${key}=[ym]$" "$DEFCONFIG" || die "${key}=${value} not present after scripts/config" ;;
    n)   grep -qE "^(# ${key} is not set|${key}=n)$" "$DEFCONFIG" || die "${key} not disabled after scripts/config" ;;
    *)   grep -qF "${key}=${value}" "$DEFCONFIG" || die "${key}=${value} not present after scripts/config" ;;
  esac
  echo "set ${key}=${value}"
done < "$FILE"
