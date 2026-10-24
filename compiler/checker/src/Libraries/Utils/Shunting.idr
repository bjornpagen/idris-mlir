-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module Libraries.Utils.Shunting

import Core.Context.Context
import Core.Core
import Core.FC

%default total

-- The shunting yard algorithm turns operators and their operands, as
-- written, into a parse tree expressing the precedence and associativity
-- correctly. We assume that brackets, functions etc are dealt with in a
-- higher level parser, so we're only dealing with operators here.

||| An infix operator's precedence and associativity.
public export
data InfixPrec
          = AssocL Nat
          | AssocR Nat
          | NonAssoc Nat

||| Operators and operands as written: an operand alone, an operand followed
||| by an infix operator and what follows it, or a prefix operator applied
||| to what follows it. An infix operator holds its own kind of operator
||| (`iop`), a prefix one its own (`pop`), and every operator has its
||| operands where it needs them, so a chain shunts to one tree.
public export
data Chain : (iop, pop, a : Type) -> Type where
  Operand : a -> Chain iop pop a
  InfixOp : a -> (expressionLoc, operatorLoc : FC) -> iop -> InfixPrec ->
            Chain iop pop a -> Chain iop pop a
  PrefixOp : (expressionLoc, operatorLoc : FC) -> pop -> (prec : Nat) ->
             Chain iop pop a -> Chain iop pop a

-- The result of shunting is a parse tree with the precedences made explicit
-- in the tree.
-- NOTE: I have been wondering if I can use types to express that the
-- subtrees use lower precedence operators, but my attempts so far have
-- ended up with more complicated types than the function 'higher', below,
-- which is the one that compares precedences. So I've just used simple
-- types instead and will rely on tests. It would be interesting to see if
-- there's a better way though!

public export
data Tree iop pop a = Infix FC FC iop (Tree iop pop a) (Tree iop pop a)
                    | Pre FC FC pop (Tree iop pop a)
                    | Leaf a

export
(Show iop, Show pop, Show a) => Show (Tree iop pop a) where
  show (Infix _ _ op l r) = "(" ++ show op ++ " " ++ show l ++ " " ++ show r ++ ")"
  show (Pre _ _ op l) = "(" ++  show op ++ " " ++ show l ++ ")"
  show (Leaf val) = show val

-- The operators read and not yet applied, the most recent first: an infix
-- one with the tree of its left operand, a prefix one waiting for its
-- operand. The trees still to be combined are each held by the operator
-- that combines them, so no operator can lack an operand.
data Pending : (iop, pop, a : Type) -> Type where
  Start : Pending iop pop a
  PendingInfix : Pending iop pop a -> (expressionLoc, operatorLoc : FC) ->
                 iop -> InfixPrec -> (left : Tree iop pop a) -> Pending iop pop a
  PendingPrefix : Pending iop pop a -> (expressionLoc, operatorLoc : FC) ->
                  pop -> (prec : Nat) -> Pending iop pop a

getPrec : InfixPrec -> Nat
getPrec (AssocL k) = k
getPrec (AssocR k) = k
getPrec (NonAssoc k) = k

isLAssoc : InfixPrec -> Bool
isLAssoc (AssocL _) = True
isLAssoc _ = False

-- Interpolation to show the operator naked, show to print the operator with its location
nonAssociative : Interpolation op => (showLoc : Show op) => FC -> op -> Error
nonAssociative loc op
    = GenericMsgSol loc "Operator \{op} is non-associative" "Possible solutions"
                        [ "Add brackets around every use of \{op}"
                        , "Change the fixity of \{show op} to `infixl` or `infixr`"]

-- Return whether the pending infix operator should be applied before the
-- one read after it.
higher : Interpolation op => (showLoc : Show op) => FC -> op -> InfixPrec -> op -> InfixPrec -> Core Bool
higher loc opx (NonAssoc x) opy oy
    = if x == getPrec oy
         then throw (nonAssociative loc opx)
         else pure (x > getPrec oy)
higher loc opx ox opy (NonAssoc y)
    = if getPrec ox == y
         then throw (nonAssociative loc opy)
         else pure (getPrec ox > y)
higher loc opl l opr r
    = pure $ (getPrec l > getPrec r) ||
             ((getPrec l == getPrec r) && isLAssoc l)

-- Return whether the pending prefix operator, of precedence `x`, should be
-- applied before the infix one read after it.
higherPrefix : Interpolation op => (showLoc : Show op) => FC -> Nat -> op -> InfixPrec -> Core Bool
higherPrefix loc x opy (NonAssoc y)
    = if x == y
         then throw (nonAssociative loc opy)
         else pure (x > y)
higherPrefix loc x opy r = pure (x > getPrec r)

-- Apply the pending operators that bind tighter than the infix one just
-- read to the tree just read, its left operand.
reduce : Interpolation iop => (showLoc : Show iop) =>
         Pending iop pop a -> Tree iop pop a -> iop -> InfixPrec ->
         Core (Pending iop pop a, Tree iop pop a)
reduce Start t opy prec = pure (Start, t)
reduce stk@(PendingInfix rest loc opFC opx sprec l) t opy prec
    = if !(higher loc opx sprec opy prec)
         then reduce rest (Infix loc opFC opx l t) opy prec
         else pure (stk, t)
reduce stk@(PendingPrefix rest loc opFC opx x) t opy prec
    = if !(higherPrefix loc x opy prec)
         then reduce rest (Pre loc opFC opx t) opy prec
         else pure (stk, t)

-- Apply every pending operator to the last tree read.
close : Pending iop pop a -> Tree iop pop a -> Tree iop pop a
close Start t = t
close (PendingInfix rest loc opFC op _ l) t = close rest (Infix loc opFC op l t)
close (PendingPrefix rest loc opFC op _) t = close rest (Pre loc opFC op t)

shunt : Interpolation iop => (showLoc : Show iop) =>
        Pending iop pop a -> Chain iop pop a -> Core (Tree iop pop a)
shunt stk (Operand x) = pure (close stk (Leaf x))
shunt stk (PrefixOp loc opFC op x rest)
    = shunt (PendingPrefix stk loc opFC op x) rest
shunt stk (InfixOp x loc opFC op prec rest)
    = do (stk', left) <- reduce stk (Leaf x) op prec
         shunt (PendingInfix stk' loc opFC op prec left) rest

export
parseOps : Interpolation iop => (showLoc : Show iop) => Chain iop pop a -> Core (Tree iop pop a)
parseOps = shunt Start
