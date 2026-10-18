// NEEDS-ACCEPTANCE: that by-name and not-by-name read the memo labels of a sum a parameter holds (the label written in the data type's body as this wave prints a role), and that the -verify-diagnostics run passes: one error each where the label's flag is the other, and one where no label names the function, all at the module.
// RUN: idris-mlir-opt %s --idr-expect=holds=by-name=@loud,not-by-name=@quiet -o /dev/null
// RUN: idris-mlir-opt %s --idr-expect=holds=by-name=@quiet,not-by-name=@loud,by-name=@hold -verify-diagnostics -o /dev/null
// expected-error @-4 {{expected by-name: the label @quiet of @quiet is not by_name}}
// expected-error @-5 {{expected not-by-name: the label @loud of @loud is by_name}}
// expected-error @-6 {{expected by-name: no memo label of the program names @hold}}
// A memo label runs again at every force when it is by_name, as one whose
// run the outside sees is (@loud), and keeps its value otherwise (@quiet);
// a function no label names (@hold) is neither. Each error is the
// module's, which has no line: the file's line 0.
!M = !idr.data<"M", memo [@loud() label @loud by_name, @quiet() label @quiet, @running() running, @forced(i64) forced]>
idr.program @"by-name" root(@root) stage(first) {
  idr.func @loud() -> i64 attributes {total} {
    %w = idr.world.new
    %c = arith.constant 1 : i64
    %w1 = idr.io.put_sint %c, %w : i64
    return %c : i64
  }
  idr.func @quiet() -> i64 attributes {total} {
    %c = arith.constant 2 : i64
    return %c : i64
  }
  idr.func @hold(%t: !idr.box<!M>) -> !idr.box<!M> {
    return %t : !idr.box<!M>
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
