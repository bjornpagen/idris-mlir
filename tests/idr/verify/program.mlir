// NEEDS-ACCEPTANCE: the texts of the program verifier's errors and the ops they are reported at, the root's kinds (a world and a status refused, IORes of a unit and a unit beside the world accepted), the graded stage (grades admitted, counts not yet checked), and the owned stage's buffer and linalg rules.
// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics
// The rules of a whole program, which its idr.program holds: it names its
// root, an idr.func of it of one of the two kinds of root, and its stage,
// and the program's rules run from the program's verifier: the data types
// it holds, and what each stage lets a value and an op hold. A function's
// visibility is no fact of its own: the root is public, every other
// function private.

// expected-error @+1 {{has root @missing, which is no idr.func of the program}}
idr.program @program root(@missing) stage(first) {
  idr.func @a() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}

// -----

idr.program @program root(@a) stage(first) {
  // expected-error @+1 {{is the root, so its type must be () -> i64, or before lowering (!idr.world) -> (...) with no result holding a runtime value, or lowered () -> (); not '(i64) -> i64'}}
  idr.func @a(%x: i64) -> i64 {
    return %x : i64
  }
}

// -----

// Both kinds of root: one whose result is the program's exit status, and
// one whose run is the program, which gives back the world and what holds
// no runtime value, as the frontend's IO result of a unit does.
idr.program @program root(@a) stage(first) {
  idr.func @a() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}

// -----

!Unit = !idr.data<"Unit", plain [@MkUnit()]>
!IORes = !idr.data<"IORes", plain [@MkIORes(!Unit, !idr.world)]>
idr.program @program root(@a) stage(first) {
  idr.func @a(%w: !idr.world) -> !IORes {
    %u = idr.con !Unit @MkUnit()
    %r = idr.con !IORes @MkIORes(%u : !Unit, %w : !idr.world)
    return %r : !IORes
  }
}

// -----

!Unit = !idr.data<"Unit", plain [@MkUnit()]>
idr.program @program root(@a) stage(first) {
  idr.func @a(%w: !idr.world) -> (!Unit, !idr.world) {
    %u = idr.con !Unit @MkUnit()
    return %u, %w : !Unit, !idr.world
  }
}

// -----

// An IO root's results hold nothing the program reports: a status beside
// the world is no exit status, and the root is refused, not read as one.
idr.program @program root(@a) stage(first) {
  // expected-error @+1 {{is the root, so its type must be () -> i64, or before lowering (!idr.world) -> (...) with no result holding a runtime value, or lowered () -> (); not '(!idr.world) -> (!idr.world, i64)'}}
  idr.func @a(%w: !idr.world) -> (!idr.world, i64) {
    %c = arith.constant 0 : i64
    return %w, %c : !idr.world, i64
  }
}

// -----

idr.program @program root(@a) stage(first) {
  // expected-error @+1 {{is the root, so its type must be () -> i64, or before lowering (!idr.world) -> (...) with no result holding a runtime value, or lowered () -> (); not '(!idr.world) -> (!idr.world, !idr.str)'}}
  idr.func @a(%w: !idr.world) -> (!idr.world, !idr.str) {
    %s = idr.constant !idr.str "a"
    return %w, %s : !idr.world, !idr.str
  }
}

// -----

// Containment in place is acyclic: a recursive type is held through a box.
!T = !idr.data<"T", plain [@A(!idr.data<"U", plain [@B(!idr.data<"T">)]>)]>
!U = !idr.data<"U", plain [@B(!idr.data<"T", plain [@A(!idr.data<"U">)]>)]>
// expected-error @+1 {{holds the data type "T", which contains itself in place; a recursive type is held through a box}}
idr.program @program root(@a) stage(first) {
  idr.func @a() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
  idr.func @b(%t: !T) -> !T {
    return %t : !T
  }
}

// -----

// Every cycle passes through a box.
!T = !idr.data<"T", plain [@A(!idr.data<"U", plain [@B(!idr.box<!idr.data<"L", list [@Nil() nil, @Cons(!idr.data<"T">, !idr.box<!idr.data<"L">>) cons]>>)]>)]>
idr.program @program root(@a) stage(first) {
  idr.func @a() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
  idr.func @b(%t: !T) -> !T {
    return %t : !T
  }
}

// -----

