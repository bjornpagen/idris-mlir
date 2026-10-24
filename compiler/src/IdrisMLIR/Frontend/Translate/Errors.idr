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
import Data.List1
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
||| of the program (`Read`: the context frozen once the program was read,
||| of the definitions the reading met, which every normaliser reads, and
||| those definitions as read once), whose errors are Idris's, giving
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

||| The context the normalisers read: frozen once, from the definitions the
||| program's reading met, and never changed after.
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
typeOfDefinition def = core ((.fst) <$> readTypeOf def)

||| A pattern-matching definition's case tree, read through the context's
||| accessor, as its type is, with the evidence that it is the tree the
||| evaluator walks, which a reading that unfolds the definition carries.
||| The evidence is erased, so a reader that carries none takes the tree
||| alone (`.fst`) at no cost.
export
caseTreeOf : RunsCore m => {args : Scope} -> (body : Body args) -> m (Subset (CaseTree args) (TreeOf body))
caseTreeOf body = core (readTreeOf body)

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
      -- `replace` takes its term once, so it is applied, not composed.
      (\rhs => Just (Builtin.replace {p = Core.TT.Term.Term} (appendNilRightNeutral args) rhs)) <$> leaves.leafTerm {outer = []} r
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

||| Whether a name is the type of Idris's `%pair`, the pair the boundary
||| read (`State.namedAt`), by address.
export
pairTyped : Name -> Front Bool
pairTyped n = (\r => namedAt r.frozen (pairTypeIn r) n) <$> reading

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

||| A module read at the home Idris found it in: its origin, the registry's
||| classification of its home and path; its source file, which only the
||| project's modules have; its printed name.
moduleReadAt : {auto c : Ref Ctxt Defs} -> ModuleIdent -> Home -> Core LoadedModule
moduleReadAt m home = do
  file <- case home of
            Project => moduleSource EmptyFC m
            _ => pure Nothing
  pure (MkLoadedModule (moduleOrigin home (modulePath m)) file (shown (show m)))

||| A module as a table of modules holds it, and the table: what the table
||| holds, or, for a module it lacks, the module read at the home Idris
||| found it in (`moduleReadAt`), added to it.
moduleIn : {auto c : Ref Ctxt Defs} -> Modules -> ModuleIdent -> Home -> Core (Modules, LoadedModule)
moduleIn ms m home = case lookup m ms of
  Just loaded => pure (ms, loaded)
  Nothing => do
    loaded <- moduleReadAt m home
    pure (insert m loaded ms, loaded)

