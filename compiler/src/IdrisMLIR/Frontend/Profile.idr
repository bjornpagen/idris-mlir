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

import IdrisMLIR.Frontend.Resolve
import IdrisMLIR.Frontend.Translate
import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.Registry
import IdrisMLIR.Registry.Libraries
import IdrisMLIR.Rule
import IdrisMLIR.Types

import Data.List
import Data.Maybe
import Data.SortedMap
import Data.SortedSet
import Data.String
import System.File

%default covering

------------------------------------------------------------------------------
-- Hooks and definitions
------------------------------------------------------------------------------

||| The rule under which the registry forbids a definition or spelling in the
||| user's code, if it does.
forbiddenBy : List Hook -> Maybe Rule
forbiddenBy [] = Nothing
forbiddenBy (Forbidden rule :: _) = Just rule
forbiddenBy (_ :: hs) = forbiddenBy hs

||| What a refusal of a forbidden definition says. Threads, finalizers and
||| raw pointers name why they are outside the language; every other
||| forbidden definition is a use of it.
exclusion : Rule -> String -> String
exclusion Threads n = n ++ " starts a thread, which is outside the language this compiler implements"
exclusion Finalizer n = n ++ " registers a collector finalizer, which is outside the language this compiler implements"
exclusion RawPointer n = n ++ " is a raw pointer, which is outside the language this compiler implements"
exclusion _ n = "uses " ++ n

||| The first of the definitions a user definition refers to that the
||| registry forbids in the user's code, with its rule.
firstForbidden : List Name -> Maybe (Name, Rule)
firstForbidden [] = Nothing
firstForbidden (r :: rs) = case forbiddenBy (hooksOf r) of
  Just rule => Just (r, rule)
  Nothing => firstForbidden rs

||| Idris-generated auxiliary definitions belong to their enclosing definition.
enclosing : Name -> Name
enclosing (NS ns (CaseBlock outer _)) = NS ns (UN (Basic (strip outer)))
  where
    strip : String -> String
    strip s = if isPrefixOf "case block in " s then strip (assert_smaller s (substr 14 (length s) s))
              else if isPrefixOf "with block in " s then strip (assert_smaller s (substr 14 (length s) s))
              else s
enclosing (NS ns (WithBlock outer _)) = NS ns (UN (Basic outer))
enclosing n = n

------------------------------------------------------------------------------
-- Imports
------------------------------------------------------------------------------

||| The modules a user module's source imports, with the location of each
||| `import`, where an error about it is reported.
export
imports : ModuleIdent -> String -> Core (List (String, FC))
imports ident path = do
  Right text <- coreLift (readFile path)
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

||| Lexes a user module's source with Idris's lexer and rejects a pragma
||| the elaborator has not already discharged.
export
checkPragmas : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
               ModuleIdent -> String -> Core ()
checkPragmas ident path = do
  Right text <- coreLift (readFile path)
    | Left err => throw (FileErr path err)
  case lex text of
    Left (_, l, col, _) =>
      reject (MkFC (PhysicalIdrSrc ident) (l, col) (l, col)) (show ident) UserPragma
             "the source could not be lexed"
    Right (_, toks) => traverse_ check toks
  where
    at : WithBounds Token -> FC
    at tok = let b = tok.bounds in
             MkFC (PhysicalIdrSrc ident) (b.startLine, b.startCol) (b.endLine, b.endCol)
    ||| An escape hatch in the source: a spelling the registry forbids. Idris
    ||| reduces `prim__believe_me` applied to a value during elaboration, so
    ||| it can vanish from TT.
    spelled : WithBounds Token -> String -> Core ()
    spelled tok n = case forbiddenBy (hooks (Spelling n)) of
      Just rule => reject (at tok) (show ident) rule ("the escape hatch " ++ n)
      Nothing => pure ()
    check : WithBounds Token -> Core ()
    check tok = case tok.val of
      Pragma p => unless (elem p discharged) $
                    reject (at tok) (show ident) UserPragma ("the pragma %" ++ p)
      HoleIdent h => reject (at tok) (show ident) EscapeHatch ("the hole ?" ++ h)
      Ident n => spelled tok n
      DotSepIdent _ n => spelled tok n
      _ => pure ()

------------------------------------------------------------------------------
-- Reachability and escape hatches
------------------------------------------------------------------------------

||| Does a term contain the `%MkWorld` literal?
mentionsWorld : Term vars -> Bool
mentionsWorld (PrimVal _ WorldVal) = True
mentionsWorld (Bind _ _ b sc) = mentionsWorld (binderType b) || mentionsWorld sc ||
                                (case b of
                                   Let _ _ v _ => mentionsWorld v
                                   _ => False)
mentionsWorld (App _ f a) = mentionsWorld f || mentionsWorld a
mentionsWorld (TDelay _ _ t a) = mentionsWorld a
mentionsWorld (TForce _ _ t) = mentionsWorld t
mentionsWorld _ = False

treeMentionsWorld : CaseTree vars -> Bool
treeMentionsWorld (Case _ _ _ alts) = any alt alts
  where
    alt : CaseAlt vs -> Bool
    alt (ConCase _ _ _ t) = treeMentionsWorld t
    alt (DelayCase _ _ t) = treeMentionsWorld t
    alt (ConstCase _ t) = treeMentionsWorld t
    alt (DefaultCase t) = treeMentionsWorld t
treeMentionsWorld (STerm _ t) = mentionsWorld t
treeMentionsWorld _ = False

