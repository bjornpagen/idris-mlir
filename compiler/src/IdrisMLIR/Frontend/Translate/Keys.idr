||| What each instance is called, and what tells two instances apart. An
||| instance is its definition and its compile-time arguments up to the
||| names of binders: that is its identity, which nothing prints. Its key is
||| how it reads: the definition's printed name, a block named by its place
||| in the definition that holds it, and the arguments printed with every
||| binder named by its depth, so that one instance prints one way whatever
||| Idris called its binders and whatever counter it numbered its blocks
||| with. Emit derives the symbol from the key.
module IdrisMLIR.Frontend.Translate.Keys

import Core.Case.CaseTree
import Core.Context
import Core.Core
import Core.Env
import Core.Hash
import Core.Name.Scoped
import Core.TT
import Libraries.Data.List.Thin
import Libraries.Data.NameMap

import IdrisMLIR.Frontend.Translate.Closed
import IdrisMLIR.Frontend.Translate.Errors
import IdrisMLIR.Frontend.Translate.State
import IdrisMLIR.Ids

import Data.List
import Data.SnocList
import Data.SortedMap
import Data.String

%default covering

------------------------------------------------------------------------------
-- Names
------------------------------------------------------------------------------

||| Idris's printed full name, except that a `DN`, which is how Idris names
||| an implementation's method, prints its inner name: the display name
||| (`Prelude.Types.map`) is every implementation's in the module, the inner
||| one (`Prelude.Types.map_Functor_Maybe`) is this one's.
plainOrigin : Name -> String
plainOrigin (NS ns (DN _ n)) = show (NS ns n)
plainOrigin (DN _ n) = show n
plainOrigin n = show n

||| The blocks Idris makes of a definition: a case block and a with block,
||| which it numbers with one counter for the whole build, and a nested
||| (`where`) function, which it numbers with its parent's place in the
||| context. None of those numbers says where the block is.
data Block = CaseB | WithB | NestedB String

blockOf : Name -> Maybe Block
blockOf (NS _ n) = blockOf n
blockOf (CaseBlock _ _) = Just CaseB
blockOf (WithBlock _ _) = Just WithB
blockOf (Nested _ inner) = Just (NestedB (plainOrigin inner))
blockOf _ = Nothing

||| The outermost definition named in the string Idris gives a case or with
||| block for its parent: `case block in f`, `with block in f`, or `f,go`
||| for a block of `f`'s nested `go`.
outermost : String -> String
outermost s =
  if isPrefixOf "case block in " s || isPrefixOf "with block in " s
     then outermost (substr 14 (length s) s)
     else pack (takeWhile (/= ',') (unpack s))

||| The definition a case, with or nested block belongs to, through every
||| block between: a case or with block's parent is a string, in the
||| block's namespace; a nested function's parent is its place in the
||| context.
export
rootOf : {auto c : Ref Ctxt Defs} -> Name -> Core Name
rootOf (NS ns (CaseBlock outer _)) = pure (NS ns (UN (Basic (outermost outer))))
rootOf (NS ns (WithBlock outer _)) = pure (NS ns (UN (Basic (outermost outer))))
rootOf (NS _ (Nested (outer, _) _)) = rootOf !(toFullNames (Resolved outer))
rootOf n = pure n

------------------------------------------------------------------------------
-- Blocks by position
------------------------------------------------------------------------------

||| What a definition refers to, in the order the walk meets it: a
||| definition, or a solved metavariable, which is walked through its
||| solution.
data Reference = ARef Name | AMeta Name

