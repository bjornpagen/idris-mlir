// RUN: idris-mlir-opt %s -split-input-file -o /dev/null
// A constant is static data, used any number of times, and so is each of
// its parts: a field is used as often as the value holding it times its
// own uses and holds what that value holds, so a string a constant holds
// is static data, which nothing frees and no count writes, as the constant
// is. In the first program a record of a word and a string is a constant,
// and the string read off it is written out at the static hold the read
// gives. In the second a vector of two strings is a constant of one run of
// two cells, and the string in the second cell is static data as the one
// in the first is. In the third a list of two strings, as the folds of
// its constructors make it, ends in an empty list held in its last cell's
// tail, a field of the list's type: a constructor stands in a field whose
// type its own refines, as a value built of it fills one. All three
// verify.
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

// -----

#Strs = #idr.family<"Strs" [] {
    @Nil ()
    @Cons (!idr.str, !idr.self)
  }>
!Nil = !idr.data<#Strs @Nil>
!Cons = !idr.data<#Strs @Cons>
!ConsS = !idr.graded<many, static, !idr.data<#Strs @Cons>>
idr.program @list root(@main) stage(higher) {
  idr.func @main() {
    %list = idr.constant !ConsS #idr.con<!Cons, ["ab", #idr.con<!Cons, ["c", #idr.con<!Nil, []>]>]>
    idr.return
  }
}
