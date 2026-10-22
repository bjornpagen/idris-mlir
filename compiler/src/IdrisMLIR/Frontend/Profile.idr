-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Profile rules checked on checked TT and on the source: pragmas, escape
||| hatches, trusted modules. The rest is checked during translation. Which
||| modules are trusted, what they admit and which definitions are escape
||| hatches the user may not use is the registry's knowledge; this module
||| asks it.
module IdrisMLIR.Frontend.Profile

import Core.Case.CaseTree
import Core.Context
import Core.Core
import Core.Directory
import Core.TT
import Libraries.Data.NameMap
import Libraries.Text.Bounded
import Libraries.Text.Lexer.Tokenizer
import Parser.Lexer.Source

import IdrisMLIR.Dialect.Idr
import IdrisMLIR.Frontend.Resolve
import IdrisMLIR.Frontend.Walk
import IdrisMLIR.Frontend.Translate
import IdrisMLIR.Frontend.Translate.Closed
import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.Proof.Requests
import IdrisMLIR.Registry
import IdrisMLIR.Registry.Libraries
import IdrisMLIR.Spec.Core.Rules
import IdrisMLIR.Spec.Grades.Grade
import IdrisMLIR.Types

import Control.WellFounded
import Data.DPair
import Data.List
import Data.Buffer
import Data.Maybe
import Data.Nat
import Data.SnocList
import Data.SortedMap
import Data.SortedSet
import Data.String
import System.File
import System.File.Buffer

%default total

------------------------------------------------------------------------------
-- Hooks and definitions
------------------------------------------------------------------------------

||| What refusing a definition a rule forbids says of it, by its name, for a
||| rule that puts it outside the language wherever the program reaches it:
||| threads, finalizers, raw memory, signals and processes. Nothing for the
||| other rules, which forbid only what user code names (`firstForbidden`).
outsideLanguage : SomeRule -> Maybe (String -> String)
outsideLanguage rule = (\why, n => n ++ " " ++ why ++ " outside the language this compiler implements") <$> reason rule
  where
    reason : SomeRule -> Maybe String
    reason (Refusal Threads) = Just "starts or coordinates threads (a mutex, a channel), which are"
    reason (Refusal Finalizer) = Just "registers a collector finalizer, which is"
    reason (Refusal RawPointer) = Just "allocates raw memory, which is"
    reason (Refusal Signal) = Just "handles or sends a signal, which is"
    reason (Refusal Process) = Just "runs another process, which is"
    reason _ = Nothing

||| What a refusal of a forbidden definition says: why it is outside the
||| language, or that it is a use of it.
exclusion : SomeRule -> String -> String
exclusion rule n = maybe ("uses " ++ n) (\says => says n) (outsideLanguage rule)

||| Does a hook answer for every call of a definition, so that its body is
||| never translated, and the growth check reads no site in it? The
||| identity on its runtime argument and a function of the array language,
||| at any arity (a call below it is a closure over the saturated call).
export
answersForCalls : Hooks -> Bool
answersForCalls hs = hs.identityOnLast || isJust hs.generating

||| Does a hook answer for a definition's body, so that the walk of what the
||| program reaches does not check it (`refsOf`)? One that answers for every
||| call (`answersForCalls`), and the exit, whose body is translated, with
||| its `believe_me` as an action that does not return: the escape hatch in
||| each body is the hook's, not the program's.
answersForBody : Hooks -> Bool
answersForBody hs = answersForCalls hs || isJust hs.exits

||| The first of the definitions a user definition refers to that the
||| registry forbids in the user's code, with its rule.
firstForbidden : List Name -> Maybe (Name, SomeRule)
firstForbidden [] = Nothing
firstForbidden (r :: rs) = case (hooksOf r).forbidden of
  Just rule => Just (r, rule)
  Nothing => firstForbidden rs

------------------------------------------------------------------------------
-- Imports
------------------------------------------------------------------------------

||| A text file's contents, read at once as the bytes its size gives: a
||| source file is what it holds when it is read. Reading line by line until
||| the end would not end on a file that has none.
export
readText : String -> Core (Either FileError String)
readText path = coreLift $ do
  Right buf <- createBufferFromFile path
    | Left err => pure (Left err)
  size <- rawSize buf
  Right <$> getString buf 0 size

