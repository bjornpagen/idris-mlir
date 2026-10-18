module Main

-- Guards that a leaf reads an erased index as the runtime field its clause
-- unified it with when a runtime index of the clause holds a term the
-- unifier computed (the shape of the fork's Show (Partitions ps), whose ps
-- is cs ++ ps'). Idris's tree never matches such a term, so the clause
-- still matches every input that reaches the leaf; read as a test, it hid
-- the clause and the leaf read the erased index at run time.

%default total

add : Nat -> Nat -> Nat
add Z m = m
add (S k) m = S (add k m)

data Span : Nat -> Nat -> Type where
  MkSpan : {start : Nat} -> (len : Nat) -> Span start (add start len)

-- The leaf names the erased start, which the clause unified with the
-- runtime field start; end is add start len.
first : {0 start : Nat} -> {end : Nat} -> Span start end -> Nat
first (MkSpan len) = start + end

-- The same in a with block, whose clauses read start through the block's
-- own arguments.
firstWith : {0 start : Nat} -> {end : Nat} -> Span start end -> Nat
firstWith sp with (True)
  firstWith (MkSpan len) | b = if b then start + end else len

main : IO ()
main = do
  printLn (first (MkSpan {start = 3} 4))
  printLn (firstWith (MkSpan {start = 3} 4))
