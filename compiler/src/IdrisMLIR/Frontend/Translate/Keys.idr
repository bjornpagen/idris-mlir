-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| What each instance is called, and what tells two instances apart. An
||| instance is its definition and its compile-time arguments written out
||| (`write`), a symbol per node, every part Idris's `==` tells terms apart
||| by but a lambda's domain, which the place the lambda stands at fixes,
||| and nothing else: that link is its identity, which nothing prints.
||| Its key is how it reads: the
||| definition's printed name, a block named by its place in the definition
||| that holds it, and the arguments printed with every binder named by its
||| depth and every `Nat` literal by its value, so that one instance prints
||| one way whatever Idris called its binders and whatever counter it
||| numbered its blocks with. The symbol is
||| the key printed (`Term.keyText`), with the hash of the link's text
||| where the print drops part of the identity.
module IdrisMLIR.Frontend.Translate.Keys

import Algebra
import Core.Case.CaseTree
import Core.Context
import Core.Core
import Core.Name.Scoped
import Core.TT
import Libraries.Data.List.Thin
import Hash.XXH3
import Idris.Host

import IdrisMLIR.Frontend.Resolve
import IdrisMLIR.Frontend.Walk
import IdrisMLIR.Frontend.Translate.Boundary
import IdrisMLIR.Frontend.Translate.Closed
import IdrisMLIR.Frontend.Translate.Definitions
import IdrisMLIR.Frontend.Translate.Errors
import IdrisMLIR.Frontend.Translate.Literals
import IdrisMLIR.Frontend.Translate.Readings
import IdrisMLIR.Frontend.Translate.State
import IdrisMLIR.Ids
import IdrisMLIR.Proof.Forms
import IdrisMLIR.Proof.Requests
import IdrisMLIR.Proof.Sizes
import IdrisMLIR.Spec.Core.Rules
import IdrisMLIR.Spec.Core.Text
import IdrisMLIR.Spec.Grades.Grade
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

-- The evaluator names a term's spine as this module names a link's head
-- and an argument's place; here each name is the frontend's.
%hide Idris.Host.Head
%hide Idris.Host.Applied

------------------------------------------------------------------------------
-- Names
------------------------------------------------------------------------------

||| A case or with block's printed name: its parent's, then `.case<k>` or
||| `.with<k>`, its ordinal under that parent; nothing for any other name.
||| Its parent is a full name Idris keeps, and may be a block itself.
typedBlock : Name -> Maybe String
typedBlock (NS _ n) = typedBlock n
typedBlock (CaseBlock parent k) = Just (fromMaybe (plainOrigin parent) (typedBlock parent) ++ ".case" ++ show k)
typedBlock (WithBlock parent k) = Just (fromMaybe (plainOrigin parent) (typedBlock parent) ++ ".with" ++ show k)
typedBlock _ = Nothing

||| The definition's printed name, which a key starts with: Idris's full
||| name (`plainOrigin`), and for a case, with or nested block its
||| parent's, then `.case<k>`, `.with<k>` or `.<name><k>`. A case or with
||| block's is read off its name, which Idris keeps; a nested block's was
||| found where the program was read, from what `main` reaches
||| (`Read.blockNames`). The translation meets only blocks read from what
||| `main` reaches, each because a definition read refers to it, so a block
||| with no name is the compiler's error.
keyOrigin : Name -> Front String
keyOrigin n = do
  full <- fullName n
  -- A case or with block names its parent and its ordinal under it, which
  -- Idris keeps: its name is read off it, with no search.
  let Nothing = typedBlock full
    | Just o => pure o
  let Just _ = blockOf full
    | Nothing => pure (plainOrigin full)
  -- A block no definition has is one no definition can refer to.
  Just d <- defined full
    | Nothing => unreferenced full
  let Just o = lookup (addressOf d.placement) (!reading).blockNames
    | Nothing => unreferenced full
  pure o
  where
    unreferenced : Name -> Front String
    unreferenced full = internal EmptyFC ("no definition read from what main reaches refers to the block " ++ show full)

------------------------------------------------------------------------------
-- What a term is read beside
------------------------------------------------------------------------------

||| What writing a term and printing it read beside it: the context, which
||| gives each name its address, and the roles of the constructors of
||| `Nat`-like types the term names (`rolesIn`), by address.
public export
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

||| How many of a successor a term is a run of down to its zero, the zero,
||| and the run.
record Down {0 vs : Scope} (t : TT vs) where
  constructor MkDown
  count : Nat
  zero : Name
  0 run : Run t count

||| How many of the successor `s` a term is a run of down to a zero, and
||| the zero, if the run ends in one. A run is of one successor, as
||| `write`'s is, since its print names the successor once. Only a data
||| constructor has a role (`roleOf`), so only one is a step of a run.
toZero : Writer -> Address -> (t : TT vs) -> Maybe (Down t)
toZero w s t@(Ref _ (DataCon _ _) z) = case roleOf w t of
  Just (_, Zero) => Just (MkDown 0 z RunZero)
  _ => Nothing
