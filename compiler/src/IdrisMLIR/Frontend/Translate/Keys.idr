-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| What each instance is called, and what tells two instances apart. An
||| instance is its definition and its compile-time arguments written out
||| (`write`), a symbol per node, every part Idris's `==` tells terms apart
||| by and nothing else: that link is its identity, the one the request
||| chains judge, which nothing prints. Its key is how it reads: the
||| definition's printed name, a block named by its place in the definition
||| that holds it, and the arguments printed with every binder named by its
||| depth, so that one instance prints one way whatever Idris called its
||| binders and whatever counter it numbered its blocks with. The symbol is
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
    let key = nameKey full
    defs <- get Ctxt
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
    let key = nameKey full
    defs <- get Ctxt
    let Nothing = blockOf full
      | Just _ => pure (Element w (noMore w))
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
  let key = nameKey full
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
  render d p (App _ f a) =
    let parts = spineParts d f [render d Applied a] in
    (parensIf (applied p) (joinBy " " (map fst parts)), any snd parts)
  render d _ (PrimVal _ c) = (show c, dropsWidth c)
  render d _ (Erased _ Placeholder) = ("_", False)
  render d _ (Erased _ _) = ("_", True)
  render d _ (TType _ _) = ("Type", False)
  render d p (TDelayed _ _ t) = let (s, lost) = render d Applied t in (parensIf (applied p) ("Lazy " ++ s), lost)
  render d p (TDelay _ _ _ t) = (parensIf (applied p) ("Delay " ++ fst (render d Applied t)), True)
  render d p (TForce _ _ t) = let (s, lost) = render d Applied t in (parensIf (applied p) ("Force " ++ s), lost)
  render d p (As _ _ _ pat) = (fst (render d p pat), True)

  ||| An application's head and arguments, each as an applied argument
  ||| prints, walked down the spine so that each is a subterm.
  spineParts : Nat -> TT vs -> List (String, Bool) -> List (String, Bool)
  spineParts d (App _ f a) parts = spineParts d f (render d Applied a :: parts)
  spineParts d f parts = render d Applied f :: parts

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
-- The identity: the arguments written out
------------------------------------------------------------------------------

||| A name of the context by its index, as the index's eight bytes, the low
||| byte first.
addressOf : Int -> Address
addressOf i = bytes 8 (cast i)
  where
    bytes : (k : Nat) -> Integer -> Vect k (Fin 256)
    bytes Z _ = []
    bytes (S k) v = restrict 255 v :: bytes k (v `div` 256)

||| The index an address is of.
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
glyphOf c = let k = cast {to = Integer} (ord c) in (restrict 1087 (k `div` 1024), restrict 1023 (k `mod` 1024))

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

mutual
  ||| A term in prefix order, a symbol per node: what Idris's `==` tells
  ||| terms apart by, but for doubles, which their prints tell apart (0.0
  ||| and -0.0 are two, every NaN is one); no location, no binder's name.
  ||| A name is its address in the context; a name the context does not
  ||| hold is no instance's (`unresolved`), and a request of one is refused
  ||| before it is written.
  write : Context -> TT vs -> List (Token Form)
  write ctx (Local _ _ idx _) = [Node (Shaped Variable) Nothing idx]
  write ctx (Ref _ _ n) = [Node (Shaped Reference) (addressOf <$> getNameID n ctx) 0]
  write ctx (Meta _ _ i args) = Node (Shaped Hole) (Just (addressOf i)) (length args) :: writeAll ctx args
  write ctx (Bind _ _ b sc) = writeBinder ctx b ++ write ctx sc
  write ctx (App _ f a) = node (Shaped Applied) :: (write ctx f ++ write ctx a)
  write ctx (As _ _ a p) = node (Shaped AsPattern) :: (write ctx a ++ write ctx p)
  write ctx (TDelayed _ _ t) = node (Shaped LazyType) :: write ctx t
  write ctx (TDelay _ _ t a) = node (Shaped Suspended) :: (write ctx t ++ write ctx a)
  write ctx (TForce _ _ t) = node (Shaped Forced) :: write ctx t
  write ctx (PrimVal _ c) = writeConstant c
  write ctx (Erased _ Placeholder) = [node (Shaped Placeholder)]
  write ctx (Erased _ Impossible) = [node (Shaped Impossible)]
  write ctx (Erased _ (Dotted t)) = node (Shaped Dotted) :: write ctx t
  write ctx (TType _ _) = [node (Shaped Universe)]

  writeAll : Context -> List (TT vs) -> List (Token Form)
  writeAll ctx [] = []
  writeAll ctx (t :: ts) = write ctx t ++ writeAll ctx ts

  writeBinder : Context -> TTBinder (TT vs) -> List (Token Form)
  writeBinder ctx (Lam _ q info ty) = writePassing ctx Lambda q info ++ write ctx ty
  writeBinder ctx (Let _ q v ty) = node (Bound LetIn (quantity q) ByHand) :: (write ctx v ++ write ctx ty)
  writeBinder ctx (Pi _ q info ty) = writePassing ctx PiType q info ++ write ctx ty
  writeBinder ctx (PVar _ q info ty) = writePassing ctx Pattern q info ++ write ctx ty
  writeBinder ctx (PLet _ q v ty) = node (Bound PatternLet (quantity q) ByHand) :: (write ctx v ++ write ctx ty)
  writeBinder ctx (PVTy _ q ty) = node (Bound PatternType (quantity q) ByHand) :: write ctx ty

  writePassing : Context -> Binding -> RigCount -> PiInfo (TT vs) -> List (Token Form)
  writePassing ctx b q Implicit = [node (Bound b (quantity q) ByUnification)]
  writePassing ctx b q Explicit = [node (Bound b (quantity q) ByHand)]
  writePassing ctx b q AutoImplicit = [node (Bound b (quantity q) BySearch)]
  writePassing ctx b q (DefImplicit t) = node (Bound b (quantity q) ByDefault) :: write ctx t

