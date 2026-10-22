#!/bin/sh
# Checks the cutover packet: every dispatch carries the required sections
# and the six rules; no two writers' paths meet; every tracked file of
# the tree has exactly one writer, or is one the cutover never touches.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../.." && pwd)
fail=0
lanes=0
for d in "$here"/dispatch/*.md; do
  lanes=$((lanes + 1))
  for h in '**Exclusive write:**' '**Read deeply:**' '**Contract:**' '**End state:**' \
           '**Recipe:**' '**Delete:**' '**QTT:**' '**NOT TO DO:**' '**Acceptance:**' \
           '**Stop and return:**' '## Common obligations' '## The six binding rules'; do
    grep -qF "$h" "$d" || { echo "missing '$h' in $(basename "$d")"; fail=1; }
  done
  rules=$(grep -cE '^[1-6]\. ' "$d" | tr -d ' ')
  [ "$rules" -ge 6 ] || { echo "rules count $rules in $(basename "$d")"; fail=1; }
done
paths=$(grep -o '"[^"]*"' "$here/ownership.json" | tr -d '"' | grep -v -E '^(coordinator|INT|L[0-9][0-9])$')
dups=$(printf '%s\n' "$paths" | sort | uniq -d)
[ -z "$dups" ] || { echo "duplicate writers: $dups"; fail=1; }
for a in $paths; do
  case "$a" in */) ;; *) continue;; esac
  for b in $paths; do
    [ "$a" = "$b" ] && continue
    case "$b" in "$a"*) echo "prefix overlap: $a $b"; fail=1;; esac
  done
done
listfile=$(mktemp)
printf '%s\n' "$paths" > "$listfile"
unowned=$(git -C "$root" ls-files | awk -v listfile="$listfile" '
  BEGIN { while ((getline line < listfile) > 0) p[++n] = line }
  /^(sources\/|"sources|third_party\/|LICENSE|LICENSES\/|NOTICE|\.editorconfig|\.gitignore)/ { next }
  { c = 0
    for (i = 1; i <= n; i++) {
      if ($0 == p[i]) c++
      else if (substr(p[i], length(p[i])) == "/" && index($0, p[i]) == 1) c++
    }
    if (c != 1) print c ": " $0 }')
rm -f "$listfile"
[ -z "$unowned" ] || { echo "files without exactly one writer:"; echo "$unowned" | head -20; fail=1; }
echo "lanes: $lanes; writer paths: $(printf '%s\n' "$paths" | wc -l | tr -d ' ')"
[ "$fail" -eq 0 ] && echo "packet: valid" || { echo "packet: INVALID"; exit 1; }
