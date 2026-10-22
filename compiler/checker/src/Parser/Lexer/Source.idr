-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module Parser.Lexer.Source

import public Parser.Lexer.Common
import public Parser.Lexer.Pragma
import public Parser.Lexer.Reserved

import Data.Either
import Data.Maybe
import Data.String
import Libraries.Data.String.Extra
import public Libraries.Text.Bounded
import Libraries.Text.Lexer.Tokenizer
import Libraries.Text.PrettyPrint.Prettyprinter
import Libraries.Text.PrettyPrint.Prettyprinter.Util

import Protocol.Hex
import Libraries.Utils.Octal
import Libraries.Utils.String

import Core.Name

%default total

public export
data IsMultiline = Multi | Single

public export
data DebugInfo
  = DebugLoc
  | DebugFile
  | DebugLine
  | DebugCol

export
Eq DebugInfo where
  DebugLoc == DebugLoc = True
  DebugFile == DebugFile = True
  DebugLine == DebugLine = True
  DebugCol == DebugCol = True
  _ == _ = False

||| A token of source, over how it spells an identifier: the lexer spells one
||| as text (`RawToken`), and the parser reads it interned (`Token`). An
||| operator's symbol is an identifier too, since it names the operator. A
||| keyword, a reserved symbol or a pragma is a word of the language, never
||| a name, and the lexer gives it as its kind, so the parser compares
||| kinds, never text.
public export
data SourceToken identifier
  -- Literals
  = CharLit String
  | DoubleLit Double
  | IntegerLit Integer
  -- String
  | StringBegin Nat IsMultiline -- The escape depth and whether is multiline string
  | StringEnd
  | InterpBegin
  | InterpEnd
  | StringLit String
  -- Identifiers
  | HoleIdent identifier
  | Ident identifier
  | DotSepIdent (List identifier) identifier -- ident.ident, the namespace's parts outermost first
  | DotIdent identifier                      -- .ident
  | Symbol identifier                        -- an operator's symbol
  -- Whitespace
  | Space
  -- Comments
  | Comment
  | DocComment String
  -- Special
  | CGDirective String
  | EndInput
  | Keyword Keyword
  | Reserved Reserved
  | Pragma KwPragma
  | MagicDebugInfo DebugInfo
  | Unrecognised String

||| A token as the lexer makes it.
public export
RawToken : Type
RawToken = SourceToken String

||| A token as the parser reads it, its identifiers interned where the source
||| enters the compiler.
public export
Token : Type
Token = SourceToken Ident

||| The token with each identifier it spells replaced.
export
traverseIdents : Applicative f => (a -> f b) -> SourceToken a -> f (SourceToken b)
traverseIdents f (CharLit x) = pure (CharLit x)
traverseIdents f (DoubleLit x) = pure (DoubleLit x)
traverseIdents f (IntegerLit x) = pure (IntegerLit x)
traverseIdents f (StringBegin hashtag multi) = pure (StringBegin hashtag multi)
traverseIdents f StringEnd = pure StringEnd
traverseIdents f InterpBegin = pure InterpBegin
traverseIdents f InterpEnd = pure InterpEnd
traverseIdents f (StringLit x) = pure (StringLit x)
traverseIdents f (HoleIdent x) = HoleIdent <$> f x
traverseIdents f (Ident x) = Ident <$> f x
traverseIdents f (DotSepIdent ns n) = DotSepIdent <$> traverse f ns <*> f n
traverseIdents f (DotIdent x) = DotIdent <$> f x
traverseIdents f (Symbol x) = Symbol <$> f x
traverseIdents f Space = pure Space
traverseIdents f Comment = pure Comment
traverseIdents f (DocComment x) = pure (DocComment x)
traverseIdents f (CGDirective x) = pure (CGDirective x)
traverseIdents f EndInput = pure EndInput
traverseIdents f (Keyword k) = pure (Keyword k)
traverseIdents f (Reserved r) = pure (Reserved r)
traverseIdents f (Pragma k) = pure (Pragma k)
traverseIdents f (MagicDebugInfo di) = pure (MagicDebugInfo di)
traverseIdents f (Unrecognised x) = pure (Unrecognised x)

