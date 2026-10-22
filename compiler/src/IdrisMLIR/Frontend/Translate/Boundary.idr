-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| What the translation reads of the program, read once, at the boundary:
||| when the program and everything it imports are loaded and its entry is
||| found, every definition the translation can meet from the entry is read
||| through the frozen context and the context's accessors, each part of it
||| once (`Defined`), and kept by its entry. The translation reads these and
||| nothing else of the context (`Errors.defined`).
|||
||| A definition is met through a name some term the translation holds
||| refers to: a definition's type or body, or a normal form of terms made
||| from those, whose names are again the names of the bodies unfolded. So
||| the definitions it can meet are those the entry refers to, and those
||| they refer to in turn, through their types, their case trees, their
||| clauses' patterns and their one clause, the unknowns in them, a type
||| constructor's constructors, the definition a block belongs to, the calls
||| Idris's size-change graphs keep, and the library function the registry
||| has a call of a definition stand for; and the pair Idris's `%pair`
||| names, which the translation builds itself.
module IdrisMLIR.Frontend.Translate.Boundary

import Core.Case.CaseTree
import Core.Context
import Core.Core
import Core.Options
import Core.TT
import Idris.Host

import IdrisMLIR.Frontend.Resolve
import IdrisMLIR.Frontend.Translate.State
import IdrisMLIR.Frontend.Walk
import IdrisMLIR.Registry

import Control.WellFounded
import Data.DPair
import Data.List
import Data.Maybe
import Data.SnocList
import Data.SortedMap

%default total

------------------------------------------------------------------------------
-- What a definition refers to
------------------------------------------------------------------------------

mutual
  ||| The names a term refers to, its unknowns among them, left to right.
  termNames : SnocList Name -> Term vs -> SnocList Name
  termNames acc (Ref _ _ n) = acc :< n
  termNames acc (Meta _ n _ args) = termsNames (acc :< n) args
  termNames acc (Bind _ _ b sc) = termNames (binderNames acc b) sc
  termNames acc (App _ f a) = termNames (termNames acc f) a
  termNames acc (As _ _ a p) = termNames (termNames acc a) p
  termNames acc (TDelayed _ _ t) = termNames acc t
  termNames acc (TDelay _ _ t a) = termNames (termNames acc t) a
  termNames acc (TForce _ _ t) = termNames acc t
  termNames acc (Erased _ (Dotted t)) = termNames acc t
  termNames acc _ = acc

  termsNames : SnocList Name -> List (Term vs) -> SnocList Name
  termsNames acc [] = acc
  termsNames acc (t :: ts) = termsNames (termNames acc t) ts

  piNames : SnocList Name -> PiInfo (Term vs) -> SnocList Name
  piNames acc (DefImplicit t) = termNames acc t
  piNames acc _ = acc

  binderNames : SnocList Name -> Binder (Term vs) -> SnocList Name
  binderNames acc (Lam _ _ p ty) = termNames (piNames acc p) ty
  binderNames acc (Let _ _ v ty) = termNames (termNames acc ty) v
  binderNames acc (Pi _ _ p ty) = termNames (piNames acc p) ty
  binderNames acc (PVar _ _ p ty) = termNames (piNames acc p) ty
  binderNames acc (PLet _ _ v ty) = termNames (termNames acc ty) v
  binderNames acc (PVTy _ _ ty) = termNames acc ty

mutual
  ||| The names a case tree refers to: each case's scrutinee type and each
  ||| alternative's constructor, and each leaf's term.
  treeNames : SnocList Name -> CaseTree vs -> SnocList Name
  treeNames acc (Case _ _ ty alts) = altsNames (termNames acc ty) alts
  treeNames acc (STerm _ t) = termNames acc t
  treeNames acc _ = acc

  altsNames : SnocList Name -> List (CaseAlt vs) -> SnocList Name
  altsNames acc [] = acc
  altsNames acc (a :: as) = altsNames (altNames acc a) as

  altNames : SnocList Name -> CaseAlt vs -> SnocList Name
  altNames acc (ConCase n _ _ sc) = treeNames (acc :< n) sc
  altNames acc (DelayCase _ _ sc) = treeNames acc sc
  altNames acc (ConstCase _ sc) = treeNames acc sc
  altNames acc (DefaultCase sc) = treeNames acc sc