||| A table of modules with some modules added, each given with where Idris
||| found it: its origin, the registry's classification of its home and
||| path; its source file, which only the project's modules have; and its
||| printed name, read here once for every module the table is built over,
||| so that no location searches for its module where it is met. A module
||| the table holds is not read again.
export
modulesOf : {auto c : Ref Ctxt Defs} -> Modules -> List (ModuleIdent, Home) -> Core Modules
modulesOf ms [] = pure ms
modulesOf ms ((m, home) :: rest) = do
  (ms', _) <- moduleIn ms m home
  modulesOf ms' rest

||| A module the session read, as a table of modules holds it, or read at
||| the home Idris found it in (`moduleIn`): what the session recorded of
||| the module is all a table needs to hold it, so no module it read is
||| missing from one.
export
loadedModule : {auto c : Ref Ctxt Defs} -> Modules -> Loaded -> Core LoadedModule
loadedModule ms l = snd <$> moduleIn ms l.ident (homeOf l.foundIn)

||| Where an Idris location is: a span of a module, which a table of the
||| modules locates; or a place in no module, a package file's span, or
||| code at no location, which is generated.
data Placed = InIdrisModule ModuleIdent Span | InNoModule Loc

||| Where an Idris location is (`Placed`).
placed : FC -> Placed
placed (MkFC (PhysicalIdrSrc ident) (sl, sc) (el, ec)) = InIdrisModule ident (MkSpan sl sc el ec)
placed (MkVirtualFC (PhysicalIdrSrc ident) (sl, sc) (el, ec)) = InIdrisModule ident (MkSpan sl sc el ec)
placed (MkFC (PhysicalPkgSrc file) (sl, sc) (el, ec)) = InNoModule (MkLoc Generated (InPackage file (MkSpan sl sc el ec)))
placed _ = InNoModule noLoc

||| The module a site's span is in: one the session read, with where its
||| code comes from and its source, as a table of modules holds them; or
||| one the session never read, by its name alone. Essential: reflection
||| can give a term a location in any module, one the session never loaded
||| among them, and nothing is known of such a module but the name the
||| location gives.
data SiteModule = ReadModule LoadedModule | UnreadModule ModuleIdent

||| A span of a site's module as a Core location. A module the session
||| never read is located as the location gives it, by its name, with no
||| source to show a span of (`InUnreadModule`), and its code is at a
||| location Idris does not have, so it comes from no module the registry
||| classified (`Generated`).
spanIn : SiteModule -> Span -> Loc
spanIn (ReadModule m) sp = MkLoc m.origin (InModule m.printed m.source sp)
spanIn (UnreadModule ident) sp = MkLoc Generated (InUnreadModule (shown (show ident)) sp)

||| An Idris location as a Core location, its module read from the
||| session's table (`TS.modules`), which holds every module the session
||| loaded: a location in a module the table lacks is in one the session
||| never read (`UnreadModule`).
export
toLoc : RunsCore m => {auto s : Ref TState TS} -> FC -> m Loc
toLoc fc = core $ do
  st <- get TState
  Core.pure (case placed fc of
               InIdrisModule ident sp => spanIn (maybe (UnreadModule ident) ReadModule (lookup ident st.modules)) sp
               InNoModule loc => loc)

||| What a module a refusal's site is in, and the table of modules lacks,
||| is: one Idris found at a home, read there (a build that failed never
||| loaded the module it was elaborating, one of the project's); or, once
||| the table holds every module the session loaded, one it never read.
public export
data Lacked = FoundAt Home | Unloaded

||| A refusal as the module of a refused program carries it, at its site,
||| and the table of modules: the site's module as the table holds it, or,
||| where the table lacks it, as `lacked` says it is (read at its home and
||| added, or never read).
moduleRefusal : {auto c : Ref Ctxt Defs} -> (lacked : ModuleIdent -> Lacked) -> Modules -> SomeRule -> NonEmptyFC ->
                String -> Core (Modules, ModuleRefusal)
moduleRefusal lacked ms rule site message = case placed (justFC site) of
  InIdrisModule ident sp => do
    (ms', m) <- case lookup ident ms of
                  Just held => pure (ms, ReadModule held)
                  Nothing => case lacked ident of
                    FoundAt home => (\loaded => (insert ident loaded ms, ReadModule loaded)) <$> moduleReadAt ident home
                    Unloaded => pure (ms, UnreadModule ident)
    pure (ms', MkModuleRefusal rule (spanIn m sp) message)
  InNoModule loc => pure (ms, MkModuleRefusal rule loc message)

||| The refusals of a refused program as its module carries them, in the
||| order given, each located as `moduleRefusal` locates it, in the table
||| the refusals before it completed.
export
moduleRefusals : {auto c : Ref Ctxt Defs} -> (lacked : ModuleIdent -> Lacked) -> Modules ->
                 List1 (SomeRule, NonEmptyFC, String) -> Core (List1 ModuleRefusal)
moduleRefusals lacked ms ((rule, site, message) ::: rest) = do
  (ms', r) <- moduleRefusal lacked ms rule site message
  (r :::) <$> others ms' rest
  where
    others : Modules -> List (SomeRule, NonEmptyFC, String) -> Core (List ModuleRefusal)
    others ms [] = pure []
    others ms ((rule, site, message) :: rs) = do
      (ms', r) <- moduleRefusal lacked ms rule site message
      (r ::) <$> others ms' rs
