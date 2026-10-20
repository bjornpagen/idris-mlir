// RUN: sed -n 's|^// REFERENCE: ||p' %s > %t.reference.mlir
// RUN: %differential %s %t.reference.mlir
// RUN: idris-mlir-opt %s --canonicalize --cse --control-flow-sink -o %t.optimized.mlir
// RUN: %differential %t.optimized.mlir %t.reference.mlir
// RUN: sed 's/"BBAA"/"BAA"/' %t.reference.mlir > %t.wrong.mlir
// RUN: not %differential %s %t.wrong.mlir 2>&1 | FileCheck %s
// RUN: idris-mlir-opt %s --test-idr-facts -verify-diagnostics=only-expected -o /dev/null
// Identical IO operations are neither merged nor removed, even unused: no
// IO op may be dropped, moved, delayed or merged, which is what dead code
// removal and CSE ask.
//
// So every one runs, in order: the program writes B twice on two forged
// worlds, then A twice and reads two bytes it never uses, and writes BBAA
// whatever it reads, as the REFERENCE lines do in one write; it means the
// same as written and after the folds, CSE and control-flow sinking, on
// inputs of no, one, two and three bytes. A reference that writes one B
// fewer is told apart. The facts come last, so that the run holds whatever
// they find.
// CHECK: differential: effects-io.mlir and {{.*}}wrong.mlir differ on ''
// STDIN:
// STDIN: x
// STDIN: xy
// STDIN: xyz

idr.program @io root(@Prog.main) stage(first) types #idr.types<> {
  idr.func @io(%w: !idr.world) -> !idr.world {
    %c = arith.constant 65 : i32
    // expected-remark @below {{facts: []}}
    %w1 = idr.io.put_char %c, %w
    // expected-remark @below {{facts: []}}
    %w2 = idr.io.put_char %c, %w1
    // expected-remark @below {{facts: []}}
    %x, %w3 = idr.io.get_byte %w2
    // expected-remark @below {{facts: []}}
    %y, %w4 = idr.io.get_byte %w3
    return %w4 : !idr.world
  }

  // A forged world (a trusted library's unsafePerformIO) starts a chain of
  // its own; two of them are two, however alike, and neither is removed, nor
  // the IO on them: the effects order them where no world does. A forged
  // world itself performs nothing and reads no memory, so it may be made
  // later, up to its first use, which stays where it is.
  idr.func @forged(%c: i32) {
    // expected-remark @below {{facts: [delay]}}
    %w = idr.world.new
    // expected-remark @below {{facts: []}}
    %w1 = idr.io.put_char %c, %w
    // expected-remark @below {{facts: [delay]}}
    %v = idr.world.new
    // expected-remark @below {{facts: []}}
    %v1 = idr.io.put_char %c, %v
    return
  }
  // The program: the forged writes, then the IO of @io.
  idr.func @Prog.main(%w: !idr.world) -> !idr.world {
    %b = arith.constant 66 : i32
    idr.call @forged(%b) : (i32) -> ()
    %w1 = idr.call @io(%w) : (!idr.world) -> !idr.world
    return %w1 : !idr.world
  }
}
// REFERENCE: idr.program @reference root(@Prog.main) stage(first) types #idr.types<> {
// REFERENCE:   idr.func @Prog.main(%w: !idr.world) -> !idr.world {
// REFERENCE:     %s = idr.constant !idr.str "BBAA"
// REFERENCE:     %w1 = idr.io.put_str %s, %w
// REFERENCE:     return %w1 : !idr.world
// REFERENCE:   }
// REFERENCE: }