mutual
  ||| A name of the term that the context does not hold, if there is one.
  unresolved : Context -> TT vs -> Maybe Name
  unresolved ctx (Ref _ _ n) = maybe (Just n) (const Nothing) (getNameID n ctx)
  unresolved ctx (Meta _ _ _ args) = unresolvedAll ctx args
  unresolved ctx (Bind _ _ b sc) = unresolvedBinder ctx b <|> unresolved ctx sc
  unresolved ctx (App _ f a) = unresolved ctx f <|> unresolved ctx a
  unresolved ctx (As _ _ a p) = unresolved ctx a <|> unresolved ctx p
  unresolved ctx (TDelayed _ _ t) = unresolved ctx t
  unresolved ctx (TDelay _ _ t a) = unresolved ctx t <|> unresolved ctx a
  unresolved ctx (TForce _ _ t) = unresolved ctx t
  unresolved ctx (Erased _ (Dotted t)) = unresolved ctx t
  unresolved ctx (Local {}) = Nothing
  unresolved ctx (PrimVal {}) = Nothing
  unresolved ctx (Erased _ Placeholder) = Nothing
  unresolved ctx (Erased _ Impossible) = Nothing
  unresolved ctx (TType {}) = Nothing

  unresolvedAll : Context -> List (TT vs) -> Maybe Name
  unresolvedAll ctx [] = Nothing
  unresolvedAll ctx (t :: ts) = unresolved ctx t <|> unresolvedAll ctx ts

  unresolvedBinder : Context -> TTBinder (TT vs) -> Maybe Name
  unresolvedBinder ctx (Lam _ _ info ty) = unresolvedPassing ctx info <|> unresolved ctx ty
  unresolvedBinder ctx (Let _ _ v ty) = unresolved ctx v <|> unresolved ctx ty
  unresolvedBinder ctx (Pi _ _ info ty) = unresolvedPassing ctx info <|> unresolved ctx ty
  unresolvedBinder ctx (PVar _ _ info ty) = unresolvedPassing ctx info <|> unresolved ctx ty
  unresolvedBinder ctx (PLet _ _ v ty) = unresolved ctx v <|> unresolved ctx ty
  unresolvedBinder ctx (PVTy _ _ ty) = unresolved ctx ty

  unresolvedPassing : Context -> PiInfo (TT vs) -> Maybe Name
  unresolvedPassing ctx (DefImplicit t) = unresolved ctx t
  unresolvedPassing ctx _ = Nothing

-- Every number a written term holds is below its weight and its depth
-- together: a variable's index is below the binders around it, each of
-- which weighs at least one; a hole's argument count is below its
-- arguments' weight; a literal's magnitude is below its own weight. So an
-- argument, closed, fits its size.

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

