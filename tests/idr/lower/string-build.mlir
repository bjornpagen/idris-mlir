// RUN: idris-mlir-opt %s --idr-lower | FileCheck %s
// A string built from a list is allocated once, at the size a first walk
// of the list counts, and written in a second walk: no string is built per
// element (no idris_rt_str_cons or idris_rt_str_append).
// CHECK-LABEL: func.func private @pack(
// CHECK-NOT: idris_rt_str_cons
// CHECK: scf.while
// CHECK: llvm.call @idris_rt_str_alloc(
// CHECK: scf.while
// CHECK: llvm.call @idris_rt_str_put_char(
// CHECK-NOT: idris_rt_str_cons
// CHECK-LABEL: func.func private @concat(
// CHECK-NOT: idris_rt_str_append
// CHECK: llvm.call @idris_rt_str_alloc(
// CHECK: llvm.call @idris_rt_str_put_str(
// CHECK-NOT: idris_rt_str_append
module attributes {idr.program, idr.stage = "owned"} {
  idr.data @Chars box {
    idr.ctor @Nil ()
    idr.ctor @Cons (i32, !idr.box<@Chars>)
  }
  idr.data @Strs box {
    idr.ctor @Nil ()
    idr.ctor @Cons (!idr.str, !idr.box<@Strs>)
  }
  func.func @root(%w: !idr.world) -> !idr.world {
    %cs = idr.constant #idr.con<@Chars::@Nil, []> : !idr.box<@Chars>
    %ss = idr.constant #idr.con<@Strs::@Nil, []> : !idr.box<@Strs>
    %a = func.call @pack(%cs) : (!idr.box<@Chars>) -> !idr.own<!idr.str>
    %b = func.call @concat(%ss) : (!idr.box<@Strs>) -> !idr.own<!idr.str>
    idr.drop %a : !idr.own<!idr.str>
    idr.drop %b : !idr.own<!idr.str>
    return %w : !idr.world
  }
  func.func private @pack(%xs: !idr.box<@Chars>) -> !idr.own<!idr.str> {
    %s = idr.str.pack %xs : !idr.box<@Chars> -> !idr.own<!idr.str>
    return %s : !idr.own<!idr.str>
  }
  func.func private @concat(%xs: !idr.box<@Strs>) -> !idr.own<!idr.str> {
    %s = idr.str.concat %xs : !idr.box<@Strs> -> !idr.own<!idr.str>
    return %s : !idr.own<!idr.str>
  }
}
