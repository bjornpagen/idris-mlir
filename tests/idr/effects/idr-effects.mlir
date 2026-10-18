// RUN: idris-mlir-opt %s --idr-effects --idr-expect=holds=\
// RUN: effects=@pure:none,\
// RUN: effects=@divides_safely:none,\
// RUN: effects=@divides:crash,\
// RUN: effects=@crashes_in_region:crash,\
// RUN: effects=@transfers:io+crash,\
// RUN: effects=@writes:io,\
// RUN: effects=@passes_world:io,\
// RUN: effects=@finishes:io,\
// RUN: effects=@calls:io+crash,\
// RUN: effects=@ping:crash,\
// RUN: effects=@pong:crash,\
// RUN: effects=@builds_divider:none,\
// RUN: effects=@has_sum_divider:none,\
// RUN: effects=@runs:crash,\
// RUN: effects=@everything:io+crash+diverge,\
// RUN: effects=@forges:io,\
// RUN: effects=@loops:diverge,\
// RUN: effects=@method:diverge,\
// RUN: effects=@method_user:diverge,\
// RUN: effects=@proved_cycle:none -o /dev/null
// RUN: idris-mlir-opt %s --idr-effects --idr-effects --idr-expect=holds=\
// RUN: effects=@pure:none,\
// RUN: effects=@divides_safely:none,\
// RUN: effects=@divides:crash,\
// RUN: effects=@crashes_in_region:crash,\
// RUN: effects=@transfers:io+crash,\
// RUN: effects=@writes:io,\
// RUN: effects=@passes_world:io,\
// RUN: effects=@finishes:io,\
// RUN: effects=@calls:io+crash,\
// RUN: effects=@ping:crash,\
// RUN: effects=@pong:crash,\
// RUN: effects=@builds_divider:none,\
// RUN: effects=@has_sum_divider:none,\
// RUN: effects=@runs:crash,\
// RUN: effects=@everything:io+crash+diverge,\
// RUN: effects=@forges:io,\
// RUN: effects=@loops:diverge,\
// RUN: effects=@method:diverge,\
// RUN: effects=@method_user:diverge,\
// RUN: effects=@proved_cycle:none -o /dev/null
// NEEDS-ACCEPTANCE: syntax swept to the data-type-first form
// idr-effects: what each function of a defunctionalized program may do,
// held by the function alone; a call's are its callee's. `io` when the
// function takes a world, as a parameter or in data one holds, or forges
// one; `crash` when it reaches an op that may crash; `diverge` when it
// reaches a body without Idris's proof (`total`), its own included. It
// reaches what it calls and the labels a dispatch of its runs; building a
// constructor of a sum of closures runs nothing. A function that may do
// all three holds no set, which the dialect reads as anything. Running the
// pass again changes nothing.