mutual
  ||| The references of a term, left to right: a function before its
  ||| argument, a binder's type and value before its scope.
  termRefs : SnocList Reference -> TT vs -> SnocList Reference
  termRefs acc (Ref _ _ n) = acc :< ARef n
  termRefs acc (Meta _ n _ args) = foldl termRefs (acc :< AMeta n) args
  termRefs acc (Bind _ _ b sc) = termRefs (binderRefs acc b) sc
  termRefs acc (App _ f a) = termRefs (termRefs acc f) a
  termRefs acc (As _ _ _ p) = termRefs acc p
  termRefs acc (TDelayed _ _ t) = termRefs acc t
  termRefs acc (TDelay _ _ t a) = termRefs (termRefs acc t) a
  termRefs acc (TForce _ _ t) = termRefs acc t
  termRefs acc _ = acc

  binderRefs : SnocList Reference -> TTBinder (TT vs) -> SnocList Reference
  binderRefs acc (Let _ _ v ty) = termRefs (termRefs acc ty) v
  binderRefs acc (PLet _ _ v ty) = termRefs (termRefs acc ty) v
  binderRefs acc b = termRefs acc (binderType b)

mutual
  ||| The references of a case tree: its alternatives in order, each leaf's
  ||| term.
  treeRefs : SnocList Reference -> CaseTree vs -> SnocList Reference
  treeRefs acc (Case _ _ _ alts) = foldl altRefs acc alts
  treeRefs acc (STerm _ tm) = termRefs acc tm
  treeRefs acc _ = acc

  altRefs : SnocList Reference -> CaseAlt vs -> SnocList Reference
  altRefs acc (ConCase _ _ _ sc) = treeRefs acc sc
  altRefs acc (DelayCase _ _ sc) = treeRefs acc sc
  altRefs acc (ConstCase _ sc) = treeRefs acc sc
  altRefs acc (DefaultCase sc) = treeRefs acc sc

||| What a definition refers to: its compile-time tree's references, then
||| its clauses' terms, which the translation also takes references from
||| when it unfolds a definition: a block whose call the tree compiled away
||| is still referred to there. The runtime tree is never read: it is built
||| from the same clauses after erasure, so it refers to nothing they do
||| not. Its type's references come last: a block no body calls may still
||| be named by a type (a local datatype of a block, named in the types
||| that mention it), and after the body's, so the blocks a body refers to
||| keep their numbers. For a solved metavariable these are its
||| solution's.
referencesOf : {auto c : Ref Ctxt Defs} -> Name -> Core (List Reference)
referencesOf n = do
  defs <- get Ctxt
  Just def <- lookupCtxtExact n (gamma defs)
    | Nothing => pure []
  let body = case definition def of
               PMDef _ _ tree _ pats => treeRefs [<] tree <>> concatMap patRefs pats
               _ => []
  pure (body ++ (termRefs [<] (type def) <>> []))
  where
    patRefs : (vs : Scope ** (Env Term vs, Term vs, Term vs)) -> List Reference
    patRefs (_ ** (_, lhs, rhs)) = termRefs (termRefs [<] lhs) rhs <>> []