toZero w s (App _ f@(Ref _ (DataCon _ _) _) a) = case successorOf w f of
  Just s' => if sameAddress s s' then (\d => MkDown (S d.count) d.zero (RunSucc d.run)) <$> toZero w s a else Nothing
  Nothing => Nothing
toZero w s _ = Nothing

||| A run of one successor down to a zero, as the writer knows them: the
||| successor applied n >= 1 times, the same at each step, to a zero of its
||| type, as n, the successor, the zero and the run. The one reading of
||| such a run: the key prints it as a literal (`literalOf`), and the
||| growth check reads its height (`Template`).
public export
record SuccessorRun {0 vs : Scope} (t : TT vs) where
  constructor MkSuccessorRun
  count : Nat
  successor : Name
  zero : Name
  0 run : Run t count

export
successorRun : Writer -> (t : TT vs) -> Maybe (SuccessorRun t)
successorRun w (App _ f@(Ref _ (DataCon _ _) s) a) = do
  sa <- successorOf w f
  d <- toZero w sa a
  pure (MkSuccessorRun (S d.count) s d.zero (RunSucc d.run))
successorRun w _ = Nothing

||| A run of a successor down to its zero (`successorRun`), as a literal of
||| its `Nat`-like type: the successor named once with how many of it there
||| are in decimal, then the zero, `Prelude.Types.S^1024 Prelude.Types.Z`,
||| so that a literal's print grows with its digits, not its value, and two
||| types' literals, whose successors are two names, print apart.
literalOf : Writer -> TT vs -> Maybe (String, Bool)
literalOf w t = do
  r <- successorRun w t
  pure (plainOrigin r.successor ++ "^" ++ show r.count ++ " " ++ plainOrigin r.zero,
        dropsName r.successor || dropsName r.zero)

mutual
  ||| A term at a depth of binders: a variable by its binder's depth, a
  ||| definition by its printed full name, a literal of a `Nat`-like type
  ||| by its value (`literalOf`), an arrow whose result does not mention
  ||| its binder as `a -> b`, one whose does as `(x0 : a) -> b`, each with
  ||| Idris's quantity and braces; and whether the print dropped part of
  ||| what tells terms apart (`eqTerm`): an erased part that is not a
  ||| placeholder, a metavariable's arguments, a name printed with less, a
  ||| lambda's quantity and passing, a let's binder type and quantity, a
  ||| binder printed through, a default implicit printed as implicit, an
  ||| integer's width, a delay's type, an as-pattern's name.
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
  render w d p tm@(App _ f a) = case literalOf w tm of
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
        inner = showCount rig ++ domain
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
argumentText : {auto c : Ref Ctxt Defs} -> Writer -> ClosedTerm -> Front (String, Bool)
argumentText w tm = pure (render w 0 Alone !(fullNames tm))

------------------------------------------------------------------------------
-- The identity: the arguments written out
------------------------------------------------------------------------------

||| A quantity by its number: 0, 1, many.
export
quantity : Use -> Fin 3
quantity Erased = 0
quantity (Used Once) = 1
quantity (Used Many) = 2

||| The runtime value a reference marks, by its number, if it marks one: a
||| marker is a bound name (`Readings.markerName`, `Walk.probeTerm`), so a
||| reference to a constructor or a definition is what it names, whatever
||| its name.
public export
holeAt : NameType -> Name -> Maybe Nat
holeAt Bound n = markerOf n
holeAt _ _ = Nothing

||| A reference by what its name is (`holeAt`): a marker of a runtime
||| value an implementation closes over by its number, whose magnitude
||| weighs itself as a literal's does, and any other name by its address.
public export
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
  ||| and -0.0 are two, every NaN is one); no location, no binder's name,
  ||| no lambda's domain. A lambda's domain is what the place it stands at
  ||| takes (a parameter's type, a function type's domain), no reduction
  ||| reads it, and Idris writes it only where it had it: `const v`
  ||| reduces to `\(_ : k) => v`, while unification solves the same family
  ||| as `\(_ : _) => v` (`Core.Unify.instantiate`). Written, it would make
  ||| one type two data instances, and a value built as one would reach a
  ||| match on the other, whose constructors no site builds.
  ||| A name is its address in the context, a marker its number; a name
  ||| the context defines as nothing is no instance's (`missingIn`), and a
  ||| request of one stops before it is written. A run of a `Nat`-like
  ||| type's successor, a literal's above all (`Fin 1024`), is two symbols.
  write : Writer -> TT vs -> List (Token Form)
  write w (Local _ _ idx _) = [Node (Shaped Variable) Nothing idx]
  write w (Ref _ nt n) = referenceTo w.context n (holeAt nt n)
  write w (Meta _ _ i args) = Node (Shaped Hole) (addressOf <$> placementOf i) (length args) :: writeAll w args
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
  writeBinder w (Lam _ q info _) = writePassing w Lambda q info
  writeBinder w (Let _ q v ty) = node (Bound LetIn (quantity (use q)) ByHand) :: (write w v ++ write w ty)
  writeBinder w (Pi _ q info ty) = writePassing w PiType q info ++ write w ty
  writeBinder w (PVar _ q info ty) = writePassing w Pattern q info ++ write w ty
  writeBinder w (PLet _ q v ty) = node (Bound PatternLet (quantity (use q)) ByHand) :: (write w v ++ write w ty)
  writeBinder w (PVTy _ q ty) = node (Bound PatternType (quantity (use q)) ByHand) :: write w ty

  writePassing : Writer -> Binding -> RigCount -> PiInfo (TT vs) -> List (Token Form)
  writePassing w b q Implicit = [node (Bound b (quantity (use q)) ByUnification)]
  writePassing w b q Explicit = [node (Bound b (quantity (use q)) ByHand)]
  writePassing w b q AutoImplicit = [node (Bound b (quantity (use q)) BySearch)]
  writePassing w b q (DefImplicit t) = node (Bound b (quantity (use q)) ByDefault) :: write w t

