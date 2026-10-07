# The Prelude's length is a loop

`length (x :: xs) = S (length xs)` reaches the passes as an addition of
the recursive result. Addition associates and commutes, and its identity
is zero, so the one is added to a sum carried down and the call is the
last thing that tail does. The function the program calls seeds that sum
at zero. A list of 33677161 elements, the size at which a gibibyte stack ended
with `idris-mlir: stack exhausted`, is counted on a 1 MiB stack.

Counting had hidden the addition: it borrowed the recursive result and
dropped it afterwards, so the call was no longer what the tail added. The
rewrite runs first, while the result is still the operand of the addition.
A call whose result is inspected, or added to another call of the same
function, stays a call.

Chez counts in constant stack too: its runtime form of `length` is the
tail-recursive one. `bench/regex-redux` still counts with an `Int`
accumulator.
