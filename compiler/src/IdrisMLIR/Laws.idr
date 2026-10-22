-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The laws of a translated program that no type of the frontend states,
||| checked on every compilation as queries over its table of instances:
||| every call names an instance of the table, and every instance is
||| reached from the root by calls. Both hold of every program the
||| translation makes, since an instance is made only where a call that
||| is reached requests it; a breach is the compiler's error, named by its
||| law, never a refusal of the program. The reach is the least fixpoint of
||| one rule over the calls, evaluated semi-naively over the universe of
||| the program's instances, each a coordinate of it by its place in the
||| table.
module IdrisMLIR.Laws

import IdrisMLIR.Ids
import IdrisMLIR.Term

import Relational

import Data.List
import Data.Nat
import Data.SortedMap
import Data.Vect

%default total

||| The instances a term calls, each as often as it is called.
callees : Term n -> List FnId
callees = cata {f = \_ => List FnId} layer
  where
    alt : AltF (\_ => List FnId) m -> List FnId
    alt (MkAltF _ _ body) = body

    arms : CaseArmsOf (AltF (\_ => List FnId) m) (List FnId) -> List FnId
    arms (Defaulted as d) = concatMap alt as ++ d
    arms (Exhaustive as) = concatMap alt (forget as)

    litArms : LitArmsOf (List FnId) -> List FnId
    litArms (LitDefault as d) = concatMap snd as ++ d
    litArms (LitNoDefault as) = concatMap snd (forget as)

    natArms : NatArmsOf (List FnId) (List FnId) -> List FnId
    natArms (OnlyZero z) = z
    natArms (OnlySucc _ s) = s
    natArms (Both z _ s) = z ++ s

    stated : Stated (List FnId) -> List FnId
    stated (SameAs x) = x
    stated (Natural x) = x

    layer : TermF (\_ => List FnId) m -> List FnId
    layer (VarF _ _) = []
    layer (LiteralF _ _) = []
    layer (PrimAppF _ _ _ xs) = concat xs
    layer (EffectF _ _ _ xs _) = concat xs
    layer (CallF _ fn _ _ xs) = fn :: concat xs
    layer (ConAppF _ _ _ xs) = concat xs
    layer (LetF _ _ _ v body) = v ++ body
    layer (CaseF _ _ as) = arms as
    layer (CaseLitF _ _ as) = litArms as
    layer (CaseNatF _ _ as) = natArms as
    layer (LamF _ _ _ body) = body
    layer (AppF _ f x) = f ++ x
    layer (SuspendF _ x) = x
    layer (ResumeF _ x) = x
    layer (UnreachableF _) = []
    layer (CrashF _ _) = []
    layer (CrashWithF _ x) = x
    layer (NewWorldF _) = []
    layer (TensorF _ _ op) = concat op
    layer (TabulateF _ _ xs body) = concat xs ++ body
    layer (TabulateIOF _ _ xs w body _ _) = concat xs ++ w ++ body
    layer (ReduceF _ _ _ _ _ z x step) = z ++ x ++ step
    layer (TieF _ x ties) = x ++ concatMap (stated . snd) ties
    layer (ReadBackF _ _ x cs _) = x ++ concat cs
    layer (ExtentsBackF _ x body _) = x ++ body

||| The coordinates of the instances of a table of `u`, each by its place in
||| it: the one place an instance's identity is read as a coordinate.
placesIn : (fns : List TFn) -> SortedMap FnId (Coord (length fns))
placesIn fns = go fns Z lteRefl empty
  where
    go : (rest : List TFn) -> (at : Nat) -> (0 _ : LTE (at + length rest) (length fns)) ->
         SortedMap FnId (Coord (length fns)) -> SortedMap FnId (Coord (length fns))
    go [] _ _ m = m
    go (f :: rest) at fits m =
      let 0 shifted = plusSuccRightSucc at (length rest)
          0 below = lteTransitive (replace {p = LTE (S at)} shifted (lteAddRight (S at))) fits
          0 room = replace {p = \k => LTE k (length fns)} (sym shifted) fits
      in go rest (S at) room (insert f.id (MkCoord at below) m)

||| Every call names an instance of the table: each instance with the
||| coordinates of the instances it calls, or the first call that names
||| none, with the symbol of the function that makes it.
resolved : (places : SortedMap FnId (Coord u)) -> List TFn ->
           Either String (List (Coord u, List (Coord u)))
resolved places [] = Right []
resolved places (f :: fs) = do
  Just here <- pure (lookup f.id places)
    | Nothing => Left ("the law that every instance is in the table fails at " ++ f.symbol)
  called <- traverse (\c => maybe (Left ("the law that every call names an instance fails in " ++ f.symbol ++
                                         " at " ++ show c))
                                  Right (lookup c places))
                     (callees f.body)
  ((here, called) ::) <$> resolved places fs

||| The instances reached from the root, the least set holding the root
||| and every instance an instance of it calls.
reached : {u : Nat} -> (root : Coord u) -> (calls : Relation 2 u) -> Relation 1 u
reached root calls = get FZ (saturate {ar = [1]} [start, step])
  where
    start : Rule [1] u
    start = MkRule {v = 1} FZ [FZ] [Fixed (MkAtom [FZ] (relation [[root]]))] [] []

    -- reach(y) :- reach(x), calls(x, y).
    step : Rule [1] u
    step = MkRule {v = 2} FZ [FS FZ] [Derived FZ [FZ], Fixed (MkAtom [FZ, FS FZ] calls)] [] []

||| The laws of a program, checked: nothing, or the first that fails, by
||| name, with what it fails at.
export
laws : Source -> Either String ()
laws src = do
  let fns = src.others ++ [src.root]
      places = placesIn fns
  edges <- resolved places fns
  Just root <- pure (lookup src.root.id places)
    | Nothing => Left ("the law that every instance is in the table fails at the root " ++ src.root.symbol)
  let calls = relation (concatMap (\(caller, called) => map (\c => [caller, c]) called) edges)
      reach = reached root calls
  case filter (\(f, (at, _)) => not (member [at] reach)) (zip fns edges) of
    [] => Right ()
    (f, _) :: _ => Left ("the law that every instance is reached from the root fails at " ++ f.symbol)