export
Show DebugInfo where
  show DebugLoc = "__LOC__"
  show DebugFile = "__FILE__"
  show DebugLine = "__LINE__"
  show DebugCol = "__COL__"

export
Show identifier => Show (SourceToken identifier) where
  -- Literals
  show (CharLit x) = "character " ++ show x
  show (DoubleLit x) = "double " ++ show x
  show (IntegerLit x) = "literal " ++ show x
  -- String
  show (StringBegin hashtag Single) = "string begin"
  show (StringBegin hashtag Multi) = "multiline string begin"
  show StringEnd = "string end"
  show InterpBegin = "string interp begin"
  show InterpEnd = "string interp end"
  show (StringLit x) = "string " ++ show x
  -- Identifiers
  show (HoleIdent x) = "hole identifier " ++ show x
  show (Ident x) = "identifier " ++ show x
  show (DotSepIdent ns n) = "namespaced identifier " ++ concatMap (\ p => show p ++ ".") ns ++ show n
  show (DotIdent x) = "dot+identifier " ++ show x
  show (Symbol x) = "symbol " ++ show x
  -- Whitespace
  show Space = "whitespace"
  -- Comments
  show Comment = "comment"
  show (DocComment c) = "doc comment: \"" ++ c ++ "\""
  -- Special
  show (CGDirective x) = "CGDirective " ++ x
  show EndInput = "end of input"
  show (Keyword k) = keywordText k
  show (Reserved r) = "symbol " ++ reservedText r
  show (Pragma k) = "pragma " ++ spelling k
  show (MagicDebugInfo di) = show di
  show (Unrecognised x) = "Unrecognised " ++ x

export
Pretty Void identifier => Pretty Void (SourceToken identifier) where
  -- Literals
  pretty (CharLit x) = pretty "character" <++> squotes (pretty x)
  pretty (DoubleLit x) = pretty "double" <++> pretty (show x)
  pretty (IntegerLit x) = pretty "literal" <++> pretty (show x)
  -- String
  pretty (StringBegin hashtag Single) = reflow "string begin"
  pretty (StringBegin hashtag Multi) = reflow "multiline string begin"
  pretty StringEnd = reflow "string end"
  pretty InterpBegin = reflow "string interp begin"
  pretty InterpEnd = reflow "string interp end"
  pretty (StringLit x) = pretty "string" <++> dquotes (pretty x)
  -- Identifiers
  pretty (HoleIdent x) = reflow "hole identifier" <++> pretty x
  pretty (Ident x) = pretty "identifier" <++> pretty x
  pretty (DotSepIdent ns n) = reflow "namespaced identifier" <++> foldr (\ p, d => pretty p <+> dot <+> d) (pretty n) ns
  pretty (DotIdent x) = pretty "dot+identifier" <++> pretty x
  pretty (Symbol x) = pretty "symbol" <++> pretty x
  -- Whitespace
  pretty Space = pretty "space"
  -- Comments
  pretty Comment = pretty "comment"
  pretty (DocComment c) = reflow "doc comment:" <++> dquotes (pretty c)
  -- Special
  pretty (CGDirective x) = pretty "CGDirective" <++> pretty x
  pretty EndInput = reflow "end of input"
  pretty (Keyword k) = pretty (keywordText k)
  pretty (Reserved r) = pretty "symbol" <++> pretty (reservedText r)
  pretty (Pragma k) = pretty "pragma" <++> pretty (spelling k)
  pretty (MagicDebugInfo di) = pretty (show di)
  pretty (Unrecognised x) = pretty "Unrecognised" <++> pretty x

docComment : Lexer
docComment = is '|' <+> is '|' <+> is '|' <+> many (isNot '\n')

holeIdent : Lexer
holeIdent = is '?' <+> identNormal

dotIdent : Lexer
dotIdent = is '.' <+> identNormal

pragma : Lexer
pragma = is '%' <+> identNormal

doubleLit : Lexer
doubleLit
    = digits <+> is '.' <+> digits <+> opt
           (is 'e' <+> opt (is '-' <|> is '+') <+> digits)

stringBegin : Lexer
stringBegin = many (is '#') <+> (is '"')

