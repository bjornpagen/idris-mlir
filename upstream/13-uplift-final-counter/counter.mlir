// while (i < 10) i = i + 1; return i. The loop ends with i = 10.
func.func @count() -> index {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c10 = arith.constant 10 : index
  %r = scf.while (%i = %c0) : (index) -> index {
    %go = arith.cmpi slt, %i, %c10 : index
    scf.condition(%go) %i : index
  } do {
  ^bb0(%i: index):
    %next = arith.addi %i, %c1 : index
    scf.yield %next : index
  }
  return %r : index
}
