// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr-pipeline{from=graded to=owned})' -o /dev/null
// A reindex that builds a cell gives a new value, holding a reference of
// its own that no other value holds, and moves its operand on into it; a
// value it gives that is then shared is counted as any shared value.
// Four words in place hold no reference; laid out open, as at a length
// unknown at compile time, the same vector is a cell, so @make's cast
// builds it, counted, and gives it back; used many times, it claims nothing
// before references are counted. @main passes the vector to @keep
// twice, which reads its head and gives it back: the first call takes a
// second reference while the second still needs the vector, and each
// vector given back is given up. The slice from the graded stage to the
// owned stage is verified after every pass, so it verifies, with nothing
// expected, only where counting and the linearity rule read the cast's
// result as a value of its own, moved on once by the return, never a part
// of the words it was built from, and the shared vector is counted with
// one reference per holder.
#Vect = #idr.family<"Vect" [nat] {
    @Nil where 0 ()
    @Cons <nat> where v0 + 1 (i64, !idr.self[v0])
  }>
!V0 = !idr.data<#Vect[0]>
!V1 = !idr.data<#Vect[1]>
!V2 = !idr.data<#Vect[2]>
!V3 = !idr.data<#Vect[3]>
!V4 = !idr.data<#Vect[4]>
!Shared = !idr.data<#Vect[4] open>
idr.program @shares root(@main) stage(graded) {
  idr.func @main() {
    %seven = arith.constant 7 : i64
    %v = idr.call @make(%seven) <{tail_kind = nontail}> : (i64) -> !Shared
    %a:2 = idr.call @keep(%v) <{tail_kind = nontail}> : (!Shared) -> (i64, !Shared)
    %b:2 = idr.call @keep(%v) <{tail_kind = nontail}> : (!Shared) -> (i64, !Shared)
    %sum = arith.addi %a#0, %b#0 : i64
    %text = idr.str.show_sint %sum : (i64) -> !idr.str
    idr.io.put_str %text : (!idr.str) -> ()
    idr.return
  }
  idr.func @make(%x: i64) -> !Shared {
    %nil = idr.data.con() : !V0
    %v1 = idr.data.con(%x : i64, %nil : !V0) : !V1
    %v2 = idr.data.con(%x : i64, %v1 : !V1) : !V2
    %v3 = idr.data.con(%x : i64, %v2 : !V2) : !V3
    %v4 = idr.data.con(%x : i64, %v3 : !V3) : !V4
    %built = idr.data.reindex %v4 : !V4 to !Shared
    idr.return %built : !Shared
  }
  idr.func @keep(%v: !Shared) -> (i64, !Shared) {
    %head = idr.data.field %v[0] : !Shared -> i64
    idr.return %head, %v : i64, !Shared
  }
}
