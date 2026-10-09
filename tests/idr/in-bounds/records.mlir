// RUN: idris-mlir-opt %s --idr-in-bounds --idr-expect=holds=in-bounds=@fields,in-bounds=@matched,in-bounds=@chosen,in-bounds=@clamped,in-bounds=@maxsi,in-bounds=@fill,in-bounds=@sorted,in-bounds=@rebuilt,in-bounds=@packed,in-bounds=@passed,bounds-checked=@apart,bounds-checked=@open,bounds-checked=@grown,bounds-checked=@wrapped,bounds-checked=@wrappedNext,bounds-checked=@predecessor -o /dev/null
// A size and the array it describes stay related when one constructor
// stored both, and after that record is read apart: two fields, the
// arguments of the constructor's match, or the record chosen by one
// condition. An array made from a size clamped at 0 — a match of the
// negative test, or a max — has that size's length. A counter from 0
// below the size, carried with the record, is inside the array the
// constructor stored. So is an index below n - 1 when n is at least 0,
// since only the smallest word wraps that subtraction.
// None of these is: a constructor that stores some other array's size;
// a record anyone may pass (the function is public); a size carried
// upward beside an array it does not grow; an index below n - 1 when n
// may be the smallest word, where n - 1 is the largest. A caller's
// counter being at least 0 is not a fact of the callee that receives it.
// A call that returns the record it was given, rebuilt around the same
// array, or that array read out of the record it returns, keeps the
// length that stayed outside.
module {
  idr.data @Pair {
    idr.ctor @MkPair (i64, memref<?xi64>)
  }
  idr.data @Arr {
    idr.ctor @MkArr (memref<?xi64>)
  }

  func.func @fields(%n: i64, %i: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %a, %w1 = idr.array.new [%n], %z, %w : i64 -> memref<?xi64>
    %rec = idr.con @Pair::@MkPair(%n, %a) : (i64, memref<?xi64>) -> !idr.data<@Pair>
    %sz = idr.field %rec[@MkPair, 0] : !idr.data<@Pair> -> i64
    %arr = idr.field %rec[@MkPair, 1] : !idr.data<@Pair> -> memref<?xi64>
    %lo = arith.cmpi sge, %i, %z : i64
    %hi = arith.cmpi slt, %i, %sz : i64
    %ok = arith.andi %lo, %hi : i1
    %r = scf.if %ok -> !idr.world {
      %ib1.z = arith.constant 0 : index
      %ib1.d = memref.dim %arr, %ib1.z : memref<?xi64>
      %ib1.n = arith.index_cast %ib1.d : index to i64
      %ib1 = idr.check.in_bounds %i, %ib1.n, "array index out of bounds"
      %s1 = idr.array.set %arr[%ib1], %i, %w1 : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %w1 : !idr.world
    }
    return %r : !idr.world
  }

  func.func @matched(%n: i64, %i: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %a, %w1 = idr.array.new [%n], %z, %w : i64 -> memref<?xi64>
    %rec = idr.con @Pair::@MkPair(%n, %a) : (i64, memref<?xi64>) -> !idr.data<@Pair>
    %r = idr.match %rec : !idr.data<@Pair> -> (!idr.world) {
    case @MkPair(%sz: i64, %arr: memref<?xi64>) {
      %lo = arith.cmpi sge, %i, %z : i64
      %hi = arith.cmpi slt, %i, %sz : i64
      %ok = arith.andi %lo, %hi : i1
      %s = scf.if %ok -> !idr.world {
        %ib2.z = arith.constant 0 : index
        %ib2.d = memref.dim %arr, %ib2.z : memref<?xi64>
        %ib2.n = arith.index_cast %ib2.d : index to i64
        %ib2 = idr.check.in_bounds %i, %ib2.n, "array index out of bounds"
        %s1 = idr.array.set %arr[%ib2], %i, %w1 : memref<?xi64>, i64
        scf.yield %s1 : !idr.world
      } else {
        scf.yield %w1 : !idr.world
      }
      idr.yield %s : !idr.world
    }
    }
    return %r : !idr.world
  }

  func.func @chosen(%c: i1, %n: i64, %m: i64, %i: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %a, %w1 = idr.array.new [%n], %z, %w : i64 -> memref<?xi64>
    %b, %w2 = idr.array.new [%m], %z, %w1 : i64 -> memref<?xi64>
    %p = idr.con @Pair::@MkPair(%n, %a) : (i64, memref<?xi64>) -> !idr.data<@Pair>
    %q = idr.con @Pair::@MkPair(%m, %b) : (i64, memref<?xi64>) -> !idr.data<@Pair>
    %rec = arith.select %c, %p, %q : !idr.data<@Pair>
    %sz = idr.field %rec[@MkPair, 0] : !idr.data<@Pair> -> i64
    %arr = idr.field %rec[@MkPair, 1] : !idr.data<@Pair> -> memref<?xi64>
    %lo = arith.cmpi sge, %i, %z : i64
    %hi = arith.cmpi slt, %i, %sz : i64
    %ok = arith.andi %lo, %hi : i1
    %r = scf.if %ok -> !idr.world {
      %ib3.z = arith.constant 0 : index
      %ib3.d = memref.dim %arr, %ib3.z : memref<?xi64>
      %ib3.n = arith.index_cast %ib3.d : index to i64
      %ib3 = idr.check.in_bounds %i, %ib3.n, "array index out of bounds"
      %s1 = idr.array.set %arr[%ib3], %i, %w2 : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %w2 : !idr.world
    }
    return %r : !idr.world
  }

  func.func @clamped(%n: i64, %i: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %neg = arith.cmpi slt, %n, %z : i64
    %negI = arith.extui %neg : i1 to i64
    %made = idr.match_lit %negI : i64 -> (i64) {
    case 0 {
      idr.yield %n : i64
    }
    default {
      idr.yield %z : i64
    }
    }
    %a, %w1 = idr.array.new [%made], %z, %w : i64 -> memref<?xi64>
    %lo = arith.cmpi sge, %i, %z : i64
    %hi = arith.cmpi slt, %i, %n : i64
    %ok = arith.andi %lo, %hi : i1
    %r = scf.if %ok -> !idr.world {
      %ib4.z = arith.constant 0 : index
      %ib4.d = memref.dim %a, %ib4.z : memref<?xi64>
      %ib4.n = arith.index_cast %ib4.d : index to i64
      %ib4 = idr.check.in_bounds %i, %ib4.n, "array index out of bounds"
      %s1 = idr.array.set %a[%ib4], %i, %w1 : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %w1 : !idr.world
    }
    return %r : !idr.world
  }

  func.func @maxsi(%n: i64, %i: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %made = arith.maxsi %n, %z : i64
    %a, %w1 = idr.array.new [%made], %z, %w : i64 -> memref<?xi64>
    %lo = arith.cmpi sge, %i, %z : i64
    %hi = arith.cmpi slt, %i, %n : i64
    %ok = arith.andi %lo, %hi : i1
    %r = scf.if %ok -> !idr.world {
      %ib5.z = arith.constant 0 : index
      %ib5.d = memref.dim %a, %ib5.z : memref<?xi64>
      %ib5.n = arith.index_cast %ib5.d : index to i64
      %ib5 = idr.check.in_bounds %i, %ib5.n, "array index out of bounds"
      %s1 = idr.array.set %a[%ib5], %i, %w1 : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %w1 : !idr.world
    }
    return %r : !idr.world
  }

  func.func @filled(%n: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %neg = arith.cmpi slt, %n, %z : i64
    %negI = arith.extui %neg : i1 to i64
    %made = idr.match_lit %negI : i64 -> (i64) {
    case 0 {
      idr.yield %n : i64
    }
    default {
      idr.yield %z : i64
    }
    }
    %a, %w1 = idr.array.new [%made], %z, %w : i64 -> memref<?xi64>
    %rec = idr.con @Arr::@MkArr(%a) : (memref<?xi64>) -> !idr.data<@Arr>
    %r = func.call @fill(%n, %rec, %w1) : (i64, !idr.data<@Arr>, !idr.world) -> !idr.world
    return %r : !idr.world
  }
  func.func private @fill(%n: i64, %rec: !idr.data<@Arr>, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %one = arith.constant 1 : i64
    %r:4 = scf.while (%k = %n, %a = %rec, %i = %z, %s = %w) : (i64, !idr.data<@Arr>, i64, !idr.world) -> (i64, !idr.data<@Arr>, i64, !idr.world) {
      %c = arith.cmpi slt, %i, %k : i64
      %e = arith.extui %c : i1 to i64
      %d:5 = idr.match_lit %e : i64 -> (i1, i64, !idr.data<@Arr>, i64, !idr.world) {
      case 0 {
        %false = arith.constant false
        %p = ub.poison : i64
        %u = ub.poison : !idr.data<@Arr>
        idr.yield %false, %p, %u, %p, %s : i1, i64, !idr.data<@Arr>, i64, !idr.world
      }
      default {
        %arr = idr.field %a[@MkArr, 0] : !idr.data<@Arr> -> memref<?xi64>
        %ib6.z = arith.constant 0 : index
        %ib6.d = memref.dim %arr, %ib6.z : memref<?xi64>
        %ib6.n = arith.index_cast %ib6.d : index to i64
        %ib6 = idr.check.in_bounds %i, %ib6.n, "array index out of bounds"
        %s1 = idr.array.set %arr[%ib6], %i, %s : memref<?xi64>, i64
        %j = arith.addi %i, %one : i64
        %b = idr.con @Arr::@MkArr(%arr) : (memref<?xi64>) -> !idr.data<@Arr>
        %true = arith.constant true
        idr.yield %true, %k, %b, %j, %s1 : i1, i64, !idr.data<@Arr>, i64, !idr.world
      }
      }
      scf.condition(%d#0) %d#1, %d#2, %d#3, %d#4 : i64, !idr.data<@Arr>, i64, !idr.world
    } do {
    ^bb0(%k: i64, %a: !idr.data<@Arr>, %i: i64, %s: !idr.world):
      scf.yield %k, %a, %i, %s : i64, !idr.data<@Arr>, i64, !idr.world
    }
    return %r#3 : !idr.world
  }

  func.func @sorted(%n: i64, %i: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %one = arith.constant 1 : i64
    %neg = arith.cmpi slt, %n, %z : i64
    %negI = arith.extui %neg : i1 to i64
    %made = idr.match_lit %negI : i64 -> (i64) {
    case 0 {
      idr.yield %n : i64
    }
    default {
      idr.yield %z : i64
    }
    }
    %a, %w1 = idr.array.new [%made], %z, %w : i64 -> memref<?xi64>
    %rec = idr.con @Arr::@MkArr(%a) : (memref<?xi64>) -> !idr.data<@Arr>
    %nonneg = arith.cmpi sge, %n, %z : i64
    %r = scf.if %nonneg -> !idr.world {
      %arr = idr.field %rec[@MkArr, 0] : !idr.data<@Arr> -> memref<?xi64>
      %last = arith.subi %n, %one : i64
      %lo = arith.cmpi sge, %i, %z : i64
      %hi = arith.cmpi slt, %i, %last : i64
      %ok = arith.andi %lo, %hi : i1
      %s = scf.if %ok -> !idr.world {
        %ib7.z = arith.constant 0 : index
        %ib7.d = memref.dim %arr, %ib7.z : memref<?xi64>
        %ib7.n = arith.index_cast %ib7.d : index to i64
        %ib7 = idr.check.in_bounds %i, %ib7.n, "array index out of bounds"
        %v, %s1 = idr.array.get %arr[%ib7], %w1 : memref<?xi64> -> i64
        %j = arith.addi %i, %one : i64
        %ib8.z = arith.constant 0 : index
        %ib8.d = memref.dim %arr, %ib8.z : memref<?xi64>
        %ib8.n = arith.index_cast %ib8.d : index to i64
        %ib8 = idr.check.in_bounds %j, %ib8.n, "array index out of bounds"
        %s2 = idr.array.set %arr[%ib8], %v, %s1 : memref<?xi64>, i64
        scf.yield %s2 : !idr.world
      } else {
        scf.yield %w1 : !idr.world
      }
      scf.yield %s : !idr.world
    } else {
      scf.yield %w1 : !idr.world
    }
    return %r : !idr.world
  }

  // The size stored beside the array is not the size the array was made with.
  func.func @apart(%n: i64, %m: i64, %i: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %a, %w1 = idr.array.new [%n], %z, %w : i64 -> memref<?xi64>
    %rec = idr.con @Pair::@MkPair(%m, %a) : (i64, memref<?xi64>) -> !idr.data<@Pair>
    %sz = idr.field %rec[@MkPair, 0] : !idr.data<@Pair> -> i64
    %arr = idr.field %rec[@MkPair, 1] : !idr.data<@Pair> -> memref<?xi64>
    %lo = arith.cmpi sge, %i, %z : i64
    %hi = arith.cmpi slt, %i, %sz : i64
    %ok = arith.andi %lo, %hi : i1
    %r = scf.if %ok -> !idr.world {
      %ib9.z = arith.constant 0 : index
      %ib9.d = memref.dim %arr, %ib9.z : memref<?xi64>
      %ib9.n = arith.index_cast %ib9.d : index to i64
      %ib9 = idr.check.in_bounds %i, %ib9.n, "array index out of bounds"
      %s1 = idr.array.set %arr[%ib9], %i, %w1 : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %w1 : !idr.world
    }
    return %r : !idr.world
  }

  func.func @open(%rec: !idr.data<@Pair>, %i: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %sz = idr.field %rec[@MkPair, 0] : !idr.data<@Pair> -> i64
    %arr = idr.field %rec[@MkPair, 1] : !idr.data<@Pair> -> memref<?xi64>
    %lo = arith.cmpi sge, %i, %z : i64
    %hi = arith.cmpi slt, %i, %sz : i64
    %ok = arith.andi %lo, %hi : i1
    %r = scf.if %ok -> !idr.world {
      %ib10.z = arith.constant 0 : index
      %ib10.d = memref.dim %arr, %ib10.z : memref<?xi64>
      %ib10.n = arith.index_cast %ib10.d : index to i64
      %ib10 = idr.check.in_bounds %i, %ib10.n, "array index out of bounds"
      %s1 = idr.array.set %arr[%ib10], %i, %w : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %w : !idr.world
    }
    return %r : !idr.world
  }

  func.func @grown(%n: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %one = arith.constant 1 : i64
    %a, %w1 = idr.array.new [%n], %z, %w : i64 -> memref<?xi64>
    %rec = idr.con @Arr::@MkArr(%a) : (memref<?xi64>) -> !idr.data<@Arr>
    %r:4 = scf.while (%k = %n, %b = %rec, %i = %z, %s = %w1) : (i64, !idr.data<@Arr>, i64, !idr.world) -> (i64, !idr.data<@Arr>, i64, !idr.world) {
      %lo = arith.cmpi sge, %i, %z : i64
      %hi = arith.cmpi slt, %i, %k : i64
      %c = arith.andi %lo, %hi : i1
      scf.condition(%c) %k, %b, %i, %s : i64, !idr.data<@Arr>, i64, !idr.world
    } do {
    ^bb0(%k: i64, %b: !idr.data<@Arr>, %i: i64, %s: !idr.world):
      %arr = idr.field %b[@MkArr, 0] : !idr.data<@Arr> -> memref<?xi64>
      %ib11.z = arith.constant 0 : index
      %ib11.d = memref.dim %arr, %ib11.z : memref<?xi64>
      %ib11.n = arith.index_cast %ib11.d : index to i64
      %ib11 = idr.check.in_bounds %i, %ib11.n, "array index out of bounds"
      %s1 = idr.array.set %arr[%ib11], %i, %s : memref<?xi64>, i64
      %k1 = arith.addi %k, %one overflow<nsw> : i64
      %j = arith.addi %i, %one overflow<nsw> : i64
      scf.yield %k1, %b, %j, %s1 : i64, !idr.data<@Arr>, i64, !idr.world
    }
    return %r#3 : !idr.world
  }

  func.func @wrapped(%n: i64, %i: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %one = arith.constant 1 : i64
    %neg = arith.cmpi slt, %n, %z : i64
    %negI = arith.extui %neg : i1 to i64
    %made = idr.match_lit %negI : i64 -> (i64) {
    case 0 {
      idr.yield %n : i64
    }
    default {
      idr.yield %z : i64
    }
    }
    %a, %w1 = idr.array.new [%made], %z, %w : i64 -> memref<?xi64>
    %rec = idr.con @Arr::@MkArr(%a) : (memref<?xi64>) -> !idr.data<@Arr>
    %arr = idr.field %rec[@MkArr, 0] : !idr.data<@Arr> -> memref<?xi64>
    %last = arith.subi %n, %one : i64
    %lo = arith.cmpi sge, %i, %z : i64
    %hi = arith.cmpi slt, %i, %last : i64
    %ok = arith.andi %lo, %hi : i1
    %r = scf.if %ok -> !idr.world {
      %ib12.z = arith.constant 0 : index
      %ib12.d = memref.dim %arr, %ib12.z : memref<?xi64>
      %ib12.n = arith.index_cast %ib12.d : index to i64
      %ib12 = idr.check.in_bounds %i, %ib12.n, "array index out of bounds"
      %s1 = idr.array.set %arr[%ib12], %i, %w1 : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %w1 : !idr.world
    }
    return %r : !idr.world
  }

  func.func @wrappedNext(%n: i64, %i: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %one = arith.constant 1 : i64
    %neg = arith.cmpi slt, %n, %z : i64
    %negI = arith.extui %neg : i1 to i64
    %made = idr.match_lit %negI : i64 -> (i64) {
    case 0 {
      idr.yield %n : i64
    }
    default {
      idr.yield %z : i64
    }
    }
    %a, %w1 = idr.array.new [%made], %z, %w : i64 -> memref<?xi64>
    %rec = idr.con @Arr::@MkArr(%a) : (memref<?xi64>) -> !idr.data<@Arr>
    %arr = idr.field %rec[@MkArr, 0] : !idr.data<@Arr> -> memref<?xi64>
    %last = arith.subi %n, %one : i64
    %lo = arith.cmpi sge, %i, %z : i64
    %hi = arith.cmpi slt, %i, %last : i64
    %ok = arith.andi %lo, %hi : i1
    %r = scf.if %ok -> !idr.world {
      %j = arith.addi %i, %one : i64
      %ib13.z = arith.constant 0 : index
      %ib13.d = memref.dim %arr, %ib13.z : memref<?xi64>
      %ib13.n = arith.index_cast %ib13.d : index to i64
      %ib13 = idr.check.in_bounds %j, %ib13.n, "array index out of bounds"
      %s1 = idr.array.set %arr[%ib13], %i, %w1 : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %w1 : !idr.world
    }
    return %r : !idr.world
  }

  // The caller counts n up from 0 and builds the array from n clamped at
  // 0. The callee's own counter starts at 0 and steps while it is below
  // n - 1. The caller's bound does not enter the callee, and the clamp
  // does not make n at least 0, so n may be the smallest word: n - 1 is
  // then the largest, and the counter is inside the comparison and
  // outside the array. The access one past that counter follows an
  // access that did run, which has already excluded that word.
  func.func @count(%n: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %one = arith.constant 1 : i64
    %r:3 = scf.while (%k = %n, %i = %z, %s = %w) : (i64, i64, !idr.world) -> (i64, i64, !idr.world) {
      %c = arith.cmpi slt, %i, %k : i64
      scf.condition(%c) %k, %i, %s : i64, i64, !idr.world
    } do {
    ^bb0(%k: i64, %i: i64, %s: !idr.world):
      %neg = arith.cmpi slt, %i, %z : i64
      %negI = arith.extui %neg : i1 to i64
      %made = idr.match_lit %negI : i64 -> (i64) {
      case 0 {
        idr.yield %i : i64
      }
      default {
        idr.yield %z : i64
      }
      }
      %a, %s1 = idr.array.new [%made], %z, %s : i64 -> memref<?xi64>
      %rec = idr.con @Arr::@MkArr(%a) : (memref<?xi64>) -> !idr.data<@Arr>
      %s2 = func.call @predecessor(%i, %rec, %s1) : (i64, !idr.data<@Arr>, !idr.world) -> !idr.world
      %j = arith.addi %i, %one : i64
      scf.yield %k, %j, %s2 : i64, i64, !idr.world
    }
    return %r#2 : !idr.world
  }
  func.func private @rewrap(%rec: !idr.data<@Arr>) -> !idr.data<@Arr> {
    %arr = idr.field %rec[@MkArr, 0] : !idr.data<@Arr> -> memref<?xi64>
    %b = idr.con @Arr::@MkArr(%arr) : (memref<?xi64>) -> !idr.data<@Arr>
    return %b : !idr.data<@Arr>
  }
  func.func @rebuilt(%n: i64, %i: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %a, %w1 = idr.array.new [%n], %z, %w : i64 -> memref<?xi64>
    %rec = idr.con @Arr::@MkArr(%a) : (memref<?xi64>) -> !idr.data<@Arr>
    %back = func.call @rewrap(%rec) : (!idr.data<@Arr>) -> !idr.data<@Arr>
    %arr = idr.field %back[@MkArr, 0] : !idr.data<@Arr> -> memref<?xi64>
    %lo = arith.cmpi sge, %i, %z : i64
    %hi = arith.cmpi slt, %i, %n : i64
    %ok = arith.andi %lo, %hi : i1
    %r = scf.if %ok -> !idr.world {
      %ib14.z = arith.constant 0 : index
      %ib14.d = memref.dim %arr, %ib14.z : memref<?xi64>
      %ib14.n = arith.index_cast %ib14.d : index to i64
      %ib14 = idr.check.in_bounds %i, %ib14.n, "array index out of bounds"
      %s1 = idr.array.set %arr[%ib14], %i, %w1 : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %w1 : !idr.world
    }
    return %r : !idr.world
  }

  func.func private @pack(%rec: !idr.data<@Arr>) -> !idr.data<@Pair> {
    %arr = idr.field %rec[@MkArr, 0] : !idr.data<@Arr> -> memref<?xi64>
    %z = arith.constant 0 : i64
    %p = idr.con @Pair::@MkPair(%z, %arr) : (i64, memref<?xi64>) -> !idr.data<@Pair>
    return %p : !idr.data<@Pair>
  }
  func.func @packed(%n: i64, %i: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %a, %w1 = idr.array.new [%n], %z, %w : i64 -> memref<?xi64>
    %rec = idr.con @Arr::@MkArr(%a) : (memref<?xi64>) -> !idr.data<@Arr>
    %back = func.call @pack(%rec) : (!idr.data<@Arr>) -> !idr.data<@Pair>
    %arr = idr.field %back[@MkPair, 1] : !idr.data<@Pair> -> memref<?xi64>
    %lo = arith.cmpi sge, %i, %z : i64
    %hi = arith.cmpi slt, %i, %n : i64
    %ok = arith.andi %lo, %hi : i1
    %r = scf.if %ok -> !idr.world {
      %ib15.z = arith.constant 0 : index
      %ib15.d = memref.dim %arr, %ib15.z : memref<?xi64>
      %ib15.n = arith.index_cast %ib15.d : index to i64
      %ib15 = idr.check.in_bounds %i, %ib15.n, "array index out of bounds"
      %s1 = idr.array.set %arr[%ib15], %i, %w1 : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %w1 : !idr.world
    }
    return %r : !idr.world
  }

  func.func private @inner(%rec: !idr.data<@Arr>) -> !idr.data<@Arr> {
    return %rec : !idr.data<@Arr>
  }
  func.func private @outer(%rec: !idr.data<@Arr>) -> !idr.data<@Pair> {
    %back = func.call @inner(%rec) : (!idr.data<@Arr>) -> !idr.data<@Arr>
    %arr = idr.field %back[@MkArr, 0] : !idr.data<@Arr> -> memref<?xi64>
    %z = arith.constant 0 : i64
    %p = idr.con @Pair::@MkPair(%z, %arr) : (i64, memref<?xi64>) -> !idr.data<@Pair>
    return %p : !idr.data<@Pair>
  }
  // The array comes back from a call, and that call's result is what the
  // outer function returns inside a record. The field read outside is the
  // array the caller passed.
  func.func @passed(%n: i64, %i: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %a, %w1 = idr.array.new [%n], %z, %w : i64 -> memref<?xi64>
    %rec = idr.con @Arr::@MkArr(%a) : (memref<?xi64>) -> !idr.data<@Arr>
    %back = func.call @outer(%rec) : (!idr.data<@Arr>) -> !idr.data<@Pair>
    %arr = idr.field %back[@MkPair, 1] : !idr.data<@Pair> -> memref<?xi64>
    %lo = arith.cmpi sge, %i, %z : i64
    %hi = arith.cmpi slt, %i, %n : i64
    %ok = arith.andi %lo, %hi : i1
    %r = scf.if %ok -> !idr.world {
      %ib16.z = arith.constant 0 : index
      %ib16.d = memref.dim %arr, %ib16.z : memref<?xi64>
      %ib16.n = arith.index_cast %ib16.d : index to i64
      %ib16 = idr.check.in_bounds %i, %ib16.n, "array index out of bounds"
      %s1 = idr.array.set %arr[%ib16], %i, %w1 : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %w1 : !idr.world
    }
    return %r : !idr.world
  }

  func.func private @predecessor(%n: i64, %rec: !idr.data<@Arr>, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %one = arith.constant 1 : i64
    %r:4 = scf.while (%k = %n, %a = %rec, %i = %z, %s = %w) : (i64, !idr.data<@Arr>, i64, !idr.world) -> (i64, !idr.data<@Arr>, i64, !idr.world) {
      %last = arith.subi %k, %one : i64
      %c = arith.cmpi slt, %i, %last : i64
      %e = arith.extui %c : i1 to i64
      %d:5 = idr.match_lit %e : i64 -> (i1, i64, !idr.data<@Arr>, i64, !idr.world) {
      case 0 {
        %false = arith.constant false
        %p = ub.poison : i64
        %u = ub.poison : !idr.data<@Arr>
        idr.yield %false, %p, %u, %p, %s : i1, i64, !idr.data<@Arr>, i64, !idr.world
      }
      default {
        %arr = idr.field %a[@MkArr, 0] : !idr.data<@Arr> -> memref<?xi64>
        %ib17.z = arith.constant 0 : index
        %ib17.d = memref.dim %arr, %ib17.z : memref<?xi64>
        %ib17.n = arith.index_cast %ib17.d : index to i64
        %ib17 = idr.check.in_bounds %i, %ib17.n, "array index out of bounds"
        %v, %s1 = idr.array.get %arr[%ib17], %s : memref<?xi64> -> i64
        %j = arith.addi %i, %one : i64
        %ib18.z = arith.constant 0 : index
        %ib18.d = memref.dim %arr, %ib18.z : memref<?xi64>
        %ib18.n = arith.index_cast %ib18.d : index to i64
        %ib18 = idr.check.in_bounds %j, %ib18.n, "array index out of bounds"
        %s2 = idr.array.set %arr[%ib18], %v, %s1 : memref<?xi64>, i64
        %true = arith.constant true
        idr.yield %true, %k, %a, %j, %s2 : i1, i64, !idr.data<@Arr>, i64, !idr.world
      }
      }
      scf.condition(%d#0) %d#1, %d#2, %d#3, %d#4 : i64, !idr.data<@Arr>, i64, !idr.world
    } do {
    ^bb0(%k: i64, %a: !idr.data<@Arr>, %i: i64, %s: !idr.world):
      scf.yield %k, %a, %i, %s : i64, !idr.data<@Arr>, i64, !idr.world
    }
    return %r#3 : !idr.world
  }
}
