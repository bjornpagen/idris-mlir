#!/bin/sh
# Assembles each lane's dispatch from its body, the common obligations and
# the six binding rules, so the shared text is written once. A body's
# first line names it: "# Lane L01 (effects-ops): ..." gives
# dispatch/L01-effects-ops.md.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
rm -rf "$here/dispatch"
mkdir -p "$here/dispatch"
for body in "$here"/parts/lanes/*.md; do
  name=$(head -1 "$body" | sed -n 's/^# Lane \([A-Z0-9]*\) (\([a-z-]*\)).*/\1-\2/p')
  [ -n "$name" ] || { echo "no name in $body"; exit 1; }
  {
    cat "$body"
    printf '\n'
    cat "$here/parts/common.md"
    printf '\n'
    cat "$here/parts/rules.md"
  } > "$here/dispatch/$name.md"
done