mutual
  ||| The names a clause's pattern refers to: its constructors and type
  ||| constructors, and the terms of what it cannot match.
  patNames : SnocList Name -> Pat -> SnocList Name
  patNames acc (PAs _ _ p) = patNames acc p
  patNames acc (PCon _ n _ _ ps) = patsNames (acc :< n) ps
  patNames acc (PTyCon _ n _ ps) = patsNames (acc :< n) ps
  patNames acc (PConst _ _) = acc
  patNames acc (PArrow _ _ s t) = patNames (patNames acc s) t
  patNames acc (PDelay _ _ s t) = patNames (patNames acc s) t
  patNames acc (PLoc _ _) = acc
  patNames acc (PUnmatchable _ t) = termNames acc t

  patsNames : SnocList Name -> List Pat -> SnocList Name
  patsNames acc [] = acc
  patsNames acc (p :: ps) = patsNames (patNames acc p) ps

||| The definition a case, with or nested block belongs to: a case or with
||| block's parent is its full name, which Idris keeps; a nested function's
||| is its place in the context (`Closed.rootOf`, which climbs them).
parentOf : Name -> Maybe Name
parentOf (NS _ n) = parentOf n
parentOf (CaseBlock outer _) = Just outer
parentOf (WithBlock outer _) = Just outer
parentOf (Nested (outer, _) _) = Just (Resolved outer)
parentOf _ = Nothing

||| The library function the registry has a call of a definition stand for:
||| a natural's comparison, as the function that makes a `Bool` of it, or
||| its operation on integers; else the function a definition is an alias
||| of. A natural's primitive operation stands for none, whatever else the
||| definition's hooks say, since a call of it is that primitive.
libraryOf : Hooks -> Maybe QName
libraryOf hs = case hs.natOperation of
  Just (Tested _ q) => Just q
  Just (OnIntegers q) => Just q
  Just _ => Nothing
  Nothing => hs.alias

||| Every name the translation may meet through a definition it meets.
referred : Defined -> List Name
referred d =
  (termNames [<] d.type <>> [])
  ++ maybe [] body d.matched
  ++ constructors (definition d.def)
  ++ maybe [] (:: []) (parentOf (fullname d.def))
  ++ map (.fnCall) (sizeChange d.def)
  ++ maybe [] (:: []) d.library
  where
    body : Matched -> List Name
    body m = (patsNames (treeNames [<] m.tree) (concat m.pats) <>> [])
               ++ maybe [] (\(_ ** rhs) => termNames [<] rhs <>> []) m.onlyClause

    constructors : Def -> List Name
    constructors (TCon _ _ _ _ _ cons _) = fromMaybe [] cons
    constructors _ = []

------------------------------------------------------------------------------
-- Reading a definition
------------------------------------------------------------------------------

||| How many clauses a body has, which a stored body says without decoding
||| one.
clauseCount : Body args -> Nat
clauseCount (LiveBody _ _ cs) = length cs
clauseCount (StoredBody _ _ cs) = length cs

||| The right-hand side of a body's clause, in its scope, when it has
||| exactly one; of a body of more, no clause is decoded.
onlyClauseOf : Body args -> Core (Maybe (vs : Scope ** Term vs))
onlyClauseOf body = case clauseCount body of
  1 => do
    [(vs ** (_, _, rhs))] <- clausesOf body
      | _ => pure Nothing
    pure (Just (vs ** rhs))
  _ => pure Nothing

