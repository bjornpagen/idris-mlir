-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module Parser.Lexer.Common

import public Libraries.Text.Lexer

import Data.List1
import Data.String

%default total

||| In `comment` we are careful not to parse closing delimiters as
||| valid comments. i.e. you may not write many dashes followed by
||| a closing brace and call it a valid comment.
export
comment : Lexer
comment
   =  is '-' <+> is '-'                  -- comment opener
  <+> many (is '-') <+> reject (is '}')  -- not a closing delimiter
  <+> many (isNot '\n')                  -- till the end of line

-- Every state below is read inside at least one open block comment, so
-- each consumes: its type is `Lexer` whatever the depth. The depth is a
-- run-time count no type depends on, `outer`, the comments open around
-- the innermost; a comment ends only at the closing delimiter of the
-- outermost, which `closing` reads as its last character.
mutual
  ||| The mutually defined functions represent different states in a
  ||| small automaton. A state that names another, or itself, does so after
  ||| a character it reads (`andThen`), so a state is made only once the
  ||| input reaches it.
  ||| `toEndComment` is the default state and it will munch through
  ||| the input until we detect a special character (a dash, an
  ||| opening brace, or a double quote) and then switch to the
  ||| appropriate state.
  toEndComment : (outer : Nat) -> Lexer
  toEndComment outer
               = some (pred (\c => c /= '-' && c /= '{' && c /= '"' && c /= '\''))
                        `andThen` (eof <|> toEndComment outer)
             <|> is '{' `andThen` singleBrace outer
             <|> is '-' `andThen` singleDash outer
             <|> (charLit <|> pred (== '\'')) `andThen` toEndComment outer
             <|> stringLit `andThen` toEndComment outer

  ||| A closing delimiter's brace: the comment's last character where no
  ||| comment is open around the one it closes, and otherwise the rest of
  ||| the comment around it.
  closing : (outer : Nat) -> Lexer
  closing Z = is '}'
  closing (S outer) = is '}' `andThen` toEndComment outer

  ||| After reading a single brace, we may either finish reading an
  ||| opening delimiter or ignore it (e.g. it could be an implicit
  ||| binder).
  singleBrace : (outer : Nat) -> Lexer
  singleBrace outer
     =  is '-' <+> many (is '-')                        -- opening delimiter
               `andThen` (eof <|> singleDash (S outer)) -- `singleDash` handles the {----} special case
                                                        -- `eof` handles the file ending with {---
    <|> toEndComment outer                              -- not a valid comment

  ||| After reading a single dash, we may either find another one,
  ||| meaning we may have started reading a line comment, or find
  ||| a closing brace meaning we have found a closing delimiter.
  singleDash : (outer : Nat) -> Lexer
  singleDash outer
     =  is '-' `andThen` doubleDash outer  -- comment or closing delimiter
    <|> closing outer                      -- closing delimiter
    <|> toEndComment outer                 -- not a valid comment

  ||| After reading a double dash, we are potentially reading a line
  ||| comment unless the series of uninterrupted dashes is ended with
  ||| a closing brace in which case it is a closing delimiter.
  doubleDash : (outer : Nat) -> Lexer
  doubleDash outer = with Prelude.(::)
      many (is '-') <+> choice                      -- absorb all dashes
        [ closing outer                             -- closing delimiter
        , many (isNot '\n') <+> toEndComment outer  -- line comment
        ]

export
blockComment : Lexer
blockComment = is '{' <+> is '-' <+> many (is '-') <+> (eof <|> toEndComment 0)

-- Identifier Lexer
-- There are multiple variants.

public export
data Flavour = AllowDashes | Capitalised | Normal

isIdentStart : Flavour -> Char -> Bool
isIdentStart _           '_' = True
isIdentStart Capitalised  x  = isUpper x || x > chr 160
isIdentStart _            x  = isAlpha x || x > chr 160

isIdentTrailing : Flavour -> Char -> Bool
isIdentTrailing AllowDashes '-'  = True
isIdentTrailing _           '\'' = True
isIdentTrailing _           '_'  = True
isIdentTrailing _            x   = isAlphaNum x || x > chr 160

export %inline
isIdent : Flavour -> String -> Bool
isIdent flavour string =
  case unpack string of
    []      => False
    (x::xs) => isIdentStart flavour x && all (isIdentTrailing flavour) xs

export %inline
ident : Flavour -> Lexer
ident flavour =
  (pred $ isIdentStart flavour) <+>
    (many . pred $ isIdentTrailing flavour)

export
identNormal : Lexer
identNormal = ident Normal

export
identAllowDashes : Lexer
identAllowDashes = ident AllowDashes

namespaceIdent : Lexer
namespaceIdent = ident Capitalised <+> many (is '.' <+> ident Capitalised <+> expect (is '.'))

export
namespacedIdent : Lexer
namespacedIdent = namespaceIdent <+> opt (is '.' <+> identNormal)

||| A dotted identifier's parts as it is written: its namespace's, outermost
||| first, and its own, last. Both lexers split here, and a part is text
||| until the parser that reads it makes it a name.
export
dottedParts : String -> (List String, String)
dottedParts str = parts (split (== '.') str)
  where
    -- `n` is the part last met: the identifier's own once no part follows.
    go : SnocList String -> String -> List String -> (List String, String)
    go ns n [] = (ns <>> [], n)
    go ns n (m :: rest) = go (ns :< n) m rest

    parts : List1 String -> (List String, String)
    parts (n ::: rest) = go [<] n rest

export
spacesOrNewlines : Lexer
spacesOrNewlines = some (space <|> newline)
