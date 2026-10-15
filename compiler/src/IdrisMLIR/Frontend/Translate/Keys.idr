-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| What each instance is called, and what tells two instances apart. An
||| instance is its definition and its compile-time arguments up to the
||| names of binders: that is its identity, which nothing prints. Its key is
||| how it reads: the definition's printed name, a block named by its place
||| in the definition that holds it, and the arguments printed with every
||| binder named by its depth, so that one instance prints one way whatever
||| Idris called its binders and whatever counter it numbered its blocks
||| with. The symbol is the key printed (`Term.keyText`), with the hash of
||| the identity where the print drops part of it.
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
import IdrisMLIR.Types
import IdrisMLIR.Term

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

||| Does a name print with less than it is? A `DN` prints its inner name
||| without its display, and a case or with block's name drops its number.
dropsName : Name -> Bool
dropsName (NS _ n) = dropsName n
dropsName (DN _ _) = True
dropsName (CaseBlock _ _) = True
dropsName (WithBlock _ _) = True
dropsName (Nested _ n) = dropsName n
dropsName _ = False

||| Does a constant print with less than it is? An integer prints its value
||| and not its width, so `5` is an `Int` and a `Bits8` alike; read on the
||| literal the constant is (`constantLit`).
dropsWidth : Constant -> Bool
dropsWidth c = case constantLit c of
  Just (LInt _ _) => True
  Just (LBig _) => True
  _ => False

mutual
  ||| A term at a depth of binders: a variable by its binder's depth, a
  ||| definition by its printed full name, an arrow whose result does not
  ||| mention its binder as `a -> b`, one whose does as `(x0 : a) -> b`,
  ||| each with Idris's quantity and braces; and whether the print dropped
  ||| part of what tells terms apart (`eqTerm`): an erased part that is not
  ||| a placeholder, a metavariable's arguments, a name printed with less, a
  ||| lambda's or a let's binder type and quantity, a binder printed
  ||| through, a default implicit printed as implicit, an integer's width,
  ||| a delay's type, an as-pattern's name.
  render : Nat -> Place -> TT vs -> (String, Bool)
  render d _ (Local _ _ idx _) = (binderAt (minus d (S idx)), False)
  render d _ (Ref _ _ n) = (plainOrigin n, dropsName n)
  render d _ (Meta _ n _ args) = ("?" ++ plainOrigin n, not (null args) || dropsName n)
  render d p (Bind _ _ (Pi _ rig info a) sc) =
    let (t, lost) = arrow d rig info a sc in (parensIf (notAlone p) t, lost)
  render d p (Bind _ _ (Lam {}) sc) =
    (parensIf (notAlone p) ("\\" ++ binderAt d ++ " => " ++ fst (render (S d) Alone sc)), True)
  render d p (Bind _ _ (Let _ _ v _) sc) =
    (parensIf (notAlone p) ("let " ++ binderAt d ++ " = " ++ fst (render d Alone v) ++ " in " ++
                            fst (render (S d) Alone sc)), True)
  render d p (Bind _ _ _ sc) = (fst (render (S d) p sc), True)
  render d p tm@(App {}) =
    let (f, as) = getFnArgs tm
        parts = map (render d Applied) (f :: as)
    in (parensIf (applied p) (joinBy " " (map fst parts)), any snd parts)
  render d _ (PrimVal _ c) = (show c, dropsWidth c)
  render d _ (Erased _ Placeholder) = ("_", False)
  render d _ (Erased _ _) = ("_", True)
  render d _ (TType _ _) = ("Type", False)
  render d p (TDelayed _ _ t) = let (s, lost) = render d Applied t in (parensIf (applied p) ("Lazy " ++ s), lost)
  render d p (TDelay _ _ _ t) = (parensIf (applied p) ("Delay " ++ fst (render d Applied t)), True)
  render d p (TForce _ _ t) = let (s, lost) = render d Applied t in (parensIf (applied p) ("Force " ++ s), lost)
  render d p (As _ _ _ pat) = (fst (render d p pat), True)

  arrow : Nat -> RigCount -> PiInfo (TT vs) -> TT vs -> TT (x :: vs) -> (String, Bool)
  arrow d rig info a sc =
    let dependent = isNothing (shrink sc (Drop Refl))
        alone = render d Alone a
        asDomain = render d Domain a
        domain = if dependent then binderAt d ++ " : " ++ fst alone else fst asDomain
        lostA = if dependent then snd alone else snd asDomain
        inner = quantityPrefix rig ++ domain
        rest = render (S d) Alone sc
    in (bound dependent inner info ++ " -> " ++ fst rest, lostA || defaulted info || snd rest)
    where
      bound : Bool -> String -> PiInfo (TT vs) -> String
      bound dependent inner Explicit = parensIf dependent inner
      bound _ inner AutoImplicit = "{{" ++ inner ++ "}}"
      bound _ inner _ = "{" ++ inner ++ "}"
      -- A default implicit prints as an implicit, without its default.
      defaulted : PiInfo (TT vs) -> Bool
      defaulted (DefImplicit _) = True
      defaulted _ = False

  notAlone : Place -> Bool
  notAlone Alone = False
  notAlone _ = True

  applied : Place -> Bool
  applied Applied = True
  applied _ = False

