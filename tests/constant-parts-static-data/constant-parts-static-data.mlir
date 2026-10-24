// RUN: idris-mlir-opt %s -split-input-file -o /dev/null
// A constant is static data, used any number of times, and so is each of
// its parts: a field is used as often as the value holding it times its
// own uses and holds what that value holds, so a string a constant holds
// is static data, which nothing frees and no count writes, as the constant
// is. In the first program a record of a word and a string is a constant,
// and the string read off it is written out at the static hold the read
// gives. In the second a vector of two strings is a constant of one run of
// two cells, and the string in the second cell is static data as the one
// in the first is. Both verify.
#P = #idr.family<"P" [] {
    @MkP (i64, !idr.str)
  }>
!MkP = !idr.data<#P @MkP>
!MkPS = !idr.graded<many, static, !idr.data<#P @MkP>>
!Str = !idr.graded<many, static, !idr.str>
idr.program @record root(@main) stage(higher) {
  idr.func @main() {
    %p = idr.constant !MkPS #idr.con<!MkP, [3 : i64, "x"]>
    %x = idr.data.field %p[1] : !MkPS -> !Str
    idr.io.put_str %x : (!Str) -> ()
    idr.return
  }
}

// -----

#Vect = #idr.family<"Vect" [nat] {
    @Nil where 0 ()
    @Cons <nat> where v0 + 1 (!idr.str, !idr.self[v0])
  }>
!V0 = !idr.data<#Vect[0]>
!V1 = !idr.data<#Vect[1]>
!V2 = !idr.data<#Vect[2]>
!V2S = !idr.graded<many, static, !idr.data<#Vect[2]>>
idr.program @run root(@main) stage(higher) {
  idr.func @main() {
    %v = idr.constant !V2S #idr.con<!V2, ["a", #idr.con<!V1, ["b", #idr.con<!V0, []>]>]>
    idr.return
  }
}