||| The modules a user module's source imports, with the location of each
||| `import`, where an error about it is reported.
export
imports : ModuleIdent -> String -> Core (List (String, FC))
imports ident path = do
  Right text <- readText path
    | Left _ => pure []
  pure (go 0 (lines text))
  where
    imported : List String -> Maybe String
    imported ("public" :: n :: _) = Just n
    imported (n :: _) = Just n
    imported [] = Nothing
    go : Int -> List String -> List (String, FC)
    go i [] = []
    go i (l :: ls) = case words l of
      ("import" :: rest) => case imported rest of
        Just n => (n, MkFC (PhysicalIdrSrc ident) (i, 0) (i, cast (length l))) :: go (i + 1) ls
        Nothing => go (i + 1) ls
      _ => go (i + 1) ls

------------------------------------------------------------------------------
-- Pragmas
------------------------------------------------------------------------------

||| Pragmas the pinned elaborator has already discharged before this
||| backend sees the term. `%default` is the totality it requires.
||| `%hide` and `%unhide` resolve names. `%logging` is the driver's log.
||| The token is not a second copy of any of those.
discharged : List String
discharged = ["default", "hide", "unhide", "logging"]

||| Lexes a user module's source with Idris's lexer and rejects each pragma
||| the elaborator has not already discharged, and each escape hatch
||| spelled, every one where it is written.
export
checkPragmas : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
               ModuleIdent -> String -> Core ()
checkPragmas ident path = do
  Right text <- readText path
    | Left err => throw (FileErr path err)
  case lex text of
    Left (_, l, col, _) =>
      reject (MkFC (PhysicalIdrSrc ident) (l, col) (l, col)) (show ident) UserPragma
             "the source could not be lexed"
    Right (_, toks) => traverse_ (noted . check) toks
  where
    at : Located Token -> FC
    at tok = let b = tok.bounds in
             MkFC (PhysicalIdrSrc ident) (b.startLine, b.startCol) (b.endLine, b.endCol)
    ||| An escape hatch found here is this module's: what reaches it in TT
    ||| is not reported again (`checkReachable`).
    found : String -> Core ()
    found n = update TState { spelled $= insert (ident, n) }
    ||| An escape hatch in the source: a spelling the registry forbids. Idris
    ||| reduces `prim__believe_me` applied to a value during elaboration, so
    ||| it can vanish from TT.
    spelled : Located Token -> String -> Core ()
    spelled tok n = case (hooks (Spelling n)).forbidden of
      Just rule => do
        found n
        refuse (at tok) (show ident) rule ("the escape hatch " ++ n)
      Nothing => pure ()
    check : Located Token -> Core ()
    check tok = case tok.val of
      Pragma p => unless (elem p discharged) $
                    reject (at tok) (show ident) UserPragma ("the pragma %" ++ p)
      HoleIdent h => do
        found h
        reject (at tok) (show ident) EscapeHatch ("the hole ?" ++ h)
      Ident n => spelled tok n
      DotSepIdent _ n => spelled tok n
      _ => pure ()

------------------------------------------------------------------------------
-- Reachability and escape hatches
------------------------------------------------------------------------------

||| Does a term contain the `%MkWorld` literal?
mentionsWorld : Term vars -> Bool
mentionsWorld (PrimVal _ WorldVal) = True
mentionsWorld (Bind _ _ b sc) = binder b || mentionsWorld sc
  where
    -- A binder's type, and a `let`'s value after it.
    binder : Binder (Term vs) -> Bool
    binder (Lam _ _ _ ty) = mentionsWorld ty
    binder (Let _ _ v ty) = mentionsWorld ty || mentionsWorld v
    binder (Pi _ _ _ ty) = mentionsWorld ty
    binder (PVar _ _ _ ty) = mentionsWorld ty
    binder (PLet _ _ _ ty) = mentionsWorld ty
    binder (PVTy _ _ ty) = mentionsWorld ty
mentionsWorld (App _ f a) = mentionsWorld f || mentionsWorld a
mentionsWorld (TDelay _ _ t a) = mentionsWorld a
mentionsWorld (TForce _ _ t) = mentionsWorld t
mentionsWorld _ = False

mutual
  treeMentionsWorld : CaseTree vars -> Bool
  treeMentionsWorld (Case _ _ _ alts) = altsMentionWorld alts
  treeMentionsWorld (STerm _ t) = mentionsWorld t
  treeMentionsWorld _ = False

  altsMentionWorld : List (CaseAlt vars) -> Bool
  altsMentionWorld [] = False
  altsMentionWorld (ConCase _ _ _ t :: alts) = treeMentionsWorld t || altsMentionWorld alts
  altsMentionWorld (DelayCase _ _ t :: alts) = treeMentionsWorld t || altsMentionWorld alts
  altsMentionWorld (ConstCase _ t :: alts) = treeMentionsWorld t || altsMentionWorld alts
  altsMentionWorld (DefaultCase t :: alts) = treeMentionsWorld t || altsMentionWorld alts

