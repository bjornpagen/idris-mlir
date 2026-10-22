-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The translation's errors, the user's and the compiler's, and its
||| locations: an Idris location as a Core one.
module IdrisMLIR.Frontend.Translate.Errors

import Core.Case.CaseTree
import Core.Context
import Core.Core
import Core.Directory
import Core.FC
import Core.Options
import Core.TT
import Idris.Host

import IdrisMLIR.Frontend.Resolve
import IdrisMLIR.Emit
import IdrisMLIR.Frontend.Translate.State
import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.Registry.Libraries
import IdrisMLIR.Spec.Core.Rules

import Data.DPair
import Data.List
import Data.Maybe
import Data.SnocList
import Data.SortedMap

%default total

export
isEmptyFC : FC -> Bool
isEmptyFC EmptyFC = True
isEmptyFC _ = False

------------------------------------------------------------------------------
-- The frontend's computations
------------------------------------------------------------------------------

||| What the frontend computes: Idris's own computation over what it reads
||| of the program (`Read`: the context frozen once the program and
||| everything it imports were loaded, which every normaliser reads, and
||| the definitions read from it once), whose errors are Idris's, giving
||| either the value or the program's refusal. A refusal is a value of the
||| computation, never an error beside it: Idris's `Error` cannot carry
||| one, and the checker, which owns it, imports nothing of the frontend's.
public export
record Front a where
  constructor MkFront
  runFront : Read -> Core (Either Refusal a)

export
Functor Front where
  map f (MkFront c) = MkFront (\fz => Core.map (map f) (c fz))

export
Applicative Front where
  pure x = MkFront (\_ => Core.pure (Right x))
  MkFront cf <*> MkFront cx = MkFront $ \fz => Core.(>>=) (cf fz) $ \case
    Left r => Core.pure (Left r)
    Right f => Core.map (map f) (cx fz)

export
Monad Front where
  MkFront cx >>= k = MkFront $ \fz => Core.(>>=) (cx fz) $ \case
    Left r => Core.pure (Left r)
    Right x => runFront (k x) fz

||| Idris's errors pass through the frontend's computation as they are; a
||| refusal is no error, so catching one leaves the refusals alone.
export
Catchable Front Error where
  throw e = MkFront (\_ => throw e)
  catch (MkFront c) h = MkFront (\fz => catch (c fz) (\e => runFront (h e) fz))
  breakpoint (MkFront c) = MkFront $ \fz => Core.(>>=) (breakpoint (c fz)) $ \case
    Left e => Core.pure (Right (Left e))
    Right (Left r) => Core.pure (Left r)
    Right (Right x) => Core.pure (Right (Right x))

||| What the frontend reads of the program, which nothing it does changes.
export
reading : Front Read
reading = MkFront (\r => Core.pure (Right r))

||| The context the normalisers read: frozen once, when the program and
||| everything it imports were loaded, and never changed after.
export
frozenContext : Front Frozen
frozenContext = (.frozen) <$> reading

||| A computation that runs Idris's own: Idris's `Core`, as it is, and the
||| frontend's, which refuses nothing there. Helpers that never refuse are
||| written once for both.
public export
interface RunsCore m where
  core : Core a -> m a

export
RunsCore Core where
  core c = c

export
RunsCore Front where
  core c = MkFront (\_ => Core.map Right c)

||| The translation's state.
export
getState : RunsCore m => {auto s : Ref TState TS} -> m TS
getState = core (get TState)

||| The translation's state, replaced.
export
putState : RunsCore m => {auto s : Ref TState TS} -> TS -> m ()
putState st = core (put TState st)

||| The translation's state, changed.
export
updateState : RunsCore m => {auto s : Ref TState TS} -> (TS -> TS) -> m ()
updateState f = core (update TState f)

||| The definitions Idris has loaded.
export
getDefs : RunsCore m => {auto c : Ref Ctxt Defs} -> m Defs
getDefs = core (get Ctxt)

||| Something with every name in it full.
export
fullNames : RunsCore m => HasNames a => {auto c : Ref Ctxt Defs} -> a -> m a
fullNames x = core (toFullNames x)

||| The definition a context holds at a name, when it holds one.
export
lookupExact : RunsCore m => Name -> Context -> m (Maybe GlobalDef)
lookupExact n ctx = core (lookupCtxtExact n ctx)

||| A definition's type, read through the context's accessor, which decodes
||| the type of a definition read from a checked module where it is held
||| stored.
export
typeOfDefinition : RunsCore m => GlobalDef -> m ClosedTerm
typeOfDefinition def = core ((.fst) <$> host.typeOf def)

