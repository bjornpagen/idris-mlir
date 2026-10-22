-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The e-graph's rules, as data of the specification: generated into the
||| C++ engine's tables and never run in Idris. A rule over pure values is a
||| pattern rooted at an op, a replacement over the same variables, and the
||| side conditions an analysis or a type holds. Every rule is one-way: it
||| rewrites its left side to its right, never the reverse. Its types prove
||| what a rule must not do (bind a variable the left side lacks, use a
||| quantity-1 variable twice). A rule that rewrites an effectful op or
||| reads regions is a skeleton rule: hand C++ the specification names with
||| the op it is rooted at.
module IdrisMLIR.Spec.Core.Rewrite

import IdrisMLIR.Spec.Core.Text
import IdrisMLIR.Spec.Core.Admitted
import IdrisMLIR.Spec.Core.Op

import Data.Fin
import Data.List
-- A rule's automatic `So` proofs are searched where the rule is written.
import public Data.So
import Data.Vect

%default total

||| How often a variable's value may be used: a quantity-1 value at most
||| once on the right.
public export
data VarUses = UsedOnce | UsedMany

||| A pattern over `n` variables: a variable, an op of ours at one of its
||| results over patterns for its operands, an admitted upstream op, or an
||| integer literal.
public export
data Pat : (n : Nat) -> Type where
  Var : Fin n -> Pat n
  Node : {0 i, o, a, r : Nat} -> Op i o a r -> Fin o -> Vect i (Pat n) -> Pat n
  UpstreamNode : Admitted -> List (Pat n) -> Pat n
  Literal : Integer -> Pat n

||| A left side: rooted at an op, never at a variable, so every rule has
||| a root kind the engine indexes it by.
public export
data Root : (n : Nat) -> Type where
  RootedAt : {0 i, o, a, r : Nat} -> Op i o a r -> Fin o -> Vect i (Pat n) -> Root n
  RootedAtUpstream : Admitted -> List (Pat n) -> Root n

||| A side condition, a fact an analysis or a type holds of a variable:
||| it is a constant; a power of two; within an interval; produced by
||| code whose row carries neither crash nor divergence, which alone lets a
||| rule delete or move it.
public export
data Cond : (n : Nat) -> Type where
  IsConstant : Fin n -> Cond n
  PowerOfTwo : Fin n -> Cond n
  InRange : Fin n -> (lo, hi : Integer) -> Cond n
  Clean : Fin n -> Cond n

mutual
  public export
  varsOf : Pat n -> List (Fin n)
  varsOf (Var v) = [v]
  varsOf (Node _ _ args) = varsOfVect args
  varsOf (UpstreamNode _ args) = varsOfList args
  varsOf (Literal _) = []

  public export
  varsOfVect : Vect k (Pat n) -> List (Fin n)
  varsOfVect [] = []
  varsOfVect (p :: ps) = varsOf p ++ varsOfVect ps

  public export
  varsOfList : List (Pat n) -> List (Fin n)
  varsOfList [] = []
  varsOfList (p :: ps) = varsOf p ++ varsOfList ps

public export
varsOfRoot : Root n -> List (Fin n)
varsOfRoot (RootedAt _ _ args) = varsOfVect args
varsOfRoot (RootedAtUpstream _ args) = varsOfList args

||| Every variable of the right side occurs on the left.
public export
covers : Root n -> Pat n -> Bool
covers lhs rhs = all (\v => elem v (varsOfRoot lhs)) (varsOf rhs)

||| No quantity-1 variable occurs twice on the right.
public export
linearIn : Vect n VarUses -> Pat n -> Bool
linearIn uses rhs = all once (varsOf rhs)
  where
    once : Fin n -> Bool
    once v = case index v uses of
      UsedMany => True
      UsedOnce => length (filter (== v) (varsOf rhs)) <= 1

public export
record Rewrite (n : Nat) where
  constructor MkRewrite
  vars : Vect n VarUses
  lhs : Root n
  rhs : Pat n
  conds : List (Cond n)
  doc : Line
  {auto 0 bound : So (covers lhs rhs)}
  {auto 0 linear : So (linearIn vars rhs)}

||| A rule of any number of variables, as a list of the dialect's holds
||| them.
public export
data AnyRewrite : Type where
  SomeRewrite : {0 n : Nat} -> Rewrite n -> AnyRewrite

||| A rule over an effectful op or a region, hand C++: the class
||| `::idr::egraph::<name>`, declared in the header at `declaredIn` (its
||| path under the include root, `idr/IR/Control/Control.h`), which the
||| engine runs where the op `root` is. The generator includes every rule's
||| header once, so the engine lists none by hand.
public export
record SkeletonRule where
  constructor MkSkeletonRule
  name : Ident
  declaredIn : Path
  root : OpRef
  doc : Line
