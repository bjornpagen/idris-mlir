// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics
// The rules of a whole program, which its idr.program holds: it names its
// root, an idr.func of it of one of the two kinds of root, and its stage,
// and the program's rules run from the program's verifier: the data types
// it holds, and what each stage lets a value and an op hold. A function's
// visibility is no fact of its own: the root is public, every other
// function private.

// expected-error @+1 {{has root @missing, which is no idr.func of the program}}
idr.program @program root(@missing) stage(first) types #idr.types<> {
  idr.func @a() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}

// -----

idr.program @program root(@a) stage(first) types #idr.types<> {
  // expected-error @+1 {{is the root, so its type must be}}
  idr.func @a(%x: i64) -> i64 {
    return %x : i64
  }
}

// -----

// Both kinds of root: one whose result is the program's exit status, and
// one whose run is the program, which gives back the world and what holds
// no runtime value, as the frontend's IO result of a unit does.
idr.program @program root(@a) stage(first) types #idr.types<> {
  idr.func @a() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}

// -----

!Unit = !idr.data<"Unit">
!IORes = !idr.data<"IORes">
#types = #idr.types<
  "IORes" = plain [@MkIORes(!Unit, !idr.world)],
  "Unit" = plain [@MkUnit()]
>
idr.program @program root(@a) stage(first) types #types {
  idr.func @a(%w: !idr.world) -> !IORes {
    %u = idr.con !Unit @MkUnit()
    %r = idr.con !IORes @MkIORes(%u : !Unit, %w : !idr.world)
    return %r : !IORes
  }
}

// -----

!Unit = !idr.data<"Unit">
#types = #idr.types<
  "Unit" = plain [@MkUnit()]
>
idr.program @program root(@a) stage(first) types #types {
  idr.func @a(%w: !idr.world) -> (!Unit, !idr.world) {
    %u = idr.con !Unit @MkUnit()
    return %u, %w : !Unit, !idr.world
  }
}

// -----

// An IO root's results hold nothing the program reports: a status beside
// the world is no exit status, and the root is refused, not read as one.
idr.program @program root(@a) stage(first) types #idr.types<> {
  // expected-error @+1 {{is the root, so its type must be}}
  idr.func @a(%w: !idr.world) -> (!idr.world, i64) {
    %c = arith.constant 0 : i64
    return %w, %c : !idr.world, i64
  }
}

// -----

idr.program @program root(@a) stage(first) types #idr.types<> {
  // expected-error @+1 {{is the root, so its type must be}}
  idr.func @a(%w: !idr.world) -> (!idr.world, !idr.str) {
    %s = idr.constant !idr.str "a"
    return %w, %s : !idr.world, !idr.str
  }
}

// -----

// Containment in place is acyclic: a recursive type is held through a box.
!T = !idr.data<"T">
!U = !idr.data<"U">
#types = #idr.types<
  "T" = plain [@A(!idr.data<"U">)],
  "U" = plain [@B(!idr.data<"T">)]
>
// expected-error @+1 {{holds the data type "T", which contains itself in place}}
idr.program @program root(@a) stage(first) types #types {
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
!T = !idr.data<"T">
#types = #idr.types<
  "L" = list [@Nil() nil, @Cons(!idr.data<"T">, !idr.box<!idr.data<"L">>) cons],
  "T" = plain [@A(!idr.data<"U">)],
  "U" = plain [@B(!idr.box<!idr.data<"L">>)]
>
idr.program @program root(@a) stage(first) types #types {
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
!M = !idr.data<"M">
#types = #idr.types<
  "M" = memo [@k() label @k, @running() running, @forced(i64) forced]
>
// expected-error @+1 {{holds the memo sum "M" in place; a memo sum is held only in a box}}
idr.program @program root(@a) stage(first) types #types {
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

// A data type is its name wherever it is written, and its body is its
// program's table's: one the program reaches that the table does not
// declare has no body, and the program is refused.
// expected-error @+1 {{'idr.program' op reaches the data type "Nowhere", which its table does not declare}}
idr.program @program root(@a) stage(higher) types #idr.types<> {
  idr.func @a() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
  idr.func @b(%x: !idr.data<"Nowhere">) {
    return
  }
}

// -----