mutual
  ||| The references of a term `write` writes by address, with their
  ||| kinds, in the order it writes them, before `acc`: every reference
  ||| but the frontend's own markers.
  namesOf : TT vs -> List (NameType, Name) -> List (NameType, Name)
  namesOf (Ref _ nt n) acc = maybe ((nt, n) :: acc) (const acc) (holeAt nt n)
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
  namesOfBinder (Lam _ _ info _) acc = namesOfPassing info acc
  namesOfBinder (Let _ _ v ty) acc = namesOf v (namesOf ty acc)
  namesOfBinder (Pi _ _ info ty) acc = namesOfPassing info (namesOf ty acc)
  namesOfBinder (PVar _ _ info ty) acc = namesOfPassing info (namesOf ty acc)
  namesOfBinder (PLet _ _ v ty) acc = namesOf v (namesOf ty acc)
  namesOfBinder (PVTy _ _ ty) acc = namesOf ty acc

  namesOfPassing : PiInfo (TT vs) -> List (NameType, Name) -> List (NameType, Name)
  namesOfPassing (DefImplicit t) acc = namesOf t acc
  namesOfPassing _ acc = acc

||| The first name the terms refer to (`namesOf`) that the frozen context
||| defines as nothing, if there is one.
missingIn : Frozen -> List (TT vs) -> Maybe Name
missingIn ctx tms = firstMissing (foldr namesOf [] tms)
  where
    firstMissing : List (NameType, Name) -> Maybe Name
    firstMissing [] = Nothing
    firstMissing ((_, n) :: ns) = case definitionIn ctx n of
      NotDefined _ => Just n
      DefinedAs {} => firstMissing ns

||| The zeros and successors of `Nat`-like types the terms name, by address:
||| the constructors of no argument and of one that Idris flags as such
||| (`natRole`, its metadata, never a name), whose runs `write` writes and
||| whose literals the key prints.
rolesIn : {auto c : Ref Ctxt Defs} -> List (TT vs) -> Front (SortedMap Address NatRole)
rolesIn tms = do
  defs <- getDefs
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

    role : Defs -> (Address, (Name, NatRole)) -> Front (Maybe (Address, NatRole))
    role defs (a, (n, admitted)) = do
      Just def <- lookupExact n (gamma defs)
        | Nothing => pure Nothing
      pure (case (natRole def, admitted) of
              (Just Zero, Zero) => Just (a, Zero)
              (Just Succ, Succ) => Just (a, Succ)
              _ => Nothing)

||| What reading terms beside the context needs (`Writer`): the context, and
||| the roles of the zeros and successors the terms name (`rolesIn`).
export
writerOf : {auto c : Ref Ctxt Defs} -> List (TT vs) -> Front Writer
writerOf tms = MkWriter (gamma !(getDefs)) <$> rolesIn tms

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
  writeWeighs w (Ref _ nt n) = referenceWeighs w.context n (holeAt nt n)
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
  binderWeighs w (Lam _ q info _) = passingWeighs w Lambda q info
  binderWeighs w (Let _ _ _ _) = LTESucc LTEZero
  binderWeighs w (Pi _ q info ty) = passingWeighsBefore w PiType q info (write w ty)
  binderWeighs w (PVar _ q info ty) = passingWeighsBefore w Pattern q info (write w ty)
  binderWeighs w (PLet _ _ _ _) = LTESucc LTEZero
  binderWeighs w (PVTy _ _ _) = LTESucc LTEZero

  0 passingWeighs : (w : Writer) -> (b : Binding) -> (q : RigCount) -> (info : PiInfo (TT vs)) ->
                     LTE 1 (weighs (writePassing w b q info))
  passingWeighs w b q Implicit = LTESucc LTEZero
  passingWeighs w b q Explicit = LTESucc LTEZero
  passingWeighs w b q AutoImplicit = LTESucc LTEZero
  passingWeighs w b q (DefImplicit _) = LTESucc LTEZero

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
  writeFits w (Ref _ nt n) = referenceFits w.context n (holeAt nt n)
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
  binderFits w (Lam _ q info _) = passingFits w Lambda q info
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
export
writtenOf : Writer -> ClosedTerm -> Written Form
writtenOf w t = writtenFrom (write w t) (writeFits w t)

