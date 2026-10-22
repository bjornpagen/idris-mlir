-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| How high a key a parameter keyed by its argument's shape can have: its
||| cap.
|||
||| A runtime parameter on whose value the rest of a callee's type reduces
||| is keyed by as much of its argument's shape as the type needs to reduce
||| (`Instances.neededShape`), and no more, so that a recursion that builds
||| its argument deeper below what the type looks at stays in one instance.
||| How much that is depends on the callee's type, not on the calls: when
||| the type inspects d levels of the value, no key is higher than d + 1,
||| however deep a cycle of calls builds the argument. That height is the
||| parameter's cap, which the growth check takes as the position's bound
||| in place of the arcs into it.
|||
||| The cap is read off the very type the key is cut against, the same way:
||| the rest of the callee's type with the parameter standing for its value
||| (`Template.markerAt`), read by the one template walk (`templateOf
||| AType`), which normalises with `normaliseClosed` as `neededShape` does
||| and records each match it meets as a `Choice` on what it matched. The
||| deepest match on the parameter is the depth the type inspects, and no
||| second reading of the type exists to drift from it.
|||
||| Only a chain is capped: a value of a type whose `natness` is `Chain`,
||| `Nat`-like with no constructor taking an erased argument. Where the type is stuck on a part
||| of the argument that its shape does not say, `neededShape` keeps the
||| whole shape. A chain of successors ends at that hole, so it is no higher
||| than the level inspected; a tree with a hole in one child can be
||| arbitrarily deep in another, and nothing about the type bounds it. A
||| shape keeps a constructor's erased arguments too (`Fin`'s index under
||| `FS`), so a `Numeral` is such a tree.
module IdrisMLIR.Frontend.Growth.Caps

import Core.Context
import Core.Core
import Core.TT

import IdrisMLIR.Frontend.Growth.Template
import IdrisMLIR.Frontend.Translate.Closed
import IdrisMLIR.Frontend.Translate.Errors
import IdrisMLIR.Frontend.Translate.Instances
import IdrisMLIR.Frontend.Translate.State
import IdrisMLIR.Frontend.Translate.Types
import IdrisMLIR.Proof.Requests
import IdrisMLIR.Proof.Template

import Data.List

%default total

mutual
  -- The depth of the deepest match on parameter j's value in a template,
  -- when j is never loose there: e + 1 for a match on `Var j e`, which
  -- looks at the constructor e + 1 levels down. j is loose where it occurs
  -- anywhere but as the scrutinee of a match: as a child of a head or of a
  -- recursion (an index, a folded call, a stuck recursion), as an applied
  -- family or its argument, as a field's record, as a match's alternative,
  -- or inside a scrutinee that is not itself a marker. A marker as the
  -- scrutinee is a match on that level of its parameter, which bounds j
  -- only when the parameter is j: two parameters are two values, a case
  -- the problem has. Any other scrutinee is a stuck computation, whose own
  -- matches are made when it is evaluated at an instance, so they count.
  deepest : (j : Nat) -> Template -> Maybe Nat
  deepest j (Choice (Var i e) alts) = max (if i == j then S e else 0) <$> deepestIn j alts
  deepest j (Choice s alts) = max <$> deepest j s <*> deepestIn j alts
  deepest j (Var i _) = if i == j then Nothing else Just 0
  deepest j (Head _ ts) = deepestIn j ts
  deepest j (Opaque _ ts) = deepestIn j ts
  deepest j (Applied i _ ts) = if i == j then Nothing else deepestIn j ts
  -- Never met: only a template read at a node of the graph
  -- (`withClosedFamilies`) computes, and a cap reads its type as
  -- `templateOf` gives it. The type admits it, so it reads as the applied
  -- family it was.
  deepest j (Computing i _ ts) = if i == j then Nothing else deepestIn j ts
  deepest j (Field _ t) = deepest j t
  deepest j (Leaf _) = Just 0
  deepest j (Token _) = Just 0
  deepest j (Formal _ _) = Just 0
  deepest j (Member _) = Just 0

  deepestIn : (j : Nat) -> List Template -> Maybe Nat
  deepestIn j [] = Just 0
  deepestIn j (t :: ts) = max <$> deepest j t <*> deepestIn j ts