mutual
  ||| Names the blocks a definition refers to, depth first: each block not
  ||| yet named gets the next number of its kind under the definition that
  ||| refers to it first, and its own references are walked at once under
  ||| its new name. The numbers count from 0 in each parent, so a block's
  ||| name changes only with its parent's definition, never with how many
  ||| blocks the rest of the build made. An ordinary reference is walked
  ||| too: a block is not always referred to by the definition being
  ||| translated or by the one Idris named it for (a case block of an
  ||| interface's default method is referred to by the implementation
  ||| methods the default was elaborated into, under the method's name),
  ||| so the walk follows references until it reaches a definition that
  ||| does refer to the block. Each definition is walked once.
  nameUnder : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
              String -> (Nat, Nat) -> List Reference -> Core ()
  nameUnder origin ks [] = pure ()
  nameUnder origin ks (AMeta m :: rest) = do
    solution <- referencesOf m
    nameUnder origin ks (solution ++ rest)
  nameUnder origin (cases, withs) (ARef r :: rest) = do
    full <- toFullNames r
    let Just kind = blockOf full
      | Nothing => do nameBlocksOf full
                      nameUnder origin (cases, withs) rest
    let key = nameKey full
    if isJust (lookup key (!(get TState)).blockNames)
       then nameUnder origin (cases, withs) rest
       else do
         let (name, ks) : (String, (Nat, Nat)) = case kind of
                            CaseB => (origin ++ ".case" ++ show cases, (S cases, withs))
                            WithB => (origin ++ ".with" ++ show withs, (cases, S withs))
                            NestedB inner => (origin ++ "." ++ inner, (cases, withs))
         update TState { blockNames $= insert key name }
         nameUnder name (0, 0) !(referencesOf full)
         nameUnder origin ks rest

  ||| Names the blocks of a definition that is no block, once.
  nameBlocksOf : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Name -> Core ()
  nameBlocksOf n = do
    full <- toFullNames n
    let key = nameKey full
    when (isNothing (blockOf full) && isNothing (lookup key (!(get TState)).blockNames)) $ do
      let origin = plainOrigin full
      update TState { blockNames $= insert key origin }
      nameUnder origin (0, 0) !(referencesOf full)

namespaceOf : Name -> Maybe Namespace
namespaceOf (NS ns _) = Just ns
namespaceOf (DN _ n) = namespaceOf n
namespaceOf _ = Nothing

||| The definition's printed name, which a key starts with: Idris's full
||| name (`plainOrigin`), and for a case, with or nested block its
||| parent's, then `.case<k>`, `.with<k>` or `.<name>`. A block is named
||| when a definition that refers to it is walked: first the one being
||| translated, then the block's root, and at last every definition in
||| the block's namespace and beyond, since neither of the first two
||| need refer to it: a default method's case block is referred to by
||| the implementation methods the default was elaborated into, and a
||| nested block's parent index is its place in the context that
||| elaborated it, which loading does not keep. The block and the
||| definition Idris made it in share a namespace, so that is where the
||| search starts.
keyOrigin : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Name -> Core String
keyOrigin n = do
  full <- toFullNames n
  let Just _ = blockOf full
    | Nothing => pure (plainOrigin full)
  let key = nameKey full
  Nothing <- named key
    | Just o => pure o
  st <- get TState
  case st.current >>= \i => lookup i st.requesters of
    Just r => nameBlocksOf r.name
    Nothing => pure ()
  Nothing <- named key
    | Just o => pure o
  nameBlocksOf !(rootOf full)
  Nothing <- named key
    | Just o => pure o
  defs <- get Ctxt
  let all = map fst (Libraries.Data.NameMap.toList (resolvedAs (gamma defs)))
  let (near, far) = partition (\c => namespaceOf c == namespaceOf full) all
  search key (near ++ far)
  Just o <- named key
    | Nothing => internal EmptyFC ("no definition refers to the block " ++ show full)
  pure o
  where
    named : String -> Core (Maybe String)
    named key = pure (lookup key (!(get TState)).blockNames)

    search : String -> List Name -> Core ()
    search key [] = pure ()
    search key (c :: cs) = do
      nameBlocksOf c
      case !(named key) of
        Just _ => pure ()
        Nothing => search key cs

------------------------------------------------------------------------------
-- Arguments as text
------------------------------------------------------------------------------

||| Where a term is printed: on its own, as the domain of an arrow, or as an
||| applied argument, which decides the parentheses it needs.
data Place = Alone | Domain | Applied

||| The name of the binder at a depth, counting from the outside.
binderAt : Nat -> String
binderAt d = "x" ++ show d

parensIf : Bool -> String -> String
parensIf True s = "(" ++ s ++ ")"
parensIf False s = s

quantityPrefix : RigCount -> String
quantityPrefix rig = if isErased rig then "0 " else if isLinear rig then "1 " else ""

mutual
  ||| A term at a depth of binders: a variable by its binder's depth, a
  ||| definition by its printed full name, an arrow whose result does not
  ||| mention its binder as `a -> b`, one whose does as `(x0 : a) -> b`,
  ||| each with Idris's quantity and braces.
  render : Nat -> Place -> TT vs -> String
  render d _ (Local _ _ idx _) = binderAt (minus d (S idx))
  render d _ (Ref _ _ n) = plainOrigin n
  render d _ (Meta _ n _ _) = "?" ++ plainOrigin n
  render d p (Bind _ _ (Pi _ rig info a) sc) = parensIf (notAlone p) (arrow d rig info a sc)
  render d p (Bind _ _ (Lam {}) sc) = parensIf (notAlone p) ("\\" ++ binderAt d ++ " => " ++ render (S d) Alone sc)
  render d p (Bind _ _ (Let _ _ v _) sc) =
    parensIf (notAlone p) ("let " ++ binderAt d ++ " = " ++ render d Alone v ++ " in " ++ render (S d) Alone sc)
  render d p (Bind _ _ _ sc) = render (S d) p sc
  render d p tm@(App {}) =
    let (f, as) = getFnArgs tm in
    parensIf (applied p) (joinBy " " (render d Applied f :: map (render d Applied) as))
  render d _ (PrimVal _ c) = show c
  render d _ (Erased _ _) = "_"
  render d _ (TType _ _) = "Type"
  render d p (TDelayed _ _ t) = parensIf (applied p) ("Lazy " ++ render d Applied t)
  render d p (TDelay _ _ _ t) = parensIf (applied p) ("Delay " ++ render d Applied t)
  render d p (TForce _ _ t) = parensIf (applied p) ("Force " ++ render d Applied t)
  render d p (As _ _ _ pat) = render d p pat

  arrow : Nat -> RigCount -> PiInfo (TT vs) -> TT vs -> TT (x :: vs) -> String
  arrow d rig info a sc =
    let dependent = isNothing (shrink sc (Drop Refl))
        domain = if dependent then binderAt d ++ " : " ++ render d Alone a else render d Domain a
        inner = quantityPrefix rig ++ domain
        bound = case info of
                  Explicit => parensIf dependent inner
                  AutoImplicit => "{{" ++ inner ++ "}}"
                  _ => "{" ++ inner ++ "}"
    in bound ++ " -> " ++ render (S d) Alone sc

  notAlone : Place -> Bool
  notAlone Alone = False
  notAlone _ = True

  applied : Place -> Bool
  applied Applied = True
  applied _ = False

||| A compile-time argument as a key prints it, every name full and every
||| binder named by its depth, so that arguments that differ only by the
||| names of their binders, which are one instance, print alike, and no
||| counter of Idris's reaches the text.
argumentText : {auto c : Ref Ctxt Defs} -> ClosedTerm -> Core String
argumentText tm = pure (render 0 Alone !(toFullNames tm))

------------------------------------------------------------------------------
-- Identities and keys
------------------------------------------------------------------------------

||| The identity and the key of the instance of a definition at its
||| compile-time arguments (`Nothing` at a position that keys nothing).
||| Instances are bucketed by a hash of their arguments, so a request
||| compares its arguments with the few instances in its bucket, not with
||| every instance of the definition; neither the comparison nor the hash
||| sees a binder's name. Only a new instance is printed, since printing is
||| the costly part and most requests are repeats. The identity is the
||| bucket and the instance's place in it, which tells instances apart and
||| says nothing to a reader.
export
instanceKey : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
              Name -> List (Maybe ClosedTerm) -> Core (String, InstanceKey)
instanceKey n args = do
  full <- toFullNames n
  args' <- traverse (traverseOpt toFullNames) args
  let bucket = nameKey full ++ "#" ++ show (hash args')
  let same = fromMaybe [] (lookup bucket (!(get TState)).named)
  case find ((== args') . fst) same of
    Just (_, found) => pure found
    Nothing => do
      origin <- keyOrigin full
      texts <- traverse argumentText (catMaybes args')
      let found = (bucket ++ "#" ++ show (length same), MkInstanceKey origin texts)
      update TState { named $= insert bucket ((args', found) :: same) }
      pure found
