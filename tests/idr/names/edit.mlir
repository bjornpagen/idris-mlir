// RUN: sed 's/%q = arith.subi %y, %k : i64/%q = arith.muli %y, %k : i64/' %s > %t.edited.mlir
// RUN: idris-mlir-opt %s --idr-optimize -o %t.mlir
// RUN: idris-mlir-opt %t.edited.mlir --idr-optimize -o %t.edited.out.mlir
// RUN: not cmp -s %s %t.edited.mlir
// RUN: sed -n 's/^ *idr\.func \(private \)\{0,1\}@\([^(]*\)(.*/\2/p' %t.mlir | grep -v '^scale' | sort > %t.names
// RUN: sed -n 's/^ *idr\.func \(private \)\{0,1\}@\([^(]*\)(.*/\2/p' %t.edited.out.mlir | grep -v '^scale' | sort > %t.edited.names
// RUN: grep -q '[.]spec[.]' %t.names
// RUN: diff %t.names %t.edited.names
// NEEDS-ACCEPTANCE: that the optimizer makes the specialization nodes here, as C09's binding-time rule allows.
// One definition edited leaves every other symbol where it was: the
// first RUN line changes the body of @scale alone, and every function the
// optimizer keeps or makes that is not @scale's, the specializations of
// @apply among them, has the same name in both modules, since a name is a
// function of its own key, never of the module around it.
module {
  idr.func private @apply(%k: i64, %n: i64) -> i64 attributes {total} {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      idr.yield %k : i64
    }
    default {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %y = idr.call @apply(%k, %m) : (i64, i64) -> i64
      %s = arith.addi %y, %k : i64
      idr.yield %s : i64
    }
    }
    return %r : i64
  }
  idr.func private @scale(%k: i64, %n: i64) -> i64 attributes {total} {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      idr.yield %k : i64
    }
    default {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %y = idr.call @scale(%k, %m) : (i64, i64) -> i64
      %q = arith.subi %y, %k : i64
      idr.yield %q : i64
    }
    }
    return %r : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %k1 = arith.constant 1 : i64
    %k2 = arith.constant 2 : i64
    %k3 = arith.constant 3 : i64
    %a = idr.call @apply(%k1, %n) : (i64, i64) -> i64
    %b = idr.call @apply(%k2, %n) : (i64, i64) -> i64
    %d = idr.call @scale(%k3, %n) : (i64, i64) -> i64
    %ab = arith.addi %a, %b : i64
    %r = arith.addi %ab, %d : i64
    %w2 = idr.io.put_int signed %r, %w1 : i64
    return %w2 : !idr.world
  }
}