||| A compile-time argument as a key prints it, every name full and every
||| binder named by its depth, so that arguments that differ only by the
||| names of their binders, which are one instance, print alike, and no
||| counter of Idris's reaches the text; and whether the print dropped part
||| of the argument's identity.
argumentText : {auto c : Ref Ctxt Defs} -> ClosedTerm -> Core (String, Bool)
argumentText tm = pure (render 0 Alone !(toFullNames tm))

------------------------------------------------------------------------------
-- The identity as text
------------------------------------------------------------------------------

||| A string with its length before it, so that no encoding is a prefix of
||| another.
counted : String -> String
counted s = show (length s) ++ ":" ++ s

quantityCode : RigCount -> String
quantityCode rig = if isErased rig then "0" else if isLinear rig then "1" else "w"

mutual
  ||| A name by its structure, as Idris's `==` tells names apart: a `DN` by
  ||| its inner name alone, and a block (case, with, nested) by the name of
  ||| its place in the definition that holds it (`keyOrigin`), never by the
  ||| counter Idris numbered it with, so an unrelated edit does not move it.
  nameIdentity : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Name -> Core String
  nameIdentity n = case blockOf n of
    Just _ => ("K" ++) . counted <$> keyOrigin n
    Nothing => structural n
    where
      structural : Name -> Core String
      structural (NS ns m) =
        let parts = unsafeUnfoldNamespace ns in
        (("N" ++ show (length parts) ++ ";" ++ concatMap counted parts) ++) <$> nameIdentity m
      structural (UN (Basic x)) = pure ("U" ++ counted x)
      structural (UN (Field x)) = pure ("V" ++ counted x)
      structural (UN Underscore) = pure "_"
      structural (MN x i) = pure ("M" ++ counted x ++ show i ++ ";")
      structural (PV m i) = (\t => "P" ++ t ++ show i ++ ";") <$> nameIdentity m
      structural (DN _ m) = nameIdentity m
      structural (Resolved i) = pure ("R" ++ show i ++ ";")
      structural other = pure ("O" ++ counted (show other))

  ||| A term by its structure, as `eqTerm` tells terms apart: no location,
  ||| no binder name, every constant with its constructor.
  termIdentity : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> TT vs -> Core String
  termIdentity (Local _ _ idx _) = pure ("L" ++ show idx ++ ";")
  termIdentity (Ref _ _ n) = ("R" ++) <$> nameIdentity n
  termIdentity (Meta _ n _ args) = do
    nm <- nameIdentity n
    as <- traverse termIdentity args
    pure ("M" ++ nm ++ show (length args) ++ ";" ++ concat as)
  termIdentity (Bind _ _ b sc) = (\bt, st => "B" ++ bt ++ st) <$> binderIdentity b <*> termIdentity sc
  termIdentity (App _ f a) = (\ft, at => "A" ++ ft ++ at) <$> termIdentity f <*> termIdentity a
  termIdentity (As _ _ a p) = (\at, pt => "S" ++ at ++ pt) <$> termIdentity a <*> termIdentity p
  termIdentity (TDelayed _ _ t) = ("D" ++) <$> termIdentity t
  termIdentity (TDelay _ _ t a) = (\tt, at => "Y" ++ tt ++ at) <$> termIdentity t <*> termIdentity a
  termIdentity (TForce _ _ t) = ("F" ++) <$> termIdentity t
  termIdentity (PrimVal _ c) = pure ("C" ++ counted (constantCode c))
  termIdentity (Erased _ Placeholder) = pure "E_"
  termIdentity (Erased _ Impossible) = pure "E!"
  termIdentity (Erased _ (Dotted t)) = ("E." ++) <$> termIdentity t
  termIdentity (TType _ _) = pure "T"

  binderIdentity : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> TTBinder (TT vs) -> Core String
  binderIdentity (Lam _ rig info ty) = (\i, t => "l" ++ quantityCode rig ++ i ++ t) <$> piIdentity info <*> termIdentity ty
  binderIdentity (Let _ rig v ty) = (\vt, t => "e" ++ quantityCode rig ++ vt ++ t) <$> termIdentity v <*> termIdentity ty
  binderIdentity (Pi _ rig info ty) = (\i, t => "p" ++ quantityCode rig ++ i ++ t) <$> piIdentity info <*> termIdentity ty
  binderIdentity (PVar _ rig info ty) = (\i, t => "v" ++ quantityCode rig ++ i ++ t) <$> piIdentity info <*> termIdentity ty
  binderIdentity (PLet _ rig v ty) = (\vt, t => "t" ++ quantityCode rig ++ vt ++ t) <$> termIdentity v <*> termIdentity ty
  binderIdentity (PVTy _ rig ty) = (\t => "y" ++ quantityCode rig ++ t) <$> termIdentity ty

  piIdentity : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> PiInfo (TT vs) -> Core String
  piIdentity Implicit = pure "i"
  piIdentity Explicit = pure "x"
  piIdentity AutoImplicit = pure "a"
  piIdentity (DefImplicit t) = ("d" ++) <$> termIdentity t

  ||| A constant as the literal it is (`constantLit`), whose print keeps its
  ||| width apart (`5:Int`, `5:Bits8`); a primitive type or the world, which
  ||| is no literal, as Idris prints it.
  constantCode : Constant -> String
  constantCode c = maybe (show c) show (constantLit c)

