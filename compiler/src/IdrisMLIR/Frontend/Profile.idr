||| Profile rules checked on checked TT and on the source (docs/architecture/02-profile.md):
||| pragmas (PROF-PRAG-1), escape hatches (PROF-ESC-1), trusted modules
||| (PROF-LIB-1, PROF-IO-3). The rest is checked during translation.
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

import IdrisMLIR.Frontend.Translate

import Data.List
import Data.SortedMap
import Data.SortedSet
import Data.String
import System.File

%default covering

------------------------------------------------------------------------------
-- Modules
------------------------------------------------------------------------------

||| The trusted modules (PROF-PROG-4).
export
trustedModule : List String -> Bool
trustedModule ns = ns == ["Builtin"] || ns == ["PrimIO"] || ns == ["IO", "IdrisMLIR"]

namespaceOf : Name -> List String
namespaceOf (NS ns _) = unsafeUnfoldNamespace ns
namespaceOf _ = []

||| PROF-LIB-1: the admitted definitions of `Builtin` and `PrimIO`.
allowed : List String
allowed =
  [ "Builtin.Unit", "Builtin.MkUnit", "Builtin.Pair", "Builtin.MkPair", "Builtin.fst"
  , "Builtin.snd", "Builtin.Equal", "Builtin.Refl", "Builtin.Void", "Builtin.id"
  , "Builtin.the", "Builtin.delay", "Builtin.force"
  , "PrimIO.IORes", "PrimIO.MkIORes", "PrimIO.PrimIO", "PrimIO.IO", "PrimIO.MkIO"
  , "PrimIO.prim__io_pure", "PrimIO.io_pure", "PrimIO.prim__io_bind", "PrimIO.io_bind"
  , "PrimIO.fromPrim", "PrimIO.toPrim", "PrimIO.unsafePerformIO"
  , "PrimIO.unsafeCreateWorld", "PrimIO.unsafeDestroyWorld" ]

||| PROF-LIB-1: literal elaboration goes through these interfaces of `Builtin`
||| (`%charLit fromChar`, `%stringLit fromString`), with their Char and String
||| implementations; the dictionaries are eliminated like any static record.
allowedPrefixes : List String
allowedPrefixes = ["Builtin.FromChar", "Builtin.fromChar", "Builtin.MkFromChar", "Builtin.FromString", "Builtin.fromString", "Builtin.MkFromString"]

admitted : String -> Bool
admitted n = elem n allowed || any (\p => isPrefixOf p n) allowedPrefixes

||| PROF-IO-3: reachable only through the root.
rootOnly : List String
rootOnly = ["PrimIO.unsafePerformIO", "PrimIO.unsafeCreateWorld", "PrimIO.unsafeDestroyWorld"]

||| Idris-generated auxiliary definitions belong to their enclosing definition.
enclosing : Name -> String
enclosing (NS ns (CaseBlock outer _)) = show (NS ns (UN (Basic (strip outer))))
  where
    strip : String -> String
    strip s = if isPrefixOf "case block in " s then strip (assert_smaller s (substr 14 (length s) s))
              else if isPrefixOf "with block in " s then strip (assert_smaller s (substr 14 (length s) s))
              else s
enclosing (NS ns (WithBlock outer _)) = show (NS ns (UN (Basic outer)))
enclosing n = show n

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
      reject (MkFC (PhysicalIdrSrc ident) (l, col) (l, col)) (show ident) "PROF-PRAG-1"
             "the source could not be lexed"
    Right (_, toks) => traverse_ check toks
  where
    check : WithBounds Token -> Core ()
    check tok = case tok.val of
      Pragma p => do
        let b = tok.bounds
        reject (MkFC (PhysicalIdrSrc ident) (b.startLine, b.startCol) (b.endLine, b.endCol))
               (show ident) "PROF-PRAG-1" ("the pragma %" ++ p)
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
        let here = if trusted then path else (full, location def) :: path
        let owner = case here of
                      ((u, _) :: _) => show u
                      [] => key
        -- PROF-ESC-1
        when (isEscapeHatch def) $
          reject (userFC here) owner "PROF-ESC-1" ("the escape hatch " ++ key ++ via here)
        case definition def of
          Builtin {} => case key of
            "prim__believe_me" => reject (userFC here) owner "PROF-ESC-1" ("believe_me" ++ via here)
            "prim__crash" => reject (userFC here) owner "PROF-ESC-1" ("idris_crash" ++ via here)
            _ => pure ()
          Hole {} => reject (userFC here) owner "PROF-ESC-1" ("the hole " ++ key ++ via here)
          ExternDef _ => reject (userFC here) owner "PROF-ESC-1" ("%extern " ++ key ++ via here)
          ForeignDef _ _ =>
            unless (ns == ["IO", "IdrisMLIR"]) $
              reject (userFC here) owner "PROF-ESC-1" ("%foreign " ++ key ++ via here)
          _ => pure ()
        -- PROF-LIB-1
        when (trusted && ns /= ["IO", "IdrisMLIR"] && not (admitted (enclosing full))) $
          reject (userFC here) owner "PROF-LIB-1" (key ++ " is not admitted from its trusted module" ++ via here)
        -- PROF-IO-3
        unless trusted $ do
          let refs = map show (refsOf def)
          case find (`elem` rootOnly) refs of
            Just r => reject (location def) key "PROF-IO-3" ("uses " ++ r)
            Nothing => pure ()
          case definition def of
            PMDef _ _ tree _ _ =>
              when (treeMentionsWorld tree) $ reject (location def) key "PROF-IO-3" "uses %MkWorld"
            _ => pure ()
        go (insert key seen) (rest ++ map (\r => (r, here)) (refsOf def))
