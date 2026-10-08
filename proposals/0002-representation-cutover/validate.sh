#!/bin/sh
# Document checks for the representation-cutover packet. Prints counts as
# JSON and exits 1 on any violation. Needs jq (macOS 15 and Linux
# distributions ship it).
# Run: sh proposals/0002-representation-cutover/validate.sh
#
# Checks: every local link resolves; every finding in findings.md appears
# exactly once in README's finding map, with the owner ownership.json
# gives; no exact or prefix intersection between any two writers,
# coordinator included; every owned path exists or is a file the packet
# creates; every dispatch has the required sections and exactly six
# binding rules, names every path its lane owns, and declares exactly its
# lane's findings; no lane waits on a sibling, the coordinator or a gate;
# no retired mechanism appears outside a Delete section; every part is
# assembled and every lane has a dispatch; at least twelve lanes.
set -u
root=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$root/../.." && pwd)
own=$root/ownership.json
command -v jq > /dev/null 2>&1 || { echo "validate.sh needs jq" >&2; exit 2; }
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
: > "$work/fails"
fail() { printf '%s\n' "$*" >> "$work/fails"; }

# Files the packet creates, as ownership.json spells them.
cat > "$work/new" << 'EOF'
IDR/Dialect/Ops/Check.cc
IDR/Dialect/Ops/Regions.cc
IDR/Lower/Checks.cppm
IDR/Lower/Entry.cppm
IDR/Lower/Entry
IDR/Lower/Meter.cppm
IDR/Lower/Meter
IDR/Isolate
IDR/Demand
EOF

expand() {
  jq -r --arg p "$1" '
    .roots as $r
    | ($r | to_entries | map(select(.key as $k | ($p == $k) or ($p | startswith($k + "/")))) | first) as $m
    | if $m == null then $p else $m.value + ($p | ltrimstr($m.key)) end' "$own"
}

# 1. Links
documents=0
links=0
for doc in $(cd "$root" && find . -name '*.md' | sort); do
  documents=$((documents + 1))
  dir=$(dirname "$root/$doc")
  for target in $(grep -oE '\]\([^)#[:space:]]+' "$root/$doc" | cut -c3-); do
    case $target in *:*) continue ;; esac
    links=$((links + 1))
    [ -e "$dir/$target" ] || fail "$doc: broken link $target"
  done
done

# 2. Ownership
jq -r '(.coordinator[] | "coordinator\t" + .),
       (.lanes | to_entries[] | .key as $k | .value.writes[] | $k + "\t" + .)' "$own" > "$work/raw"
: > "$work/writes"
while IFS="$(printf '\t')" read -r writer path; do
  printf '%s\t%s\t%s\n' "$writer" "$path" "$(expand "$path")" >> "$work/writes"
done < "$work/raw"
writers=$(cut -f1 "$work/writes" | sort -u | wc -l | tr -d ' ')
awk -F'\t' '
  { w[NR] = $1; p[NR] = $3 }
  END {
    for (i = 1; i <= NR; i++)
      for (j = i + 1; j <= NR; j++) {
        if (w[i] == w[j]) continue
        a = p[i]; b = p[j]
        if (a == b || index(a, b "/") == 1 || index(b, a "/") == 1)
          printf "write intersection: %s %s vs %s %s\n", w[i], a, w[j], b
      }
  }' "$work/writes" >> "$work/fails"
while IFS="$(printf '\t')" read -r writer path full; do
  [ -e "$repo/$full" ] && continue
  grep -qxF "$path" "$work/new" && continue
  fail "$writer: owned path does not exist in the tree: $full"
done < "$work/writes"

# 3. Finding map
grep -oE '^## F-[a-z]+-[0-9]+ ' "$root/findings.md" | awk '{print $2}' | sort > "$work/findings"
grep -E '^\| F-[a-z]+-[0-9]+ \|' "$root/README.md" |
  awk -F'|' '{ gsub(/ /, "", $2); gsub(/ /, "", $4); print $2 "\t" $4 }' | sort > "$work/map"
jq -r '.lanes | to_entries[] | .key as $k | .value.findings[] | . + "\t" + $k' "$own" | sort > "$work/owned"
cut -f1 "$work/map" | uniq -d | while read -r id; do fail "finding $id appears twice in the finding map"; done
while read -r id; do
  owner=$(awk -F'\t' -v id="$id" '$1 == id { print $2 }' "$work/map" | head -n 1)
  if [ -z "$owner" ]; then fail "finding $id missing from the finding map"; continue; fi
  [ "$owner" = coordinator ] && continue
  grep -qxF "$(printf '%s\t%s' "$id" "$owner")" "$work/owned" ||
    fail "finding $id: map owner $owner does not own it in ownership.json"
