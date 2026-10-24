// RUN: idris-mlir-opt %s -split-input-file --pass-pipeline='builtin.module(idr-pipeline{from=first to=first},idr-expect{holds=in-place=@write})' -verify-diagnostics -o /dev/null
// A field holds an array as its buffer, and the array is opened from the
// value that holds it, so what that value claims of its sharing decides
// whether the array may be written in place: a value that claims its own
// cells unshared holds the only reference to its buffer's storage, and
// one that claims less gives an array a write copies first. @write opens
// the array a box holds, writes a word into it and reads back the word at
// an index it is given, so no fold takes the write away. In the first
// program the box @write is given claims its own cells unshared, and once
// its arrays are buffers nothing copies one. In the second it claims
// nothing, so the write copies the array first, which the property reports
// at the write. Nothing calls @write, so its box is its parameter as
// written.
#Box = #idr.family<"Box" [] {
    @MkBox (memref<?xi64>)
  }>
!Unique = !idr.graded<once, counted unique self, !idr.data<#Box @MkBox>>
idr.program @unique root(@main) stage(first) {
  idr.func @main() {
    idr.return
  }
  idr.func @write(%box: !Unique, %x: i64, %j: index) -> i64 {
    %a = idr.array.open %box[0] : !Unique -> tensor<?xi64>
    %zero = arith.constant 0 : index
    %w = tensor.insert %x into %a[%zero] : tensor<?xi64>
    %e = tensor.extract %w[%j] : tensor<?xi64>
    idr.return %e : i64
  }
}

// -----

#Box = #idr.family<"Box" [] {
    @MkBox (memref<?xi64>)
  }>
!Shared = !idr.data<#Box @MkBox>
idr.program @shared root(@main) stage(first) {
  idr.func @main() {
    idr.return
  }
  idr.func @write(%box: !Shared, %x: i64, %j: index) -> i64 {
    %a = idr.array.open %box[0] : !Shared -> tensor<?xi64>
    %zero = arith.constant 0 : index
    // expected-error @below {{expected in-place: }}
    %w = tensor.insert %x into %a[%zero] : tensor<?xi64>
    %e = tensor.extract %w[%j] : tensor<?xi64>
    idr.return %e : i64
  }
}
