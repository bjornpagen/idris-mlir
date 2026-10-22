-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module Idris.Parser.Let

import Idris.Syntax
import Idris.Syntax.Tree
import Libraries.Text.Bounded

import Data.Either
import Data.List1

%default total

-- Core's own monad functions are hidden: every applicative and monadic step
-- here is an interface's, at the type the step is taken in.
%hide Core.Core.(>>=)
%hide Core.Core.(>>)
%hide Core.Core.pure
%hide Core.Core.(<*>)
%hide Core.Core.traverse
%hide Core.Core.map

------------------------------------------------------------------------
-- Types

-- `let ... in ...` is used for two different notions:
-- * pattern-matching let binders to locally take an expression apart
-- * Local definitions that can be recursive

public export
record LetBinder where
  constructor MkLetBinder
  letUsage     : RigCount
  letPattern   : Id FTerm
  letBoundType : Id FTerm
  letBoundTerm : Id FTerm
  letUnhappy   : List (Id FClause)

||| A block of local definitions, as written: its neighbouring clauses are
||| collected into definitions when it is decoded.
public export
LetDecl : Type
LetDecl = List (Id FDecl)

------------------------------------------------------------------------
-- Let-binding functions

-- A run of neighbouring blocks of definitions keeps each block apart, as
-- each was collected on its own.
letFactory : (List (WithBounds LetBinder) -> a -> Build a) ->
             (WithBounds (List LetDecl) -> a -> Build a) ->
             List1 (WithBounds (Either LetBinder LetDecl)) ->
             a -> Build a
letFactory letBind letDeclare blocks scope = foldr mkLet (pure scope) groups where

  LetBlock : Type
  LetBlock = Either (List1 (WithBounds LetBinder)) (List1 (WithBounds LetDecl))

  groups : List LetBlock
  groups = compress (forget $ map (\ b => bimap (<$ b) (<$ b) b.val) blocks)

  mkLet : LetBlock -> Build a -> Build a
  mkLet (Left  letBinds) inner = inner >>= letBind (forget letBinds)
  mkLet (Right letDecls) inner =
    let bounds = mergeBounds (head letDecls) (last letDecls)
    in inner >>= letDeclare (map val (forget letDecls) <$ bounds)

export
mkLets : OriginDesc ->
         List1 (WithBounds (Either LetBinder LetDecl)) ->
         Id FTerm -> Build (Id FTerm)
mkLets origin = letFactory buildLets
  (\ decls, scope => make (TmLocal (virtualiseFC $ boundToFC origin decls) decls.val scope))

  where

    buildLets : List (WithBounds LetBinder) -> Id FTerm -> Build (Id FTerm)
    buildLets [] sc = pure sc
    buildLets (b :: rest) sc
      = do inner <- buildLets rest sc
           let (MkLetBinder rig pat ty val alts) = b.val
           make (TmLet (virtualiseFC $ boundToFC origin b) rig pat ty val inner alts)

||| The statements a `let` block in a `do` block makes: a statement for each
||| binding, whose pattern decides when it is decoded whether it binds a
||| variable, and one for each run of local definitions.
export
mkDoLets : OriginDesc ->
           List1 (WithBounds (Either LetBinder LetDecl)) ->
           Build (List (Id FDo))
mkDoLets origin lets = letFactory
    (\ binds, rest => (++ rest) <$> traverse binding binds)
    (\ decls, rest => (:: rest) <$> make (StLetLocal (boundToFC origin decls) decls.val))
    lets
    []

  where

    binding : WithBounds LetBinder -> Build (Id FDo)
    binding b = let (MkLetBinder rig pat ty val alts) = b.val in
                make (StLet (boundToFC origin b) rig pat ty val alts)
