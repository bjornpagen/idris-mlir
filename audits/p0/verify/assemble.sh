#!/bin/sh
# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# Assembles each lane's dispatch from its body, the common obligations and
# the six binding rules, so the shared text is written once. A body's
# first heading names it: "# Lane L01 (effects-ops): ..." gives
# dispatch/L01-effects-ops.md. A dispatch names its licence once, at its
# head, as its body does, so the common parts' own lines are left out.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
rm -rf "$here/dispatch"
mkdir -p "$here/dispatch"
for body in "$here"/parts/lanes/*.md; do
  name=$(sed -n 's/^# Lane \([A-Z0-9]*\) (\([a-z-]*\)).*/\1-\2/p' "$body" | head -1)
  [ -n "$name" ] || { echo "no name in $body"; exit 1; }
  {
    cat "$body"
    printf '\n'
    tail -n +3 "$here/parts/common.md"
    printf '\n'
    tail -n +3 "$here/parts/rules.md"
  } > "$here/dispatch/$name.md"
done