------------------------------------------------------------------------------
-- What a key weighs, against what the universe lets it weigh
------------------------------------------------------------------------------

-- A term's key read as a tree of its heads (`Proof.Sizes.KeyTree`), so
-- that its weight is bounded by its height, its widest node and its
-- heaviest symbol, the measures a template has: a head applied to k
-- arguments is one node of k children, each application one more child of
-- its function's node; a binder is a node over its scope and the parts it
-- writes; a string or a double a node with a child per character, as a
-- template reads it (`Readings.constant`); a literal or a marker one node
-- whose weight is its token's. A run of successors is a node per
-- successor, which weighs what the run's two symbols do.

0 lteL : x = x' -> LTE x y -> LTE x' y
lteL Refl le = le

0 lteR : y = y' -> LTE x y -> LTE x y'
lteR Refl le = le

public export
0 glyphTrees : List Char -> List KeyTree
glyphTrees [] = []
glyphTrees (_ :: cs) = KeyNode 1 [] :: glyphTrees cs

public export
0 constantTree : Constant -> KeyTree
constantTree (Str x) = KeyNode 1 (glyphTrees (unpack x))
constantTree (Db x) = KeyNode 1 (glyphTrees (unpack (show x)))
constantTree c = KeyNode (weighs (writeConstant c)) []

mutual
  ||| A term's key as a tree of its heads. Never computed: the proofs of
  ||| what a key weighs read it.
  public export
  0 keyTree : Writer -> TT vs -> KeyTree
  keyTree w (Local _ _ _ _) = KeyNode 1 []
  keyTree w (Ref _ nt n) = KeyNode (weighs (referenceTo w.context n (holeAt nt n))) []
  keyTree w (Meta _ _ _ args) = KeyNode 1 (keyTrees w args)
  keyTree w (Bind _ _ b sc) = KeyNode 1 (keyTree w sc :: binderTrees w b)
  keyTree w (App _ f a) = addChild (keyTree w f) (keyTree w a)
  keyTree w (As _ _ a p) = KeyNode 1 [keyTree w a, keyTree w p]
  keyTree w (TDelayed _ _ t) = KeyNode 1 [keyTree w t]
  keyTree w (TDelay _ _ t a) = KeyNode 1 [keyTree w t, keyTree w a]
  keyTree w (TForce _ _ t) = KeyNode 1 [keyTree w t]
  keyTree w (PrimVal _ c) = constantTree c
  keyTree w (Erased _ Placeholder) = KeyNode 1 []
  keyTree w (Erased _ Impossible) = KeyNode 1 []
  keyTree w (Erased _ (Dotted t)) = KeyNode 1 [keyTree w t]
  keyTree w (TType _ _) = KeyNode 1 []

  public export
  0 keyTrees : Writer -> List (TT vs) -> List KeyTree
  keyTrees w [] = []
  keyTrees w (t :: ts) = keyTree w t :: keyTrees w ts

  public export
  0 binderTrees : Writer -> TTBinder (TT vs) -> List KeyTree
  binderTrees w (Lam _ _ info _) = passingTrees w info
  binderTrees w (Let _ _ v ty) = [keyTree w v, keyTree w ty]
  binderTrees w (Pi _ _ info ty) = keyTree w ty :: passingTrees w info
  binderTrees w (PVar _ _ info ty) = keyTree w ty :: passingTrees w info
  binderTrees w (PLet _ _ v ty) = [keyTree w v, keyTree w ty]
  binderTrees w (PVTy _ _ ty) = [keyTree w ty]

  public export
  0 passingTrees : Writer -> PiInfo (TT vs) -> List KeyTree
  passingTrees w Implicit = []
  passingTrees w Explicit = []
  passingTrees w AutoImplicit = []
  passingTrees w (DefImplicit t) = [keyTree w t]

||| A bound reference marking runtime value i is one node, weighing its
||| marker's token.
export
0 markerNode : (w : Writer) -> (fc : FC) -> (n : Name) -> markerOf n = Just i -> keyTree w (Ref fc Bound n) = KeyNode (S i + 0) []
markerNode w fc n found = cong (\mo => KeyNode (weighs (referenceTo w.context n mo)) []) found

