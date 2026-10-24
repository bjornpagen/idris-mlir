-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
||| A simple module to process 'literate' documents.
|||
||| The module uses a lexer to split the document into code blocks,
||| delineated by user-defined markers, and code lines that are
||| indicated be a line marker. The lexer returns a document stripped
||| of non-code elements but preserving the original document's line
||| count. Column numbering of code lines are not preserved.
|||
||| The underlying tokeniser is greedy.
|||
||| Once it identifies a line marker it reads a prettifying space then
||| consumes until the end of line. Once identifies a starting code
||| block marker, the lexer will consume input until the next
||| identifiable end block is encountered. Any other content is
||| treated as part of the original document.
|||
||| Thus, the input literate files *must* be well-formed w.r.t
||| to code line markers and code blocks.
|||
||| A further restriction is that literate documents cannot contain
||| the markers within the document's main text: This will confuse the
||| lexer.
|||
module Libraries.Text.Literate

import Libraries.Text.Lexer

import Data.List1
import Data.List.Views
import Data.String
import Libraries.Utils.String

%default total

untilEOL : Recognise False
untilEOL = manyUntil newline any

line : String -> Lexer
line s = exact s <+> (newline <|> space <+> untilEOL)

block : String -> String -> Lexer
block s e = surround (exact s <+> untilEOL) (exact e <+> untilEOL) any

notCodeLine : Lexer
notCodeLine = newline
           <|> any <+> untilEOL

public export
data LitToken
  = CodeBlock String String String
  | Any String
  | CodeLine String String

Show LitToken where
  showPrec d (CodeBlock l r x) = showCon d "CodeBlock" $ showArg l ++ showArg r ++ showArg x
  showPrec d (Any x)           = showCon d "Any" $ showArg x
  showPrec d (CodeLine m x)    = showCon d "CodeLine" $ showArg m ++ showArg x

-- A code block between each pair of delimiters, a code line after each
-- marker, and else any other line, tried in that order.
rawTokens : (delims  : List (String, String))
         -> (markers : List String)
         -> Tokenizer LitToken
rawTokens delims ls = foldr codeBlock (foldr codeLine (match notCodeLine Any) ls) delims
  where
    codeBlock : (String, String) -> Tokenizer LitToken -> Tokenizer LitToken
    codeBlock (l, r) rest = match (block l r) (CodeBlock (trimSpace l) (trimSpace r)) <|> rest

    codeLine : String -> Tokenizer LitToken -> Tokenizer LitToken
    codeLine m rest = match (line m) (CodeLine (trimSpace m)) <|> rest

||| Merge the tokens into a single source file.
reduce : List (Located LitToken) -> List String -> String
reduce [] acc = fastConcat (reverse acc)
reduce (MkLocated (Any x) _ :: rest) acc =
  -- newline will always be tokenized as a single token
  if x == "\n"
  then reduce rest ("\n"::acc)
  else reduce rest acc

reduce (MkLocated (CodeLine m src) _ :: rest) acc =
    if m == trimSpace src
    then reduce rest ("\n"::acc)
    else reduce rest ((substr (length m + 1) -- remove space to right of marker.
                              (length src)
                              src
                      )::acc)

reduce (MkLocated (CodeBlock l r src) _ :: rest) acc with (lines src) -- Strip the deliminators surrounding the block.
  reduce (MkLocated (CodeBlock l r src) _ :: rest) acc | [] = reduce rest acc -- 1
  reduce (MkLocated (CodeBlock l r src) _ :: rest) acc | (s :: ys) with (snocList ys)
    reduce (MkLocated (CodeBlock l r src) _ :: rest) acc | (s :: []) | Empty = reduce rest acc -- 2
    reduce (MkLocated (CodeBlock l r src) _ :: rest) acc | (s :: (srcs ++ [f])) | (Snoc f srcs rec) =
        -- the "\n" counts for the open deliminator; the closing deliminator should always be followed by a (Any "\n"), so we don't add a newline
        reduce rest ((unlines srcs) :: "\n" :: acc)

-- [ NOTE ] 1 & 2 shouldn't happen as code blocks are well formed i.e. have two deliminators.


public export
record LiterateError where
  constructor MkLitErr
  line   : Int
  column : Int
  input  : String

export
Show LiterateError where
  show (MkLitErr line col input) = "\{input}:\{show line}:\{show col}"

||| Description of literate styles.
|||
||| A 'literate' style comprises of
|||
||| + a list of code block deliminators (`deliminators`);
||| + a list of code line markers (`line_markers`); and
||| + a list of known file extensions `file_extensions`.
|||
||| Some example specifications:
|||
||| + Bird Style
|||
|||```
|||MkLitStyle Nil [">"] [".lidr"]
|||```
|||
||| + Literate Haskell (for LaTeX)
|||
|||```
|||MkLitStyle [("\\begin{code}", "\\end{code}"),("\\begin{spec}","\\end{spec}")]
|||           Nil
|||           [".lhs", ".tex"]
|||```
|||
||| + OrgMode
|||
|||```
|||MkLitStyle [("#+BEGIN_SRC idris","#+END_SRC"), ("#+COMMENT idris","#+END_COMMENT")]
|||           ["#+IDRIS:"]
|||           [".org"]
|||```
|||
||| + Common Mark
|||
|||```
|||MkLitStyle [("```idris","```"), ("<!-- idris","--!>")]
|||           Nil
|||           [".md", ".markdown"]
|||```
|||
public export
record LiterateStyle where
  constructor MkLitStyle
  ||| The pairs of start and end tags for code blocks.
  deliminators : List (String, String)

  ||| Line markers that indicate a line contains code.
  line_markers : List String

  ||| Recognised file extensions. Not used by the module, but will be
  ||| of use when connecting to code that reads in the original source
  ||| files.
  file_extensions : List String

||| Given a 'literate specification' lex the file to extract code blocks
|||
||| @specification The literate specification to use.
||| @litStr  The literate source file.
|||
||| Returns a `LiterateError` if the literate file contains malformed
||| code blocks or code lines.
export
lexLiterate : (specification : LiterateStyle)
           -> (litStr        : String)
           -> Either LiterateError (List (Located LitToken))
lexLiterate (MkLitStyle delims markers exts) str =
      case lex (rawTokens delims markers) str of
        (toks, (_,_,_,"")) => Right toks
        (_, (_,l,c,i))     => Left (MkLitErr l c i)

||| Given a 'literate specification' extract the code from the
||| literate source file (`litStr`) that follows the presented style.
|||
||| @specification The literate specification to use.
||| @litStr The literate source file.
|||
||| Returns a `LiterateError` if the literate file contains malformed
||| code blocks or code lines.
|||
export
extractCode : (specification : LiterateStyle)
           -> (litStr        : String)
           -> Either LiterateError String
extractCode spec str = flip reduce Nil <$> lexLiterate spec str

||| Synonym for `extractCode`.
export
unlit : (specification : LiterateStyle)
     -> (litStr        : String)
     -> Either LiterateError String
unlit = extractCode

-- --------------------------------------------------------------------- [ EOF ]
