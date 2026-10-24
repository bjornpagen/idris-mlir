// RUN: idris-mlir-opt %s -split-input-file --pass-pipeline='builtin.module(idr-pipeline{from=first to=first},idr-expect{holds=in-place=@write})' -verify-diagnostics -o /dev/null
// A cell the in-place check rebuilds is taken apart before bufferization,
// by a take that opens the arrays the cell holds, so what the cell claims
// of its sharing still decides, past the take, whether an array may be
// written in place: a cell that claims its own cells unshared holds the
// only reference to its buffer's storage, and one that claims less gives
// an array a write copies first. A box holds an array and the rest of a
// chain of boxes, so it is a cell. In the first program @write is given a
// box of a family promised to be rebuilt in place, claiming its own cells
// unshared; it opens the array the box holds, writes a word into it and
// builds the box again of the array written and the rest it read, which
// the in-place check makes a take of the box and a rebuild in its cell.
// Once its arrays are buffers nothing copies one. In the second a box that
// claims nothing is taken by hand as the check takes one, and its array
// written, so the write copies the array first, which the property reports
// at the write; @write reads back the word at an index it is given, so no
// fold takes the write away. Nothing calls @write, so its box is its
// parameter as written.
#Box = #idr.family<"Box" in_place [] {
    @End ()
    @MkBox (memref<?xi64>, !idr.self)
  }>
!Box = !idr.data<#Box>
!MkBox = !idr.graded<once, counted unique self, !idr.data<#Box @MkBox>>
!Built = !idr.graded<once, counted, !idr.data<#Box @MkBox>>
idr.program @unique root(@main) stage(first) {
  idr.func @main() {
    idr.return
  }
  idr.func @write(%box: !MkBox, %x: i64) -> !Built {
    %r = idr.data.match %box : !MkBox -> (!Built) {
    case @MkBox(%c: !MkBox) {
      %a = idr.array.open %c[0] : !MkBox -> tensor<?xi64>
      %rest = idr.data.field %c[1] : !MkBox -> !Box
      %zero = arith.constant 0 : index
      %w = tensor.insert %x into %a[%zero] : tensor<?xi64>
      %b = bufferization.to_buffer %w : tensor<?xi64> to memref<?xi64>
      %n = idr.data.con(%b : memref<?xi64>, %rest : !Box) : !Built
      idr.yield %n : !Built
    }
    }
    idr.return %r : !Built
  }
}

// -----

#Box = #idr.family<"Box" [] {
    @End ()
    @MkBox (memref<?xi64>, !idr.self)
  }>
!Shared = !idr.graded<once, counted, !idr.data<#Box @MkBox>>
idr.program @shared root(@main) stage(first) {
  idr.func @main() {
    idr.return
  }
  idr.func @write(%box: !Shared, %x: i64, %j: index) -> i64 {
    %token, %a, %rest = idr.count.take_open %box : !Shared
    %zero = arith.constant 0 : index
    // expected-error @below {{expected in-place: }}
    %w = tensor.insert %x into %a[%zero] : tensor<?xi64>
    %e = tensor.extract %w[%j] : tensor<?xi64>
    idr.return %e : i64
  }
}