||| A bound reference marking no runtime value is one node of weight one.
export
0 unmarkedNode : (w : Writer) -> (fc : FC) -> (n : Name) -> markerOf n = Nothing -> keyTree w (Ref fc Bound n) = KeyNode 1 []
unmarkedNode w fc n none = cong (\mo => KeyNode (weighs (referenceTo w.context n mo)) []) none

-- A leaf charges its own weight.
0 leafWithin : (n : Nat) -> LTE n (keyWeight (KeyNode n []))
leafWithin n = lteAddRight {m = Z} n

-- A node over one part charges two more than the part, and a node over two
-- parts two more than both and one more besides.
0 overOne : {x, t : Nat} -> LTE x t -> LTE (S x) (S (S (t + 0)))
overOne le = LTESucc (lteSuccRight (transitive le (lteAddRight {m = Z} t)))

0 overTwo : {x, y, s, t : Nat} -> LTE x s -> LTE y t -> LTE (x + y) (s + S (t + 0))
overTwo ls lt = plusLteMonotone ls (lteSuccRight (transitive lt (lteAddRight {m = Z} t)))

-- A run one successor longer weighs two more.
0 succeedingWeight : (s : Address) -> (ts : List (Token Form)) -> LTE (weighs (succeeding s ts)) (S (S (weighs ts)))
succeedingWeight s [] = reflexive
succeedingWeight s [t] = reflexive
succeedingWeight s (t :: Node f k n :: rest) = reflexive
succeedingWeight s (t :: Number g m :: rest) = lengthenedWeight (runOf s t g)
  where
    lengthenedWeight : (starts : Bool) ->
                       LTE (weighs (lengthened starts s t g m rest)) (S (S (weighs (t :: Number g m :: rest))))
    lengthenedWeight True = lteL (sym (twoMore (weight t) (S m + weighs rest))) reflexive
    lengthenedWeight False = reflexive

0 glyphsWithin : (cs : List Char) -> LTE (weighs (spellChars cs)) (childWeights (glyphTrees cs))
glyphsWithin [] = LTEZero
glyphsWithin (_ :: cs) = LTESucc (lteSuccRight (glyphsWithin cs))

0 constantWithin : (c : Constant) -> LTE (weighs (writeConstant c)) (keyWeight (constantTree c))
constantWithin (I x) = leafWithin (weighs (writeConstant (I x)))
constantWithin (I8 x) = leafWithin (weighs (writeConstant (I8 x)))
constantWithin (I16 x) = leafWithin (weighs (writeConstant (I16 x)))
constantWithin (I32 x) = leafWithin (weighs (writeConstant (I32 x)))
constantWithin (I64 x) = leafWithin (weighs (writeConstant (I64 x)))
constantWithin (BI x) = leafWithin (weighs (writeConstant (BI x)))
constantWithin (B8 x) = leafWithin (weighs (writeConstant (B8 x)))
constantWithin (B16 x) = leafWithin (weighs (writeConstant (B16 x)))
constantWithin (B32 x) = leafWithin (weighs (writeConstant (B32 x)))
constantWithin (B64 x) = leafWithin (weighs (writeConstant (B64 x)))
constantWithin (Str x) = LTESucc (glyphsWithin (unpack x))
constantWithin (Ch x) = leafWithin (weighs (writeConstant (Ch x)))
constantWithin (Db x) = LTESucc (glyphsWithin (unpack (show x)))
constantWithin (PrT t) = leafWithin (weighs (writeConstant (PrT t)))
constantWithin WorldVal = leafWithin (weighs (writeConstant WorldVal))

