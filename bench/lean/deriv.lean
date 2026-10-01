/-
Symbolic differentiation: Lean's deriv.lean (tests/compile_bench in the
Lean 4 repository; Counting Immutable Beans), reading the number of
derivatives from stdin as every version here does.
-/
inductive Expr
| Val : Int → Expr
| Var : String → Expr
| Add : Expr → Expr → Expr
| Mul : Expr → Expr → Expr
| Pow : Expr → Expr → Expr
| Ln  : Expr → Expr

namespace Expr

partial def pown : Int → Int → Int
| _, 0 => 1
| a, 1 => a
| a, n =>
  let b := pown a (n / 2);
  b * b * (if n % 2 = 0 then 1 else a)

partial def add : Expr → Expr → Expr
| Val n,     Val m           => Val (n + m)
| Val 0,     f               => f
| f,         Val 0           => f
| f,         Val n           => add (Val n) f
| Val n,     Add (Val m) f   => add (Val (n+m)) f
| f,         Add (Val n) g   => add (Val n) (add f g)
| Add f g,   h               => add f (add g h)
| f,         g               => Add f g

partial def mul : Expr → Expr → Expr
| Val n,     Val m           => Val (n*m)
| Val 0,     _               => Val 0
| _,         Val 0           => Val 0
| Val 1,     f               => f
| f,         Val 1           => f
| f,         Val n           => mul (Val n) f
| Val n,     Mul (Val m) f   => mul (Val (n*m)) f
| f,         Mul (Val n) g   => mul (Val n) (mul f g)
| Mul f g,   h               => mul f (mul g h)
| f,         g               => Mul f g

def pow : Expr → Expr → Expr
| Val m,   Val n   => Val (pown m n)
| _,       Val 0   => Val 1
| f,       Val 1   => f
| Val 0,   _       => Val 0
| f,       g       => Pow f g

def ln : Expr → Expr
| Val 1   => Val 0
| f       => Ln f

def d (x : String) : Expr → Expr
| Val _     => Val 0
| Var y     => if x = y then Val 1 else Val 0
| Add f g   => add (d x f) (d x g)
| Mul f g   => add (mul f (d x g)) (mul g (d x f))
| Pow f g   => mul (pow f g) (add (mul (mul g (d x f)) (pow f (Val (-1)))) (mul (ln f) (d x g)))
| Ln f      => mul (d x f) (pow f (Val (-1)))

def count : Expr → UInt32
| Val _   => 1
| Var _   => 1
| Add f g   => count f + count g
| Mul f g   => count f + count g
| Pow f g   => count f + count g
| Ln f      => count f

def nestAux (s : Nat) (f : Nat → Expr → IO Expr) : Nat → Expr → IO Expr
| 0,       x => pure x
| m@(n+1), x => f (s - m) x >>= nestAux s f n

def nest (f : Nat → Expr → IO Expr) (n : Nat) (e : Expr) : IO Expr :=
nestAux n f n e

def deriv (i : Nat) (f : Expr) : IO Expr :=
do
  let d := d "x" f;
  IO.println (toString (i+1) ++ " count: " ++ (toString $ count d));
  pure d

end Expr

open Expr

def readNat : IO Nat := do
  let line ← (← IO.getStdin).getLine
  pure <| (line.toList.takeWhile Char.isDigit).foldl (fun acc c => acc * 10 + (c.toNat - '0'.toNat)) 0

def main : IO Unit := do
  let n ← readNat
  let x := Var "x"
  let f := pow x x
  _ ← nest deriv n f