||| A definition as the translation reads it (`Defined`), each part through
||| the context's accessors once: its type; of one that matches, its case
||| tree, its clauses' patterns and its one clause; and the library function
||| its hooks name, interned where it enters the compiler.
readDefinition : {auto c : Ref Ctxt Defs} -> Placement -> GlobalDef -> Core Defined
readDefinition p def = do
  ty <- (.fst) <$> host.typeOf def
  m <- case definition def of
         PMDef _ args body => Just <$> matched args body
         _ => pure Nothing
  library <- traverse toName (hooksRead def >>= libraryOf)
  pure (MkDefined p def ty m library)
  where
    -- The hooks a call of the definition is translated by: a foreign
    -- declaration's by its specs, where a call of one whose specs the
    -- registry does not give a hook is refused before any is read; any
    -- other's by its name.
    hooksRead : GlobalDef -> Maybe Hooks
    hooksRead d = case definition d of
      ForeignDef _ specs => case foreignHook (qname (fullname d)) specs of
        Just (Right hs) => Just hs
        _ => Nothing
      _ => Just (hooksOf (fullname d))

    matched : (args : Scope) -> Body args -> Core Matched
    matched args body = do
      tree <- (.fst) <$> host.treeOf body
      pats <- clausePatsOf body
      only <- onlyClauseOf body
      pure (MkMatched args tree pats only)

------------------------------------------------------------------------------
-- Reading the program
------------------------------------------------------------------------------

||| Every definition met from the names, after those read so far, each read
||| once and kept by its entry, then what it refers to read in turn. A
||| definition is entered into a walk when it is read (`Walk`), and every
||| one read leaves fewer to enter, which is why the reading ends; a name
||| the frozen context defines as nothing, a probe's or a binder's, is no
||| definition to read.
readFrom : {auto c : Ref Ctxt Defs} -> Frozen -> (w : Walked) -> (0 _ : SizeAccessible w) ->
           SortedMap Int Defined -> List Name -> Core (SortedMap Int Defined)
readFrom fz w acc found [] = pure found
readFrom fz w acc@(Access rec) found (n :: ns) = case definitionIn fz n of
  NotDefined _ => readFrom fz w acc found ns
  DefinedAs i _ def _ => case placementOf i of
    Nothing => readFrom fz w acc found ns
    Just p => case enter p w of
      -- Read already.
      Nothing => readFrom fz w acc found ns
      Just (Element w' less) => do
        d <- readDefinition p def
        readFrom fz w' (rec w' less) (insert i d found) (referred d ++ ns)

||| What the translation reads of a program whose entry is the definition
||| at `entry`, in what it read before its entry was found (the frozen
||| context, and the type a member at a use is applied as): every
||| definition it can meet from the entry and from the pair `%pair` names.
export
readProgram : {auto c : Ref Ctxt Defs} -> Read -> (entry : Name) -> Core Read
readProgram r entry = do
  let fz = r.frozen
  let pair = maybe [] (\ns => [pairType ns, fstName ns, sndName ns]) (pairnames (options (defsOf fz)))
  found <- readFrom fz start (sizeAccessible start) empty (entry :: pair)
  pure ({ definitions := found } r)

||| The type a member at a use is applied as by (`AtUse`): `{0 t : Type} ->
||| (f : t) -> t`, the form's type, then the form, giving a value of the
||| form's type, its binders' names interned once.
export
applicationOf : {auto c : Ref Ctxt Defs} -> Core ClosedTerm
applicationOf = do
  t <- intern "t"
  f <- intern "f"
  u <- intern "u"
  pure (Bind EmptyFC (UN (Basic t)) (Pi EmptyFC erased Implicit (TType EmptyFC (UN (Basic u))))
          (Bind EmptyFC (UN (Basic f)) (Pi EmptyFC top Explicit (Local EmptyFC Nothing 0 First))
                (Local EmptyFC Nothing 1 (Later First))))