// A memo sum is a cell two references share, so it is held only in a box.
!M = !idr.data<"M", memo [@k() label @k, @running() running, @forced(i64) forced]>
// expected-error @+1 {{holds the memo sum "M" in place; a memo sum is held only in a box}}
idr.program @program root(@a) stage(first) {
  idr.func @k() -> i64 {
    %c = arith.constant 1 : i64
    return %c : i64
  }
  idr.func @a() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
  idr.func @b(%m: !M) -> !M {
    return %m : !M
  }
}

// -----

// A data type carries its body wherever it is written, but inside its own
// body: one written by its name alone elsewhere is no type.
idr.program @program root(@a) stage(higher) {
  // expected-error @+1 {{a data type is written without its body only inside its own body}}
  idr.func @b(%f: !idr.fn<() -> (!idr.data<"Nowhere">)>) {
    return
  }
}

// -----

// A body that never returns ends in ub.unreachable, as a match region that
// crashes does: after a match none of whose regions returns, or after a
// crash.
idr.program @program root(@a) stage(first) {
  idr.func @never(%x: i64) -> i64 {
    idr.match_lit %x : i64 -> () {
    case 0 {
      idr.crash "zero"
      ub.unreachable
    }
    default(%d: i64) {
      idr.crash "no"
      ub.unreachable
    }
    }
    ub.unreachable
  }
  idr.func @crashes() -> i64 {
    idr.crash "no"
    ub.unreachable
  }
  idr.func @a() -> i64 {
    %c = arith.constant 0 : i64
    %r = idr.call @never(%c) : (i64) -> i64
    return %r : i64
  }
}

// -----

// The stage says what a value may hold, and the program says it, never
// what a function happens to hold. A closure or a suspension exists only
// in the higher stage: idr-defunctionalize makes each a sum.
idr.program @program root(@a) stage(higher) {
  idr.func @a() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
  idr.func @apply(%f: !idr.fn<(i64) -> (i64)>, %x: i64) -> i64 {
    %r = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
    return %r : i64
  }
  idr.func @force(%t: !idr.lazy<i64>) -> i64 {
    %v = idr.force %t : !idr.lazy<i64> -> i64
    return %v : i64
  }
}

// -----

idr.program @program root(@a) stage(first) {
  idr.func @a() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
  // expected-error @+1 {{binds argument #0 of region #0, of type '!idr.fn<(i64) -> (i64)>', which holds a closure or a suspension in a program past the higher stage, where idr-defunctionalize has made each a sum}}
  idr.func @apply(%f: !idr.fn<(i64) -> (i64)>, %x: i64) -> i64 {
    %r = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
    return %r : i64
  }
}

// -----

idr.program @program root(@a) stage(owned) {
  idr.func @a() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
  // expected-error @+1 {{binds argument #0 of region #0, of type '!idr.lazy<i64>', which holds a closure or a suspension in a program past the higher stage, where idr-defunctionalize has made each a sum}}
  idr.func @force(%t: !idr.lazy<i64>) -> i64 {
    %v = idr.force %t : !idr.lazy<i64> -> i64
    return %v : i64
  }
}

// -----

// A grade own or excl exists only once idr-rc counts references.
idr.program @program root(@a) stage(first) {
  idr.func @a() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
  // expected-error @+1 {{binds argument #0 of region #0, of type '!idr.own<!idr.str>', which is graded own or excl in a program before the graded stage, whose grades idr-rc gives}}
  idr.func @keeps(%s: !idr.own<!idr.str>) -> !idr.own<!idr.str> {
    return %s : !idr.own<!idr.str>
  }
}

// -----

// In the owned stage every reference of ours is graded: owned, exclusive,
// or a view, borrowed. A plain one says nothing of who frees it.
idr.program @program root(@a) stage(owned) {
  idr.func @a() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
  // expected-error @+1 {{binds argument #0 of region #0, of type '!idr.str', which holds references at the plain grade in a graded program, where a value of ours that holds one is owned, exclusive or borrowed}}
  idr.func @length(%s: !idr.str) -> i64 {
    %n = idr.str.length %s
    return %n : i64
  }
}

// -----

// Graded is not yet counted: idr-rc's grades step has graded every
// reference, and its placement has not yet made the counts exact, so an
// owned parameter nothing consumes verifies there, and only the owned
// stage's count walk refuses it.
idr.program @program root(@a) stage(graded) {
  idr.func @a() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
  idr.func @drops(%s: !idr.own<!idr.str>) -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}

// -----

idr.program @program root(@a) stage(owned) {
  idr.func @a() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
  // expected-note @+1 {{the value is defined here}}
  idr.func @drops(%s: !idr.own<!idr.str>) -> i64 {
    %z = arith.constant 0 : i64
    // expected-error @+1 {{returns while a value still holds a reference}}
    return %z : i64
  }
}

