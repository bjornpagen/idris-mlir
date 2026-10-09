module Main

-- Functions that are the identity once Idris's indices are erased:
-- Data.Fin's weaken, finToNat and last; the weakening of a term to a larger
-- scope, which rebuilds every node and weakens every variable, alone and
-- with a count of binders it carries and never gives back; and a tree and
-- a forest weakened by mutual recursion, main calling both, so that
-- neither is a continuation of the other. Each call of one becomes the
-- argument it gives back: mlir.expect states that none is called after the
-- simplify loop. The terms are built from the input, so that none of it is
-- evaluated at compile time.

import Prelude
import Data.Fin

data Term : Nat -> Type where
  Var : Fin n -> Term n
  App : Term n -> Term n -> Term n
  Lam : Term (S n) -> Term n
  Lit : Integer -> Term n

weakenTerm : Term n -> Term (S n)
weakenTerm (Var i) = Var (weaken i)
weakenTerm (App f a) = App (weakenTerm f) (weakenTerm a)
weakenTerm (Lam b) = Lam (weakenTerm b)
weakenTerm (Lit v) = Lit v

weakenUnder : Nat -> Term n -> Term (S n)
weakenUnder d (Var i) = Var (weaken i)
weakenUnder d (App f a) = App (weakenUnder d f) (weakenUnder d a)
weakenUnder d (Lam b) = Lam (weakenUnder (S d) b)
weakenUnder d (Lit v) = Lit v

mutual
  data Tree : Nat -> Type where
    Leaf : Fin n -> Tree n
    Node : Forest n -> Tree n

  data Forest : Nat -> Type where
    Done : Forest n
    More : Tree n -> Forest n -> Forest n

mutual
  weakenTree : Tree n -> Tree (S n)
  weakenTree (Leaf i) = Leaf (weaken i)
  weakenTree (Node f) = Node (weakenForest f)

  weakenForest : Forest n -> Forest (S n)
  weakenForest Done = Done
  weakenForest (More t f) = More (weakenTree t) (weakenForest f)

-- d binders deep, each applying the term below it to the variable it
-- binds; at the bottom, the outermost variable applied to v.
build : (n : Nat) -> Nat -> Integer -> Term (S n)
build n Z v = App (Var last) (Lit v)
build n (S d) v = Lam (App (build (S n) d v) (Var FZ))

describe : Term n -> String
describe (Var i) = "v" ++ show (finToNat i)
describe (App f a) = "(" ++ describe f ++ " " ++ describe a ++ ")"
describe (Lam b) = "L " ++ describe b
describe (Lit v) = show v

-- k nodes, each of one leaf, the last variable of the scope.
leaves : (n : Nat) -> Nat -> Forest (S n)
leaves n Z = Done
leaves n (S k) = More (Node (More (Leaf last) Done)) (leaves n k)

mutual
  showTree : Tree n -> String
  showTree (Leaf i) = show (finToNat i)
  showTree (Node f) = "[" ++ showForest f ++ "]"

  showForest : Forest n -> String
  showForest Done = ""
  showForest (More t f) = showTree t ++ ";" ++ showForest f

main : IO ()
main = do
  line <- getLine
  let k = the Nat (cast line)
  let t = build Z k (cast k * 10)
  putStrLn (describe t)
  putStrLn (describe (weakenTerm (weakenTerm t)))
  putStrLn (describe (weakenUnder k t))
  let f = leaves k (S k)
  putStrLn (showForest (weakenForest f))
  putStrLn (showTree (weakenTree (Node f)))
  printLn (finToNat (weaken (the (Fin (S (S k))) last)))
