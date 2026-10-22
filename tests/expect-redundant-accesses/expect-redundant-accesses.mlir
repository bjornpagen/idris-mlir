// RUN: idris-mlir-opt %s -split-input-file --idr-expect=holds=writes-forwarded,overwrites-dropped -verify-diagnostics -o /dev/null
// Two accesses of one element of mutable memory, the second right after
// the first with only computation between, in a program whose references
// are not yet counted. In the first program each such pair is reported at
// the access that should have gone: @forwards' read, @computes' read past
// an addition, @overwrites' first write. Its near misses are not: accesses
// of two array values (@others), a write after a read of another array
// value (@readBetween), and a value Idris proved used once, whose one use
// the pair is (@onceRead, @onceOverwritten). The second program counts its
// references, so neither property is stated of it, and each fails there.
!Ref = memref<i64, #idr.mutable>
!Once = !idr.graded<once, i64>
idr.program @accesses root(@main) stage(first) {
  idr.func @main() -> i64 {
    %c = arith.constant 0 : i64
    idr.return %c : i64
  }
  idr.func @forwards(%r: !Ref, %x: i64) -> i64 {
    idr.array.set %r[], %x : !Ref, i64
    // expected-error @below {{expected writes-forwarded: }}
    %y = idr.array.get %r[] : !Ref -> i64
    idr.return %y : i64
  }
  idr.func @computes(%r: !Ref, %x: i64) -> i64 {
    idr.array.set %r[], %x : !Ref, i64
    %d = arith.addi %x, %x : i64
    // expected-error @below {{expected writes-forwarded: }}
    %y = idr.array.get %r[] : !Ref -> i64
    %s = arith.addi %y, %d : i64
    idr.return %s : i64
  }
  idr.func @overwrites(%r: !Ref, %x: i64, %y: i64) -> i64 {
    // expected-error @below {{expected overwrites-dropped: }}
    idr.array.set %r[], %x : !Ref, i64
    idr.array.set %r[], %y : !Ref, i64
    idr.return %y : i64
  }
  idr.func @others(%a: !Ref, %b: !Ref, %x: i64, %z: i64) -> i64 {
    idr.array.set %a[], %x : !Ref, i64
    %y = idr.array.get %b[] : !Ref -> i64
    idr.array.set %b[], %z : !Ref, i64
    idr.array.set %a[], %z : !Ref, i64
    idr.return %y : i64
  }
  idr.func @readBetween(%r: !Ref, %q: !Ref, %x: i64, %z: i64) -> i64 {
    idr.array.set %r[], %x : !Ref, i64
    %y = idr.array.get %q[] : !Ref -> i64
    idr.array.set %r[], %z : !Ref, i64
    idr.return %y : i64
  }
  idr.func @onceRead(%r: !Ref, %x: !Once) -> i64 {
    idr.array.set %r[], %x : !Ref, !Once
    %y = idr.array.get %r[] : !Ref -> i64
    idr.return %y : i64
  }
  idr.func @onceOverwritten(%r: !Ref, %x: !Once, %z: i64) -> i64 {
    idr.array.set %r[], %x : !Ref, !Once
    idr.array.set %r[], %z : !Ref, i64
    idr.return %z : i64
  }
}

// -----

// expected-error @below {{expected writes-forwarded: }}
// expected-error @below {{expected overwrites-dropped: }}
idr.program @counted root(@main) stage(owned) {
  idr.func @main() -> i64 {
    %c = arith.constant 0 : i64
    idr.return %c : i64
  }
}