||| A pattern-matching definition's case tree, read through the context's
||| accessor, as its type is, with the evidence that it is the tree the
||| evaluator walks, which a reading that unfolds the definition carries.
||| The evidence is erased, so a reader that carries none takes the tree
||| alone (`.fst`) at no cost.
export
caseTreeOf : RunsCore m => {args : Scope} -> (body : Body args) -> m (Subset (CaseTree args) (TreeOf body))
caseTreeOf body = core (host.treeOf body)

||| The right-hand side of a definition whose case tree is one leaf, or
||| nothing for one that matches: read through the context's walk of the
||| tree, so that of a stored definition only that leaf is decoded, and of
||| one that matches nothing is.
export
leafOfBody : RunsCore m => {args : Scope} -> Body args -> m (Maybe (Core.TT.Term.Term args))
leafOfBody body = core (walkTree body leaf)
  where
    leaf : {0 t : Scoped} -> Leaves t -> CaseTree' t args -> Core (Maybe (Core.TT.Term.Term args))
    leaf leaves (STerm _ r) =
      Just . replace {p = Core.TT.Term.Term} (appendNilRightNeutral args) <$> leaves.leafTerm {outer = []} r
    leaf _ _ = pure Nothing

||| An action of the host.
export
ioLift : RunsCore m => IO a -> m a
ioLift act = core (coreLift act)

||| The elements a test keeps, in order, the test run on each in turn.
export
keepIf : Monad m => (a -> m Bool) -> List a -> m (List a)
keepIf p [] = pure []
keepIf p (x :: xs) = do
  keep <- p x
  rest <- keepIf p xs
  pure (if keep then x :: rest else rest)

||| Where a refusal at an Idris location is: there, or, at no location, at
||| the module being compiled.
export
siteAt : RunsCore m => {auto s : Ref TState TS} -> FC -> m NonEmptyFC
siteAt fc = core $ case isNonEmptyFC fc of
  Just site => Core.pure site
  Nothing => Core.map (.moduleFC) (get TState)

||| Refuses the program: the refusal is the computation's value, which
||| every step after it passes on untouched up to `noting`.
export
rejectWith : Refusal -> Front a
rejectWith r = MkFront (\_ => Core.pure (Left r))

||| A user error, by the rule that refuses it, at a location (the module's
||| when Idris gives none), the message naming the definition that owns
||| what is refused.
export
reject : {auto s : Ref TState TS} -> {c : Category} -> FC -> String -> Rule c -> String -> Front a
reject fc owner rule what = do
  site <- siteAt fc
  rejectWith (MkRefusal (Refusal rule) site (owner ++ ": " ++ what))

||| A user error by a rule a registry row names, of whatever category the
||| row's rule is: as `reject` refuses.
export
refuse : {auto s : Ref TState TS} -> FC -> String -> SomeRule -> String -> Front a
refuse fc owner rule what = do
  site <- siteAt fc
  rejectWith (MkRefusal rule site (owner ++ ": " ++ what))

||| A compiler bug, not the user's: Idris's own error for one, which the
||| frontend's exit status tells apart from every error of the program.
export
internal : RunsCore m => FC -> String -> m a
internal fc msg = core (throw (InternalError (show fc ++ ": internal error: " ++ msg)))

||| The definition the frozen context gives a name, as it was read once
||| (`Defined`); nothing for a name the context defines as nothing, a
||| probe's among them. Every definition the translation can meet was read
||| from its entry (`Boundary.readProgram`), so one the context defines and
||| the reading missed is the compiler's error.
export
defined : Name -> Front (Maybe Defined)
defined n = reading >>= \r => core (definedIn r n)

||| A name with every part full, as the frozen context names it: a
||| resolved name is the full name of the definition at its entry.
export
fullName : Name -> Front Name
fullName n = (\r => fullNameIn r.frozen n) <$> reading

||| A term with every name in it full (`fullName`).
export
fullTerm : Core.TT.Term.Term vs -> Front (Core.TT.Term.Term vs)
fullTerm tm = (\r => fullNamesIn r.frozen tm) <$> reading

||| Whether a name is the type of Idris's `%pair`, as the frozen context's
||| options name it, both names full.
export
pairTyped : Name -> Front Bool
pairTyped n = do
  r <- reading
  pure (case pairnames (options (defsOf r.frozen)) of
          Nothing => False
          Just ns => fullNameIn r.frozen n == fullNameIn r.frozen (pairType ns))

