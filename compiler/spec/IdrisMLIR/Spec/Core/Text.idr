-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The text the specification holds, each kind a type of its own: an
||| identifier, a line of prose, a C++ name, an op's mnemonic, a runtime
||| symbol. Every one is ASCII by an erased proof at its definition, so the
||| generator prints the same bytes on both hosts and all four targets: no
||| code-point operation, case mapping or host printer ever touches it.
module IdrisMLIR.Spec.Core.Text

import Data.List
-- A mnemonic, a C++ name and a path are non-empty lists, in every module that holds one.
import public Data.List1
-- Every literal of these types is checked by an automatic `So` search in
-- the module that writes it, which finds `Oh` only where `So` is visible.
import public Data.So
import Data.String

%default total

------------------------------------------------------------------------------
-- Characters
------------------------------------------------------------------------------

||| A lower-case ASCII letter.
public export
lower : Char -> Bool
lower c = 'a' <= c && c <= 'z'

||| An upper-case ASCII letter.
public export
upper : Char -> Bool
upper c = 'A' <= c && c <= 'Z'

||| An ASCII digit.
public export
digit : Char -> Bool
digit c = '0' <= c && c <= '9'

||| A character of an identifier after its first.
public export
identTail : Char -> Bool
identTail c = lower c || upper c || digit c || c == '_'

||| A character a line of prose may hold: printable ASCII and the space.
||| Neither a newline nor a tab: a paragraph is a list of lines.
public export
printable : Char -> Bool
printable c = ' ' <= c && c <= '~'

------------------------------------------------------------------------------
-- Identifiers
------------------------------------------------------------------------------

||| Whether `s` is an identifier in every language the generator prints:
||| a letter or an underscore, then letters, digits and underscores.
public export
isIdent : String -> Bool
isIdent s = case unpack s of
  [] => False
  (c :: cs) => (lower c || upper c || c == '_') && all identTail cs

||| An identifier: the same text in TableGen, C++ and Idris.
public export
data Ident : Type where
  MkIdent : (text : String) -> (0 ok : So (isIdent text)) -> Ident

||| An identifier from a literal, refused where it is written if it is none.
public export
ident : (s : String) -> {auto 0 ok : So (isIdent s)} -> Ident
ident s = MkIdent s ok

public export
identText : Ident -> String
identText (MkIdent s _) = s

namespace Ident
  ||| A literal identifier, refused where it is written if it is none.
  public export
  fromString : (s : String) -> {auto 0 ok : So (isIdent s)} -> Ident
  fromString s = MkIdent s ok

public export
Eq Ident where
  a == b = identText a == identText b

||| Whether `s` is lower-case snake: lower-case letters, digits and single
||| underscores, starting with a letter. A mnemonic's segments, a pass's
||| words and a printed spelling are this.
public export
isSnake : String -> Bool
isSnake s = case unpack s of
  [] => False
  (c :: cs) => lower c && all (\x => lower x || digit x || x == '_') cs

||| A segment of a mnemonic or of a printed spelling: lower-case snake.
public export
data Word : Type where
  MkWord : (text : String) -> (0 ok : So (isSnake text)) -> Word

public export
word : (s : String) -> {auto 0 ok : So (isSnake s)} -> Word
word s = MkWord s ok

public export
wordText : Word -> String
wordText (MkWord s _) = s

namespace Word
  public export
  fromString : (s : String) -> {auto 0 ok : So (isSnake s)} -> Word
  fromString s = MkWord s ok

public export
Eq Word where
  a == b = wordText a == wordText b

||| A word in upper camel case: `file_time` is `FileTime`. The one place a
||| case is changed, over ASCII letters only, so both hosts agree.
public export
camel : Word -> String
camel w = pack (go True (unpack (wordText w)))
  where
    up : Char -> Char
    up c = if lower c then chr (ord c - 32) else c
    go : Bool -> List Char -> List Char
    go _ [] = []
    go start ('_' :: cs) = go True cs
    go start (c :: cs) = (if start then up c else c) :: go False cs

