-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| What each instance is called, and what tells two instances apart. An
||| instance is its definition and its compile-time arguments written out
||| (`write`), a symbol per node, every part Idris's `==` tells terms apart
||| by and nothing else: that link is its identity, the one the request
||| chains judge, which nothing prints. Its key is how it reads: the
||| definition's printed name, a block named by its place in the definition
||| that holds it, and the arguments printed with every binder named by its
||| depth and every `Nat` literal by its value, so that one instance prints
||| one way whatever Idris called its binders and whatever counter it
||| numbered its blocks with. The symbol is
||| the key printed (`Term.keyText`), with the hash of the link's text
||| where the print drops part of the identity.
module IdrisMLIR.Frontend.Translate.Keys

import Core.Case.CaseTree
import Core.Context
import Core.Core
import Core.Env
import Core.Name.Scoped
import Core.TT
import Libraries.Data.List.Thin
import Libraries.Data.NameMap

import IdrisMLIR.Frontend.Walk
import IdrisMLIR.Frontend.Translate.Closed
import IdrisMLIR.Frontend.Translate.Errors
import IdrisMLIR.Frontend.Translate.State
import IdrisMLIR.Ids
import IdrisMLIR.Proof.Forms
import IdrisMLIR.Proof.Requests
import IdrisMLIR.Syntax.Idr
import IdrisMLIR.Types
import IdrisMLIR.Term

import Control.WellFounded
import Data.DPair
import Data.Nat
import Data.List
import Data.SnocList
import Data.SortedMap
import Data.List.Quantifiers
import Data.String
import Data.Vect

%default total

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
  termRefs acc (Meta _ n _ args) = termsRefs (acc :< AMeta n) args
  termRefs acc (Bind _ _ b sc) = termRefs (binderRefs acc b) sc
  termRefs acc (App _ f a) = termRefs (termRefs acc f) a
  termRefs acc (As _ _ _ p) = termRefs acc p
  termRefs acc (TDelayed _ _ t) = termRefs acc t
  termRefs acc (TDelay _ _ t a) = termRefs (termRefs acc t) a
  termRefs acc (TForce _ _ t) = termRefs acc t
  termRefs acc _ = acc

  termsRefs : SnocList Reference -> List (TT vs) -> SnocList Reference
  termsRefs acc [] = acc
  termsRefs acc (t :: ts) = termsRefs (termRefs acc t) ts

  binderRefs : SnocList Reference -> TTBinder (TT vs) -> SnocList Reference
  binderRefs acc (Lam _ _ _ ty) = termRefs acc ty
  binderRefs acc (Let _ _ v ty) = termRefs (termRefs acc ty) v
  binderRefs acc (Pi _ _ _ ty) = termRefs acc ty
  binderRefs acc (PVar _ _ _ ty) = termRefs acc ty
  binderRefs acc (PLet _ _ v ty) = termRefs (termRefs acc ty) v
  binderRefs acc (PVTy _ _ ty) = termRefs acc ty

mutual
  ||| The references of a case tree: its alternatives in order, each leaf's
  ||| term.
  treeRefs : SnocList Reference -> CaseTree vs -> SnocList Reference
  treeRefs acc (Case _ _ _ alts) = altsRefs acc alts
  treeRefs acc (STerm _ tm) = termRefs acc tm
  treeRefs acc _ = acc

  altsRefs : SnocList Reference -> List (CaseAlt vs) -> SnocList Reference
  altsRefs acc [] = acc
  altsRefs acc (a :: as) = altsRefs (altRefs acc a) as

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