mutual
  -- What a term's key weighs is at most what its tree charges.
  0 writeWithinTree : (w : Writer) -> (t : TT vs) -> LTE (weighs (write w t)) (keyWeight (keyTree w t))
  writeWithinTree w (Local _ _ _ _) = reflexive
  writeWithinTree w (Ref _ nt n) = leafWithin (weighs (referenceTo w.context n (holeAt nt n)))
  writeWithinTree w (Meta _ _ _ args) = LTESucc (allWithinTrees w args)
  writeWithinTree w (Bind _ _ b sc) =
    lteL (sym (weighsAppend (writeBinder w b) (write w sc))) $
      lteSuccRight $
        lteR (cong S (plusCommutative (childWeights (binderTrees w b)) (keyWeight (keyTree w sc)))) $
          plusLteMonotone (binderWithinTrees w b) (writeWithinTree w sc)
  writeWithinTree w (App _ f a) =
    lteR (sym (addChildWeight (keyTree w f) (keyTree w a))) (applicationWithin w (successorOf w f) f a)
  writeWithinTree w (As _ _ a p) =
    LTESucc (lteSuccRight (lteL (sym (weighsAppend (write w a) (write w p)))
                                (overTwo (writeWithinTree w a) (writeWithinTree w p))))
  writeWithinTree w (TDelayed _ _ t) = overOne (writeWithinTree w t)
  writeWithinTree w (TDelay _ _ t a) =
    LTESucc (lteSuccRight (lteL (sym (weighsAppend (write w t) (write w a)))
                                (overTwo (writeWithinTree w t) (writeWithinTree w a))))
  writeWithinTree w (TForce _ _ t) = overOne (writeWithinTree w t)
  writeWithinTree w (PrimVal _ c) = constantWithin c
  writeWithinTree w (Erased _ Placeholder) = reflexive
  writeWithinTree w (Erased _ Impossible) = reflexive
  writeWithinTree w (Erased _ (Dotted t)) = overOne (writeWithinTree w t)
  writeWithinTree w (TType _ _) = reflexive

  -- An application charges one for itself, its function's tree and its
  -- argument's; a successor's run, two more than its argument, which its
  -- function's node, weighing at least one, covers.
  0 applicationWithin : (w : Writer) -> (m : Maybe Address) -> (f, a : TT vs) ->
                        LTE (weighs (writeApplication w m f a)) (S (keyWeight (keyTree w f) + keyWeight (keyTree w a)))
  applicationWithin w Nothing f a =
    LTESucc (lteL (sym (weighsAppend (write w f) (write w a)))
                  (plusLteMonotone (writeWithinTree w f) (writeWithinTree w a)))
  applicationWithin w (Just s) f a =
    transitive (succeedingWeight s (write w a))
               (LTESucc (plusLteMonotone (transitive (writeWeighs w f) (writeWithinTree w f)) (writeWithinTree w a)))

  0 allWithinTrees : (w : Writer) -> (ts : List (TT vs)) -> LTE (weighs (writeAll w ts)) (childWeights (keyTrees w ts))
  allWithinTrees w [] = LTEZero
  allWithinTrees w (t :: ts) =
    lteL (sym (weighsAppend (write w t) (writeAll w ts))) $
      lteSuccRight (plusLteMonotone (writeWithinTree w t) (allWithinTrees w ts))

  0 binderWithinTrees : (w : Writer) -> (b : TTBinder (TT vs)) ->
                        LTE (weighs (writeBinder w b)) (S (childWeights (binderTrees w b)))
  binderWithinTrees w (Lam _ q info _) = passingWithinTrees w Lambda q info
  binderWithinTrees w (Let _ q v ty) =
    LTESucc (lteSuccRight (lteL (sym (weighsAppend (write w v) (write w ty)))
                                (overTwo (writeWithinTree w v) (writeWithinTree w ty))))
  binderWithinTrees w (Pi _ q info ty) = typedWithinTrees w PiType q info ty
  binderWithinTrees w (PVar _ q info ty) = typedWithinTrees w Pattern q info ty
  binderWithinTrees w (PLet _ q v ty) =
    LTESucc (lteSuccRight (lteL (sym (weighsAppend (write w v) (write w ty)))
                                (overTwo (writeWithinTree w v) (writeWithinTree w ty))))
  binderWithinTrees w (PVTy _ q ty) = overOne (writeWithinTree w ty)

  0 passingWithinTrees : (w : Writer) -> (b : Binding) -> (q : RigCount) -> (info : PiInfo (TT vs)) ->
                         LTE (weighs (writePassing w b q info)) (S (childWeights (passingTrees w info)))
  passingWithinTrees w b q Implicit = reflexive
  passingWithinTrees w b q Explicit = reflexive
  passingWithinTrees w b q AutoImplicit = reflexive
  passingWithinTrees w b q (DefImplicit t) = overOne (writeWithinTree w t)

  -- A pi's or a pattern variable's passing, then its type.
  0 typedWithinTrees : (w : Writer) -> (b : Binding) -> (q : RigCount) -> (info : PiInfo (TT vs)) -> (ty : TT vs) ->
                       LTE (weighs (writePassing w b q info ++ write w ty))
                           (S (childWeights (keyTree w ty :: passingTrees w info)))
  typedWithinTrees w b q Implicit ty = overOne (writeWithinTree w ty)
  typedWithinTrees w b q Explicit ty = overOne (writeWithinTree w ty)
  typedWithinTrees w b q AutoImplicit ty = overOne (writeWithinTree w ty)
  typedWithinTrees w b q (DefImplicit t) ty =
    LTESucc (lteSuccRight (lteL (sym (weighsAppend (write w t) (write w ty)))
                                (lteL (plusCommutative (weighs (write w ty)) (weighs (write w t)))
                                      (overTwo (writeWithinTree w ty) (writeWithinTree w t)))))

||| A key's written size is at most what the universe lets a key weigh
||| (`Proof.Requests.sizeWithin`) at any height at least its tree's, any
||| arity at least its widest node's, and any heaviest token at least its
||| heaviest own symbol's weight, or 1: the measures the template it is
||| read as gives it.
export
0 writtenWithin : (w : Writer) -> (t : ClosedTerm) -> {a, h, e : Nat} ->
                  LTE (keyHeight (keyTree w t)) h -> LTE (keyArity (keyTree w t)) a ->
                  LTE (keyHeaviest (keyTree w t)) (maximum 1 e) ->
                  LTE (writtenOf w t).size (sizeWithin a h e)