||| Runs one check, or translates one part, of the program so that its
||| refusal does not stop the others: the part's refusal, recorded once
||| however many parts find it, or else the error Idris raised, and the part
||| gives nothing. The compiler's own error still ends the run, since
||| nothing after it can be trusted.
export
noting : {auto s : Ref TState TS} -> Front a -> Core (Maybe a)
noting part = do
  r <- Core.map (.reads) (get TState)
  outcome <- catch (Core.map Right (runFront part r)) $ \err => case err of
               InternalError _ => throw err
               _ => Core.pure (Left err)
  case outcome of
    Right (Right x) => Core.pure (Just x)
    Right (Left r) => recordIt (Refused r)
    Left err => recordIt (ByIdris err)
  where
    -- Two refusals are one when they are equal, by value. An error of
    -- Idris's has no equality, and no print stands for one: each is
    -- recorded where a part finds it.
    same : Rejection -> Rejection -> Bool
    same (Refused r) (Refused r') = r == r'
    same _ _ = False

    recordIt : Rejection -> Core (Maybe a)
    recordIt found = do
      update TState { rejected $= \rs => if any (same found) rs then rs else rs :< found }
      Core.pure Nothing

||| A check run as `noting` runs it, for what it finds alone.
export
noted : {auto s : Ref TState TS} -> Front () -> Core ()
noted check = ignore (noting check)

||| The rejections recorded so far, the first found first.
export
rejections : {auto s : Ref TState TS} -> Core (List Rejection)
rejections = pure ((!(get TState)).rejected <>> [])

||| A table of modules with some modules added, each given with where Idris
||| found it: its origin, the registry's classification of its home and
||| path; its source file, which only the project's modules have; and its
||| printed name, read here once for every module the table is built over,
||| so that no location searches for its module where it is met. A module
||| the table holds is not read again.
export
modulesOf : {auto c : Ref Ctxt Defs} -> Modules -> List (ModuleIdent, Home) -> Core Modules
modulesOf ms [] = pure ms
modulesOf ms ((m, home) :: rest) = case lookup m ms of
  Just _ => modulesOf ms rest
  Nothing => do
    file <- case home of
              Project => moduleSource EmptyFC m
              _ => pure Nothing
    modulesOf (insert m (MkLoadedModule (moduleOrigin home (modulePath m)) file (shown (show m))) ms) rest

||| The module a site is in, when it is in one: a package file and no
||| location are in none.
export
siteModule : NonEmptyFC -> Maybe ModuleIdent
siteModule (PhysicalIdrSrc ident, _, _) = Just ident
siteModule _ = Nothing

||| A span of a module as a Core location, what the module is read from a
||| table; nothing for a module the table lacks.
inModule : Modules -> ModuleIdent -> Span -> Maybe Loc
inModule ms ident sp = (\m => MkLoc m.origin (InModule m.printed m.source sp)) <$> lookup ident ms

||| An Idris location as a Core location, what its module is read from a
||| table; nothing for a module the table lacks. A package file is in no
||| module, and code at no location is generated.
located : Modules -> FC -> Maybe Loc
located ms (MkFC (PhysicalIdrSrc ident) (sl, sc) (el, ec)) = inModule ms ident (MkSpan sl sc el ec)
located ms (MkVirtualFC (PhysicalIdrSrc ident) (sl, sc) (el, ec)) = inModule ms ident (MkSpan sl sc el ec)
located ms (MkFC (PhysicalPkgSrc file) (sl, sc) (el, ec)) = Just (MkLoc Generated (InPackage file (MkSpan sl sc el ec)))
located ms _ = Just noLoc

||| An Idris location as a Core location, what its module is read from the
||| session's table (`TS.modules`). A location Idris gives a term is in the
||| module that term was elaborated in, which the session loaded to hold
||| the term, and the frontend locates its own refusals in the modules it
||| reads: a location outside the table is the compiler's error.
export
toLoc : RunsCore m => {auto s : Ref TState TS} -> FC -> m Loc
toLoc fc = core $ do
  st <- get TState
  case located st.modules fc of
    Just loc => Core.pure loc
    Nothing => internal fc "a location in a module the session did not load"

||| A refusal as the module of a refused program carries it, its site's
||| module read from a table built over every refusal's module
||| (`Driver.refusing`), the modules Idris could not load among them.
export
moduleRefusal : Modules -> SomeRule -> NonEmptyFC -> String -> Core ModuleRefusal
moduleRefusal ms rule site message = case located ms (justFC site) of
  Just loc => pure (MkModuleRefusal rule loc message)
  Nothing => internal (justFC site) "a refusal in a module its table was not built over"