||| The identity of an instance as text: its definition and its
||| compile-time arguments by their structure, a position that keys nothing
||| written `-`. Two identities are one text exactly when Idris's `==`
||| makes them one, but for the blocks, named by their place.
export
identityText : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
               Name -> List (Maybe ClosedTerm) -> Core String
identityText n args = do
  nm <- nameIdentity n
  as <- traverse (maybe (pure "-") (map ("+" ++) . termIdentity)) args
  pure (nm ++ "|" ++ show (length args) ++ ";" ++ concat as)

------------------------------------------------------------------------------
-- Identities and keys
------------------------------------------------------------------------------

||| The identity and the key of the instance of a definition at its
||| compile-time arguments (`Nothing` at a position that keys nothing). The
||| identity is the instance's symbol, its key printed (`keyText`), which
||| carries the low 64 bits of the identity's hash when the print drops
||| part of the identity: a function of this key alone, interned once, two
||| identities on one symbol being a broken invariant. Instances are
||| bucketed by a hash of their arguments, so a request compares its
||| arguments with the few instances in its bucket, not with every instance
||| of the definition; neither the comparison nor the hash sees a binder's
||| name. Only a new instance is printed, since printing is the costly part
||| and most requests are repeats.
export
instanceKey : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
              Name -> List (Maybe ClosedTerm) -> Core (String, InstanceKey)
instanceKey n args = do
  full <- toFullNames n
  args' <- traverse (traverseOpt toFullNames) args
  let base = nameKey full
  let bucket = base ++ "#" ++ show (hash args')
  let same = fromMaybe [] (lookup bucket (!(get TState)).named)
  case find ((== args') . fst) same of
    Just (_, found) => pure found
    Nothing => do
      origin <- keyOrigin full
      printed <- traverse argumentText (catMaybes args')
      print <- if any snd printed
                 then (\t => Lossy (xxh3_128 (utf8 t)).low) <$> identityText full args'
                 else pure Whole
      let key = MkInstanceKey origin (map fst printed) print
      let symbol = keyText key
      case lookup symbol (!(get TState)).symbols of
        Just (b, as) => unless (b == base && as == args') $
          internal EmptyFC ("two instances on the symbol " ++ symbol ++ ": " ++ b ++ " and " ++ base)
        Nothing => pure ()
      update TState { named $= insert bucket ((args', (symbol, key)) :: same)
                    , symbols $= insert symbol (base, args') }
      pure (symbol, key)