stringEnd : Nat -> String
stringEnd hashtag = "\"" ++ replicate hashtag '#'

multilineBegin : Lexer
multilineBegin = many (is '#') <+> (exact "\"\"\"") <+>
                    manyUntil newline space <+> newline

multilineEnd : Nat -> String
multilineEnd hashtag = "\"\"\"" ++ replicate hashtag '#'

-- Do this as an entire token, because the contents will be processed by
-- a specific back end
cgDirective : Lexer
cgDirective
    = exact "%cg" <+>
      ((some space <+>
           some (pred isAlphaNum) <+> many space <+>
           is '{' <+> many (isNot '}') <+>
           is '}')
         <|> many (isNot '\n'))

mkDirective : String -> RawToken
mkDirective str = CGDirective (trimSpace (substr 3 (length str) str))

public export
debugInfo : List (String, DebugInfo)
debugInfo = map (\ di => (show di, di))
          [ DebugLoc, DebugFile, DebugLine, DebugCol ]

-- The punctuation, read before any other symbol.
punctuation : List Reserved
punctuation = [SymComma, SymSemicolon, SymUnderscore, SymBackquote]

-- Each bracket that opens a group, with the bracket that closes it, in the
-- order they are tried: one that begins another (`.(` and `(`, `[|` and
-- `[`) first.
brackets : List (Reserved, Reserved)
brackets
    = [ (SymDotParen, SymParenClose), (SymDotIdiom, SymIdiomClose)
      , (SymAtBrace, SymBraceClose), (SymIdiom, SymIdiomClose)
      , (SymParen, SymParenClose), (SymBrace, SymBraceClose)
      , (SymSnocBracket, SymBracketClose), (SymListBracket, SymBracketClose)
      , (SymBracket, SymBracketClose), (SymQuoteParen, SymParenClose)
      , (SymQuoteBrace, SymBraceClose), (SymQuoteBracket, SymBracketClose)
      ]

-- What closes the group the bracket written so opens: the bracket paired
-- with it, read only after the bracket that opens.
closing : String -> Lexer
closing begin
    = case reservedOf begin >>= \b => lookup b brackets of
           Just close => exact (reservedText close)
           Nothing => fail

-- A symbol's token: the reserved symbol it spells, or else an operator's.
symbolToken : String -> RawToken
symbolToken s = maybe (Symbol s) Reserved (reservedOf s)

validSymbol : Lexer
validSymbol = some (pred isOpChar)

-- Each of these literals' digits follow its two-character prefix (`0b`, `0x`,
-- `0o`).
fromBinLit : String -> Integer
fromBinLit str = fromBin . reverse . map castBin . unpack $ drop 2 str
    where
      castBin : Char -> Integer
      castBin '1' = 1; castBin _ = 0 -- This can only be '1' and '0' once lexed
      fromBin : List Integer -> Integer
      fromBin [] = 0
      fromBin (0 :: xs) = 2 * fromBin xs
      fromBin (x :: xs) = x + (2 * fromBin xs)

fromHexLit : String -> Integer
fromHexLit str = fromMaybe 0 (fromHex (reverse (drop 2 str)))
                 --        ^-- can't happen if the literal was lexed correctly

fromOctLit : String -> Integer
fromOctLit str = fromMaybe 0 (fromOct (reverse (drop 2 str)))
                 --        ^-- can't happen if the literal lexed correctly

