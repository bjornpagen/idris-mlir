# Upstream bugs in clang that a unit of ours reproduces: the report holds the
# unit as it was before the workaround, and the check compiles it in place of
# today's unit with the build's own command for that unit, so it sees the
# same flags and the same modules (it needs make build).

# crashes_in_place SOURCE TARGET FILE MESSAGE: says whether clang still
# prints MESSAGE when it compiles SOURCE as the build's TARGET (an object
# file under the dev build) would compile FILE.
crashes_in_place() {
  in_place_command=$(cd "$dev_prefix" &&
    "$toolchain/ninja/bin/ninja" -t commands "$2" 2> /dev/null | tail -n 1)
  if [ -z "$in_place_command" ]; then
    say "${1##*/}: no build (make build)"
    return 0
  fi
  # Every output goes to $work, so the check leaves the build as it found
  # it: a BMI written over the module's would be imported by later builds.
  # The object and the dependency file are on the command line; the BMI is
  # in the unit's module map, the response file CMake passes it, which also
  # names the build's BMI of every module the unit imports. The command
  # reads a copy of the map that writes the BMI to $work and keeps the rest.
  # A crash writes its reproducer (the preprocessed unit and a script) to
  # the temporary directory, which for the command is $work too.
  in_place_bmi="s|-fmodule-output=[^ ]*|-fmodule-output=$work/unit.pcm|"
  in_place_map=$(printf '%s\n' "$in_place_command" | sed -n 's|.* @\([^ ]*\) .*|\1|p')
  if [ -n "$in_place_map" ]; then
    (cd "$dev_prefix" && sed "$in_place_bmi" "$in_place_map") > "$work/unit.modmap"
  fi
  in_place_command=$(printf '%s\n' "$in_place_command" |
    sed "s| -o [^ ]*\\.o | -o $work/unit.o |; s| -MF [^ ]*| -MF $work/unit.d|; s| @[^ ]*| @$work/unit.modmap|; $in_place_bmi; s| -c [^ ]*$3| -c $1|")
  (cd "$dev_prefix" && export TMPDIR="$work" && eval "bounded $in_place_command") \
    > "$work/in-place.log" 2>&1
  if grep -qF "$4" "$work/in-place.log"; then
    say "${1##*/}: still crashes clang"
  else
    say "${1##*/}: no longer crashes clang"
    show "$work/in-place.log"
  fi
}