writtenWithin w t high wide light =
  transitive (writeWithinTree w t)
             (treeWithin {a} {h} {e} (keyTree w t) high wide
                         (lightEnough {h} {e} (transitive (keyTall (keyTree w t)) high) light))

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
  nameIdentity : {auto s : Ref TState TS} -> Name -> Front String
  nameIdentity n = case blockOf n of
    Just _ => ("K" ++) . counted <$> keyOrigin n
    Nothing => structural n
    where
      structural : Name -> Front String
      structural (NS ns m) =
        let parts = unsafeUnfoldNamespace ns in
        (("N" ++ show (length parts) ++ ";" ++ concatMap (counted . (.text)) parts) ++) <$> nameIdentity m
      structural (UN (Basic x)) = pure ("U" ++ counted x.text)
      structural (UN (Field x)) = pure ("V" ++ counted x.text)
      structural (UN Underscore) = pure "_"
      structural (MN x i) = pure ("M" ++ counted x.text ++ show i ++ ";")
      structural (PV m i) = (\t => "P" ++ t ++ show i ++ ";") <$> nameIdentity m
      structural (DN _ m) = nameIdentity m
      structural (Resolved i) = pure ("R" ++ show i ++ ";")
      structural other = pure ("O" ++ counted (show other))

||| A name of the context by its address, as it reads in every build.
addressIdentity : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Address -> Front String
addressIdentity a = nameIdentity !(fullNames (Resolved (addressIndex a)))

||| A written argument as text that reads the same in every build, each
||| name by its full name.
writtenText : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Written Form -> Front String
writtenText w = ("+" ++) . concat <$> traverse symbolText w.symbols
  where
    symbolText : Token Form -> Front String
    symbolText (Node f m k) = do
      nm <- maybe (pure "") (map ("@" ++) . addressIdentity) m
      pure ("N" ++ formText f ++ nm ++ ":" ++ show k ++ ";")
    symbolText (Number f m) = pure ("#" ++ formText f ++ ":" ++ show m ++ ";")

||| An instance's identity as text that reads the same in every build, for
||| the hash a symbol carries when its key's print drops part of the
||| identity: the link, each name by its full name, each block by its
||| place.
linkText : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Link Form -> Front String
linkText (MkLink h as) = do
  dn <- headText h
  args <- traverse (maybe (pure "-") writtenText) as
  pure (dn ++ "|" ++ show (length as) ++ ";" ++ concat args)
  where
    -- A definition by its name; an application by what it is, which no
    -- name of the context spells.
    headText : Head -> Front String
    headText (ADefinition d) = addressIdentity d
    headText AnApplication = pure "$application"

------------------------------------------------------------------------------
-- Identities and keys
------------------------------------------------------------------------------

||| The positions a key prints: every position up to the last that keys the
||| instance, one that keys nothing as nothing, and whether a print drops
||| part of what it prints. The definition fixes how many positions it
||| has, so the ones after the last that keys tell no two instances apart,
||| and a definition that keys nothing prints none.
keyed : {auto c : Ref Ctxt Defs} -> Writer -> List (Maybe ClosedTerm) -> Front (KeyArguments, Bool)
keyed w args = case lastKeyed args of
  Nothing => pure (NoArguments, False)
  Just (before, l) => do
    printed <- traverse (traverse (argumentText w)) before
    (text, lost) <- argumentText w l
    pure (UpTo (map (map fst) printed) text, any (maybe False snd) printed || lost)
  where
    -- The positions before the last that keys, and the last, if one keys.
    lastKeyed : List (Maybe ClosedTerm) -> Maybe (List (Maybe ClosedTerm), ClosedTerm)
    lastKeyed [] = Nothing
    lastKeyed (x :: xs) = case lastKeyed xs of
      Just (before, l) => Just (x :: before, l)
      Nothing => (\l => ([], l)) <$> x

||| An instance as a request finds or makes it: its identity, which is its
||| link (the definition's address and the compile-time arguments written
||| out); its key; its symbol, the key printed; and each compile-time
||| argument as the request gave it, with how the link writes it, by
||| position (`Nothing` where the request gave none).
public export
record Instance a where
  constructor MkInstance
  link : Link Form
  key : InstanceKey
  symbol : String
  arguments : List (Maybe (a, Written Form))

||| The instance of what a link heads (`head`) at its compile-time arguments
||| (`Nothing` at a position that keys nothing), each given as whatever the
||| request knows of it, which holds its term (`term`). Two requests are one
||| instance exactly when their links are equal: the map of instances is
||| keyed by the link, and a request of an instance already made finds it
||| there without printing anything. A new one is printed: its key, its
||| origin (`originOf`, read only then), and its symbol, which carries the low
||| 64 bits of the hash of the link's text when the print drops part of the
||| identity, a function of the key alone, two links on one key being a
||| broken invariant. `what` names it for a message.
instanceAt : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
             FC -> (what : String) -> Head -> (originOf : Front String) -> (term : a -> ClosedTerm) -> List (Maybe a) ->
             Front (Instance a)