mutual
  0 writeWeighs : (ctx : Context) -> (t : TT vs) -> LTE 1 (weighs (write ctx t))
  writeWeighs ctx (Local _ _ _ _) = LTESucc LTEZero
  writeWeighs ctx (Ref _ _ _) = LTESucc LTEZero
  writeWeighs ctx (Meta _ _ _ _) = LTESucc LTEZero
  writeWeighs ctx (Bind _ _ b sc) =
    rewrite weighsAppend (writeBinder ctx b) (write ctx sc) in
    transitive (binderWeighs ctx b) (lteAddRight (weighs (writeBinder ctx b)))
  writeWeighs ctx (App _ _ _) = LTESucc LTEZero
  writeWeighs ctx (As _ _ _ _) = LTESucc LTEZero
  writeWeighs ctx (TDelayed _ _ _) = LTESucc LTEZero
  writeWeighs ctx (TDelay _ _ _ _) = LTESucc LTEZero
  writeWeighs ctx (TForce _ _ _) = LTESucc LTEZero
  writeWeighs ctx (PrimVal _ c) = constantWeighs c
  writeWeighs ctx (Erased _ Placeholder) = LTESucc LTEZero
  writeWeighs ctx (Erased _ Impossible) = LTESucc LTEZero
  writeWeighs ctx (Erased _ (Dotted _)) = LTESucc LTEZero
  writeWeighs ctx (TType _ _) = LTESucc LTEZero

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

  0 binderWeighs : (ctx : Context) -> (b : TTBinder (TT vs)) -> LTE 1 (weighs (writeBinder ctx b))
  binderWeighs ctx (Lam _ q info ty) = passingWeighsBefore ctx Lambda q info (write ctx ty)
  binderWeighs ctx (Let _ _ _ _) = LTESucc LTEZero
  binderWeighs ctx (Pi _ q info ty) = passingWeighsBefore ctx PiType q info (write ctx ty)
  binderWeighs ctx (PVar _ q info ty) = passingWeighsBefore ctx Pattern q info (write ctx ty)
  binderWeighs ctx (PLet _ _ _ _) = LTESucc LTEZero
  binderWeighs ctx (PVTy _ _ _) = LTESucc LTEZero

  0 passingWeighsBefore : (ctx : Context) -> (b : Binding) -> (q : RigCount) -> (info : PiInfo (TT vs)) ->
                          (rest : List (Token Form)) -> LTE 1 (weighs (writePassing ctx b q info ++ rest))
  passingWeighsBefore ctx b q Implicit rest = LTESucc LTEZero
  passingWeighsBefore ctx b q Explicit rest = LTESucc LTEZero
  passingWeighsBefore ctx b q AutoImplicit rest = LTESucc LTEZero
  passingWeighsBefore ctx b q (DefImplicit _) rest = LTESucc LTEZero

0 argsWeigh : (ctx : Context) -> (ts : List (TT vs)) -> LTE (length ts) (weighs (writeAll ctx ts))
argsWeigh ctx [] = LTEZero
argsWeigh ctx (t :: ts) =
  rewrite weighsAppend (write ctx t) (writeAll ctx ts) in
  plusLteMonotone (writeWeighs ctx t) (argsWeigh ctx ts)

