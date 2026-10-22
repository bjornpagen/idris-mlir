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
import IdrisMLIR.Frontend.Translate.State
import IdrisMLIR.Frontend.Walk
import IdrisMLIR.Frontend.Translate.Types
import IdrisMLIR.Proof.Requests

import Data.List

%default total

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
  -- binds, at depth `d`: a binder found there is that position's marker,
  -- under as many constructors as it is nested in, so that a field
  -- reading it says how much smaller than the position it is.
  pattern : Nat -> Nat -> ClosedTerm -> List (Nat, ClosedTerm)
  pattern j d t = case standInOf t of
    Just k => [(k, markerAt j d)]
    Nothing => fromMaybe [] (parts j (S d) t)

  -- What the arguments of an application bind, left to right, at depth
  -- `d`, when its head is a type or data constructor: only a constructor's
  -- arguments are parts of the value it makes. A function need not be
  -- injective, so what its arguments hold says nothing of its result, and
  -- any other head binds nothing. The head decides once, where the walk
  -- meets it.
  parts : Nat -> Nat -> ClosedTerm -> Maybe (List (Nat, ClosedTerm))
  parts j d (App _ f a) = (\bs => bs ++ pattern j d a) <$> parts j d f
  parts j d (Ref _ (DataCon _ _) _) = Just []
  parts j d (Ref _ (TyCon _) _) = Just []
  parts j d _ = Nothing

-- What a constructor's return type binds at the represented positions
-- `rs`: each of its arguments, left to right, at depth 0. Walking the
-- arguments that are there, a position is never looked for past the last
-- of them. An argument at a position not represented is none the check
-- watches, so it binds nothing: the problem's case. A binder bound twice
-- keeps its first binding: both bindings hold the same value, so either is
-- sound.
bindings : List Nat -> ClosedTerm -> List (Nat, ClosedTerm)
bindings rs ret = argumentsFrom 0 (snd (getFnArgs ret))
  where
    argumentsFrom : Nat -> List ClosedTerm -> List (Nat, ClosedTerm)
    argumentsFrom j [] = []
    argumentsFrom j (a :: as) =
      (if elem j rs then pattern j 0 a else []) ++ argumentsFrom (S j) as

-- The types of a constructor's runtime fields, in binder order, read with
-- each binder given what the return type binds it to. A binder no
-- represented position binds is `Erased`, as the translation reads a
-- constructor. A binder of quantity 0 is no field, and an implementation
-- or a polymorphic function (`compileTimeBinder`) is a member of a closed
-- sum the constructor holds, never data the type writes: both are the
-- problem's cases, not the reading's.
fieldTypes : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
             Given vs -> Nat -> List (Nat, ClosedTerm) -> TT vs -> Front (List ClosedTerm)
fieldTypes g k bound (Bind bfc _ (Pi _ rig _ a) sc) = do
  rest <- fieldTypes (give (fromMaybe (Erased bfc Placeholder) (lookup k bound)) g) (S k) bound sc
  case use rig of
    Erased => pure rest
    Used _ => do
      a' <- normaliseClosed (close g a)
      if !(compileTimeBinder rig a') then pure rest else pure (a' :: rest)
fieldTypes _ _ _ _ = pure []

||| The sites a type constructor's fields write: each runtime field of each
||| of its constructors, constructors in their declared order and fields in
||| binder order, read over the type's represented arguments (`represented`,
||| which the caller has read). The type is each site's writer, since its
||| markers are the type's arguments; the constructor is where the site is
||| written, its `within` and its location, for the message that names it.
||| The field types go to the site walk as they are: it reads each type
||| constructor they apply as its key does, so reading them here too would
||| be a second reading.
export
fieldSites : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
             (t : Address) -> GlobalDef -> (constructors : List Name) -> (represented : List Nat) -> Front (List Site)
fieldSites t tdef cons rs = (>>= id) <$> traverse constructorSites cons
  where
    -- One constructor's sites. Its address is its placement, from the
    -- lookup that finds it, so a constructor found without an address
    -- cannot happen. A type's constructor names carry no proof of their
    -- entries: one the context does not hold is the compiler's error.
    constructorSites : Name -> Front (List Site)
    constructorSites cn = do
      Just (placement, cdef) <- core (resolve cn)
        | Nothing => internal (location tdef)
                       ("the context does not hold " ++ show cn ++ ", a constructor of " ++ show (fullname tdef))
      -- The type as written may hide binders behind a definition (`a -@
      -- b`); its normal form shows each one, as the translation reads it.
      ty <- normaliseClosed !(typeOfDefinition cdef)
      fts <- fieldTypes none 0 (bindings rs (returned none 0 ty)) ty
      (>>= id) <$> traverse (\ft => map (\st => { fc := location cdef } st) <$> sitesIn t (addressOf placement) ft) fts