// A body that never returns ends in ub.unreachable, as a match region that
// crashes does: after a match none of whose regions returns, or after a
// crash.
idr.program @program root(@a) stage(first) types #idr.types<> {
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
idr.program @program root(@a) stage(higher) types #idr.types<> {
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

idr.program @program root(@a) stage(first) types #idr.types<> {
  idr.func @a() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
  // expected-error @+1 {{binds argument #0 of region #0, of type '!idr.fn<(i64) -> i64>', which holds a closure or a suspension in a program past the higher stage}}
  idr.func @apply(%f: !idr.fn<(i64) -> (i64)>, %x: i64) -> i64 {
    %r = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
    return %r : i64
  }
}

// -----

idr.program @program root(@a) stage(owned) types #idr.types<> {
  idr.func @a() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
  // expected-error @+1 {{binds argument #0 of region #0, of type '!idr.lazy<i64>', which holds a closure or a suspension in a program past the higher stage}}
  idr.func @force(%t: !idr.lazy<i64>) -> i64 {
    %v = idr.force %t : !idr.lazy<i64> -> i64
    return %v : i64
  }
}

// -----

// A grade own or excl exists only once idr-rc counts references.
idr.program @program root(@a) stage(first) types #idr.types<> {
  idr.func @a() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
  // expected-error @+1 {{binds argument #0 of region #0, of type '!idr.own<!idr.str>', which is graded own or excl in a program before the graded stage}}
  idr.func @keeps(%s: !idr.own<!idr.str>) -> !idr.own<!idr.str> {
    return %s : !idr.own<!idr.str>
  }
}

// -----

// In the owned stage every reference of ours is graded: owned, exclusive,
// or a view, borrowed. A plain one says nothing of who frees it.
idr.program @program root(@a) stage(owned) types #idr.types<> {
  idr.func @a() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
  // expected-error @+1 {{binds argument #0 of region #0, of type '!idr.str', which holds references at the plain grade in a graded program}}
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
idr.program @program root(@a) stage(graded) types #idr.types<> {
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

idr.program @program root(@a) stage(owned) types #idr.types<> {
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
idr.program @program root(@a) stage(owned) types #idr.types<> {
  idr.func @a() -> i64 {
    %s = idr.constant !idr.q<many, borrow, !idr.str> "abc"
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
idr.program @program root(@main) stage(lowered) types #idr.types<> {
  // expected-error @+1 {{is an idr.func in a lowered program, which holds upstream's functions}}
  idr.func @main() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}

// -----

idr.program @program root(@main) stage(lowered) types #idr.types<> {
  func.func @main() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}

// -----

// Lowered, an IO root takes and gives nothing: the world and what holds no
// runtime value have no form.
idr.program @program root(@main) stage(lowered) types #idr.types<> {
  func.func @main() {
    return
  }
}

// -----

// expected-error @+1 {{has root @main, which is no func.func of the program}}
idr.program @program root(@main) stage(lowered) types #idr.types<> {
}

// -----

idr.program @program root(@a) stage(lowered) types #idr.types<> {
  // expected-error @+1 {{is the root, so its type must be}}
  func.func @a() -> (i64, i64) {
    %c = arith.constant 0 : i64
    %d = arith.constant 1 : i64
    return %c, %d : i64, i64
  }
}

// -----

// In the owned stage a buffer is a cell of the runtime: its elements start
// a word aligned and no more, and its layout is a cell's.
idr.program @program root(@a) stage(owned) types #idr.types<> {
  idr.func @a() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
  idr.func @wide(%n: index) -> memref<?xf64> {
    // expected-error @+1 {{is aligned to 64 bytes, past a cell's element, whose alignment is at most 8}}
    %b = "memref.alloc"(%n) <{alignment = 64 : i64, operandSegmentSizes = array<i32: 1, 0>}> : (index) -> memref<?xf64>
    return %b : memref<?xf64>
  }
}

// -----

idr.program @program root(@a) stage(owned) types #idr.types<> {
  idr.func @a() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
  idr.func @strided() -> memref<4x4xf64, strided<[1, 4]>> {
    // expected-error @+1 {{allocates 'memref<4x4xf64, strided<[1, 4]>>', whose layout is not a cell's}}
    %b = memref.alloc() : memref<4x4xf64, strided<[1, 4]>>
    return %b : memref<4x4xf64, strided<[1, 4]>>
  }
}

