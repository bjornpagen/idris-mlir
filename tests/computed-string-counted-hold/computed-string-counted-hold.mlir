// RUN: idris-mlir-opt %s -split-input-file --pass-pipeline='builtin.module(idr-pipeline{from=first to=first},idr-expect{holds=folded=@ab})' -verify-diagnostics -o /dev/null
// A string computed from constants, "a" ++ "b", typed as a primitive's
// result is, at a hold its count frees, where its constant cannot stand:
// static data stands only at a static hold. After the first stage it is
// the constant wherever a use takes static data in its place, and left to
// be computed where a use asks its own type. In the first program an op
// that only reads it compares it with a line of standard input, and the
// comparison is written out: nothing a fold would replace is left in @ab.
// In the second @ab gives it back at the hold @ab's signature states, so
// the append is left there; @ab calls itself too, so it stays a function
// of its own wherever @main's call goes, and @main writes out what it
// gives.
!Str = !idr.graded<many, static, !idr.str>
idr.program @compared root(@ab) stage(first) {
  idr.func @ab() {
    %a = idr.constant !Str "a"
    %b = idr.constant !Str "b"
    %ab = idr.str.append %a, %b : (!Str, !Str) -> !idr.str
    %line = idr.io.get_line : () -> !idr.str
    %same = idr.str.cmp eq %ab, %line : (!idr.str, !idr.str) -> i1
    %written = arith.extui %same : i1 to i32
    idr.io.put_char %written : (i32) -> ()
    idr.return
  }
}

// -----

!Str = !idr.graded<many, static, !idr.str>
idr.program @returned root(@main) stage(first) {
  idr.func @ab() -> !idr.str {
    %again = idr.call @ab() <{tail_kind = nontail}> : () -> !idr.str
    %a = idr.constant !Str "a"
    %b = idr.constant !Str "b"
    // expected-error @below {{expected folded: }}
    %ab = idr.str.append %a, %b : (!Str, !Str) -> !idr.str
    idr.return %ab : !idr.str
  }
  idr.func @main() {
    %given = idr.call @ab() <{tail_kind = nontail}> : () -> !idr.str
    idr.io.put_str %given : (!idr.str) -> ()
    idr.return
  }
}
