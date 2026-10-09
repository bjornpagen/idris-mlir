// %b has no property set. sccp simulates its fold, which folds it in place
// through %a and takes %a's nneg flag; sccp puts the operand back but not
// the flag.
func.func @unset_property(%x: i3) -> i16 {
  %a = arith.extui %x nneg : i3 to i8
  %b = arith.extui %a : i8 to i16
  return %b : i16
}
