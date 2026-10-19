// RUN: awk 'BEGIN { ORS = "" } NR == 1, /^idr\.program / { print $0 "\n"; next } /^  idr\.func/ { n++ } /^\}$/ { for (i = 0; i <= n; i++) print c[i == 0 ? 0 : n + 1 - i]; print $0 "\n"; next } { c[n] = c[n] $0 "\n" }' %s > %t.reversed.mlir
// RUN: sed 's/%q = arith.subi %y, %x : i64/%q = arith.addi %y, %x : i64/' %s > %t.edited.mlir
// RUN: not cmp -s %s %t.edited.mlir
// RUN: sed -e 's/@apply(%k, %f,/@apply(%k, %h,/' -e 's/@apply(%k, %g,/@apply(%k, %f,/' -e 's/@apply(%k, %h,/@apply(%k, %g,/' %s > %t.swapped.mlir
// RUN: not cmp -s %s %t.swapped.mlir
// RUN: idris-mlir-opt %s --mlir-print-op-generic | grep -o 'sym_name = "[^"]*"' | sort > %t.input.names
// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr-defunctionalize,idr-optimize))' -o %t.optimized.mlir
// RUN: %differential %s %t.optimized.mlir
// RUN: idris-mlir-opt %t.optimized.mlir --mlir-print-op-generic | grep -o 'sym_name = "[^"]*"' | sort > %t.names
// RUN: comm -13 %t.input.names %t.names | grep -q .
// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr-defunctionalize,idr-optimize))' --mlir-disable-threading -o %t.serial.mlir
// RUN: idris-mlir-opt %t.reversed.mlir --pass-pipeline='builtin.module(idr.program(idr-defunctionalize,idr-optimize))' -o %t.reversed.optimized.mlir
// RUN: idris-mlir-opt %t.edited.mlir --pass-pipeline='builtin.module(idr.program(idr-defunctionalize,idr-optimize))' -o %t.edited.optimized.mlir
// RUN: idris-mlir-opt %t.swapped.mlir --pass-pipeline='builtin.module(idr.program(idr-defunctionalize,idr-optimize))' -o %t.swapped.optimized.mlir
// RUN: awk '/^    idr\.func/ { if (f != "") print f; f = $0; next } /^  }$/ { if (f != "") print f; f = ""; next } f != "" { f = f " " $0 }' %t.optimized.mlir | sort > %t.functions
// RUN: awk '/^    idr\.func/ { if (f != "") print f; f = $0; next } /^  }$/ { if (f != "") print f; f = ""; next } f != "" { f = f " " $0 }' %t.serial.mlir | sort | diff %t.functions -
// RUN: awk '/^    idr\.func/ { if (f != "") print f; f = $0; next } /^  }$/ { if (f != "") print f; f = ""; next } f != "" { f = f " " $0 }' %t.reversed.optimized.mlir | sort | diff %t.functions -
// RUN: awk '/^    idr\.func/ { if (f != "") print f; f = $0; next } /^  }$/ { if (f != "") print f; f = ""; next } f != "" { f = f " " $0 }' %t.edited.optimized.mlir | sort > %t.edited.functions
// RUN: grep -v '^    idr\.func [^@]*@scale' %t.functions > %t.kept
// RUN: grep -v '^    idr\.func [^@]*@scale' %t.edited.functions | diff %t.kept -
// RUN: grep '^    idr\.func [^@]*@scale' %t.functions > %t.scale
// RUN: grep '^    idr\.func [^@]*@scale' %t.edited.functions | not diff %t.scale -
// RUN: awk '/^    idr\.func/ { if (f != "") print f; f = $0; next } /^  }$/ { if (f != "") print f; f = ""; next } f != "" { f = f " " $0 }' %t.swapped.optimized.mlir | grep -v '^    idr\.func [^@]*@Main\.main(' | sort > %t.swapped.functions
// RUN: grep -v '^    idr\.func [^@]*@Main\.main(' %t.functions | diff - %t.swapped.functions
// A function the optimizer makes is named from its key, the function it
// copies and the static pattern it is copied for, never from a counter,
// from the order the work ran in or from the module around it. @apply is
// specialized on each of its two closures and @scale on its one, so the
// optimizer makes functions the input does not hold (its symbols, read off
// the generic form's `sym_name`, are not all the input's). Each function
// of the optimized module, its name with its body (one line of the custom
// form each, sorted), is then the same
// - when the passes run on one thread (--mlir-disable-threading);
// - when the module's functions come in reverse order (the first RUN line
//   writes it);
// - when the root calls @apply on its two closures in the other order (the
//   third RUN line), for every function but the root, whose body that
//   changes: a name counted in the order the calls are met would give the
//   copy of @apply for @mul the name the copy for @add had;
// - when the body of @scale alone is edited (the second RUN line), for
//   every function not made from @scale, the root's call of @scale's copy
//   among them; and the functions made from @scale differ, as they must,
//   so the comparison reads bodies.
// The optimized program means what the program as written does, on every
// one-byte input (%differential).
idr.program @keys root(@Main.main) stage(higher) {
  idr.func @add(%k: i64, %x: i64) -> i64 attributes {total} {
    %y = arith.addi %x, %k : i64
    return %y : i64
  }
  idr.func @mul(%k: i64, %x: i64) -> i64 attributes {total} {
    %y = arith.muli %x, %k : i64
    return %y : i64
  }
  idr.func @apply(%n: i64, %f: !idr.fn<(i64) -> (i64)>, %x: i64) -> i64 {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      idr.yield %x : i64
    }
    default(%d: i64) {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %y = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
      %z = idr.call @apply(%m, %f, %y) : (i64, !idr.fn<(i64) -> (i64)>, i64) -> i64
      idr.yield %z : i64
    }
    }
    return %r : i64
  }
  idr.func @scale(%n: i64, %f: !idr.fn<(i64) -> (i64)>, %x: i64) -> i64 {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      idr.yield %x : i64
    }
    default(%d: i64) {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %y = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
      %q = arith.subi %y, %x : i64
      %z = idr.call @scale(%m, %f, %q) : (i64, !idr.fn<(i64) -> (i64)>, i64) -> i64
      idr.yield %z : i64
    }
    }
    return %r : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %k = arith.extui %c : i32 to i64
    %f = idr.closure @add(%k) : (i64) -> !idr.fn<(i64) -> (i64)>
    %g = idr.closure @mul(%k) : (i64) -> !idr.fn<(i64) -> (i64)>
    %zero = arith.constant 0 : i64
    %a = idr.call @apply(%k, %f, %zero) : (i64, !idr.fn<(i64) -> (i64)>, i64) -> i64
    %b = idr.call @apply(%k, %g, %zero) : (i64, !idr.fn<(i64) -> (i64)>, i64) -> i64
    %d = idr.call @scale(%k, %g, %zero) : (i64, !idr.fn<(i64) -> (i64)>, i64) -> i64
    %ab = arith.addi %a, %b : i64
    %r = arith.addi %ab, %d : i64
    %w2 = idr.io.put_sint %r, %w1 : i64
    return %w2 : !idr.world
  }
}
