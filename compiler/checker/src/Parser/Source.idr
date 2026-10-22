-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module Parser.Source

import public Parser.Lexer.Source
import public Parser.Rule.Source
import public Parser.Unlit

import Core.Context
import Core.Core
import Core.Name
import Core.Metadata
import Core.FC

import Idris.Syntax.Pragmas
import Idris.Syntax.Tree

import System.File

%default total

lexSource : (origin : OriginDesc) ->
            Maybe LiterateStyle -> Lexer -> String ->
            Either Error (List (Located ()), List (Located RawToken))
lexSource origin lit reject str
    = do str <- mapFst (fromLitError origin) $ unlit lit str
         mapFst (fromLexError origin) $ lexTo reject str

||| The tokens as columns, the identifiers they spell interned: text becomes
||| an identifier here, where a source enters the compiler, so no rule of
||| the grammar interns.
internTokens : {auto c : Ref Ctxt Defs} ->
               List (Located RawToken) -> Core (Tokens Token)
internTokens toks
    = do defs <- get Ctxt
         columns <$> traverse (internToken defs.gamma.idents) toks
  where
    internToken : Ref Interned Idents -> Located RawToken -> Core (Located Token)
    internToken ids tok
        = do val <- traverseIdents @{Applicative.CORE} (internWith ids) tok.val
             pure (MkLocated val tok.bounds)

-- The parse tree a grammar made is frozen and read here, once the parse is
-- done, so the syntax a parse gives is made once, of what it kept.
parseTokens : {0 e : Bool} -> (origin : OriginDesc) ->
              ({0 n : Nat} -> BRule n False e (Read ty)) ->
              List (Located ()) -> Tokens Token ->
              Either Error (List Warning, State, ty)
parseTokens origin p cs toks
    = do (st, ws, reader) <- mapFst (fromParsingErrors origin) $ parseWith parsing p toks
         let (decorated, uses, tree) = madeBy st
         let Just frozen = frozenTree tree
             | Nothing => Left (InternalError "A parse tree has a child that is none of its nodes")
         let Just parsed = reader frozen
             | Nothing => Left (InternalError "A parse tree decodes to no syntax")
         let cs : SemanticDecorations
                = cs <&> \ c => ((origin, startBounds c.bounds, endBounds c.bounds), Comment, Nothing)
         let ws = ws <&> \ (mb, warn) =>
                    let mkFC = \ b => MkFC origin (startBounds b) (endBounds b)
                    in ParserWarning (maybe EmptyFC mkFC mb) warn
         let state : State
             state = MkState (cs ++ decorated) (holesWritten tree) uses
         pure (ws, state, parsed)

export
runParserTo : {auto c : Ref Ctxt Defs} -> {0 e : Bool} ->
              (origin : OriginDesc) ->
              Maybe LiterateStyle -> Lexer ->
              String -> ({0 n : Nat} -> BRule n False e (Read ty)) ->
              Core (Either Error (List Warning, State, ty))
runParserTo origin lit reject str p
    = case lexSource origin lit reject str of
           Left err => pure (Left err)
           Right (cs, toks) => parseTokens origin p cs <$> internTokens toks

export
runParser : {auto c : Ref Ctxt Defs} -> {0 e : Bool} ->
            (origin : OriginDesc) -> Maybe LiterateStyle -> String ->
            ({0 n : Nat} -> BRule n False e (Read ty)) ->
            Core (Either Error (List Warning, State, ty))
runParser origin lit = runParserTo origin lit (pred $ const False)

export covering
parseFile : {auto c : Ref Ctxt Defs}
         -> (fname : String)
         -> (origin : OriginDesc)
         -> ({0 n : Nat} -> Rule n False (Read ty))
         -> Core (Either Error (List Warning, State, ty))
parseFile fname origin p
    = do Right str <- coreLift (readFile fname)
             | Left err => pure (Left (FileErr fname err))
         runParser origin (isLitFile fname) str p
