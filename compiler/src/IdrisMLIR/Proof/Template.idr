-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| What a definition writes at a static argument, as the growth check and
||| its proof read it: a tree of heads whose leaves are the writer's
||| markers, the closed parts, and what a type computes from a marker.
|||
||| The readers of checked terms into templates are the frontend's
||| (`Frontend.Growth.Template`); the type and its measures are here, so
||| that the growth theorem (`Proof.Bound`) is stated over the type the
||| readers produce, with nothing of Idris's compiler in scope.
module IdrisMLIR.Proof.Template

import IdrisMLIR.Proof.Requests

import Data.Nat

%default total

public export
data Template
  = ||| The writer's parameter i, bound by its pattern at depth d (0:
    ||| unmatched).
    Var Nat Nat
  | ||| A head: a type or data constructor, an implementation, an
    ||| interface's constructor (`Just`), a binder or a primitive type
    ||| former (`Nothing`).
    Head (Maybe Address) (List Template)
  | ||| A closed part of that height: a `Nat` literal's run (n successors:
    ||| n + 1), a primitive type, a bound variable, an erased placeholder
    ||| (1).
    Leaf Nat
  | ||| Any other literal, or a hole marker: height 1, carrying its key
    ||| token's weight for `Bounds.heaviest`.
    Token Nat
  | ||| One of its leaves at every instance, behind what it matched on: a
    ||| stuck non-recursive definition, unfolded; a definition given fewer
    ||| arguments than its parameters, as written and walked over the
    ||| arguments it lacks; one stuck on an argument of a family's value, as
    ||| written and as what beta computes; a projection of a record no
    ||| constructor yet, as written and as its field; a structural
    ||| recursion, its other leaves and its argument raised by them.
    Choice Template (List Template)
  | ||| A recursive definition, stuck on what its arguments hold.
    Opaque Address (List Template)
  | ||| The writer's family `Var i d` applied, which every instance
    ||| beta-reduces.
    Applied Nat Nat (List Template)
  | ||| The writer's family `Var i d` applied where its value, or an
    ||| argument, computes from what it is given: what beta makes there
    ||| nothing bounds.
    Computing Nat Nat (List Template)
  | ||| Argument j of a family's value, taking a arguments of its own: what
    ||| beta substitutes, a leaf of height 1 until it does. Nothing matches
    ||| one, so it has no depth.
    Formal Nat Nat
  | ||| Field k (a method or a superclass) of a dictionary not yet a
    ||| constructor.
    Field Nat Template
  | ||| The dictionary data constructor C holds at field p, matched out of a
    ||| value (`SortedDMap`'s `Ord`).
    Held Address Nat

mutual
  ||| The tallest of some templates; 0 for none.
  public export
  tallest : List Template -> Nat
  tallest [] = 0
  tallest (t :: ts) = maximum (height t) (tallest ts)

  ||| A template's height: a marker, a field and a held dictionary are 0
  ||| (what they stand for is weighed by their arcs), a leaf its own, a
  ||| token and an argument of a family's value 1 (the key's bound
  ||| variable), a head, a recursion and an applied family one above their
  ||| tallest child, a choice its tallest leaf.
  public export
  height : Template -> Nat
  height (Var _ _) = 0
  height (Field _ _) = 0
  height (Held _ _) = 0
  height (Leaf h) = h
  height (Token _) = 1
  height (Formal _ _) = 1
  height (Head _ ts) = S (tallest ts)
  height (Opaque _ ts) = S (tallest ts)
  height (Applied _ _ ts) = S (tallest ts)
  height (Computing _ _ ts) = S (tallest ts)
  height (Choice _ ts) = tallest ts

||| `c` levels of a head above a template: an applied family read where
||| only closed values no higher than c land at it.
public export
raise : Nat -> Template -> Template
raise Z t = t
raise (S c) t = Head Nothing [raise c t]

mutual
  widest : List Template -> Nat
  widest [] = 0
  widest (t :: ts) = maximum (arity t) (widest ts)

  ||| The most children of any node, a choice's leaves' own.
  export
  arity : Template -> Nat
  arity (Head _ ts) = maximum (length ts) (widest ts)
  arity (Opaque _ ts) = maximum (length ts) (widest ts)
  arity (Applied _ _ ts) = maximum (S (length ts)) (widest ts)
  arity (Computing _ _ ts) = maximum (S (length ts)) (widest ts)
  arity (Choice _ ts) = widest ts
  arity (Field _ s) = arity s
  arity (Var _ _) = 0
  arity (Leaf _) = 0
  arity (Token _) = 0
  arity (Held _ _) = 0
  arity (Formal _ _) = 0

mutual
  heaviestOf : List Template -> Nat
  heaviestOf [] = 0
  heaviestOf (t :: ts) = maximum (heaviest t) (heaviestOf ts)

  ||| The heaviest literal or hole token a template holds, a choice's
  ||| leaves' included and its scrutinee skipped; 0 for none.
  export
  heaviest : Template -> Nat
  heaviest (Token k) = k
  heaviest (Head _ ts) = heaviestOf ts
  heaviest (Opaque _ ts) = heaviestOf ts
  heaviest (Applied _ _ ts) = heaviestOf ts
  heaviest (Computing _ _ ts) = heaviestOf ts
  heaviest (Choice _ ts) = heaviestOf ts
  heaviest (Field _ s) = heaviest s
  heaviest (Var _ _) = 0
  heaviest (Leaf _) = 0
  heaviest (Held _ _) = 0
  heaviest (Formal _ _) = 0
