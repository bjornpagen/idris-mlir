-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module Parser.Support

import public Libraries.Text.Lexer.Tokenizer
import public Libraries.Text.Lexer
import public Libraries.Text.Parser
import Libraries.Data.String.Extra
import public Libraries.Text.PrettyPrint.Prettyprinter

import Core.TT
import Core.Core
import Parser.Unlit
import public Parser.Support.Escaping

%default total

export
fromLitError : OriginDesc -> LiterateError -> Error
fromLitError origin (MkLitErr l c _) = LitFail (MkFC origin (l, c) (l, c + 1))

export
fromLexError : OriginDesc -> (StopReason, Int, Int, String) -> Error
fromLexError origin (ComposeNotClosing begin end, _, _, _)
    = LexFail (MkFC origin begin end) "Bracket is not properly closed."
fromLexError origin (_, l, c, _)
    = LexFail (MkFC origin (l, c) (l, c + 1)) "Can't recognise token."

export
fromParsingErrors : OriginDesc -> List1 ParsingError -> Error
fromParsingErrors origin = ParseFail . (map fromError)
  where
    fromError : ParsingError -> (FC, String)
    fromError (Error msg Nothing)
        = (MkFC origin (0, 0) (0, 0), msg +> '.')
    fromError (Error msg (Just t))
        = let start = startBounds t; end = endBounds t in
            let fc = if start == end
                      then MkFC origin start (mapSnd (+1) start)
                      else MkFC origin start end
            in (fc, msg +> '.')

export
getCharLit : String -> Maybe Char
getCharLit str
   = do e <- unescape 0 str
        case unpack e of
             [c] => Just c
             [] => Just '\0000' -- parsed the NULL character that terminated the string!
             _ => Nothing