------------------------------------------------------------------------------
-- Mnemonics
------------------------------------------------------------------------------

||| An op's, a type's or an attribute's name within its dialect, segment by
||| segment: `str.length` is `[str, length]`. Its C++ class is ODS's default
||| from it (camelMnemonic), so the name and the class cannot disagree.
public export
data Mnemonic : Type where
  MkMnemonic : List1 Word -> Mnemonic

public export
segments : Mnemonic -> List1 Word
segments (MkMnemonic ws) = ws

||| The mnemonic as the dialect prints it: its segments joined by dots.
public export
mnemonicText : Mnemonic -> String
mnemonicText m = concat (intersperse "." (map wordText (forget (segments m))))

||| The mnemonic in upper camel case: `str.length` is `StrLength`.
public export
camelMnemonic : Mnemonic -> String
camelMnemonic m = concat (map camel (forget (segments m)))

||| Whether every string is snake.
public export
allSnake : List String -> Bool
allSnake [] = True
allSnake (x :: xs) = isSnake x && allSnake xs

||| Whether `s` is a mnemonic: snake segments joined by single dots.
public export
isMnemonic : String -> Bool
isMnemonic s = allSnake (forget (split (== '.') s))

||| Strings proved snake, as words: the proof is split as the list is, so
||| no piece is ever checked again.
public export
wordsOf : (xs : List String) -> (0 ok : So (allSnake xs)) -> List Word
wordsOf [] _ = []
wordsOf (x :: xs) ok = MkWord x (fst (soAnd ok)) :: wordsOf xs (snd (soAnd ok))

||| Pieces proved snake, as a mnemonic.
public export
mnemonicOf : (ps : List1 String) -> (0 ok : So (allSnake (forget ps))) -> Mnemonic
mnemonicOf (p ::: ps) ok = MkMnemonic (MkWord p (fst (soAnd ok)) ::: wordsOf ps (snd (soAnd ok)))

namespace Mnemonic
  ||| A literal mnemonic, `"str.length"`, split at its dots, each segment a
  ||| word by the proof.
  public export
  fromString : (s : String) -> {auto 0 ok : So (isMnemonic s)} -> Mnemonic
  fromString s = mnemonicOf (split (== '.') s) ok

public export
Eq Mnemonic where
  a == b = mnemonicText a == mnemonicText b

------------------------------------------------------------------------------
-- Prose
------------------------------------------------------------------------------

||| Whether `s` is one line of prose.
public export
isLine : String -> Bool
isLine s = all printable (unpack s)

||| One line of prose, printed verbatim.
public export
data Line : Type where
  MkLine : (text : String) -> (0 ok : So (isLine text)) -> Line

public export
line : (s : String) -> {auto 0 ok : So (isLine s)} -> Line
line s = MkLine s ok

public export
lineText : Line -> String
lineText (MkLine s _) = s

namespace Line
  public export
  fromString : (s : String) -> {auto 0 ok : So (isLine s)} -> Line
  fromString s = MkLine s ok

||| Whether `s` is prose: printable ASCII and newlines.
public export
isProse : String -> Bool
isProse s = all (\c => printable c || c == '\n') (unpack s)

||| Prose of whole lines, a declaration's description, printed verbatim.
public export
data Prose : Type where
  MkProse : (text : String) -> (0 ok : So (isProse text)) -> Prose

public export
proseText : Prose -> String
proseText (MkProse s _) = s

namespace Prose
  public export
  fromString : (s : String) -> {auto 0 ok : So (isProse s)} -> Prose
  fromString s = MkProse s ok

||| What a declaration says of itself: a summary of one line, and a
||| description, which ODS copies into the generated C++ and the generator
||| into the Idris it prints.
public export
record Doc where
  constructor MkDoc
  summary : Line
  description : Prose

