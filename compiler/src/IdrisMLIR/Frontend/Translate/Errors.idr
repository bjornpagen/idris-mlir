-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The translation's errors, the user's and the compiler's, and its
||| locations: an Idris location as a Core one.
module IdrisMLIR.Frontend.Translate.Errors

import Core.Context
import Core.Core
import Core.Directory
import Core.TT

import IdrisMLIR.Frontend.Resolve
import IdrisMLIR.Frontend.Translate.State
import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.Registry.Libraries
import IdrisMLIR.Syntax.Idr

import Data.Maybe
import Data.SnocList
import Data.SortedMap

%default total

export
isEmptyFC : FC -> Bool
isEmptyFC EmptyFC = True
isEmptyFC _ = False

||| A user error, never at an empty location: `<owner>: unsupported
||| (<reason>): <what>`, which Idris prints at its location.
export
reject : {auto s : Ref TState TS} -> FC -> String -> Rule -> String -> Core a
reject fc owner rule what = do
  st <- get TState
  let fc' = if isEmptyFC fc then st.moduleFC else fc
  throw (GenericMsg fc' (owner ++ ": unsupported (" ++ show rule ++ "): " ++ what))

||| A compiler bug, not the user's: Idris's own error for one, which the
||| frontend's exit status tells apart from every error of the program.
export
internal : FC -> String -> Core a
internal fc msg = throw (InternalError (show fc ++ ": internal error: " ++ msg))

||| Runs one check, or translates one part, of the program so that its
||| rejection does not stop the others: the program's error is recorded,
||| once however many parts find it, and the part gives nothing. The
||| compiler's own error still ends the run, since nothing after it can be
||| trusted.
export
noting : {auto s : Ref TState TS} -> Core a -> Core (Maybe a)
noting part = catch (Just <$> part) $ \err => case err of
  InternalError _ => throw err
  _ => do
    st <- get TState
    let shown = show err
    unless (any (\e => show e == shown) st.rejected) $
      put TState ({ rejected $= (:< err) } st)
    pure Nothing

||| A check run as `noting` runs it, for what it finds alone.
export
noted : {auto s : Ref TState TS} -> Core () -> Core ()
noted check = ignore (noting check)

||| The rejections recorded so far, the first found first.
export
rejections : {auto s : Ref TState TS} -> Core (List Error)
rejections = pure ((!(get TState)).rejected <>> [])

||| A location in a module as a Core location, with the source file
||| resolved and the origin the registry gives the module, each found once
||| per module (`places`).
moduleLoc : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
            ModuleIdent -> (Int, Int) -> (Int, Int) -> Core Loc
moduleLoc ident (sl, sc) (el, ec) = do
  (origin, file) <- case lookup ident (!(get TState)).places of
    Just known => pure known
    Nothing => do
      file <- fromMaybe "" <$> moduleSource (MkFC (PhysicalIdrSrc ident) (sl, sc) (el, ec)) ident
      origin <- originOf ident
      update TState { places $= insert ident (origin, file) }
      pure (origin, file)
  pure (MkLoc origin (shown (show ident)) file sl sc el ec)

||| An Idris location as a Core location. A package file is in no module.
export
toLoc : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> FC -> Core Loc
toLoc (MkFC (PhysicalIdrSrc ident) start end) = moduleLoc ident start end
toLoc (MkVirtualFC (PhysicalIdrSrc ident) start end) = moduleLoc ident start end
toLoc (MkFC (PhysicalPkgSrc file) (sl, sc) (el, ec)) = pure (MkLoc Generated (shown "") file sl sc el ec)
toLoc _ = pure noLoc