||| Where a walk that names blocks has got to: the counters of the blocks
||| named so far under the definition being walked, and what the walk has
||| entered, no more than where it was.
record Reached (w : Walked) where
  constructor MkReached
  counters : (Nat, Nat)
  after : Walked
  0 noMore : NoMore after w

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
  ||| does refer to the block. A solved metavariable is walked through its
  ||| solution, under the same parent and counters. Each definition and
  ||| each metavariable is entered once (`Walk`), which is why the walk
  ||| ends: `w0` is where this level of it began, and every definition it
  ||| enters leaves fewer than `w0` to enter.
  nameUnder : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
              String -> (Nat, Nat) -> (w0 : Walked) -> (0 _ : SizeAccessible w0) ->
              (w : Walked) -> (0 _ : NoMore w w0) -> List Reference -> Core (Reached w)
  nameUnder origin ks w0 acc w p [] = pure (MkReached ks w (noMore w))
  nameUnder origin ks w0 acc@(Access rec) w p (AMeta m :: rest) = do
    defs <- get Ctxt
    case enter (gamma defs) m w of
      Nothing => nameUnder origin ks w0 acc w p rest
      Just (Element w1 q) => do
        MkReached ks' w2 q2 <- nameUnder origin ks w1 (rec w1 (fewerThen q p)) w1 (noMore w1) !(referencesOf m)
        MkReached ks'' w3 q3 <- nameUnder origin ks' w0 acc w2 (thenNoMore q2 (thenNoMore (fewer q) p)) rest
        pure (MkReached ks'' w3 (thenNoMore q3 (thenNoMore q2 (fewer q))))
  nameUnder origin ks w0 acc@(Access rec) w p (ARef r :: rest) = do
    full <- toFullNames r
    let (cases, withs) = ks
    let Just kind = blockOf full
      | Nothing => do
          Element w1 q1 <- blocksFrom full w0 acc w p
          MkReached ks' w2 q2 <- nameUnder origin ks w0 acc w1 (thenNoMore q1 p) rest
          pure (MkReached ks' w2 (thenNoMore q2 q1))
    defs <- get Ctxt
    -- A name the context does not hold has no address and is no block to
    -- name, as `enter` never enters it.
    let Just key = definitionAddress (gamma defs) full
      | Nothing => nameUnder origin ks w0 acc w p rest
    let Nothing = lookup key (!(get TState)).blockNames
      | Just _ => nameUnder origin ks w0 acc w p rest
    let Just (Element w1 q) = enter (gamma defs) full w
      | Nothing => nameUnder origin ks w0 acc w p rest
    let (name, ks') : (String, (Nat, Nat)) = case kind of
                        CaseB => (origin ++ ".case" ++ show cases, (S cases, withs))
                        WithB => (origin ++ ".with" ++ show withs, (cases, S withs))
                        NestedB inner => (origin ++ "." ++ inner, (cases, withs))
    update TState { blockNames $= insert key name }
    MkReached _ w2 q2 <- nameUnder name (0, 0) w1 (rec w1 (fewerThen q p)) w1 (noMore w1) !(referencesOf full)
    MkReached ks'' w3 q3 <- nameUnder origin ks' w0 acc w2 (thenNoMore q2 (thenNoMore (fewer q) p)) rest
    pure (MkReached ks'' w3 (thenNoMore q3 (thenNoMore q2 (fewer q))))

  ||| Names the blocks of a definition that is no block, once, by its full
  ||| name.
  blocksFrom : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
               Name -> (w0 : Walked) -> (0 _ : SizeAccessible w0) ->
               (w : Walked) -> (0 _ : NoMore w w0) -> Core (Subset Walked (\w' => NoMore w' w))
  blocksFrom full w0 acc@(Access rec) w p = do
    defs <- get Ctxt
    let Nothing = blockOf full
      | Just _ => pure (Element w (noMore w))
    -- Nor is a name the context does not hold a definition to walk.
    let Just key = definitionAddress (gamma defs) full
      | Nothing => pure (Element w (noMore w))
    let Nothing = lookup key (!(get TState)).blockNames
      | Just _ => pure (Element w (noMore w))
    let Just (Element w1 q) = enter (gamma defs) full w
      | Nothing => pure (Element w (noMore w))
    let origin = plainOrigin full
    update TState { blockNames $= insert key origin }
    MkReached _ w2 q2 <- nameUnder origin (0, 0) w1 (rec w1 (fewerThen q p)) w1 (noMore w1) !(referencesOf full)
    pure (Element w2 (thenNoMore q2 (fewer q)))

||| Names the blocks of a definition that is no block, once.
nameBlocksOf : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Name -> Core ()
nameBlocksOf n = ignore (blocksFrom !(toFullNames n) start (sizeAccessible start) start (noMore start))

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
  -- Naming blocks only reads the context, so this one read is the context
  -- the search below lists.
  defs <- get Ctxt
  -- A block with no address is one no definition can refer to.
  let Just key = definitionAddress (gamma defs) full
    | Nothing => unreferenced full
  Nothing <- named key
    | Just o => pure o
  st <- get TState
  case st.chain of
    r :: _ => nameBlocksOf r.name
    [] => pure ()
  Nothing <- named key
    | Just o => pure o
  nameBlocksOf !(rootOf full)
  Nothing <- named key
    | Just o => pure o
  let all = map fst (Libraries.Data.NameMap.toList (resolvedAs (gamma defs)))
  let (near, far) = partition (\c => namespaceOf c == namespaceOf full) all
  search key (near ++ far)
  Just o <- named key
    | Nothing => unreferenced full
  pure o
  where
    unreferenced : Name -> Core String
    unreferenced full = internal EmptyFC ("no definition refers to the block " ++ show full)

    named : Address -> Core (Maybe String)
    named key = pure (lookup key (!(get TState)).blockNames)

    search : Address -> List Name -> Core ()
    search key [] = pure ()
    search key (c :: cs) = do
      nameBlocksOf c
      case !(named key) of
        Just _ => pure ()
        Nothing => search key cs

------------------------------------------------------------------------------
-- What a term is read beside
------------------------------------------------------------------------------

||| What writing a term and printing it read beside it: the context, which
||| gives each name its address, and the roles of the constructors of
||| `Nat`-like types the term names (`rolesIn`), by address.
record Writer where
  constructor MkWriter
  context : Context
  roles : SortedMap Address NatRole

||| The role of the constructor a term is, if the writer knows it as a zero
||| or a successor, with its address.
roleOf : Writer -> TT vs -> Maybe (Address, NatRole)
roleOf w (Ref _ (DataCon _ _) n) = do
  a <- definitionAddress w.context n
  r <- lookup a w.roles
  pure (a, r)
roleOf w _ = Nothing

||| The successor a term is, if it is a constructor the writer knows as one.
successorOf : Writer -> TT vs -> Maybe Address
successorOf w t = case roleOf w t of
  Just (s, Succ) => Just s
  _ => Nothing

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

||| How many of the successor `s` a term is a run of down to a zero, and
||| the zero, if the run ends in one. A run is of one successor, as
||| `write`'s is, since its print names the successor once.
toZero : Writer -> Address -> TT vs -> Maybe (Nat, Name)
toZero w s t@(Ref _ _ z) = case roleOf w t of
  Just (_, Zero) => Just (0, z)
  _ => Nothing
toZero w s (App _ f a) = case successorOf w f of
  Just s' => if sameAddress s s' then (\(k, z) => (S k, z)) <$> toZero w s a else Nothing
  Nothing => Nothing
toZero w s _ = Nothing

||| A successor `f` applied to `a`, as a literal of its `Nat`-like type
||| when `a` is a run of it down to its zero: the successor named once
||| with how many of it there are in decimal, then the zero,
||| `Prelude.Types.S^1024 Prelude.Types.Z`, so that a literal's print
||| grows with its digits, not its value, and two types' literals, whose
||| successors are two names, print apart.
literalOf : Writer -> TT vs -> TT vs -> Maybe (String, Bool)
literalOf w f@(Ref _ _ s) a = do
  sa <- successorOf w f
  (k, z) <- toZero w sa a
  pure (plainOrigin s ++ "^" ++ show (S k) ++ " " ++ plainOrigin z, dropsName s || dropsName z)
literalOf w _ _ = Nothing

mutual
  ||| A term at a depth of binders: a variable by its binder's depth, a
  ||| definition by its printed full name, a literal of a `Nat`-like type
  ||| by its value (`literalOf`), an arrow whose result does not mention
  ||| its binder as `a -> b`, one whose does as `(x0 : a) -> b`, each with
  ||| Idris's quantity and braces; and whether the print dropped part of
  ||| what tells terms apart (`eqTerm`): an erased part that is not a
  ||| placeholder, a metavariable's arguments, a name printed with less, a
  ||| lambda's or a let's binder type and quantity, a binder printed
  ||| through, a default implicit printed as implicit, an integer's width,
  ||| a delay's type, an as-pattern's name.
  render : Writer -> Nat -> Place -> TT vs -> (String, Bool)
  render w d _ (Local _ _ idx _) = (binderAt (minus d (S idx)), False)
  render w d _ (Ref _ _ n) = (plainOrigin n, dropsName n)
  render w d _ (Meta _ n _ args) = ("?" ++ plainOrigin n, not (null args) || dropsName n)
  render w d p (Bind _ _ (Pi _ rig info a) sc) =
    let (t, lost) = arrow w d rig info a sc in (parensIf (notAlone p) t, lost)
  render w d p (Bind _ _ (Lam {}) sc) =
    (parensIf (notAlone p) ("\\" ++ binderAt d ++ " => " ++ fst (render w (S d) Alone sc)), True)
  render w d p (Bind _ _ (Let _ _ v _) sc) =
    (parensIf (notAlone p) ("let " ++ binderAt d ++ " = " ++ fst (render w d Alone v) ++ " in " ++
                            fst (render w (S d) Alone sc)), True)
  render w d p (Bind _ _ _ sc) = (fst (render w (S d) p sc), True)
  render w d p (App _ f a) = case literalOf w f a of
    Just (t, lost) => (parensIf (applied p) t, lost)
    Nothing =>
      let parts = spineParts w d f [render w d Applied a] in
      (parensIf (applied p) (joinBy " " (map fst parts)), any snd parts)
  render w d _ (PrimVal _ c) = (show c, dropsWidth c)
  render w d _ (Erased _ Placeholder) = ("_", False)
  render w d _ (Erased _ _) = ("_", True)
  render w d _ (TType _ _) = ("Type", False)
  render w d p (TDelayed _ _ t) = let (s, lost) = render w d Applied t in (parensIf (applied p) ("Lazy " ++ s), lost)
  render w d p (TDelay _ _ _ t) = (parensIf (applied p) ("Delay " ++ fst (render w d Applied t)), True)
  render w d p (TForce _ _ t) = let (s, lost) = render w d Applied t in (parensIf (applied p) ("Force " ++ s), lost)
  render w d p (As _ _ _ pat) = (fst (render w d p pat), True)

  ||| An application's head and arguments, each as an applied argument
  ||| prints, walked down the spine so that each is a subterm.
  spineParts : Writer -> Nat -> TT vs -> List (String, Bool) -> List (String, Bool)
  spineParts w d (App _ f a) parts = spineParts w d f (render w d Applied a :: parts)
  spineParts w d f parts = render w d Applied f :: parts

  arrow : Writer -> Nat -> RigCount -> PiInfo (TT vs) -> TT vs -> TT (x :: vs) -> (String, Bool)
  arrow w d rig info a sc =
    let dependent = isNothing (shrink sc (Drop Refl))
        alone = render w d Alone a
        asDomain = render w d Domain a
        domain = if dependent then binderAt d ++ " : " ++ fst alone else fst asDomain
        lostA = if dependent then snd alone else snd asDomain
        inner = quantityPrefix rig ++ domain
        rest = render w (S d) Alone sc
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
argumentText : {auto c : Ref Ctxt Defs} -> Writer -> ClosedTerm -> Core (String, Bool)
argumentText w tm = pure (render w 0 Alone !(toFullNames tm))

------------------------------------------------------------------------------
-- The identity: the arguments written out
------------------------------------------------------------------------------

||| The index an address is of (`State.addressOf`'s inverse).
indexOf : Address -> Integer
indexOf = foldr (\b, rest => cast (finToNat b) + 256 * rest) 0

||| A quantity by its number: 0, 1, many.
quantity : RigCount -> Fin 3
quantity q = if isErased q then 0 else if isLinear q then 1 else 2

||| A primitive type by its number.
primitive : PrimType -> Fin 14
primitive IntType = 0
primitive Int8Type = 1
primitive Int16Type = 2
primitive Int32Type = 3
primitive Int64Type = 4
primitive IntegerType = 5
primitive Bits8Type = 6
primitive Bits16Type = 7
primitive Bits32Type = 8
primitive Bits64Type = 9
primitive StringType = 10
primitive CharType = 11
primitive DoubleType = 12
primitive WorldType = 13

node : Form -> Token Form
node f = Node f Nothing 0

glyphOf : Char -> Glyph
glyphOf c = let k = cast {to = Integer} (ord c) in (lowBits 11 (k `div` 1024), lowBits 10 k)

spellChars : List Char -> List (Token Form)
spellChars [] = []
spellChars (c :: cs) = node (Spelt (glyphOf c)) :: spellChars cs

spell : String -> List (Token Form)
spell s = spellChars (unpack s)

integer : PrimType -> Integer -> List (Token Form)
integer t v = [Number (IntegerLit (primitive t) (v < 0)) (integerToNat (abs v))]

||| A constant: an integer by its type, sign and magnitude, a string and a
||| double by their characters (a double's print tells doubles apart), a
||| character, a primitive type, the world.
writeConstant : Constant -> List (Token Form)
writeConstant (I x) = integer IntType (cast x)
writeConstant (I8 x) = integer Int8Type (cast x)
writeConstant (I16 x) = integer Int16Type (cast x)
writeConstant (I32 x) = integer Int32Type (cast x)
writeConstant (I64 x) = integer Int64Type (cast x)
writeConstant (BI x) = integer IntegerType x
writeConstant (B8 x) = integer Bits8Type (cast x)
writeConstant (B16 x) = integer Bits16Type (cast x)
writeConstant (B32 x) = integer Bits32Type (cast x)
writeConstant (B64 x) = integer Bits64Type (cast x)
writeConstant (Str x) = node (Shaped Text) :: spell x
writeConstant (Ch x) = [node (Character (glyphOf x))]
writeConstant (Db x) = node (Shaped Floating) :: spell (show x)
writeConstant (PrT t) = [node (PrimitiveType (primitive t))]
writeConstant WorldVal = [node (Shaped World)]

||| A reference by what its name is (`markerOf`): a marker of a runtime
||| value an implementation closes over by its number, whose magnitude
||| weighs itself as a literal's does, and any other name by its address.
referenceTo : Context -> Name -> Maybe Nat -> List (Token Form)
referenceTo ctx n (Just i) = [Number (Shaped Marker) i]
referenceTo ctx n Nothing = [Node (Shaped Reference) (definitionAddress ctx n) 0]

||| A run of one successor before a written term: the successor's node,
||| and a magnitude, which for a run of one is 0.
runOfOne : Address -> List (Token Form) -> List (Token Form)
runOfOne s ts = Node (Shaped Successors) (Just s) 0 :: Number (Shaped Successors) 0 :: ts

||| Do two symbols start a run of the successor?
runOf : Address -> Token Form -> Form -> Bool
runOf s (Node (Shaped Successors) (Just s') _) (Shaped Successors) = sameAddress s s'
runOf _ _ _ = False

||| A run one successor longer, if the symbols start a run of it; a run of
||| one before them, if not.
lengthened : (starts : Bool) -> Address -> Token Form -> Form -> Nat -> List (Token Form) -> List (Token Form)
lengthened True s t g m rest = t :: Number g (S (S m)) :: rest
lengthened False s t g m rest = runOfOne s (t :: Number g m :: rest)

||| A successor applied to a term written: the run the term starts with,
||| if it is one of the same successor, one longer; else a run of one. A
||| run of `n` weighs `2n`, as the `n` applications and references of the
||| successor it stands for do, so an argument weighs what it weighed
||| spelt out, and a run is two symbols however long it is.
succeeding : Address -> List (Token Form) -> List (Token Form)
succeeding s (t :: Number g m :: rest) = lengthened (runOf s t g) s t g m rest
succeeding s ts = runOfOne s ts

mutual
  ||| A term in prefix order, a symbol per node: what Idris's `==` tells
  ||| terms apart by, but for doubles, which their prints tell apart (0.0
  ||| and -0.0 are two, every NaN is one); no location, no binder's name.
  ||| A name is its address in the context, a marker its number; a name
  ||| the context does not hold is no instance's (`unresolved`), and a
  ||| request of one stops before it is written. A run of a `Nat`-like
  ||| type's successor, a literal's above all (`Fin 1024`), is two symbols.
  write : Writer -> TT vs -> List (Token Form)
  write w (Local _ _ idx _) = [Node (Shaped Variable) Nothing idx]
  write w (Ref _ _ n) = referenceTo w.context n (markerOf n)
  write w (Meta _ _ i args) = Node (Shaped Hole) (Just (addressOf i)) (length args) :: writeAll w args
  write w (Bind _ _ b sc) = writeBinder w b ++ write w sc
  write w (App _ f a) = writeApplication w (successorOf w f) f a
  write w (As _ _ a p) = node (Shaped AsPattern) :: (write w a ++ write w p)
  write w (TDelayed _ _ t) = node (Shaped LazyType) :: write w t
  write w (TDelay _ _ t a) = node (Shaped Suspended) :: (write w t ++ write w a)
  write w (TForce _ _ t) = node (Shaped Forced) :: write w t
  write w (PrimVal _ c) = writeConstant c
  write w (Erased _ Placeholder) = [node (Shaped Placeholder)]
  write w (Erased _ Impossible) = [node (Shaped Impossible)]
  write w (Erased _ (Dotted t)) = node (Shaped Dotted) :: write w t
  write w (TType _ _) = [node (Shaped Universe)]

  ||| An application, by its function: a successor, which runs with what
  ||| it is applied to, or any other.
  writeApplication : Writer -> Maybe Address -> TT vs -> TT vs -> List (Token Form)
  writeApplication w (Just s) f a = succeeding s (write w a)
  writeApplication w Nothing f a = node (Shaped Applied) :: (write w f ++ write w a)

  writeAll : Writer -> List (TT vs) -> List (Token Form)
  writeAll w [] = []
  writeAll w (t :: ts) = write w t ++ writeAll w ts

  writeBinder : Writer -> TTBinder (TT vs) -> List (Token Form)
  writeBinder w (Lam _ q info ty) = writePassing w Lambda q info ++ write w ty
  writeBinder w (Let _ q v ty) = node (Bound LetIn (quantity q) ByHand) :: (write w v ++ write w ty)
  writeBinder w (Pi _ q info ty) = writePassing w PiType q info ++ write w ty
  writeBinder w (PVar _ q info ty) = writePassing w Pattern q info ++ write w ty
  writeBinder w (PLet _ q v ty) = node (Bound PatternLet (quantity q) ByHand) :: (write w v ++ write w ty)
  writeBinder w (PVTy _ q ty) = node (Bound PatternType (quantity q) ByHand) :: write w ty

  writePassing : Writer -> Binding -> RigCount -> PiInfo (TT vs) -> List (Token Form)
  writePassing w b q Implicit = [node (Bound b (quantity q) ByUnification)]
  writePassing w b q Explicit = [node (Bound b (quantity q) ByHand)]
  writePassing w b q AutoImplicit = [node (Bound b (quantity q) BySearch)]
  writePassing w b q (DefImplicit t) = node (Bound b (quantity q) ByDefault) :: write w t

mutual
  ||| The references of a term `write` writes by address, with their
  ||| kinds, in the order it writes them, before `acc`: every reference
  ||| but the frontend's own markers.
  namesOf : TT vs -> List (NameType, Name) -> List (NameType, Name)
  namesOf (Ref _ nt n) acc = maybe ((nt, n) :: acc) (const acc) (markerOf n)
  namesOf (Meta _ _ _ args) acc = namesOfAll args acc
  namesOf (Bind _ _ b sc) acc = namesOfBinder b (namesOf sc acc)
  namesOf (App _ f a) acc = namesOf f (namesOf a acc)
  namesOf (As _ _ a p) acc = namesOf a (namesOf p acc)
  namesOf (TDelayed _ _ t) acc = namesOf t acc
  namesOf (TDelay _ _ t a) acc = namesOf t (namesOf a acc)
  namesOf (TForce _ _ t) acc = namesOf t acc
  namesOf (Erased _ (Dotted t)) acc = namesOf t acc
  namesOf (Local {}) acc = acc
  namesOf (PrimVal {}) acc = acc
  namesOf (Erased _ Placeholder) acc = acc
  namesOf (Erased _ Impossible) acc = acc
  namesOf (TType {}) acc = acc

  namesOfAll : List (TT vs) -> List (NameType, Name) -> List (NameType, Name)
  namesOfAll [] acc = acc
  namesOfAll (t :: ts) acc = namesOf t (namesOfAll ts acc)

  namesOfBinder : TTBinder (TT vs) -> List (NameType, Name) -> List (NameType, Name)
  namesOfBinder (Lam _ _ info ty) acc = namesOfPassing info (namesOf ty acc)
  namesOfBinder (Let _ _ v ty) acc = namesOf v (namesOf ty acc)
  namesOfBinder (Pi _ _ info ty) acc = namesOfPassing info (namesOf ty acc)
  namesOfBinder (PVar _ _ info ty) acc = namesOfPassing info (namesOf ty acc)
  namesOfBinder (PLet _ _ v ty) acc = namesOf v (namesOf ty acc)
  namesOfBinder (PVTy _ _ ty) acc = namesOf ty acc

  namesOfPassing : PiInfo (TT vs) -> List (NameType, Name) -> List (NameType, Name)
  namesOfPassing (DefImplicit t) acc = namesOf t acc
  namesOfPassing _ acc = acc

||| A name of the term that the context does not hold, if there is one.
unresolved : Context -> TT vs -> Maybe Name
unresolved ctx t = snd <$> find (\(_, n) => isNothing (definitionAddress ctx n)) (namesOf t [])

||| The zeros and successors of `Nat`-like types the terms name, by address:
||| the constructors of no argument and of one that Idris flags as such
||| (`natRole`, its metadata, never a name), whose runs `write` writes and
||| whose literals the key prints.
rolesIn : {auto c : Ref Ctxt Defs} -> List ClosedTerm -> Core (SortedMap Address NatRole)
rolesIn tms = do
  defs <- get Ctxt
  let candidates = SortedMap.fromList (mapMaybe (candidate (gamma defs)) (foldr namesOf [] tms))
  found <- traverse (role defs) (SortedMap.toList candidates)
  pure (SortedMap.fromList (catMaybes found))
  where
    -- A constructor by its address, with the role its arity admits: a zero
    -- takes no argument, a successor one.
    candidate : Context -> (NameType, Name) -> Maybe (Address, (Name, NatRole))
    candidate ctx (DataCon _ 0, n) = (\a => (a, (n, Zero))) <$> definitionAddress ctx n
    candidate ctx (DataCon _ 1, n) = (\a => (a, (n, Succ))) <$> definitionAddress ctx n
    candidate ctx _ = Nothing

    role : Defs -> (Address, (Name, NatRole)) -> Core (Maybe (Address, NatRole))
    role defs (a, (n, admitted)) = do
      Just def <- lookupCtxtExact n (gamma defs)
        | Nothing => pure Nothing
      pure (case (natRole def, admitted) of
              (Just Zero, Zero) => Just (a, Zero)
              (Just Succ, Succ) => Just (a, Succ)
              _ => Nothing)

-- Every number a written term holds is below its weight and its depth
-- together: a variable's index is below the binders around it, each of
-- which weighs at least one; a hole's argument count is below its
-- arguments' weight; a literal's magnitude is below its own weight, and a
-- run's below the run's. So an argument, closed, fits its size.

0 varBelow : IsVar n idx vs -> LT idx (length vs)
varBelow First = LTESucc LTEZero
varBelow (Later p) = LTESucc (varBelow p)

0 spellFits : (cs : List Char) -> All (Fits (S s)) (spellChars cs)
spellFits [] = []
spellFits (c :: cs) = LTESucc LTEZero :: spellFits cs

0 selfBelow : (m, d : Nat) -> LTE m ((m + 0) + d)
selfBelow m d = rewrite plusZeroRightNeutral m in lteAddRight m

0 constantFits : (c : Constant) -> All (Fits (weighs (writeConstant c) + d)) (writeConstant c)
constantFits (I x) = [LTESucc (selfBelow _ _)]
constantFits (I8 x) = [LTESucc (selfBelow _ _)]
constantFits (I16 x) = [LTESucc (selfBelow _ _)]
constantFits (I32 x) = [LTESucc (selfBelow _ _)]
constantFits (I64 x) = [LTESucc (selfBelow _ _)]
constantFits (BI x) = [LTESucc (selfBelow _ _)]
constantFits (B8 x) = [LTESucc (selfBelow _ _)]
constantFits (B16 x) = [LTESucc (selfBelow _ _)]
constantFits (B32 x) = [LTESucc (selfBelow _ _)]
constantFits (B64 x) = [LTESucc (selfBelow _ _)]
constantFits (Str x) = LTESucc LTEZero :: spellFits (unpack x)
constantFits (Ch x) = [LTESucc LTEZero]
constantFits (Db x) = LTESucc LTEZero :: spellFits (unpack (show x))
constantFits (PrT t) = [LTESucc LTEZero]
constantFits WorldVal = [LTESucc LTEZero]

0 headed : All (Fits (weighs ts + d)) ts -> All (Fits (S (weighs ts + d))) (node f :: ts)
headed fs = LTESucc LTEZero :: fittingMore (lteSuccRight reflexive) fs

0 referenceWeighs : (ctx : Context) -> (n : Name) -> (m : Maybe Nat) -> LTE 1 (weighs (referenceTo ctx n m))
referenceWeighs ctx n (Just _) = LTESucc LTEZero
referenceWeighs ctx n Nothing = LTESucc LTEZero

0 referenceFits : (ctx : Context) -> (n : Name) -> (m : Maybe Nat) ->
                  All (Fits (weighs (referenceTo ctx n m) + d)) (referenceTo ctx n m)
referenceFits ctx n (Just i) = [LTESucc (selfBelow _ _)]
referenceFits ctx n Nothing = [LTESucc LTEZero]

-- A run of one weighs two more than what follows it, and its numbers are
-- 0.
0 oneFits : (s : Address) -> (ts : List (Token Form)) -> All (Fits (weighs ts + d)) ts ->
            All (Fits (weighs (runOfOne s ts) + d)) (runOfOne s ts)
oneFits s ts fs = LTESucc LTEZero :: LTESucc LTEZero :: fittingMore (lteSuccRight (lteSuccRight reflexive)) fs

0 twoMore : (a, b : Nat) -> a + S (S b) = S (S (a + b))
twoMore a b = rewrite sym (plusSuccRightSucc a (S b)) in rewrite sym (plusSuccRightSucc a b) in Refl

-- A run one longer weighs two more, and its magnitude is two more.
0 lengthenedFits : (starts : Bool) -> (s : Address) -> (t : Token Form) -> (g : Form) -> (m : Nat) ->
                   (rest : List (Token Form)) -> All (Fits (weighs (t :: Number g m :: rest) + d)) (t :: Number g m :: rest) ->
                   All (Fits (weighs (lengthened starts s t g m rest) + d)) (lengthened starts s t g m rest)
lengthenedFits False s t g m rest fs = oneFits s (t :: Number g m :: rest) fs
lengthenedFits True s t g m rest (ft :: fm :: frest) =
  rewrite twoMore (weight t) (S (m + weighs rest)) in
  let (ft' :: frest') = fittingMore (lteSuccRight (lteSuccRight reflexive)) (the (All _ (t :: rest)) (ft :: frest)) in
  ft' :: LTESucc (LTESucc fm) :: frest'

0 succeedingFits : (s : Address) -> (ts : List (Token Form)) -> All (Fits (weighs ts + d)) ts ->
                   All (Fits (weighs (succeeding s ts) + d)) (succeeding s ts)
succeedingFits s [] fs = oneFits s [] fs
succeedingFits s [t] fs = oneFits s [t] fs
succeedingFits s (t :: Node f k n :: rest) fs = oneFits s (t :: Node f k n :: rest) fs
succeedingFits s (t :: Number g m :: rest) fs = lengthenedFits (runOf s t g) s t g m rest fs

0 succeedingWeighs : (s : Address) -> (ts : List (Token Form)) -> LTE 1 (weighs (succeeding s ts))
succeedingWeighs s [] = LTESucc LTEZero
succeedingWeighs s [t] = LTESucc LTEZero
succeedingWeighs s (t :: Node f k n :: rest) = LTESucc LTEZero
succeedingWeighs s (t :: Number g m :: rest) = lengthenedWeighs (runOf s t g) t
  where
    lengthenedWeighs : (starts : Bool) -> (t : Token Form) -> LTE 1 (weighs (lengthened starts s t g m rest))
    lengthenedWeighs False t = LTESucc LTEZero
    lengthenedWeighs True (Node _ _ _) = LTESucc LTEZero
    lengthenedWeighs True (Number _ _) = LTESucc LTEZero

0 appliedWeighs : (w : Writer) -> (m : Maybe Address) -> (f, a : TT vs) -> LTE 1 (weighs (writeApplication w m f a))
appliedWeighs w (Just s) f a = succeedingWeighs s (write w a)
appliedWeighs w Nothing f a = LTESucc LTEZero

mutual
  0 writeWeighs : (w : Writer) -> (t : TT vs) -> LTE 1 (weighs (write w t))
  writeWeighs w (Local _ _ _ _) = LTESucc LTEZero
  writeWeighs w (Ref _ _ n) = referenceWeighs w.context n (markerOf n)
  writeWeighs w (Meta _ _ _ _) = LTESucc LTEZero
  writeWeighs w (Bind _ _ b sc) =
    rewrite weighsAppend (writeBinder w b) (write w sc) in
    transitive (binderWeighs w b) (lteAddRight (weighs (writeBinder w b)))
  writeWeighs w (App _ f a) = appliedWeighs w (successorOf w f) f a
  writeWeighs w (As _ _ _ _) = LTESucc LTEZero
  writeWeighs w (TDelayed _ _ _) = LTESucc LTEZero
  writeWeighs w (TDelay _ _ _ _) = LTESucc LTEZero
  writeWeighs w (TForce _ _ _) = LTESucc LTEZero
  writeWeighs w (PrimVal _ c) = constantWeighs c
  writeWeighs w (Erased _ Placeholder) = LTESucc LTEZero
  writeWeighs w (Erased _ Impossible) = LTESucc LTEZero
  writeWeighs w (Erased _ (Dotted _)) = LTESucc LTEZero
  writeWeighs w (TType _ _) = LTESucc LTEZero

  0 constantWeighs : (c : Constant) -> LTE 1 (weighs (writeConstant c))
  constantWeighs (I _) = LTESucc LTEZero
  constantWeighs (I8 _) = LTESucc LTEZero
  constantWeighs (I16 _) = LTESucc LTEZero
  constantWeighs (I32 _) = LTESucc LTEZero
  constantWeighs (I64 _) = LTESucc LTEZero
  constantWeighs (BI _) = LTESucc LTEZero
  constantWeighs (B8 _) = LTESucc LTEZero
  constantWeighs (B16 _) = LTESucc LTEZero
  constantWeighs (B32 _) = LTESucc LTEZero
  constantWeighs (B64 _) = LTESucc LTEZero
  constantWeighs (Str _) = LTESucc LTEZero
  constantWeighs (Ch _) = LTESucc LTEZero
  constantWeighs (Db _) = LTESucc LTEZero
  constantWeighs (PrT _) = LTESucc LTEZero
  constantWeighs WorldVal = LTESucc LTEZero

  0 binderWeighs : (w : Writer) -> (b : TTBinder (TT vs)) -> LTE 1 (weighs (writeBinder w b))
  binderWeighs w (Lam _ q info ty) = passingWeighsBefore w Lambda q info (write w ty)
  binderWeighs w (Let _ _ _ _) = LTESucc LTEZero
  binderWeighs w (Pi _ q info ty) = passingWeighsBefore w PiType q info (write w ty)
  binderWeighs w (PVar _ q info ty) = passingWeighsBefore w Pattern q info (write w ty)
  binderWeighs w (PLet _ _ _ _) = LTESucc LTEZero
  binderWeighs w (PVTy _ _ _) = LTESucc LTEZero

  0 passingWeighsBefore : (w : Writer) -> (b : Binding) -> (q : RigCount) -> (info : PiInfo (TT vs)) ->
                          (rest : List (Token Form)) -> LTE 1 (weighs (writePassing w b q info ++ rest))
  passingWeighsBefore w b q Implicit rest = LTESucc LTEZero
  passingWeighsBefore w b q Explicit rest = LTESucc LTEZero
  passingWeighsBefore w b q AutoImplicit rest = LTESucc LTEZero
  passingWeighsBefore w b q (DefImplicit _) rest = LTESucc LTEZero

0 argsWeigh : (w : Writer) -> (ts : List (TT vs)) -> LTE (length ts) (weighs (writeAll w ts))
argsWeigh w [] = LTEZero
argsWeigh w (t :: ts) =
  rewrite weighsAppend (write w t) (writeAll w ts) in
  plusLteMonotone (writeWeighs w t) (argsWeigh w ts)

mutual
  0 writeFits : (w : Writer) -> (t : TT vs) -> All (Fits (weighs (write w t) + length vs)) (write w t)
  writeFits w (Local _ _ idx p) = [LTESucc (lteSuccLeft (varBelow p))]
  writeFits w (Ref _ _ n) = referenceFits w.context n (markerOf n)
  writeFits w (Meta _ _ _ args) =
    LTESucc (transitive (argsWeigh w args) (lteAddRight (weighs (writeAll w args))))
      :: fittingMore (lteSuccRight reflexive) (writeAllFits w args)
  writeFits w (Bind _ _ b sc) =
    fittingUnder (writeBinder w b) (write w sc) (binderWeighs w b) (binderFits w b) (writeFits w sc)
  writeFits w (App _ f a) = appliedFits w (successorOf w f) f a
  writeFits w (As _ _ a p) = headed (fittingAppend (write w a) (write w p) (writeFits w a) (writeFits w p))
  writeFits w (TDelayed _ _ t) = headed (writeFits w t)
  writeFits w (TDelay _ _ t a) = headed (fittingAppend (write w t) (write w a) (writeFits w t) (writeFits w a))
  writeFits w (TForce _ _ t) = headed (writeFits w t)
  writeFits w (PrimVal _ c) = constantFits c
  writeFits w (Erased _ Placeholder) = [LTESucc LTEZero]
  writeFits w (Erased _ Impossible) = [LTESucc LTEZero]
  writeFits w (Erased _ (Dotted t)) = headed (writeFits w t)
  writeFits w (TType _ _) = [LTESucc LTEZero]

  0 appliedFits : (w : Writer) -> (m : Maybe Address) -> (f, a : TT vs) ->
                  All (Fits (weighs (writeApplication w m f a) + length vs)) (writeApplication w m f a)
  appliedFits w (Just s) f a = succeedingFits s (write w a) (writeFits w a)
  appliedFits w Nothing f a = headed (fittingAppend (write w f) (write w a) (writeFits w f) (writeFits w a))

  0 writeAllFits : (w : Writer) -> (ts : List (TT vs)) ->
                   All (Fits (weighs (writeAll w ts) + length vs)) (writeAll w ts)
  writeAllFits w [] = []
  writeAllFits w (t :: ts) = fittingAppend (write w t) (writeAll w ts) (writeFits w t) (writeAllFits w ts)

  0 binderFits : (w : Writer) -> (b : TTBinder (TT vs)) ->
                 All (Fits (weighs (writeBinder w b) + length vs)) (writeBinder w b)
  binderFits w (Lam _ q info ty) =
    fittingAppend (writePassing w Lambda q info) (write w ty) (passingFits w Lambda q info) (writeFits w ty)
  binderFits w (Let _ _ v ty) = headed (fittingAppend (write w v) (write w ty) (writeFits w v) (writeFits w ty))
  binderFits w (Pi _ q info ty) =
    fittingAppend (writePassing w PiType q info) (write w ty) (passingFits w PiType q info) (writeFits w ty)
  binderFits w (PVar _ q info ty) =
    fittingAppend (writePassing w Pattern q info) (write w ty) (passingFits w Pattern q info) (writeFits w ty)
  binderFits w (PLet _ _ v ty) = headed (fittingAppend (write w v) (write w ty) (writeFits w v) (writeFits w ty))
  binderFits w (PVTy _ _ ty) = headed (writeFits w ty)

  0 passingFits : (w : Writer) -> (b : Binding) -> (q : RigCount) -> (info : PiInfo (TT vs)) ->
                  All (Fits (weighs (writePassing w b q info) + length vs)) (writePassing w b q info)
  passingFits w b q Implicit = [LTESucc LTEZero]
  passingFits w b q Explicit = [LTESucc LTEZero]
  passingFits w b q AutoImplicit = [LTESucc LTEZero]
  passingFits w b q (DefImplicit t) = headed (writeFits w t)

writtenFrom : (ts : List (Token Form)) -> (0 _ : All (Fits (weighs ts + 0)) ts) -> Written Form
writtenFrom ts fits = MkWritten (weighs ts) ts Refl (replace {p = \b => All (Fits b) ts} (plusZeroRightNeutral _) fits)

||| A compile-time argument written out: its size the weight of its
||| symbols, every number in it below that size.
writtenOf : Writer -> ClosedTerm -> Written Form
writtenOf w t = writtenFrom (write w t) (writeFits w t)

------------------------------------------------------------------------------
-- The identity as text
------------------------------------------------------------------------------

||| A string with its length before it, so that no encoding is a prefix of
||| another.
counted : String -> String
counted s = show (length s) ++ ":" ++ s

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

||| A name of the context by its address, as it reads in every build.
addressIdentity : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Address -> Core String
addressIdentity a = nameIdentity !(toFullNames (Resolved (cast (indexOf a))))

||| An instance's identity as text that reads the same in every build, for
||| the hash a symbol carries when its key's print drops part of the
||| identity: the link, each name by its full name, each block by its
||| place.
linkText : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Link Form -> Core String
linkText (MkLink d as) = do
  dn <- addressIdentity d
  args <- traverse argumentText' as
  pure (dn ++ "|" ++ show (length as) ++ ";" ++ concat args)
  where
    symbolText : Token Form -> Core String
    symbolText (Node f m k) = do
      nm <- maybe (pure "") (map ("@" ++) . addressIdentity) m
      pure ("N" ++ formText f ++ nm ++ ":" ++ show k ++ ";")
    symbolText (Number f m) = pure ("#" ++ formText f ++ ":" ++ show m ++ ";")

    argumentText' : Maybe (Written Form) -> Core String
    argumentText' Nothing = pure "-"
    argumentText' (Just w) = ("+" ++) . concat <$> traverse symbolText w.symbols

------------------------------------------------------------------------------
-- Identities and keys
------------------------------------------------------------------------------

||| The positions a key prints, a position that keys nothing as `-`, which
||| no compile-time value prints as: every position up to the last that
||| keys the instance. The definition fixes how many positions it has, so
||| the ones after the last that keys tell no two instances apart, and a
||| definition that keys nothing prints none.
keyed : {auto c : Ref Ctxt Defs} -> Writer -> List (Maybe ClosedTerm) -> Core (List (String, Bool))
keyed w args = traverse (maybe (pure ("-", False)) (argumentText w)) (reverse (dropWhile isNothing (reverse args)))

||| An instance as a request finds or makes it: its identity, which is its
||| link (the definition's address and the compile-time arguments written
||| out); its key; and its symbol, the key printed.
public export
record Instance where
  constructor MkInstance
  link : Link Form
  key : InstanceKey
  symbol : String

||| The instance of a definition at its compile-time arguments (`Nothing` at
||| a position that keys nothing). Two requests are one instance exactly
||| when their links are equal: the map of instances is keyed by the link,
||| and a request of an instance already made finds it there without
||| printing anything. A new one is printed: its key, and its symbol, which
||| carries the low 64 bits of the hash of the link's text when the print
||| drops part of the identity, a function of the key alone, two links on
||| one symbol being a broken invariant. The definition is the one the
||| request names, missing from the context as a lookup of it is.
export
instanceKey : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
              FC -> String -> Name -> List (Maybe ClosedTerm) -> Core Instance
instanceKey fc owner n args = do
  full <- toFullNames n
  args' <- traverse (traverseOpt toFullNames) args
  defs <- get Ctxt
  let Just d = getNameID full (gamma defs)
    | Nothing => reject fc owner CompiledModule ("missing definition " ++ show full)
  -- A broken invariant: a compile-time argument is checked TT, every name
  -- of which the context holds, but the frontend's own markers, which are
  -- written by their numbers (`markerOf`).
  let Nothing = foldr (\a, rest => (a >>= unresolved (gamma defs)) <|> rest) Nothing args'
    | Just stray => internal fc ("a compile-time argument of " ++ show full ++ " names " ++ show stray ++
                                 ", which the context does not hold")
  writer <- MkWriter (gamma defs) <$> rolesIn (catMaybes args')
  let link = MkLink (addressOf d) (map (map (writtenOf writer)) args')
  case lookup link (!(get TState)).named of
    Just (symbol, key) => pure (MkInstance link key symbol)
    Nothing => do
      origin <- keyOrigin full
      printed <- keyed writer args'
      print <- if any snd printed
                 then (\t => Lossy (xxh3_128 (utf8 t)).low) <$> linkText link
                 else pure Whole
      let key = MkInstanceKey origin (map fst printed) print
      let symbol = keyText key
      -- A broken invariant: the key prints the link whole, or carries 64
      -- bits of the hash of its text where it does not, so two links on
      -- one symbol are a print that drops what it claims to keep, or a
      -- collision of those bits. The symbol, not the link, is what reaches
      -- MLIR, so this is checked on the symbol.
      case lookup symbol (!(get TState)).symbols of
        Just other => unless (other == link) $
          internal fc ("two instances on the symbol " ++ symbol)
        Nothing => pure ()
      update TState { named $= insert link (symbol, key), symbols $= insert symbol link }
      pure (MkInstance link key symbol)