done < "$work/findings"
cut -f1 "$work/map" | while read -r id; do
  grep -qxF "$id" "$work/findings" || fail "finding map names unknown finding $id"
done
while IFS="$(printf '\t')" read -r id lane; do
  grep -qxF "$id" "$work/findings" || fail "ownership $lane names unknown finding $id"
  grep -qxF "$(printf '%s\t%s' "$id" "$lane")" "$work/map" ||
    fail "finding $id: ownership says $lane, the map does not"
done < "$work/owned"
findings=$(wc -l < "$work/findings" | tr -d ' ')
mapped=$(wc -l < "$work/map" | tr -d ' ')

# 4. Dispatches
grep '^- retired: ' "$root/README.md" | cut -c12- > "$work/retired"
retired=$(wc -l < "$work/retired" | tr -d ' ')
dispatches=0
for file in "$root"/dispatch/U[0-9][0-9]-*.md; do
  [ -e "$file" ] || continue
  dispatches=$((dispatches + 1))
  name=$(basename "$file")
  lane=$(printf '%s' "$name" | cut -c1-3)
  for section in "## Permitted outcome" "## Owner / exclusive writes" "## Implement" "## Delete" \
                 "## NOT TO DO" "## Acceptance" "## Stop and return" "## Common obligations" \
                 "## Binding rules"; do
    grep -qxF "$section" "$file" || fail "$name: missing section $section"
  done
  rules=$(sed -n '/^## Binding rules$/,$p' "$file" | grep -cE '^[0-9]+\. ')
  [ "$rules" -eq 6 ] || fail "$name: $rules binding rules, expected 6"
  if ! jq -e --arg l "$lane" '.lanes[$l]' "$own" > /dev/null; then
    fail "$name: no ownership entry for $lane"
    continue
  fi
  jq -r --arg l "$lane" '.lanes[$l].writes[]' "$own" | while read -r path; do
    grep -qF "$path" "$file" || fail "$name: does not name owned path $path"
  done
  declared=$(grep -m1 '^Mandatory findings: ' "$file" | grep -oE 'F-[a-z]+-[0-9]+' | sort | tr '\n' ' ')
  expected=$(jq -r --arg l "$lane" '.lanes[$l].findings[]' "$own" | sort | tr '\n' ' ')
  [ "$declared" = "$expected" ] || fail "$name: mandatory findings [$declared] != ownership [$expected]"
  sed '/^## Common obligations$/,$d' "$file" | grep -v '^[[:space:]]*>' > "$work/prose"
  grep -inE '(^|[^[:alnum:]_])wait(s|ing)? (for|on|until) (U[0-9]{2}|the (coordinator|migration|schema|sibling|foundation|gate))([^[:alnum:]_]|$)|(^|[^[:alnum:]_])blocked (on|by)([^[:alnum:]_]|$)|(^|[^[:alnum:]_])(after|once) U[0-9]{2}([^[:alnum:]_]|$)' "$work/prose" |
    while IFS= read -r hit; do fail "$name: waits on something: $hit"; done
  awk '/^## Delete$/ { skip = 1; next } /^## / { skip = 0 } !skip' "$work/prose" > "$work/outside"
  while IFS= read -r mechanism; do
    grep -qF "$mechanism" "$work/outside" && fail "$name: prescribes retired mechanism \"$mechanism\" outside Delete"
  done < "$work/retired"
done
for part in "$root"/dispatch/parts/U[0-9][0-9]-*.md; do
  name=$(basename "$part")
  [ -e "$root/dispatch/$name" ] || fail "dispatch/$name not assembled from parts/$name"
done
lanes=$(jq -r '.lanes | keys | length' "$own")
for lane in $(jq -r '.lanes | keys[]' "$own"); do
  ls "$root"/dispatch/"$lane"-*.md > /dev/null 2>&1 || fail "no dispatch for $lane"
done
[ "$lanes" -ge 12 ] || fail "only $lanes lanes; a swarm is at least twelve"

failures=$(wc -l < "$work/fails" | tr -d ' ')
printf '{\n  "documents": %s,\n  "links": %s,\n  "findings": %s,\n  "mapped": %s,\n  "lanes": %s,\n  "dispatches": %s,\n  "writers": %s,\n  "retiredMechanisms": %s,\n  "failures": %s\n}\n' \
  "$documents" "$links" "$findings" "$mapped" "$lanes" "$dispatches" "$writers" "$retired" "$failures"
sed 's/^/FAIL /' "$work/fails" >&2
[ "$failures" -eq 0 ]