||| What a definition refers to, with the metavariables its body mentions:
||| the translation follows a solved one to its solution. Of a definition
||| whose hook answers for its body, only the type.
||| Whether a name is a definition of quantity 0, which exists for the
||| type checker alone and never runs.
proofOnly : {auto c : Ref Ctxt Defs} -> Name -> Core Bool
proofOnly n = do
  defs <- get Ctxt
  Just def <- lookupCtxtExact n (gamma defs)
    | Nothing => pure False
  pure (isErased (multiplicity def))

refsOf : Hooks -> GlobalDef -> List Name
refsOf hs def =
  let fromType = keys (Core.TT.getRefs (UN (Basic "")) (type def)) in
  case definition def of
    PMDef _ _ tree _ _ =>
      if answersForBody hs then fromType
      else fromType ++ keys (Core.Case.CaseTree.getRefs (UN (Basic "")) tree) ++ keys (Core.Case.CaseTree.getMetas tree)
    TCon _ _ _ _ _ cons _ => fromType ++ fromMaybe [] cons
    _ => fromType

||| What refers to a definition the walk reaches: a user definition, or the
||| program's root; or a trusted definition, by its placement, which the
||| walk enters once, for whichever user definition reaches it first.
data Referrer = User | Library Placement

||| A definition the walk of what the roots reach is to check: its name, the
||| path from the user definition that reaches it, the nearest first, each
||| definition on it with its address and its location, and what refers to
||| it.
record Reach where
  constructor MkReach
  name : Name
  path : List (Name, Address, FC)
  from : Referrer

||| Does a trusted definition refer to the one reached?
byLibrary : Referrer -> Bool
byLibrary User = False
byLibrary (Library _) = True

||| What the walk keeps besides what it has entered: the rejected
||| definitions reported, each with the user definition it was reported
||| for; every reach of each trusted definition, by its address, the first
||| and those after it was entered; and every reach of a rejected
||| definition. A trusted definition is walked once, so a user definition
||| that reaches it after the first is behind whatever its walk rejected
||| all the same: the reaches of the trusted definitions say who is.
record Kept where
  constructor MkKept
  reported : SortedSet (Address, Address)
  arrivals : SortedMap Address (List Reach)
  refusals : List Reach

||| A walk ended: what it entered, and what it kept.
record Ended where
  constructor MkEnded
  entered : Walked
  kept : Kept

||| What a level of the walk has found for the next: nothing yet, or the
||| definitions found, once one was entered into the walk since the level
||| began (`w0`), which leaves fewer to enter.
data Pending : (w0, w : Walked) -> Type where
  Idle : Pending w0 w
  Queued : (0 _ : Smaller w w0) -> SnocList Reach -> Pending w0 w

||| The definitions found for the next level so far.
queued : Pending w0 w -> SnocList Reach
queued Idle = [<]
queued (Queued _ next) = next

||| Walks everything reachable from the roots, at runtime or compile time, and
||| checks escape hatches, what trusted modules admit and what the user may
||| not call. Errors name the path from the nearest user definition. Every
||| user definition that reaches a rejected definition is reported, each
||| once, and the walk goes on without what the rejected definition refers
||| to: whatever that reaches is reached through the rejection, and is
||| reported once it is fixed, so that every rejection found is
||| independent of the others. An escape hatch the source of the user
||| definition's module spells was reported there, by `checkPragmas`, and
||| is not reported again. The definitions rejected, the user definitions
||| an error names and those that refer to them are `refused`: the
||| translation leaves them out.
export
checkReachable : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
                 FC -> List Name -> Core ()
