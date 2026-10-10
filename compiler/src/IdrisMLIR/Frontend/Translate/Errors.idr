||| The translation's errors, the user's and the compiler's, and its
||| locations: an Idris location as a Core one and back.
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
import IdrisMLIR.Rule

import Data.Maybe
import Data.SnocList
import Data.SortedMap

%default covering

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

||| An Idris location as a Core location, with the source file resolved and
||| the origin the registry gives its module, each found once per module
||| (`places`). A package file is in no module.
export
toLoc : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> FC -> Core Loc
toLoc fc@(MkFC (PhysicalIdrSrc ident) (sl, sc) (el, ec)) = do
  let place = show ident
  (origin, file) <- case lookup place (!(get TState)).places of
    Just known => pure known
    Nothing => do
      file <- fromMaybe "" <$> moduleSource fc ident
      origin <- originOf ident
      update TState { places $= insert place (origin, file) }
      pure (origin, file)
  pure (MkLoc origin (shown place) file sl sc el ec)
toLoc (MkFC (PhysicalPkgSrc file) (sl, sc) (el, ec)) = pure (MkLoc Generated (shown "") file sl sc el ec)
toLoc (MkVirtualFC (PhysicalIdrSrc ident) (sl, sc) (el, ec)) =
  toLoc (MkFC (PhysicalIdrSrc ident) (sl, sc) (el, ec))
toLoc _ = pure noLoc

||| A Core location as an Idris location, for errors raised after
||| translation: the module is the one Idris named.
export
fromLoc : Loc -> FC
fromLoc l = case l.origin of
  Generated => if l.file == "" then EmptyFC else MkFC (PhysicalPkgSrc l.file) start end
  _ => MkFC (PhysicalIdrSrc (nsAsModuleIdent (mkNamespace (show l.place)))) start end
  where
    start : FilePos
    start = (l.startLine, l.startCol)
    end : FilePos
    end = (l.endLine, l.endCol)