mutual
  0 writeFits : (ctx : Context) -> (t : TT vs) -> All (Fits (weighs (write ctx t) + length vs)) (write ctx t)
  writeFits ctx (Local _ _ idx p) = [LTESucc (lteSuccLeft (varBelow p))]
  writeFits ctx (Ref _ _ n) = [LTESucc LTEZero]
  writeFits ctx (Meta _ _ _ args) =
    LTESucc (transitive (argsWeigh ctx args) (lteAddRight (weighs (writeAll ctx args))))
      :: fittingMore (lteSuccRight reflexive) (writeAllFits ctx args)
  writeFits ctx (Bind _ _ b sc) =
    fittingUnder (writeBinder ctx b) (write ctx sc) (binderWeighs ctx b) (binderFits ctx b) (writeFits ctx sc)
  writeFits ctx (App _ f a) = headed (fittingAppend (write ctx f) (write ctx a) (writeFits ctx f) (writeFits ctx a))
  writeFits ctx (As _ _ a p) = headed (fittingAppend (write ctx a) (write ctx p) (writeFits ctx a) (writeFits ctx p))
  writeFits ctx (TDelayed _ _ t) = headed (writeFits ctx t)
  writeFits ctx (TDelay _ _ t a) = headed (fittingAppend (write ctx t) (write ctx a) (writeFits ctx t) (writeFits ctx a))
  writeFits ctx (TForce _ _ t) = headed (writeFits ctx t)
  writeFits ctx (PrimVal _ c) = constantFits c
  writeFits ctx (Erased _ Placeholder) = [LTESucc LTEZero]
  writeFits ctx (Erased _ Impossible) = [LTESucc LTEZero]
  writeFits ctx (Erased _ (Dotted t)) = headed (writeFits ctx t)
  writeFits ctx (TType _ _) = [LTESucc LTEZero]

  0 writeAllFits : (ctx : Context) -> (ts : List (TT vs)) ->
                   All (Fits (weighs (writeAll ctx ts) + length vs)) (writeAll ctx ts)
  writeAllFits ctx [] = []
  writeAllFits ctx (t :: ts) = fittingAppend (write ctx t) (writeAll ctx ts) (writeFits ctx t) (writeAllFits ctx ts)

  0 binderFits : (ctx : Context) -> (b : TTBinder (TT vs)) ->
                 All (Fits (weighs (writeBinder ctx b) + length vs)) (writeBinder ctx b)
  binderFits ctx (Lam _ q info ty) =
    fittingAppend (writePassing ctx Lambda q info) (write ctx ty) (passingFits ctx Lambda q info) (writeFits ctx ty)
  binderFits ctx (Let _ _ v ty) = headed (fittingAppend (write ctx v) (write ctx ty) (writeFits ctx v) (writeFits ctx ty))
  binderFits ctx (Pi _ q info ty) =
    fittingAppend (writePassing ctx PiType q info) (write ctx ty) (passingFits ctx PiType q info) (writeFits ctx ty)
  binderFits ctx (PVar _ q info ty) =
    fittingAppend (writePassing ctx Pattern q info) (write ctx ty) (passingFits ctx Pattern q info) (writeFits ctx ty)
  binderFits ctx (PLet _ _ v ty) = headed (fittingAppend (write ctx v) (write ctx ty) (writeFits ctx v) (writeFits ctx ty))
  binderFits ctx (PVTy _ _ ty) = headed (writeFits ctx ty)

  0 passingFits : (ctx : Context) -> (b : Binding) -> (q : RigCount) -> (info : PiInfo (TT vs)) ->
                  All (Fits (weighs (writePassing ctx b q info) + length vs)) (writePassing ctx b q info)
  passingFits ctx b q Implicit = [LTESucc LTEZero]
  passingFits ctx b q Explicit = [LTESucc LTEZero]
  passingFits ctx b q AutoImplicit = [LTESucc LTEZero]
  passingFits ctx b q (DefImplicit t) = headed (writeFits ctx t)

writtenFrom : (ts : List (Token Form)) -> (0 _ : All (Fits (weighs ts + 0)) ts) -> Written Form
writtenFrom ts fits = MkWritten (weighs ts) ts Refl (replace {p = \b => All (Fits b) ts} (plusZeroRightNeutral _) fits)

||| A compile-time argument written out: its size the weight of its
||| symbols, every number in it below that size.
writtenOf : Context -> ClosedTerm -> Written Form
writtenOf ctx t = writtenFrom (write ctx t) (writeFits ctx t)

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
keyed : {auto c : Ref Ctxt Defs} -> List (Maybe ClosedTerm) -> Core (List (String, Bool))
keyed args = traverse (maybe (pure ("-", False)) argumentText) (reverse (dropWhile isNothing (reverse args)))

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
  let Nothing = foldr (\a, rest => (a >>= unresolved (gamma defs)) <|> rest) Nothing args'
    | Just stray => internal fc ("a compile-time argument of " ++ show full ++ " names " ++ show stray ++
                                 ", which the context does not hold")
  let link = MkLink (addressOf d) (map (map (writtenOf (gamma defs))) args')
  case lookup link (!(get TState)).named of
    Just (symbol, key) => pure (MkInstance link key symbol)
    Nothing => do
      origin <- keyOrigin full
      printed <- keyed args'
      print <- if any snd printed
                 then (\t => Lossy (xxh3_128 (utf8 t)).low) <$> linkText link
                 else pure Whole
      let key = MkInstanceKey origin (map fst printed) print
      let symbol = keyText key
      case lookup symbol (!(get TState)).symbols of
        Just other => unless (other == link) $
          internal fc ("two instances on the symbol " ++ symbol)
        Nothing => pure ()
      update TState { named $= insert link (symbol, key), symbols $= insert symbol link }
      pure (MkInstance link key symbol)
