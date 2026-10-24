// RUN: idris-mlir-opt %s -split-input-file --pass-pipeline='builtin.module(idr-pipeline{from=first to=first},idr-expect{holds=no-guards=@main})' -verify-diagnostics -o /dev/null
// A guard reads the value it checks as the value it is, through each cast
// into or out of a linear position the value passed: a cast changes a
// grade, never what a guard checks. In the first program a character read
// at run time put before a line read at run time, a string never empty, is
// cast into a linear position and checked not empty: no guard is left. In
// the second a line read at run time is checked not empty, cast into a
// linear position and checked again: the second guard checks what the
// first did, and only the first is left.
!S1 = !idr.graded<once, counted, !idr.str>
idr.program @consed root(@main) stage(first) {
  idr.func @main() {
    %byte = idr.io.get_byte : () -> i32
    %line = idr.io.get_line : () -> !idr.str
    %s = idr.str.cons %byte, %line : (i32, !idr.str) -> !idr.str
    %once = idr.lin.cast %s : !idr.str -> !S1
    %checked = idr.check.nonempty %once, head_of_empty_string at #idr.site<"Main.idr", 3, 5, "Main.main"> : (!S1) -> !S1
    %many = idr.lin.cast %checked : !S1 -> !idr.str
    idr.io.put_str %many : (!idr.str) -> ()
    idr.return
  }
}

// -----

!S1 = !idr.graded<once, counted, !idr.str>
idr.program @repeated root(@main) stage(first) {
  idr.func @main() {
    %line = idr.io.get_line : () -> !idr.str
    // expected-error @below {{expected no-guards: }}
    %first = idr.check.nonempty %line, head_of_empty_string at #idr.site<"Main.idr", 3, 5, "Main.main"> : (!idr.str) -> !idr.str
    %once = idr.lin.cast %first : !idr.str -> !S1
    %again = idr.check.nonempty %once, head_of_empty_string at #idr.site<"Main.idr", 4, 5, "Main.main"> : (!S1) -> !S1
    %many = idr.lin.cast %again : !S1 -> !idr.str
    idr.io.put_str %many : (!idr.str) -> ()
    idr.return
  }
}
