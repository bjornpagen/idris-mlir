# The patches this repository carries on the pinned upstreams, in one
# place: sourced, with $root set to the repository and host.sh's sha256,
# by tools/bootstrap.sh, which applies them and records them in the inputs
# and stamps of the steps they change, and by tools/verify-pins.sh, which
# refuses a stamp that records other patches than the tree carries.
#
# A bug in a pinned upstream is fixed by a patch to that upstream's source,
# upstream/<bug>/<project>.patch, where <project> names the pinned source it
# applies to:
#
#   llvm    the llvm-project of toolchain.lock.json: LLVM, MLIR, clang, lld
#           and the runtimes (steps stage2 and runtimes)
#   chez    Chez Scheme at the lock's revision (step chez)
#   idris   Idris 2 at third_party/Idris2's gitlink (step idris)
#
# A bug has one patch per project it touches. The patches of a project
# apply in the byte order of their bugs' names, each to the source as the
# ones before it left it.

patch_projects='llvm chez idris'

# patches PROJECT: the project's patch files, in the order they apply.
patches() {
  find "$root/upstream" -mindepth 2 -maxdepth 2 -type f -name "$1.patch" | LC_ALL=C sort
}

# patch_record PROJECT: one line per patch, `<bug> <SHA-256>`, in the order
# they apply; nothing when the project carries none.
patch_record() {
  patches "$1" | while IFS= read -r patch_record_file; do
    patch_record_bug=${patch_record_file%/*}
    patch_record_sum=$(sha256 "$patch_record_file" | cut -c1-64) || exit 1
    printf '%s %s\n' "${patch_record_bug##*/}" "$patch_record_sum"
  done
}

# patch_stamp PROJECT: the record on one line, as a stamp holds it.
patch_stamp() {
  patch_stamp_record=$(patch_record "$1") || return 1
  printf '%s' "$patch_stamp_record" | tr '\n' ' '
}