// -----

// A view is borrowed, a reference held is owned, and static data, which no
// count reaches, stays plain; a word holds no reference at all.
idr.program @program root(@a) stage(owned) {
  idr.func @a() -> i64 {
    %s = idr.constant !idr.str "abc"
    %n = idr.str.length borrow %s
    return %n : i64
  }
  idr.func @length(%s: !idr.q<many, borrow, !idr.str>) -> i64 {
    %n = idr.str.length borrow %s
    return %n : i64
  }
  idr.func @keeps(%s: !idr.own<!idr.str>) -> !idr.own<!idr.str> {
    return %s : !idr.own<!idr.str>
  }
}

// -----

// A lowered program holds upstream's functions: its root names one of
// them, and no idr.func is left.
idr.program @program root(@main) stage(lowered) {
  // expected-error @+1 {{is an idr.func in a lowered program, which holds upstream's functions}}
  idr.func @main() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}

// -----

idr.program @program root(@main) stage(lowered) {
  func.func @main() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}

// -----

// Lowered, an IO root takes and gives nothing: the world and what holds no
// runtime value have no form.
idr.program @program root(@main) stage(lowered) {
  func.func @main() {
    return
  }
}

// -----

// expected-error @+1 {{has root @main, which is no func.func of the program}}
idr.program @program root(@main) stage(lowered) {
}

// -----

idr.program @program root(@a) stage(lowered) {
  // expected-error @+1 {{is the root, so its type must be () -> i64, or before lowering (!idr.world) -> (...) with no result holding a runtime value, or lowered () -> (); not '() -> (i64, i64)'}}
  func.func @a() -> (i64, i64) {
    %c = arith.constant 0 : i64
    %d = arith.constant 1 : i64
    return %c, %d : i64, i64
  }
}

// -----

// In the owned stage a buffer is a cell of the runtime: its elements start
// a word aligned and no more, and its layout is a cell's.
idr.program @program root(@a) stage(owned) {
  idr.func @a() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
  idr.func @wide(%n: index) -> memref<?xf64> {
    // expected-error @+1 {{is aligned to 64 bytes, past a cell's element, whose alignment is at most 8}}
    %b = memref.alloc(%n) {alignment = 64 : i64} : memref<?xf64>
    return %b : memref<?xf64>
  }
}

// -----

idr.program @program root(@a) stage(owned) {
  idr.func @a() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
  idr.func @strided() -> memref<4x4xf64, strided<[1, 4]>> {
    // expected-error @+1 {{allocates 'memref<4x4xf64, strided<[1, 4]>>', whose layout is not a cell's, the identity}}
    %b = memref.alloc() : memref<4x4xf64, strided<[1, 4]>>
    return %b : memref<4x4xf64, strided<[1, 4]>>
  }
}

// -----

idr.program @program root(@a) stage(owned) {
  idr.func @a() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
  // expected-error @+1 {{binds argument #0 of region #0, of type 'memref<8xf64, affine_map<(d0) -> (d0 floordiv 2)>>', which is a buffer of no strided layout, whose descriptor the lowering cannot read}}
  idr.func @halves(%b: memref<8xf64, affine_map<(d0) -> (d0 floordiv 2)>>) {
    return
  }
}

// -----

idr.program @program root(@a) stage(owned) {
  idr.func @a() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
  // expected-error @+1 {{is aligned to 64 bytes, past a cell's element, whose alignment is at most 8}}
  memref.global "private" constant @table : memref<2xi64> = dense<[1, 2]> {alignment = 64 : i64}
}

// -----

// Past the higher stage no linalg op reads or writes an element that holds
// references: idr-structure-loops makes them only of arrays of words.
idr.program @program root(@a) stage(first) {
  idr.func @a() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
  idr.func @copies(%in: tensor<4x!idr.str>, %out: tensor<4x!idr.str>) -> tensor<4x!idr.str> {
    // expected-error @+1 {{binds argument #0 of region #0, of type '!idr.str', which holds references, an element no linalg op reads or writes past the higher stage}}
    %r = linalg.generic {indexing_maps = [affine_map<(d0) -> (d0)>, affine_map<(d0) -> (d0)>],
                         iterator_types = ["parallel"]}
        ins(%in : tensor<4x!idr.str>) outs(%out : tensor<4x!idr.str>) {
    ^bb0(%x: !idr.str, %y: !idr.str):
      linalg.yield %x : !idr.str
    } -> tensor<4x!idr.str>
    return %r : tensor<4x!idr.str>
  }
}