||| What a definition refers to, with the metavariables its body mentions:
||| the translation follows a solved one to its solution.
refsOf : GlobalDef -> List Name
refsOf def =
  let fromType = keys (getRefs (UN (Basic "")) (type def)) in
  case definition def of
    PMDef _ _ tree _ _ => fromType ++ keys (getRefs (UN (Basic "")) tree) ++ keys (getMetas tree)
    TCon _ _ _ _ _ cons _ => fromType ++ fromMaybe [] cons
    _ => fromType

||| Walks everything reachable from the roots, at runtime or compile time, and
||| checks escape hatches, what trusted modules admit and what the user may
||| not call. Errors name the path from the nearest user definition.
export
checkReachable : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
                 FC -> List Name -> Core ()
checkReachable fc roots = go empty (map (\r => (r, [], False)) roots)
  where
    userFC : List (Name, FC) -> FC
    userFC [] = fc
    userFC ((_, f) :: _) = f

    via : List (Name, FC) -> String
    via [] = ""
    via path = " (reached through " ++ joinBy " -> " (map (show . fst) (reverse path)) ++ ")"

    go : SortedSet String -> List (Name, List (Name, FC), Bool) -> Core ()
    go seen [] = pure ()
    go seen ((n, path, fromTrusted) :: rest) = do
      defs <- get Ctxt
      Just def <- lookupCtxtExact n (gamma defs)
        | Nothing => go seen rest
      let full = fullname def
      let key = show full
      if contains key seen then go seen rest else do
        -- Where the definition comes from, as the registry classifies it.
        loc <- toLoc (location def)
        let origin = loc.origin
        let trusted = covers Trusted origin
        -- Primitives have no location; errors name the user definition.
        let here = if trusted || isNothing (isNonEmptyFC (location def)) then path else (full, location def) :: path
        let owner = case here of
                      ((u, _) :: _) => show u
                      [] => key
        -- A trusted library may load a module outside the table (base's
        -- `Data.IORef` loads `System.Concurrency`); what decides is whether
        -- the program reaches it.
        case origin of
          Untrusted => reject (userFC path) (maybe key (show . fst) (head' path)) TrustedLibrary
                         (key ++ " is in " ++ show loc.place ++ ", which is not a trusted library module" ++ via path)
          _ => pure ()
        -- Threads, finalizers and raw pointers are outside the language
        -- wherever they are reached. The world's forbidden operations are
        -- not: the program root is one, and user code is refused where it
        -- names them.
        case forbiddenBy (hooksOf full) of
          Just Threads => reject (userFC here) owner Threads (exclusion Threads key ++ via here)
          Just Finalizer => reject (userFC here) owner Finalizer (exclusion Finalizer key ++ via here)
          Just RawPointer => reject (userFC here) owner RawPointer (exclusion RawPointer key ++ via here)
          _ => pure ()
        -- A deprecated name is rejected wherever it is reached. The hook's
        -- text names the replacement.
        case deprecatedOf (hooksOf full) of
          Just msg => reject (userFC here) owner Deprecated msg
          Nothing => pure ()
        -- A trusted library may crash with a string. The reach has to come
        -- from a trusted definition: a user's call of the same function is
        -- still an escape hatch, and believe_me stays one either way.
        let libraryCrash = fromTrusted && libraryCrashOf (hooksOf full)
        let builtinCrash = fromTrusted && case definition def of
                                            Builtin Crash => True
                                            _ => False
        when (isEscapeHatch def) $
          unless (libraryCrash || builtinCrash) $
            reject (userFC here) owner EscapeHatch ("the escape hatch " ++ key ++ via here)
        case definition def of
          Builtin BelieveMe => reject (userFC here) owner EscapeHatch ("believe_me" ++ via here)
          Builtin Crash => unless fromTrusted $
            reject (userFC here) owner EscapeHatch ("idris_crash" ++ via here)
          Hole {} => reject (userFC here) owner EscapeHatch ("the hole " ++ key ++ via here)
          -- Only the IO primitives the registry lists may be reached: an
          -- `%extern` one by its name, a `%foreign` one by its spec.
          ExternDef _ =>
            unless (isJust (ioCallOf (hooksOf full)) || isJust (arrayCallOf (hooksOf full)) ||
                    isJust (systemFactOf (hooksOf full))) $
              reject (userFC here) owner EscapeHatch ("%extern " ++ key ++ via here)
          ForeignDef _ specs => case foreignHookOf full specs of
            Just (Right (Deprecated msg)) => reject (userFC here) owner Deprecated msg
            Just (Right _) => pure ()
            Just (Left wrong) => reject (userFC here) key HookShape wrong
            Nothing => reject (userFC here) owner EscapeHatch ("%foreign " ++ key ++ via here)
          _ => pure ()
        -- A trusted module admits only some of its definitions.
        when (trusted && not (admits origin (qname (enclosing full)))) $
          reject (userFC here) owner TrustedLibrary (key ++ " is not admitted from its trusted module" ++ via here)
        refs <- traverse toFullNames (refsOf def)
        -- User code may not use what the registry forbids, nor forge a world.
        unless trusted $ do
          case firstForbidden refs of
            Just (r, rule) => reject (location def) key rule (exclusion rule (show r))
            Nothing => pure ()
          case definition def of
            PMDef _ _ tree _ _ =>
              when (treeMentionsWorld tree) $ reject (location def) key WorldUse "uses %MkWorld"
            _ => pure ()
        -- A library's own totality assertions are trusted.
        let refs' = if trusted then filter (not . assertion . qname) refs else refs
        go (insert key seen) (rest ++ map (\r => (r, here, trusted)) refs')
