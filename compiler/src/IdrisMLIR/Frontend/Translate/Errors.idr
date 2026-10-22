-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The translation's errors, the user's and the compiler's, and its
||| locations: an Idris location as a Core one.
module IdrisMLIR.Frontend.Translate.Errors

import Core.Context
import Core.Core
import Core.Directory
import Core.FC
import Core.TT

import IdrisMLIR.Frontend.Resolve
import IdrisMLIR.Emit
import IdrisMLIR.Frontend.Translate.State
import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.Registry.Libraries
import IdrisMLIR.Spec.Core.Rules

import Data.Maybe
import Data.SnocList
import Data.SortedMap

%default total

export
isEmptyFC : FC -> Bool
isEmptyFC EmptyFC = True
isEmptyFC _ = False

||| Where a refusal at an Idris location is: there, or, at no location, at
||| the module being compiled.
export
siteAt : {auto s : Ref TState TS} -> FC -> Core NonEmptyFC
siteAt fc = case isNonEmptyFC fc of
  Just site => pure site
  Nothing => (.moduleFC) <$> get TState

||| Refuses the program: the refusal is held as the one in flight, and an
||| Idris error unwinds to `noting`, which records the refusal. The error is
||| never printed: the refusal is what the program's compilation reports.
export
rejectWith : {auto s : Ref TState TS} -> Refusal -> Core a
rejectWith r = do
  update TState { inFlight := Just r }
  throw (GenericMsg (justFC r.site) r.message)

||| A user error, by the rule that refuses it, at a location (the module's
||| when Idris gives none), the message naming the definition that owns
||| what is refused.
export
reject : {auto s : Ref TState TS} -> {c : Category} -> FC -> String -> Rule c -> String -> Core a
reject fc owner rule what = do
  site <- siteAt fc
  rejectWith (MkRefusal (Refusal rule) site (owner ++ ": " ++ what))

||| A user error by a rule a registry row names, of whatever category the
||| row's rule is: as `reject` refuses.
export
refuse : {auto s : Ref TState TS} -> FC -> String -> SomeRule -> String -> Core a
refuse fc owner rule what = do
  site <- siteAt fc
  rejectWith (MkRefusal rule site (owner ++ ": " ++ what))

||| A compiler bug, not the user's: Idris's own error for one, which the
||| frontend's exit status tells apart from every error of the program.
export
internal : FC -> String -> Core a
internal fc msg = throw (InternalError (show fc ++ ": internal error: " ++ msg))

||| Runs one check, or translates one part, of the program so that its
||| rejection does not stop the others: the refusal in flight, recorded once
||| however many parts find it, or else the error Idris raised, and the part
||| gives nothing. The compiler's own error still ends the run,
||| since nothing after it can be trusted.
export
noting : {auto s : Ref TState TS} -> Core a -> Core (Maybe a)
noting part = catch (Just <$> part) $ \err => case err of
  InternalError _ => throw err
  _ => do
    st <- get TState
    let found = maybe (ByIdris err) Refused st.inFlight
    put TState ({ inFlight := Nothing, rejected $= recorded found } st)
    pure Nothing
  where
    -- Two refusals are one when they are equal, by value. An error of
    -- Idris's has no equality, and no print stands for one: each is
    -- recorded where a part finds it.
    same : Rejection -> Rejection -> Bool
    same (Refused r) (Refused r') = r == r'
    same _ _ = False

    recorded : Rejection -> SnocList Rejection -> SnocList Rejection
    recorded r rs = if any (same r) rs then rs else rs :< r

||| A check run as `noting` runs it, for what it finds alone.
export
noted : {auto s : Ref TState TS} -> Core () -> Core ()
noted check = ignore (noting check)

||| The rejections recorded so far, the first found first.
export
rejections : {auto s : Ref TState TS} -> Core (List Rejection)
rejections = pure ((!(get TState)).rejected <>> [])

||| Where the code of a module comes from, as the registry gives its origin,
||| and its source file when the project has one, both found anew.
placeOf : {auto c : Ref Ctxt Defs} -> ModuleIdent -> Span -> Core (Origin, Maybe String)
placeOf ident sp = do
  file <- moduleSource (MkFC (PhysicalIdrSrc ident) (sp.startLine, sp.startCol) (sp.endLine, sp.endCol)) ident
  origin <- originOf ident
  pure (origin, file)

||| A span of a module as a Core location, the module's origin and source
||| file found by `place`.
inModule : (place : ModuleIdent -> Span -> Core (Origin, Maybe String)) -> ModuleIdent -> Span -> Core Loc
inModule place ident sp = do
  (origin, file) <- place ident sp
  pure (MkLoc origin (InModule (shown (show ident)) file sp))

||| An Idris location as a Core location, each module's origin and source
||| file found by `place`. A package file is in no module.
located : (place : ModuleIdent -> Span -> Core (Origin, Maybe String)) -> FC -> Core Loc
located place (MkFC (PhysicalIdrSrc ident) (sl, sc) (el, ec)) = inModule place ident (MkSpan sl sc el ec)
located place (MkVirtualFC (PhysicalIdrSrc ident) (sl, sc) (el, ec)) = inModule place ident (MkSpan sl sc el ec)
located place (MkFC (PhysicalPkgSrc file) (sl, sc) (el, ec)) = pure (MkLoc Generated (InPackage file (MkSpan sl sc el ec)))
located place _ = pure noLoc

||| An Idris location as a Core location, each module's origin and source
||| file found once per module (`places`).
export
toLoc : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> FC -> Core Loc
toLoc = located cached
  where
    cached : ModuleIdent -> Span -> Core (Origin, Maybe String)
    cached ident sp = case lookup ident (!(get TState)).places of
      Just known => pure known
      Nothing => do
        known <- placeOf ident sp
        update TState { places $= insert ident known }
        pure known

||| A refusal as the module of a refused program carries it, its site the
||| location `toLoc` gives, found anew: the program is no longer being
||| translated when its refusals are written.
export
moduleRefusal : {auto c : Ref Ctxt Defs} -> SomeRule -> NonEmptyFC -> String -> Core ModuleRefusal
moduleRefusal rule site message = do
  loc <- located placeOf (justFC site)
  pure (MkModuleRefusal rule loc message)