mutual
  stringTokens : IsMultiline -> Nat -> Tokenizer RawToken
  stringTokens multi hashtag
      = let escapeChars = "\\" ++ replicate hashtag '#'
            interpStart = escapeChars ++ "{"
            escapeLexer = escape (exact escapeChars) any
            charLexer = case multi of
                             Multi => non $ exact (multilineEnd hashtag)
                             Single => non (newline <|> exact (stringEnd hashtag))
          in
            match (someUntil (exact interpStart) (escapeLexer <|> charLexer)) (\x => StringLit x)
        <|> compose (exact interpStart)
                    (\_ => MkGroup InterpBegin rawTokens (is '}') (const InterpEnd))

  rawTokens : Tokenizer RawToken
  rawTokens =
          match comment (const Comment)
      <|> match blockComment (const Comment)
      <|> match docComment (DocComment . removeOptionalLeadingSpace . drop 3)
      <|> match cgDirective mkDirective
      <|> match holeIdent (\x => HoleIdent (drop 1 x))
      <|> compose (choiceMap (exact . reservedText . fst) brackets)
                  (\begin => MkGroup (symbolToken begin) rawTokens (closing begin) symbolToken)
      <|> match (choice $ (exact . fst) <$> debugInfo) (MagicDebugInfo . fromMaybe DebugLoc . flip lookup debugInfo)
      <|> match (choiceMap (exact . reservedText) punctuation) symbolToken
      <|> match doubleLit (DoubleLit . cast)
      <|> match binUnderscoredLit (IntegerLit . fromBinLit . removeUnderscores)
      <|> match hexUnderscoredLit (IntegerLit . fromHexLit . removeUnderscores)
      <|> match octUnderscoredLit (IntegerLit . fromOctLit . removeUnderscores)
      <|> match digitsUnderscoredLit (IntegerLit . cast . removeUnderscores)
      <|> compose multilineBegin
                  (\begin => let hashtag = countHashtag begin in
                                 MkGroup (StringBegin hashtag Multi) (stringTokens Multi hashtag)
                                         (exact (multilineEnd hashtag)) (const StringEnd))
      <|> compose stringBegin
                  (\begin => let hashtag = countHashtag begin in
                                 MkGroup (StringBegin hashtag Single) (stringTokens Single hashtag)
                                         (exact (stringEnd hashtag) <+> reject (is '"')) (const StringEnd))
      <|> match charLit (CharLit . stripQuotes)
      <|> match dotIdent (\x => DotIdent (drop 1 x))
      <|> match namespacedIdent parseNamespace
      <|> match identNormal parseIdent
      <|> match pragma pragmaToken
      <|> match space (const Space)
      <|> match validSymbol symbolToken
      <|> match symbol Unrecognised
    where
      parseIdent : String -> RawToken
      parseIdent x = maybe (Ident x) Keyword (keywordOf x)

      -- A `%` and a word: the pragma the word spells, or else no token of
      -- the language, which every rule refuses as it refuses any token it
      -- does not take.
      pragmaToken : String -> RawToken
      pragmaToken x = maybe (Unrecognised x) Pragma (pragmaOf (drop 1 x))

      -- A single part is an identifier or a keyword; a namespaced one is
      -- never a keyword.
      dotted : (List String, String) -> RawToken
      dotted ([], n) = parseIdent n
      dotted (ns, n) = DotSepIdent ns n

      parseNamespace : String -> RawToken
      parseNamespace = dotted . dottedParts

      countHashtag : String -> Nat
      countHashtag = count (== '#') . unpack

      removeOptionalLeadingSpace : String -> String
      removeOptionalLeadingSpace str = case strUncons str of
                                            Just (' ', tail) => tail
                                            _ => str

      removeUnderscores : String -> String
      removeUnderscores s = fastPack $ filter (/= '_') (fastUnpack s)

export
lexTo : Lexer ->
        String ->
        Either (StopReason, Int, Int, String)
               ( List (Located ())        -- bounds of comments
               , List (Located RawToken)) -- tokens
lexTo reject str
    = case lexTo reject rawTokens str of
           (toks, (EndInput, l, c, _)) =>
             -- Add the EndInput token so that we'll have a line and column
             -- number to read when storing spans in the file
             let end = [MkLocated EndInput (MkBounds l c l c)] in
             Right $ map (++ end)
                   $ partitionEithers
                   $ map spotComment
                   $ filter isNotSpace toks
           (_, fail) => Left fail
    where

      isNotSpace : Located RawToken -> Bool
      isNotSpace t = case t.val of
        Space => False
        _ => True

      spotComment : Located RawToken ->
                    Either (Located ()) (Located RawToken)
      spotComment t = case t.val of
        Comment => Left (() <$ t)
        _ => Right t

export
lex : String ->
      Either (StopReason, Int, Int, String)
             ( List (Located ())        -- bounds of comments
             , List (Located RawToken)) -- tokens
lex = lexTo (pred $ const False)
