||| Profile rules checked on checked TT and on the source (docs/architecture/02-profile.md):
||| pragmas (PROF-PRAG-1), escape hatches (PROF-ESC-1), trusted modules
||| (PROF-LIB-1, PROF-IO-3). The rest is checked during translation. Which
||| modules are trusted, what they admit and which definitions are escape
||| hatches the user may not use is the registry's knowledge
||| (docs/architecture/17-registry.md); this module asks it.
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
import IdrisMLIR.Loc
import IdrisMLIR.Registry
import IdrisMLIR.Registry.Libraries
import IdrisMLIR.Rule

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

||| The first of the definitions a user definition refers to that the
||| registry forbids in the user's code, with its rule (PROF-IO-3).
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
-- Imports (PROF-PROG-1, PROF-PROG-4)
------------------------------------------------------------------------------

||| The modules a user module's source imports, with the location of each
||| `import` (PROF-PROG-1, PROF-PROG-4; DIAG-LOC-1).
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
-- Pragmas (PROF-PRAG-1)
------------------------------------------------------------------------------

||| Lexes a user module's source with Idris's lexer and rejects any pragma.
export
checkPragmas : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
               ModuleIdent -> String -> Core ()
checkPragmas ident path = do
  Right text <- coreLift (readFile path)
    | Left err => throw (FileErr path err)
  case lex text of
    Left (_, l, col, _) =>
      reject (MkFC (PhysicalIdrSrc ident) (l, col) (l, col)) (show ident) ProfPrag1
             "the source could not be lexed"
    Right (_, toks) => traverse_ check toks
  where
    at : WithBounds Token -> FC
    at tok = let b = tok.bounds in
             MkFC (PhysicalIdrSrc ident) (b.startLine, b.startCol) (b.endLine, b.endCol)
    ||| PROF-ESC-1 in the source: Idris reduces `prim__believe_me` applied to
    ||| a value during elaboration, so it can vanish from TT.
    escape : String -> Bool
    escape n = elem n (the (List String) ["prim__believe_me", "prim__crash", "believe_me", "idris_crash"])
    check : WithBounds Token -> Core ()
    check tok = case tok.val of
      -- %default only sets the totality Idris requires.
      Pragma "default" => pure ()
      Pragma p => reject (at tok) (show ident) ProfPrag1 ("the pragma %" ++ p)
      HoleIdent h => reject (at tok) (show ident) ProfEsc1 ("the hole ?" ++ h)
      Ident n => when (escape n) $ reject (at tok) (show ident) ProfEsc1 ("the escape hatch " ++ n)
      DotSepIdent _ n => when (escape n) $ reject (at tok) (show ident) ProfEsc1 ("the escape hatch " ++ n)
      _ => pure ()

||| PROF-PRAG-1 over every user module of the program.
export
checkUserModules : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
                   List ModuleIdent -> Core ()
checkUserModules mods = for_ mods $ \ident =>
  unless (trustedModule (unsafeUnfoldModuleIdent ident)) $ do
    path <- nsToSource EmptyFC ident
    checkPragmas ident path

------------------------------------------------------------------------------
-- Reachability (FE-REACH-1) and escape hatches (PROF-ESC-1)
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

refsOf : GlobalDef -> List Name
refsOf def =
  let fromType = keys (getRefs (UN (Basic "")) (type def)) in
  case definition def of
    PMDef _ _ tree _ _ => fromType ++ keys (getRefs (UN (Basic "")) tree)
    TCon _ _ _ _ _ cons _ => fromType ++ fromMaybe [] cons
    _ => fromType

||| Walks everything reachable from the roots, at runtime or compile time, and
||| checks PROF-ESC-1, PROF-LIB-1 and PROF-IO-3. Errors name the path from
||| the nearest user definition.
export
checkReachable : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
                 FC -> List Name -> Core ()
checkReachable fc roots = go empty (map (\r => (r, [])) roots)
  where
    userFC : List (Name, FC) -> FC
    userFC [] = fc
    userFC ((_, f) :: _) = f

    via : List (Name, FC) -> String
    via [] = ""
    via path = " (reached through " ++ joinBy " -> " (map (show . fst) (reverse path)) ++ ")"

    go : SortedSet String -> List (Name, List (Name, FC)) -> Core ()
    go seen [] = pure ()
    go seen ((n, path) :: rest) = do
      defs <- get Ctxt
      Just def <- lookupCtxtExact n (gamma defs)
        | Nothing => go seen rest
      let full = fullname def
      let key = show full
      if contains key seen then go seen rest else do
        let ns = namespaceOf full
        let trusted = trustedModule ns
        -- Primitives have no location; errors name the user definition.
        let here = if trusted || isNothing (isNonEmptyFC (location def)) then path else (full, location def) :: path
        let owner = case here of
                      ((u, _) :: _) => show u
                      [] => key
        -- PROF-ESC-1
        when (isEscapeHatch def) $
          reject (userFC here) owner ProfEsc1 ("the escape hatch " ++ key ++ via here)
        case definition def of
          Builtin {} => case key of
            "prim__believe_me" => reject (userFC here) owner ProfEsc1 ("believe_me" ++ via here)
            "prim__crash" => reject (userFC here) owner ProfEsc1 ("idris_crash" ++ via here)
            _ => pure ()
          Hole {} => reject (userFC here) owner ProfEsc1 ("the hole " ++ key ++ via here)
          ExternDef _ =>
            unless (key == "Prelude.IO.prim__getChar") $
              reject (userFC here) owner ProfEsc1 ("%extern " ++ key ++ via here)
          ForeignDef _ _ =>
            unless (ns == ["IO", "IdrisMLIR"] ||
                    elem key (the (List String) ["Prelude.IO.prim__putStr", "Prelude.IO.prim__putChar",
                                                 "Prelude.IO.prim__getChar"])) $
              reject (userFC here) owner ProfEsc1 ("%foreign " ++ key ++ via here)
          _ => pure ()
        -- PROF-LIB-1
        when (trusted && ns /= ["IO", "IdrisMLIR"] && not (admitted (enclosing full))) $
          reject (userFC here) owner ProfLib1 (key ++ " is not admitted from its trusted module" ++ via here)
        -- PROF-IO-3
        unless trusted $ do
          refs <- traverse (\r => show <$> toFullNames r) (refsOf def)
          case find (`elem` rootOnly) refs of
            Just r => reject (location def) key ProfIO3 ("uses " ++ r)
            Nothing => pure ()
          case definition def of
            PMDef _ _ tree _ _ =>
              when (treeMentionsWorld tree) $ reject (location def) key ProfIO3 "uses %MkWorld"
            _ => pure ()
        -- PROF-ESC-1: a library's own assert_total is trusted.
        refs <- traverse toFullNames (refsOf def)
        let refs' = if trusted then filter (\r => show r /= "Builtin.assert_total") refs else refs
        go (insert key seen) (rest ++ map (\r => (r, here)) refs')
