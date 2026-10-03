# Upstream bugs in clang that a unit of ours reproduces: the report holds the
# unit as it was before the workaround, and the check compiles it in place of
# today's unit with the build's own command for that unit, so it sees the
# same flags and the same modules (it needs make build).

# crashes_in_place SOURCE TARGET FILE MESSAGE: says whether clang still
# prints MESSAGE when it compiles SOURCE as the build's TARGET (an object
# file under build/dev) would compile FILE.
crashes_in_place() {
  in_place_command=$(cd "$root/build/dev" &&
    "$toolchain/ninja/bin/ninja" -t commands "$2" 2> /dev/null | tail -n 1)
  if [ -z "$in_place_command" ]; then
    say "${1##*/}: no build (make build)"
    return 0
  fi
  in_place_command=$(printf '%s\n' "$in_place_command" |
    sed "s| -o [^ ]*\\.o | -o $work/unit.o |; s|-fmodule-output=[^ ]*|-fmodule-output=$work/unit.pcm|; s| -c [^ ]*$3| -c $1|")
  (cd "$root/build/dev" && eval "bounded $in_place_command") > "$work/in-place.log" 2>&1
  if grep -qF "$4" "$work/in-place.log"; then
    say "${1##*/}: still crashes clang"
  else
    say "${1##*/}: no longer crashes clang"
    show "$work/in-place.log"
  fi
}
