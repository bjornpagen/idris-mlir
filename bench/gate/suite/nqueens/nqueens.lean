/-
All solutions of the n-queens problem: Perceus's nqueens.kk in Lean (the
Lean 4 repository has no nqueens benchmark), reading n from stdin as every
version here does.
-/

def safe (queen diag : Int) : List Int → Bool
  | q :: qs => queen != q && queen != q + diag && queen != q - diag && safe queen (diag + 1) qs
  | [] => true

partial def appendSafe (queen : Int) (xs : List Int) (xss : List (List Int)) : List (List Int) :=
  if queen <= 0 then xss
  else if safe queen 1 xs then appendSafe (queen - 1) xs ((queen :: xs) :: xss)
  else appendSafe (queen - 1) xs xss

def extend (queen : Int) : List (List Int) → List (List Int) → List (List Int)
  | acc, xs :: rest => extend queen (appendSafe queen xs acc) rest
  | acc, [] => acc

partial def findSolutions (n queen : Int) : List (List Int) :=
  if queen == 0 then [[]] else extend n [] (findSolutions n (queen - 1))

def readNat : IO Nat := do
  let line ← (← IO.getStdin).getLine
  pure <| (line.toList.takeWhile Char.isDigit).foldl (fun acc c => acc * 10 + (c.toNat - '0'.toNat)) 0

def main : IO Unit := do
  let n ← readNat
  IO.println (toString (findSolutions n n).length)