// -----

idr.program @program root(@a) stage(owned) types #idr.types<> {
  idr.func @a() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
  // expected-error @+1 {{binds argument #0 of region #0, of type 'memref<8xf64, affine_map<(d0) -> (d0 floordiv 2)>>', which is a buffer of no strided layout}}
  idr.func @halves(%b: memref<8xf64, affine_map<(d0) -> (d0 floordiv 2)>>) {
    return
  }
}

// -----

idr.program @program root(@a) stage(owned) types #idr.types<> {
  idr.func @a() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
  // expected-error @+1 {{is aligned to 64 bytes, past a cell's element, whose alignment is at most 8}}
  "memref.global"() <{alignment = 64 : i64, constant, initial_value = dense<[1, 2]> : tensor<2xi64>, sym_name = "table", sym_visibility = "private", type = memref<2xi64>}> : () -> ()
}

// -----

// Past the higher stage no linalg op reads or writes an element that holds
// references: idr-structure-loops makes them only of arrays of words.
idr.program @program root(@a) stage(first) types #idr.types<> {
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

// -----

// The alignment a buffer may have is at most a cell element's, 8 bytes:
// the next, 16, is refused as 64 is.
idr.program @program root(@a) stage(owned) types #idr.types<> {
  idr.func @a() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
  idr.func @wide(%n: index) -> !idr.own<memref<?xf64>> {
    // expected-error @+1 {{is aligned to 16 bytes, past a cell's element, whose alignment is at most 8}}
    %b = "memref.alloc"(%n) <{alignment = 16 : i64, operandSegmentSizes = array<i32: 1, 0>}> : (index) -> memref<?xf64>
    %o = idr.own.adopt %b : memref<?xf64>
    return %o : !idr.own<memref<?xf64>>
  }
}

// -----

// The nearest the refusals above have that verifies, where none is above:
// a memo sum held in a box; a data type written with its body; buffers
// aligned to 8 bytes, the most a cell's element has, in an allocation and
// a global; a buffer of the identity layout, and one of a strided layout,
// the one a cell's is; and a linalg op of words.
!M = !idr.data<"M">
#types = #idr.types<
  "M" = memo [@k() label @k, @running() running, @forced(i64) forced],
  "Somewhere" = plain [@S()]
>
idr.program @program root(@a) stage(first) types #types {
  idr.func @k() -> i64 {
    %c = arith.constant 1 : i64
    return %c : i64
  }
  idr.func @a() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
  idr.func @b(%m: !idr.box<!M>) -> !idr.box<!M> {
    return %m : !idr.box<!M>
  }
  idr.func @c(%x: !idr.data<"Somewhere">) {
    return
  }
  idr.func @copies(%in: tensor<4xi64>, %out: tensor<4xi64>) -> tensor<4xi64> {
    %r = linalg.generic {indexing_maps = [affine_map<(d0) -> (d0)>, affine_map<(d0) -> (d0)>],
                         iterator_types = ["parallel"]}
        ins(%in : tensor<4xi64>) outs(%out : tensor<4xi64>) {
    ^bb0(%x: i64, %y: i64):
      linalg.yield %x : i64
    } -> tensor<4xi64>
    return %r : tensor<4xi64>
  }
}

// -----

idr.program @program root(@a) stage(owned) types #idr.types<> {
  idr.func @a() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
  idr.func @aligned(%n: index) -> !idr.own<memref<?xf64>> {
    %b = "memref.alloc"(%n) <{alignment = 8 : i64, operandSegmentSizes = array<i32: 1, 0>}> : (index) -> memref<?xf64>
    %o = idr.own.adopt %b : memref<?xf64>
    return %o : !idr.own<memref<?xf64>>
  }
  idr.func @plain() -> !idr.own<memref<4x4xf64>> {
    %b = memref.alloc() : memref<4x4xf64>
    %o = idr.own.adopt %b : memref<4x4xf64>
    return %o : !idr.own<memref<4x4xf64>>
  }
  idr.func @strided(%b: memref<8xf64, strided<[1]>>) {
    return
  }
  "memref.global"() <{alignment = 8 : i64, constant, initial_value = dense<[1, 2]> : tensor<2xi64>, sym_name = "table", sym_visibility = "private", type = memref<2xi64>}> : () -> ()
}
