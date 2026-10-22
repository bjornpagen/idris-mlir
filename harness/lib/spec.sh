# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# The specification's generated files, as the tests of them see them:
# specgen (compiler/spec, IdrisMLIR.Spec.Generator.Main) writes each
# output and the one committed manifest, or checks that the committed ones
# are what it would write. The manifest is the list of the outputs, so no
# test lists them again: its first two lines are the specification's and
# the generator's fingerprints, and every line after them an output's
# fingerprint and its path from the root.

spec_manifest=foreign/idr/generated.manifest

# spec_outputs ROOT: the path of each output the manifest of the tree at
# ROOT names, one a line, in the manifest's order.
spec_outputs() {
  sed -n '3,$ s/^[0-9a-f]\{1,\} //p' "$1/$spec_manifest" 2> /dev/null
}

# spec_sources ROOT DEST: the specification's sources of the tree at ROOT
# copied to DEST/compiler/spec, without a build left in them.
spec_sources() {
  mkdir -p "$2/compiler" && cp -R "$1/compiler/spec" "$2/compiler/spec" &&
    rm -rf "$2/compiler/spec/build"
}

# spec_tree ROOT DEST: what specgen reads and writes of the tree at ROOT,
# copied to DEST: the specification's sources, and every output and the
# manifest at its path.
spec_tree() {
  spec_sources "$1" "$2" || return 1
  for st_path in $(spec_outputs "$1") "$spec_manifest"; do
    mkdir -p "$2/${st_path%/*}" && cp "$1/$st_path" "$2/$st_path" || return 1
  done
}

# spec_check SPECGEN ROOT: `SPECGEN check ROOT`, which writes nothing; its
# exit status in $spec_status, and the paths it names as differing from
# the specification, from ROOT, one a line, in $work/spec-named. Anything
# else it says is in $work/spec-check.out.
spec_check() {
  bounded "$1" check "$2" > "$work/spec-check.out" 2>&1
  spec_status=$?
  sed -n "s|^specgen: differs from the specification: $2/||p" "$work/spec-check.out" > "$work/spec-named"
}

# spec_named WHAT EXPECTED...: one line: WHAT, spec_check's status, and
# whether the paths it named are exactly EXPECTED... (in any order); the
# paths otherwise, and what specgen said.
spec_named() {
  sn_what=$1
  shift
  : > "$work/spec-expected"
  [ $# -eq 0 ] || printf '%s\n' "$@" | LC_ALL=C sort > "$work/spec-expected"
  LC_ALL=C sort "$work/spec-named" > "$work/spec-got"
  if cmp -s "$work/spec-expected" "$work/spec-got"; then
    say "$sn_what: exit $spec_status, naming $(spec_naming "$@")"
  else
    say "$sn_what: exit $spec_status, naming otherwise"
    show "$work/spec-check.out"
  fi
}

# spec_naming PATH...: the paths as a transcript says them: the manifest
# by that name, an output as `an output`, so a transcript holds no path
# of the generated tree, which the specification's areas decide.
spec_naming() {
  sg_said=
  for sg_path do
    case $sg_path in
      "$spec_manifest") sg_word="the manifest" ;;
      *) sg_word="an output" ;;
    esac
    sg_said="${sg_said:+$sg_said and }$sg_word"
  done
  say "${sg_said:-nothing}"
}

# spec_written SPECGEN ROOT: SPECGEN writes every output into a tree that
# holds the specification of ROOT and none of its outputs, and each file
# it writes is byte for byte the one ROOT holds; one line. A file written
# that ROOT's manifest does not name, or one it names and SPECGEN did not
# write, is said too.
spec_written() {
  sw_tree=$work/written
  rm -rf "$sw_tree"
  spec_sources "$2" "$sw_tree" || { say "written into an empty tree: the sources not copied"; return; }
  for sw_path in $(spec_outputs "$2") "$spec_manifest"; do
    mkdir -p "$sw_tree/${sw_path%/*}"
  done
  if ! bounded "$1" write "$sw_tree" > "$work/spec-write.out" 2>&1; then
    say "written into an empty tree: specgen write failed"
    show "$work/spec-write.out"
    return
  fi
  : > "$work/spec-written.faults"
  for sw_path in $(spec_outputs "$2") "$spec_manifest"; do
    if [ ! -f "$sw_tree/$sw_path" ]; then
      say "  not written: $sw_path" >> "$work/spec-written.faults"
    elif ! cmp -s "$2/$sw_path" "$sw_tree/$sw_path"; then
      say "  not the committed bytes: $sw_path" >> "$work/spec-written.faults"
    fi
  done
  (cd "$sw_tree" && find . -type f ! -path './compiler/spec/*' | sed 's|^\./||') |
    while IFS= read -r sw_path; do
      [ "$sw_path" = "$spec_manifest" ] && continue
      spec_outputs "$2" | grep -qxF "$sw_path" || say "  written, and named by no committed manifest: $sw_path"
    done >> "$work/spec-written.faults"
  if [ -s "$work/spec-written.faults" ]; then
    say "written into an empty tree: otherwise than committed"
    cat "$work/spec-written.faults"
  else
    say "written into an empty tree: each file byte for byte the committed one"
  fi
}
