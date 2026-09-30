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

%default covering

export
isEmptyFC : FC -> Bool
isEmptyFC EmptyFC = True
isEmptyFC _ = False

||| A user error, never at an empty location.
export
reject : {auto s : Ref TState TS} -> FC -> String -> Rule -> String -> Core a
reject fc owner rule what = do
  st <- get TState
  let fc' = if isEmptyFC fc then st.moduleFC else fc
  throw (GenericMsg fc' ("mlir backend: " ++ owner ++ ": unsupported (" ++ show rule ++ "): " ++ what))

||| A compiler bug, not the user's.
export
internal : FC -> String -> Core a
internal fc msg = throw (GenericMsg fc ("mlir backend: internal error: " ++ msg))

||| An Idris location as a Core location, with the source file resolved and
||| the origin the registry gives its module. A package file is in no module.
export
toLoc : {auto c : Ref Ctxt Defs} -> FC -> Core Loc
toLoc fc@(MkFC (PhysicalIdrSrc ident) (sl, sc) (el, ec)) = do
  file <- catch (nsToSource fc ident) (\_ => pure "")
  pure (MkLoc !(originOf ident) (shown (show ident)) file sl sc el ec)
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
