module Core.Metadata

import Core.Context
import Core.Env

%default covering

-- Upstream records here what the IDE mode and the REPL's editing commands
-- read back: the types and left-hand sides at each source span, semantic
-- highlighting, and the .ttm file that saves them beside the TTC. This
-- compiler has neither, and nothing it keeps reads them, so the state is
-- empty and every adder does nothing. The names stay, because the
-- elaborator threads `Ref MD Metadata` through most of its functions and
-- the parser produces decorations as it goes.

public export
data Decoration : Type where
  Comment   : Decoration
  Typ       : Decoration
  Function  : Decoration
  Data      : Decoration
  Keyword   : Decoration
  Bound     : Decoration
  Namespace : Decoration
  Postulate : Decoration
  Module    : Decoration

public export
Eq Decoration where
  Comment   == Comment   = True
  Typ       == Typ       = True
  Function  == Function  = True
  Data      == Data      = True
  Keyword   == Keyword   = True
  Bound     == Bound     = True
  Namespace == Namespace = True
  Postulate == Postulate = True
  Module    == Module    = True
  _         == _         = False

public export
Show Decoration where
  show Comment   = "comment"
  show Typ       = "type"
  show Function  = "function"
  show Data      = "data"
  show Keyword   = "keyword"
  show Bound     = "bound"
  show Namespace = "namespace"
  show Postulate = "postulate"
  show Module    = "module"

export
nameDecoration : Name -> NameType -> Decoration
nameDecoration nm nt
  = ifThenElse (isUnsafeBuiltin nm) Postulate (nameTypeDecoration nt)

  where

  nameTypeDecoration : NameType -> Decoration
  nameTypeDecoration Bound        = Bound
  nameTypeDecoration Func         = Function
  nameTypeDecoration (DataCon {}) = Data
  nameTypeDecoration (TyCon {})   = Typ

public export
ASemanticDecoration : Type
ASemanticDecoration = (NonEmptyFC, Decoration, Maybe Name)

public export
SemanticDecorations : Type
SemanticDecorations = List ASemanticDecoration

public export
data Metadata = MkMetadata

export
initMetadata : OriginDesc -> Metadata
initMetadata _ = MkMetadata

-- A label for metadata in the global state
export
data MD : Type where

export
addLHS : {vars : _} ->
         {auto c : Ref Ctxt Defs} ->
         {auto m : Ref MD Metadata} ->
         FC -> Nat -> Env Term vars -> Term vars -> Core ()
addLHS _ _ _ _ = pure ()

export
addNameType : {vars : _} ->
              {auto c : Ref Ctxt Defs} ->
              {auto m : Ref MD Metadata} ->
              FC -> Name -> Env Term vars -> Term vars -> Core ()
addNameType _ _ _ _ = pure ()

export
addTyDecl : {vars : _} ->
            {auto c : Ref Ctxt Defs} ->
            {auto m : Ref MD Metadata} ->
            FC -> Name -> Env Term vars -> Term vars -> Core ()
addTyDecl _ _ _ _ = pure ()

export
addNameLoc : {auto m : Ref MD Metadata} ->
             {auto c : Ref Ctxt Defs} ->
             FC -> Name -> Core ()
addNameLoc _ _ = pure ()

export
setHoleLHS : {auto m : Ref MD Metadata} -> ClosedTerm -> Core ()
setHoleLHS _ = pure ()

export
clearHoleLHS : {auto m : Ref MD Metadata} -> Core ()
clearHoleLHS = pure ()

export
withCurrentLHS : {auto c : Ref Ctxt Defs} ->
                 {auto m : Ref MD Metadata} ->
                 Name -> Core ()
withCurrentLHS _ = pure ()

export
addSemanticDefault : {auto m : Ref MD Metadata} ->
                     ASemanticDecoration -> Core ()
addSemanticDefault _ = pure ()

export
addSemanticAlias : {auto m : Ref MD Metadata} ->
                   NonEmptyFC -> NonEmptyFC -> Core ()
addSemanticAlias _ _ = pure ()

export
addSemanticDecorations : {auto m : Ref MD Metadata} ->
                         {auto c : Ref Ctxt Defs} ->
   SemanticDecorations -> Core ()
addSemanticDecorations _ = pure ()