checkReachable fc roots = do
  MkEnded end kept <- level start (sizeAccessible start) start (noMore start) (MkKept empty empty [])
                            (map (\r => MkReach r [] User) roots) Idle
  -- Each rejected definition again, as every user definition behind its
  -- reach reaches it, which reports it for each of them once.
  behind <- traverse (\r => map (\u => MkReach r.name u r.from)
                                <$> usersBehind kept.arrivals start (sizeAccessible start) [r])
                     kept.refusals
  ignore (level end (sizeAccessible end) end (noMore end) kept (behind >>= id) Idle)
  where
    userFC : List (Name, Address, FC) -> FC
    userFC [] = fc
    userFC ((_, _, f) :: _) = f

    -- The module a location is in; a package file and no location are in
    -- none.
    moduleOf : FC -> Maybe ModuleIdent
    moduleOf (MkFC (PhysicalIdrSrc ident) _ _) = Just ident
    moduleOf (MkVirtualFC (PhysicalIdrSrc ident) _ _) = Just ident
    moduleOf _ = Nothing

    via : List (Name, Address, FC) -> String
    via [] = ""
    via path = " (reached through " ++ joinBy " -> " (map (show . fst) (reverse path)) ++ ")"

    -- One definition, from where the registry says it comes, reached by
    -- the path, and `here` the path from it and `owner` the user
    -- definition an error names: what it refers to, each with the path
    -- that reaches it, or the definition's rejection.
    visit : GlobalDef -> Placement -> Loc -> (here : List (Name, Address, FC)) -> (owner : String) ->
            (path : List (Name, Address, FC)) -> (from : Referrer) ->
            Core (List Reach)
    visit def placement loc here owner path from = do
      let full = fullname def
      let key = show full
      let origin = loc.origin
      let trusted = covers Trusted origin
      -- A trusted library may load a module outside the table (base's
      -- `Data.IORef` loads `System.Concurrency`); what decides is whether
      -- the program reaches it.
      case origin of
        Untrusted => reject (userFC path) (maybe key (show . fst) (head' path)) TrustedLibrary
                       (key ++ " is in " ++ maybe "" show (locModule loc) ++ ", which is not a trusted library module" ++
                        via path)
        _ => pure ()
      -- Threads, finalizers, raw memory, signals and processes are
      -- outside the language wherever they are reached. The world's
      -- forbidden operations are not: the program root is one, and user
      -- code is refused where it names them.
      case (hooksOf full).forbidden >>= \rule => (rule,) <$> outsideLanguage rule of
        Just (rule, says) => reject (userFC here) owner rule (says key ++ via here)
        Nothing => pure ()
      -- A deprecated name is rejected wherever it is reached. The hook's
      -- text names the replacement.
      case (hooksOf full).deprecated of
        Just msg => reject (userFC here) owner Deprecated msg
        Nothing => pure ()
      -- A trusted library may crash with a string. The reach has to come
      -- from a trusted definition: a user's call of the same function is
      -- still an escape hatch, and believe_me stays one either way.
      let libraryCrash = byLibrary from && (hooksOf full).libraryCrash
      let builtinCrash = byLibrary from && case definition def of
                                          Builtin Crash => True
                                          _ => False
      when (isEscapeHatch def) $
        unless (libraryCrash || builtinCrash) $
          reject (userFC here) owner EscapeHatch ("the escape hatch " ++ key ++ via here)
      case definition def of
        Builtin BelieveMe => reject (userFC here) owner EscapeHatch ("believe_me" ++ via here)
        Builtin Crash => unless (byLibrary from) $
          reject (userFC here) owner EscapeHatch ("idris_crash" ++ via here)
        Hole {} => reject (userFC here) owner EscapeHatch ("the hole " ++ key ++ via here)
        -- Only the declarations the registry gives a meaning may be
        -- reached: an `%extern` one by its name, a `%foreign` one by its
        -- spec.
        ExternDef _ =>
          unless (meansExtern (hooksOf full)) $
            reject (userFC here) owner EscapeHatch ("%extern " ++ key ++ via here)
        ForeignDef _ specs => do
          site <- siteAt (userFC here)
          case foreignHookOf site owner (via here) full specs of
            Right hs => case hs.deprecated of
              Just msg => reject (userFC here) owner Deprecated msg
              Nothing => pure ()
            Left r => rejectWith r
        _ => pure ()
      -- A trusted module admits only some of its definitions, and a block
      -- Idris made of one with it.
      root <- rootOf full
      when (trusted && not (admits origin (qname root))) $
        reject (userFC here) owner TrustedLibrary (key ++ " is not admitted from its trusted module" ++ via here)
      refs <- traverse toFullNames (refsOf (hooksOf full) def)
      -- User code may not use what the registry forbids, nor forge a world.
      unless trusted $ do
        case firstForbidden refs of
          Just (r, rule) => refuse (location def) key rule (exclusion rule (show r))
          Nothing => pure ()
        case definition def of
          PMDef _ _ tree _ _ =>
            when (treeMentionsWorld tree) $ reject (location def) key TrustedLibrary "uses %MkWorld"
          _ => pure ()
      -- A library's own totality assertions are trusted, and so are its
      -- proofs: a definition of quantity 0 (the `0 lemma` of a where block,
      -- which base's Fin literals prove their bound by) never runs, so
      -- nothing it reaches is the program's. A user's is walked, since a
      -- proof it forges is a bound the compiler would trust.
      refs' <- if trusted
                 then filterM (\r => not <$> proofOnly r) (filter (not . assertion . qname) refs)
                 else pure refs
      pure (map (\r => MkReach r here (if trusted then Library placement else User)) refs')

    -- The definitions to visit, breadth first, so that a path in a message
    -- is a shortest one: a level of the walk, and what its definitions
    -- refer to, the next level, once the level is done. A definition is
    -- entered into the walk (`Walk`) once it is checked and found good, so
    -- the walk is the set of those, and the next level is not empty only
    -- if one was entered in this one: each level starts with fewer
    -- definitions left to enter than the last. A rejected one is not
    -- entered, and is reported for each owner once (`reported`).
    level : (w0 : Walked) -> (0 acc : SizeAccessible w0) -> (w : Walked) -> (0 _ : NoMore w w0) ->
            Kept -> List Reach -> Pending w0 w -> Core Ended
    level w0 acc@(Access rec) w p kept [] Idle = pure (MkEnded w kept)
    level w0 acc@(Access rec) w p kept [] (Queued lt next) =
      level w (rec w lt) w (noMore w) kept (next <>> []) Idle
    level w0 acc@(Access rec) w p kept (r :: rest) pending = do
      -- What tells definitions apart is their place in the context; a
      -- name no definition has is never entered (`Walk`).
      Just (placement, def) <- resolve r.name
        | Nothing => level w0 acc w p kept rest pending
      let full = fullname def
      let key = addressOf placement
      -- Where the definition comes from, as the registry classifies it.
      loc <- toLoc (location def)
      let trusted = covers Trusted loc.origin
      -- Only a trusted definition is walked for a user definition other
      -- than itself: a user definition is the owner of what it reaches.
      let kept' = if trusted then { arrivals $= insertWith (++) key [r] } kept else kept
      -- Primitives have no location; errors name the user definition.
      let here = if trusted || isNothing (isNonEmptyFC (location def))
                   then r.path else (full, key, location def) :: r.path
      let owner = maybe full fst (head' here)
      let ownerKey = maybe key (fst . snd) (head' here)
      let refuse = update TState { refused $= (insert key . insert ownerKey .
                                                maybe id (insert . fst . snd) (head' r.path)) }
      -- Checked and found good already: entered into the walk.
      let Just (Element w1 q) = enter placement w
        | Nothing => level w0 acc w p kept' rest pending
      st <- get TState
      let reach = (key, ownerKey)
      let refusing = { reported $= insert reach, refusals $= (r ::) } kept'
      if contains reach kept'.reported ||
         maybe False (\m => contains (m, nameRoot full) st.spelled) (moduleOf (userFC here))
        then do
          refuse
          level w0 acc w p refusing rest pending
        else do
          Nothing <- noting (visit def placement loc here (show owner) r.path r.from)
            | Just next => level w0 acc w1 (thenNoMore (fewer q) p) kept' rest
                                 (Queued (fewerThen q p) (queued pending <>< next))
          refuse
          level w0 acc w p refusing rest pending

    -- The paths of the user definitions behind reaches: a user
    -- definition's own, and through a trusted definition, those behind
    -- each reach of it, each trusted definition walked back through once.
    usersBehind : SortedMap Address (List Reach) -> (w : Walked) -> (0 _ : SizeAccessible w) ->
                  List Reach -> Core (List (List (Name, Address, FC)))
    usersBehind arrivals w (Access rec) [] = pure []
    usersBehind arrivals w acc@(Access rec) (r :: rest) = case r.from of
      User => (r.path ::) <$> usersBehind arrivals w acc rest
      Library placement => do
        -- Walked back through already, it is not again.
        let Just (Element w' less) = enter placement w
          | Nothing => usersBehind arrivals w acc rest
        let reaches = fromMaybe [] (lookup (addressOf placement) arrivals)
        usersBehind arrivals w' (rec w' less) (reaches ++ rest)
