-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| What a data type's fields write. A value of a type holds its fields, so
||| a field whose type names a type constructor makes an instance of it
||| whenever an instance of the type is made: the type writes it, at the
||| arguments the field's type gives it. Read over the type's own arguments,
||| a field that holds the type again at a larger argument (`N : T (a, a) ->
||| T a`) is a site from the type to itself that grows on every level of
||| nesting, which the growth check refuses at the constructor.
module IdrisMLIR.Frontend.Growth.Fields

import Core.Context
import Core.Core
import Core.TT

import IdrisMLIR.Frontend.Growth.Sites
import IdrisMLIR.Frontend.Growth.Template
import IdrisMLIR.Frontend.Translate.Closed
import IdrisMLIR.Frontend.Translate.Errors
import IdrisMLIR.Frontend.Translate.Given
import IdrisMLIR.Frontend.Resolve
import IdrisMLIR.Frontend.Translate.Readings
import IdrisMLIR.Frontend.Translate.State
import IdrisMLIR.Frontend.Walk
import IdrisMLIR.Frontend.Translate.Place
import IdrisMLIR.Frontend.Translate.Types
import IdrisMLIR.Proof.Requests

import Data.List

%default total

-- A term is closed here over what a given scope holds (`Given.close`),
-- never over a reading's values.
%hide IdrisMLIR.Frontend.Translate.Readings.close

-- A stand-in for the `k`th binder of a constructor's type, so that the
-- return type can say which binder it holds where. Only the match below
-- reads it, and nothing normalises a term that holds one.
standIn : Nat -> ClosedTerm
standIn k = probeTerm (ProbeStandIn k)

standInOf : ClosedTerm -> Maybe Nat
standInOf t = case probeOfTerm t of
  Just (ProbeStandIn k) => Just k
  _ => Nothing

-- The return type of a constructor's type, each binder its stand-in.
returned : Given vs -> Nat -> TT vs -> ClosedTerm
returned g k (Bind _ _ (Pi {}) sc) = returned (give (standIn k) g) (S k) sc
returned g k t = close g t

mutual
  -- What the argument at represented position `j` of the return type
  -- binds, at the part `path` reaches: a binder found there is that part
  -- of the position's value, the field of each constructor it is nested
  -- in on its path, so that a field reading it says which part of the
  -- position it is, one value: the binder, the position and the path.
  pattern : Nat -> List Nat -> ClosedTerm -> List (Nat, Nat, List Nat)
  pattern j path t = case standInOf t of
    Just k => [(k, j, path)]
    Nothing => maybe [] fst (parts j path t)

  -- What the arguments of an application bind, left to right, each at its
  -- own field below `path`, when its head is a type or data constructor,
  -- with how many arguments it has: only a constructor's arguments are
  -- parts of the value it makes. A function need not be injective, so
  -- what its arguments hold says nothing of its result, and any other
  -- head binds nothing. The head decides once, where the walk meets it.
  parts : Nat -> List Nat -> ClosedTerm -> Maybe (List (Nat, Nat, List Nat), Nat)
  parts j path (App _ f a) = (\(bs, k) => (bs ++ pattern j (path ++ [k]) a, S k)) <$> parts j path f
  parts j path (Ref _ (DataCon _ _) _) = Just ([], 0)
  parts j path (Ref _ (TyCon _) _) = Just ([], 0)
  parts j path _ = Nothing

-- What a constructor's return type binds at the represented positions
-- `rs`: each of its arguments, left to right, at the whole position, each
-- binder a stand-in of its own, numbered from 0, at the path to the part
-- it is, so that two binders of one position are two markers, each for
-- one value. Walking the arguments that are there, a position is never
-- looked for past the last of them. An argument at a position not
-- represented is none the check watches, so it binds nothing: the
-- problem's case. A binder bound twice keeps its first binding: both
-- bindings hold the same value, so either is sound.
bindings : List Nat -> ClosedTerm -> List (Nat, StandIn)
bindings rs ret = numbered 0 (argumentsFrom 0 (snd (getFnArgs ret)))
  where
    argumentsFrom : Nat -> List ClosedTerm -> List (Nat, Nat, List Nat)
    argumentsFrom j [] = []
    argumentsFrom j (a :: as) =
      (if elem j rs then pattern j [] a else []) ++ argumentsFrom (S j) as

    numbered : Nat -> List (Nat, Nat, List Nat) -> List (Nat, StandIn)
    numbered n [] = []
    numbered n ((k, j, path) :: bs) = (k, MkStandIn n j path) :: numbered (S n) bs

-- The types of a constructor's runtime fields, in binder order, read with
-- each binder given what the return type binds it to, each at its place in
-- the constructor's type, the binder `here`: its type a step into the
-- binder, and the binders after it a step into its scope, as the type's
-- own constructors are. A binder no represented position binds is
-- `Erased`, as the translation reads a constructor. A binder of quantity 0
-- is no field, and an implementation or a polymorphic function
-- (`compileTimeBinder`) is a member of a closed sum the constructor holds,
-- never data the type writes: both are the problem's cases, not the
-- reading's.
fieldTypes : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
             Given vs -> Nat -> List (Nat, ClosedTerm) -> (here : Place) -> TT vs -> Front (List (Place, ClosedTerm))
fieldTypes g k bound here (Bind bfc _ (Pi _ rig _ a) sc) = do
  rest <- fieldTypes (give (fromMaybe (Erased bfc Placeholder) (lookup k bound)) g) (S k) bound (into BinderScope here) sc
  case use rig of
    Erased => pure rest
    Used _ => do
      a' <- normaliseClosed (close g a)
      if !(compileTimeBinder rig a') then pure rest else pure ((into BinderType here, a') :: rest)
fieldTypes _ _ _ _ _ = pure []

||| The sites a type constructor's fields write: each runtime field of each
||| of its constructors, as the boundary read them (`ConstructorAt`, which
||| the type's facts hold), constructors in their declared order and fields
||| in binder order, read over the type's represented arguments
||| (`represented`, which the caller has read). The type, at its address
||| and as it was read, is each site's writer, since its markers are the
||| type's arguments; the constructor is where the site is written, its
||| `within` and its location, for the message that names it. The field
||| types go to the site walk as they are: it reads each type constructor
||| they apply as its key does, so reading them here too would be a second
||| reading. Each field's sites are made in the type's text at the field's
||| binder in its constructor's type, a step into the constructor by its
||| name.
export
fieldSites : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
             (t : Address) -> Defined -> (constructors : List ConstructorAt) -> (represented : List Nat) -> Front (List Made)
fieldSites t td cons rs = (>>= id) <$> traverse constructorSites cons
  where
    constructorSites : ConstructorAt -> Front (List Made)
    constructorSites con = do
      -- The type as written may hide binders behind a definition (`a -@
      -- b`); its normal form shows each one, as the translation reads it.
      ty <- normaliseClosed con.read.type
      let bound = bindings rs (returned none 0 ty)
      let typed = [< OfConstructor (fullname con.read.def), DefinitionType]
      fts <- fieldTypes none 0 (map (\(k, p) => (k, standInAt p)) bound) typed ty
      (>>= id) <$> traverse (\(place, ft) => map (\m => { site->fc := location con.read.def } m) <$>
                                               sitesIn t td con.read.def (map snd bound) place ft)
                            fts