instanceAt fc what head originOf term given = do
  let forms = map (map term) given
  -- A link writes each name a compile-time argument refers to by the
  -- address of the definition the frozen context gives it, but the
  -- frontend's own markers, which are written by their numbers (`holeAt`).
  -- A name the context defines as nothing is a definition the compiled
  -- modules miss, refused before anything is written, as a request of one
  -- is (`instanceKey`).
  let present = catMaybes forms
  ctx <- frozenContext
  let Nothing = missingIn ctx present
    | Just missing => reject fc what CompiledModule ("a compile-time argument names the missing definition " ++
                                                    show !(fullNames missing))
  writer <- writerOf present
  -- The link writes each argument as given, a name by the address it
  -- resolves to, whichever spelling it has, so that the key a request's
  -- reading bounds (`Template.keyedWithin`) is the one written; only the
  -- print names each by its full name.
  let arguments = map (map (\x => (x, writtenOf writer (term x)))) given
  let link = MkLink head (map (map snd) arguments)
  case lookupFact (.named) link !(getState) of
    Just (symbol, key) => pure (MkInstance link key symbol arguments)
    Nothing => do
      origin <- originOf
      shown <- traverse (traverse fullNames) forms
      (printed, lost) <- keyed writer shown
      -- Whole only when the print keeps all of the identity and fits a
      -- symbol (keyText).
      let fits = length (utf8 (keyPrint origin printed)) <= symbolBytes
      print <- if lost || not fits
                 then (\t => Lossy (xxh3_128 (utf8 t)).low) <$> linkText link
                 else pure Whole
      let key = MkInstanceKey origin printed print
      let symbol = keyText key
      -- Essential: the key claims the whole identity when it prints whole,
      -- and carries only 64 bits of the hash of the link's text when it does
      -- not, which no type can make collision-free. Two links on one key are
      -- that claim broken or those bits colliding, found here, at the
      -- request, before the two are translated as one key. That no two
      -- functions share a symbol is the program's symbol table's, which
      -- MLIR verifies where the symbol is.
      case lookupFact (.keyLinks) key !(getState) of
        Just other => unless (other == link) $
          internal fc ("two instances on the key " ++ symbol)
        Nothing => pure ()
      updateState (derive { named $= insert link (symbol, key), keyLinks $= insert key link })
      pure (MkInstance link key symbol arguments)

||| The instance of a definition at its compile-time arguments
||| (`instanceAt`), and the definition's address, which heads its link.
||| The definition is the one the frozen context gives the name the
||| request names; a name it defines as nothing is a definition the
||| compiled modules miss.
export
instanceKey : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
              FC -> String -> Name -> (term : a -> ClosedTerm) -> List (Maybe a) -> Front (Address, Instance a)
instanceKey fc owner n term given = do
  full <- fullNames n
  ctx <- frozenContext
  let DefinedAs i resolved _ defines = definitionIn ctx full
    | NotDefined _ => reject fc owner CompiledModule ("missing definition " ++ show full)
  let address = definedAddress i resolved defines
  (address,) <$> instanceAt fc (show full) (ADefinition address) (keyOrigin full) term given

||| The instance of a member at a use's types (`AtUse uses`) at its
||| compile-time arguments (`instanceAt`): the form's type, the form, the
||| use's arguments. No definition heads its link, and its key's origin
||| says how many arguments the use gives, which a print that stops at the
||| last argument that keys would not.
export
applicationKey : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
                 FC -> (uses : Nat) -> (term : a -> ClosedTerm) -> List (Maybe a) -> Front (Instance a)
applicationKey fc uses term given =
  instanceAt fc "a member at a use" AnApplication (pure ("$idris-mlir.application." ++ show uses)) term given

||| A polymorphic function type as its choice is keyed (`ChoiceKey`): the
||| type written out, which is its identity, and its key, the type printed
||| as a function's choice prints, which labels the choice's family. No
||| definition is a function type, so its key's origin names the kind of
||| choice; a print that drops part of the type carries the hash of the
||| whole, as an instance's symbol does.
export
functionKey : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
              ClosedTerm -> Front (Written Form, InstanceKey)
functionKey ty = do
  full <- fullNames ty
  writer <- writerOf [full]
  let written = writtenOf writer full
  (printed, lost) <- keyed writer [Just full]
  let origin = "function"
  print <- if lost || length (utf8 (keyPrint origin printed)) > symbolBytes
             then (\t => Lossy (xxh3_128 (utf8 t)).low) <$> writtenText written
             else pure Whole
  pure (written, MkInstanceKey origin printed print)
