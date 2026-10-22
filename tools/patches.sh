# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
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
#   snmalloc
#           the runtime's snmalloc at third_party/snmalloc's gitlink, the
#           lock's revision (step snmalloc)
#   simdutf the runtime's simdutf at third_party/simdutf's gitlink, the
#           lock's revision (step simdutf)
#
# A bug has one patch per project it touches. The patches of a project
# apply in the order of their bugs' numbers, each to the source as the
# ones before it left it: a number is the order to file in, and a later
# patch may build on an earlier one's lines, so 100 applies after 99,
# which the names' byte order would put it before.

patch_projects='llvm chez idris snmalloc simdutf'

# patches PROJECT: the project's patch files, in the order they apply.
patches() {
  find "$root/upstream" -mindepth 2 -maxdepth 2 -type f -name "$1.patch" |
    awk -F/ '{ print $(NF - 1) "\t" $0 }' | LC_ALL=C sort -n | cut -f 2-
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