||| A declaration with a summary alone.
public export
brief : Line -> Doc
brief s = MkDoc s (MkProse "" Oh)

------------------------------------------------------------------------------
-- C++ names
------------------------------------------------------------------------------

||| A fully qualified C++ name, segment by segment from the global
||| namespace: `::idr::effects::Heap` is `[idr, effects, Heap]`.
public export
CppName : Type
CppName = List1 Ident

||| The name as C++ spells it, from the global namespace.
public export
cppText : CppName -> String
cppText n = concat (map (\i => "::" ++ identText i) (forget n))

||| The last segment: the name within its namespace.
public export
cppLeaf : CppName -> Ident
cppLeaf n = last n

||| A name in the dialect's namespace, `::idr::<leaf>`.
public export
inIdr : Ident -> CppName
inIdr leaf = ident "idr" ::: [leaf]

||| C++ that the specification names but cannot type: a type's spelling in
||| a parameter or a result, a default argument's expression. The one
||| untyped island, kept to declarations: no body of a function is ever
||| written here, so no semantics hides in it.
public export
data Code : Type where
  MkCode : (text : String) -> (0 ok : So (isLine text)) -> Code

public export
code : (s : String) -> {auto 0 ok : So (isLine s)} -> Code
code s = MkCode s ok

public export
codeText : Code -> String
codeText (MkCode s _) = s

namespace Code
  public export
  fromString : (s : String) -> {auto 0 ok : So (isLine s)} -> Code
  fromString s = MkCode s ok

------------------------------------------------------------------------------
-- Runtime symbols
------------------------------------------------------------------------------

||| A runtime function's name without its prefix: `str_length` is the
||| symbol `idris_rt_str_length`. The prefix is printed, never written, so
||| no symbol lacks it.
public export
data Symbol : Type where
  MkSymbol : (stem : String) -> (0 ok : So (isSnake stem)) -> Symbol

public export
symbol : (s : String) -> {auto 0 ok : So (isSnake s)} -> Symbol
symbol s = MkSymbol s ok

public export
symbolText : Symbol -> String
symbolText (MkSymbol s _) = "idris_rt_" ++ s

namespace Symbol
  public export
  fromString : (s : String) -> {auto 0 ok : So (isSnake s)} -> Symbol
  fromString s = MkSymbol s ok

------------------------------------------------------------------------------
-- Bytes
------------------------------------------------------------------------------

||| A string's bytes in UTF-8, each character's one to four bytes before the
||| next character's: what both hosts read a source file as, what a
||| fingerprint hashes, and what the frontend writes and hashes. The one
||| encoder, so no two readers of a string's bytes can disagree.
export
utf8 : String -> List Bits8
utf8 s = foldr encode [] (unpack s)
  where
    byte : Int -> Bits8
    byte = cast
    encode : Char -> List Bits8 -> List Bits8
    encode c rest =
      let v = ord c in
      if v < 0x80 then byte v :: rest
      else if v < 0x800 then byte (0xC0 + v `div` 0x40) :: byte (0x80 + v `mod` 0x40) :: rest
      else if v < 0x10000 then byte (0xE0 + v `div` 0x1000) :: byte (0x80 + (v `div` 0x40) `mod` 0x40)
                                 :: byte (0x80 + v `mod` 0x40) :: rest
      else byte (0xF0 + v `div` 0x40000) :: byte (0x80 + (v `div` 0x1000) `mod` 0x40)
             :: byte (0x80 + (v `div` 0x40) `mod` 0x40) :: byte (0x80 + v `mod` 0x40) :: rest

------------------------------------------------------------------------------
-- Paths
------------------------------------------------------------------------------

||| A path of a generated file, relative to the checkout's root, segment by
||| segment: no separator is ever spelled by hand, and no path is absolute.
public export
Path : Type
Path = List1 String

public export
pathText : Path -> String
pathText p = concat (intersperse "/" (forget p))