// A sum of closures as idr-defunctionalize makes it: one constructor per
// label, naming its function.
!IORes = !idr.data<"IORes", plain [@MkIORes(i64, !idr.world)]>
!fn$0 = !idr.data<"fn$0", closures [@divides() label @divides, @pure() label @pure]>
idr.program @"idr-effects" root(@passes_world) stage(first) {
  idr.func @pure(%x: i64) -> i64 attributes {total} {
    %r = arith.addi %x, %x : i64
    return %r : i64
  }

  // A division by a nonzero constant cannot crash, and needs no guard; a
  // stale fact goes.
  idr.func effects<io, crash> @divides_safely(%x: i64) -> i64 attributes {total} {
    %c = arith.constant 3 : i64
    %r = idr.divs %x, %c : i64
    return %r : i64
  }

  idr.func @divides(%x: i64) -> i64 attributes {total} {
    %y = idr.check.nonzero %x, "division by zero" : i64
    %r = idr.divs %x, %y : i64
    return %r : i64
  }

  idr.func @crashes_in_region(%x: i64) -> i64 attributes {total} {
    %r = idr.match_lit %x : i64 -> (i64) {
    case 0 {
      idr.yield %x : i64
    }
    default(%d: i64) {
      idr.crash "no"
      ub.unreachable
    }
    }
    return %r : i64
  }

  // A byte transfer ends the program when its range lies outside the buffer:
  // io, and the crash of the guard of its range.
  idr.func @transfers(%buf: memref<?xi8, #idr.world>, %w: !idr.world) -> !idr.world attributes {total} {
    %zero = arith.constant 0 : i64
    %one = arith.constant 1 : i64
    %c0 = arith.constant 0 : index
    %d = memref.dim %buf, %c0 : memref<?xi8, #idr.world>
    %size = arith.index_cast %d : index to i64
    %at = idr.check.range %zero, %one, %size, "a byte range outside the buffer"
    %written, %w1 = idr.io.write_bytes %one, %buf[%at, %one], %w : memref<?xi8, #idr.world>
    %again = idr.check.range %zero, %one, %size, "a byte range outside the buffer"
    %read, %w2 = idr.io.read_bytes %zero, %buf[%again, %one], %w1 : memref<?xi8, #idr.world>
    return %w2 : !idr.world
  }

  // Taking a world is performing IO, whatever the body does with it.
  idr.func @writes(%w: !idr.world) -> !idr.world attributes {total} {
    %c = arith.constant 65 : i32
    %w1 = idr.io.put_char %c, %w
    return %w1 : !idr.world
  }
  idr.func @passes_world(%w: !idr.world) -> !idr.world attributes {total} {
    return %w : !idr.world
  }
  // A world in data counts too.
  idr.func @finishes(%r: !IORes) -> !idr.world attributes {total} {
    %w = idr.field %r : !IORes @MkIORes[1] -> !idr.world
    %w1 = idr.call @writes(%w) : (!idr.world) -> !idr.world
    return %w1 : !idr.world
  }

  // Crashes flow through calls, and around a cycle of calls.
  idr.func @calls(%x: i64, %w: !idr.world) -> !idr.world attributes {total} {
    %q = idr.call @divides(%x) : (i64) -> i64
    %w1 = idr.call @writes(%w) : (!idr.world) -> !idr.world
    return %w1 : !idr.world
  }
  idr.func @ping(%x: i64) -> i64 attributes {total} {
    %r = idr.call @pong(%x) : (i64) -> i64
    return %r : i64
  }
  idr.func @pong(%x: i64) -> i64 attributes {total} {
    %y = idr.call @ping(%x) : (i64) -> i64
    %r = idr.call @divides(%y) : (i64) -> i64
    return %r : i64
  }

  // Building a closure runs nothing, whatever its label may do: a
  // constructor of a sum of closures, built or a constant, is a value.
  idr.func @builds_divider() -> !fn$0 attributes {total} {
    %c = idr.con !fn$0 @divides()
    return %c : !fn$0
  }
  idr.func @has_sum_divider() -> !fn$0 attributes {total} {
    %c = idr.constant !fn$0 #idr.con<!fn$0, @divides, []>
    return %c : !fn$0
  }

  // Running one is a dispatch on its sum, each arm a call of its label: it
  // may do what any of them may.
  idr.func @runs(%f: !fn$0, %x: i64) -> i64 attributes {total} {
    %r = idr.match %f : !fn$0 -> (i64) {
    case @divides() {
      %d = idr.call @divides(%x) : (i64) -> i64
      idr.yield %d : i64
    }
    case @pure() {
      %p = idr.call @pure(%x) : (i64) -> i64
      idr.yield %p : i64
    }
    }
    return %r : i64
  }

  // A function that may do everything carries no attribute: no writer
  // stores the full set.
  idr.func @everything(%x: i64, %w: !idr.world) -> !idr.world {
    %d = idr.call @divides(%x) : (i64) -> i64
    %w1 = idr.call @everything(%d, %w) : (i64, !idr.world) -> !idr.world
    return %w1 : !idr.world
  }

  // A world forged in the body is IO that no parameter announces.
  idr.func @forges(%c: i32) attributes {total} {
    %w = idr.world.new
    %w1 = idr.io.put_char %c, %w
    return
  }

  // A body without Idris's proof may diverge, and so may whatever reaches
  // it: by a call, around a cycle, or by a dispatch on a label of it. Idris's proof
  // of a function does not stop it: the proof counts the calls Idris saw,
  // and a call of an interface's method reaches its implementation only
  // once the dictionary is known, as @method_user's call of @method does.
  idr.func @loops(%x: i64) -> i64 {
    %r = idr.call @loops(%x) : (i64) -> i64
    return %r : i64
  }
  idr.func @method(%x: i64) -> i64 attributes {total} {
    %r = idr.call @loops(%x) : (i64) -> i64
    return %r : i64
  }
  idr.func @method_user(%x: i64) -> i64 attributes {total} {
    %r = idr.call @method(%x) : (i64) -> i64
    return %r : i64
  }
  // A cycle Idris proved does not diverge.
  idr.func @proved_cycle(%x: i64) -> i64 attributes {total} {
    %r = idr.call @proved_cycle(%x) : (i64) -> i64
    return %r : i64
  }
}