-- The cap of parameter j, from the template of the rest of its callee's
-- type with j marked: one more than the deepest match on j, and none when
-- j occurs anywhere but as what a match inspects.
--
-- Why every key `classify` makes at j is no higher. Take a call that keys
-- j by the shape `found`. `neededShape` normalises the rest of the type at
-- `found` cut at depth d (`cutShape unknownPart d found`), for d = 0, 1,
-- and so on, with `normaliseClosed`, and stops at the first d at which the
-- result mentions the unknown part only as an index; the cut it then keeps
-- has holes for the unknown part, and d = 0 keys nothing. The template is
-- the same rest, at j's marker, read with the same normaliser: every match
-- the normaliser makes on j's value at level e + 1 is a `Choice` on
-- `Var j e` holding all its alternatives. An earlier parameter is the
-- placeholder `classify` gives one it does not know (`Erased Placeholder`),
-- so a match on it reads as the application it leaves stuck, which holds
-- `Var j _`, loose, wherever it holds a part of j: no cap rests on a value
-- a call may not give it (an erased or unkeyed parameter, a shape with a
-- hole, a type with a part cut at runtime).
-- Let D be the deepest match on j, counting the matches inside a
-- scrutinee, which evaluating it at an instance makes. The cap is D + 1,
-- and a hole is one level of a shape's height.
--
-- 1. No `Var j _` is loose, and found has a constructor at every level the
--    evaluation inspects. At d = D the cut is found down to level D, so
--    every match, at a level e + 1 <= D, meets found's own constructor, and
--    the normaliser takes its alternative, one of the template's. No match
--    is deeper, so the evaluation ends at a leaf of the template, which
--    holds no part of j and so no unknown part. `neededShape` stops at some
--    d <= D, and keeps a cut at most d + 1 <= D + 1 high.
-- 2. found has a hole (an erased part of `skeleton`'s) at a level k that a
--    match inspects, so k <= D. The type is stuck on the hole at every
--    depth, since every cut leaves it unknown and nothing loose mentions a
--    deeper part, so `neededShape` keeps all of found. j's type is a
--    chain, whose constructors hold nothing but the predecessor, so found
--    is a run of successors that the hole ends: k - 1 of them around the
--    hole, k <= D + 1 high.
-- 3. found ends in its zero above the matches. The path to it inspects
--    nothing deeper than the zero, so case 1 holds on it, at some d no
--    deeper than `shapeDepth found`.
-- 4. Some `Var j _` is loose: a leaf holds a part of j outside any match
--    (`F (S k) = Foo k`), or an index, a folded call, a recursion or a
--    field's record does. The type can then mention a part of j at any
--    depth, and `neededShape` keeps the whole shape, which nothing bounds,
--    so there is no cap. Where the occurrence is only an index, that costs
--    precision, never soundness.
--
-- So every key `classify` makes at j is, as `closedHeight AShape` reads it,
-- at most `capFrom j` of the template high. The worklist's bound check is
-- the run-time witness of this statement.
capFrom : (j : Nat) -> Template -> Maybe Nat
capFrom j t = S <$> deepest j t

-- A type's first binder: the parameter's type, and the rest of the type as
-- a function of the parameter's value.
binder : {auto c : Ref Ctxt Defs} -> ClosedTerm -> Front (ClosedTerm, ClosedTerm -> ClosedTerm)
binder ty = do
  Bind _ _ (Pi _ _ _ a) sc <- showingBinder ty
    | _ => internal EmptyFC "more parameters than the type has binders"
  pure (a, \v => subst v sc)

-- Parameter j's type, and the rest of the type after it as a function of
-- its value, every earlier parameter the placeholder `classify` gives a
-- parameter whose value it does not know, as the template walk already
-- reads every later one.
parameterAt : {auto c : Ref Ctxt Defs} -> (j : Nat) -> ClosedTerm ->
              Front (ClosedTerm, ClosedTerm -> ClosedTerm)
parameterAt Z ty = binder ty
parameterAt (S j) ty = do
  (_, rest) <- binder ty
  parameterAt j (rest (Erased EmptyFC Placeholder))

||| The cap of a definition's parameter j (the j-th binder of its type,
||| erased ones counted): the most a key of j can hold of its argument's
||| shape, as the height `closedHeight AShape` reads, for a parameter keyed
||| by the shape of a chain whose matches the type inspects to a fixed depth.
||| Nothing for every other parameter. Whether j is keyed by its shape is
||| `staticsOver`'s to say, the one reading of `classify`'s decisions, over
||| markers for every parameter as a definition's own sites give them.
export
capOf : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
        Address -> (j : Nat) -> Front (Maybe Nat)
capOf addr j = do
  -- Every address the frontend holds came from `addressOf` of a definition
  -- the boundary read, so the lookup finds one.
  Just d <- definitionRead addr
    | Nothing => internal EmptyFC "an address with no definition"
  let owner = show (fullname d.def)
  let ty = d.type
  (kinds, _) <- staticsOver owner (S j) ty [Just (markerAt i 0, AValue) | i <- [0 .. j]]
  case Vect.last kinds of
    Just AShape => do
      (a, rest) <- parameterAt j ty
      -- `tyConFacts`' `natness` is the one reading of whether a shape is a
      -- run of successors, read as a data instance reads its type; a type
      -- that is no type constructor applied is no `Nat`-like one. A chain is
      -- no interface's type, so no call passes an implementation at j, and
      -- `staticsOver`'s kind, decided with no argument a dictionary, is
      -- `classify`'s at every call.
      a' <- normaliseClosed a
      natness <- case getFnArgs a' of
        (Ref _ (TyCon _) tn, _) => (.natness) <$> tyConFacts !(lookupDef EmptyFC owner tn)
        _ => pure NotNat
      case natness of
        Chain => capFrom j <$> templateOf [] AType (rest (markerAt j 0))
        -- A tree, a `Numeral`'s shape included, whose whole shape, which
        -- `neededShape` keeps where the type is stuck on a hole, no depth of
        -- the type bounds.
        Numeral => pure Nothing
        NotNat => pure Nothing
    -- A type, an implementation, a form or a runtime value keyed by nothing:
    -- no shape, so nothing to cap.
    _ => pure Nothing
