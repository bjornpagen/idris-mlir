||| MLIR's generic operation form as data, and its one printer.
|||
||| Every MLIR operation has the same shape: results, a name, operands,
||| properties, regions, attributes, a function type and a location. `Emit`
||| builds these; only this module knows how they are written, so what the
||| compiler emits and how it is printed can be tested apart. The printed text
||| is MLIR's generic syntax, which every dialect parses.
module IdrisMLIR.MLIR

import IdrisMLIR.Ids
import IdrisMLIR.Loc

import Data.List
import Data.Maybe
import Data.String

%default total

||| An operation's location: a source span (IDR-LOC-1), or an Idris name at
||| one, MLIR's `NameLoc` (IDR-DATA-5). Names reach MLIR only this way: as
||| debug information, which passes keep and diagnostics print, and never
||| as data a pass could compare.
public export
data Location = At Loc | Named Shown Loc

------------------------------------------------------------------------------
-- Types and attributes
------------------------------------------------------------------------------

public export
data MType = I Nat | F64
           | IdrData String | IdrErased | IdrStr | IdrWorld
           | FunctionT (List MType) (List MType)

public export
Eq MType where
  I a == I b = a == b
  F64 == F64 = True
  IdrData a == IdrData b = a == b
  IdrErased == IdrErased = True
  IdrStr == IdrStr = True
  IdrWorld == IdrWorld = True
  FunctionT a r == FunctionT b s = assert_total (a == b && r == s)
  _ == _ = False

public export
data Attr = IntA Integer MType          -- 3 : i64
          | FloatA Double               -- 1.5 : f64, exactly
          | StrA String                 -- a string, escaped
          | BytesA String               -- a string as UTF-8 bytes
          | SymA (List String)          -- @a::@b
          | TypeA MType
          | ArrayA (List Attr)
          | I64ArrayA (List Integer)    -- array<i64: ...>
          | I32ArrayA (List Integer)    -- array<i32: ...>
          | DenseI64A (List Integer)    -- dense<[...]> : vector<Nxi64>
          | DictA (List (String, Attr))
          | UnitA                       -- a flag: present

||| An SSA value, as it is written: `%3` or `%3#1`.
public export
Value : Type
Value = String

mutual
  public export
  record MOp where
    constructor MkMOp
    ||| The result name and the number of results.
    results : Maybe (String, Nat)
    name : String
    operands : List Value
    ||| The blocks a terminator branches to, as `^bb3`.
    successors : List String
    props : List (String, Attr)
    regions : List Region
    attrs : List (String, Attr)
    inputs : List MType
    outputs : List MType
    loc : Location

  ||| A block: its label, its arguments and its operations.
  public export
  record Block where
    constructor MkBlock
    label : String
    args : List (Value, MType)
    ops : List MOp

  ||| A region: its blocks, the entry block first.
  public export
  record Region where
    constructor MkRegion
    blocks : List Block

||| A region of one block.
export
single : List (Value, MType) -> List MOp -> Region
single as ops = MkRegion [MkBlock "^bb0" as ops]

||| An operation without regions, successors or attributes.
export
simple : Maybe (String, Nat) -> String -> List Value -> List (String, Attr) ->
         List MType -> List MType -> Loc -> MOp
simple rs n os ps is out l = MkMOp rs n os [] ps [] [] is out (At l)

------------------------------------------------------------------------------
-- Printing
------------------------------------------------------------------------------

hex : Int -> String
hex n = let digits = unpack "0123456789ABCDEF" in
        pack [ fromMaybe '0' (getAt (cast (n `div` 16)) digits)
             , fromMaybe '0' (getAt (cast (n `mod` 16)) digits) ]

||| A string literal with MLIR's escapes.
export
quoted : String -> String
quoted s = "\"" ++ concatMap esc (unpack s) ++ "\""
  where
    esc : Char -> String
    esc '"' = "\\\""
    esc '\\' = "\\\\"
    esc c = if ord c < 32 || ord c == 127 then "\\" ++ hex (ord c) else singleton c

||| UTF-8 encoding of a string, as the bytes of a string attribute.
utf8 : String -> String
utf8 s = "\"" ++ concatMap enc (unpack s) ++ "\""
  where
    byte : Int -> String
    byte b = if b >= 32 && b < 127 && b /= 34 && b /= 92 then singleton (chr b) else "\\" ++ hex b
    enc : Char -> String
    enc c =
      let n = ord c in
      if n < 0x80 then byte n
      else if n < 0x800 then byte (0xC0 + n `div` 64) ++ byte (0x80 + n `mod` 64)
      else if n < 0x10000 then byte (0xE0 + n `div` 4096) ++ byte (0x80 + (n `div` 64) `mod` 64)
                               ++ byte (0x80 + n `mod` 64)
      else byte (0xF0 + n `div` 262144) ++ byte (0x80 + (n `div` 4096) `mod` 64)
           ++ byte (0x80 + (n `div` 64) `mod` 64) ++ byte (0x80 + n `mod` 64)

mutual
  export
  showType : MType -> String
  showType (I w) = "i" ++ show w
  showType F64 = "f64"
  showType (IdrData s) = "!idr.data<@" ++ s ++ ">"
  showType IdrErased = "!idr.erased"
  showType IdrStr = "!idr.str"
  showType IdrWorld = "!idr.world"
  showType (FunctionT is os) = "(" ++ types is ++ ") -> " ++ results os

  types : List MType -> String
  types [] = ""
  types [t] = showType t
  types (t :: ts) = showType t ++ ", " ++ types ts

  results : List MType -> String
  results [t@(FunctionT _ _)] = "(" ++ showType t ++ ")"
  results [t] = showType t
  results ts = "(" ++ types ts ++ ")"

||| An exact MLIR float literal: the shortest decimal that reads back as the
||| same double (the compiler runs on Chez Scheme, whose `number->string`
||| prints that), with a point as MLIR requires, and hexadecimal bits for
||| NaN and the infinities.
export
floatLiteral : Double -> String
floatLiteral d =
  if d /= d then "0x7FF8000000000000"
  else if d > 1.7976931348623157e308 then "0x7FF0000000000000"
  else if d < -1.7976931348623157e308 then "0xFFF0000000000000"
  else decimal (prim__cast_DoubleString d)
  where
    -- Chez marks subnormals with a precision suffix, `5e-324|1`.
    decimal : String -> String
    decimal s =
      let s' = fst (break (== '|') s)
          (mant, ex) = break (== 'e') s'
          mant' = if any (== '.') (unpack mant) then mant else mant ++ ".0"
      in mant' ++ ex

mutual
  showAttr : Attr -> String
  showAttr (IntA n t) = show n ++ " : " ++ showType t
  showAttr (FloatA d) = floatLiteral d ++ " : f64"
  showAttr (StrA s) = quoted s
  showAttr (BytesA s) = utf8 s
  showAttr (SymA ss) = joinBy "::" (map ("@" ++) ss)
  showAttr (TypeA t) = showType t
  showAttr (ArrayA as) = "[" ++ attrs as ++ "]"
  showAttr (I64ArrayA ns) = "array<i64" ++ (if null ns then "" else ": " ++ joinBy ", " (map show ns)) ++ ">"
  showAttr (I32ArrayA ns) = "array<i32" ++ (if null ns then "" else ": " ++ joinBy ", " (map show ns)) ++ ">"
  showAttr (DenseI64A ns) = "dense<[" ++ joinBy ", " (map show ns) ++ "]> : vector<" ++ show (length ns) ++ "xi64>"
  showAttr (DictA es) = "{" ++ entries es ++ "}"
  showAttr UnitA = "unit"

  attrs : List Attr -> String
  attrs [] = ""
  attrs [a] = showAttr a
  attrs (a :: as) = showAttr a ++ ", " ++ attrs as

  entries : List (String, Attr) -> String
  entries [] = ""
  entries [e] = entry e
  entries (e :: es) = entry e ++ ", " ++ entries es

  entry : (String, Attr) -> String
  entry (k, UnitA) = k
  entry (k, a) = k ++ " = " ++ showAttr a

||| IDR-LOC-1: the file and the 1-based line and column of the start.
span : Loc -> String
span l = if l.file == "" then "unknown"
         else quoted l.file ++ ":" ++ show (l.startLine + 1) ++ ":" ++ show (l.startCol + 1)

||| A location; a `NameLoc` (IDR-DATA-5) is the name around the span, or the
||| name alone when the span is unknown.
location : Location -> String
location (At l) = "loc(" ++ span l ++ ")"
location (Named n l) = "loc(" ++ quoted (show n) ++ (if l.file == "" then "" else "(" ++ span l ++ ")") ++ ")"

indent : Nat -> String
indent d = replicate (2 * d) ' '

mutual
  ||| An operation in generic form, at an indentation depth.
  export covering
  showOp : Nat -> MOp -> String
  showOp d op =
    indent d ++ maybe "" result op.results ++ quoted op.name ++
    "(" ++ joinBy ", " op.operands ++ ")" ++
    (if null op.successors then "" else "[" ++ joinBy ", " op.successors ++ "]") ++
    (if null op.props then "" else " <" ++ showAttr (DictA op.props) ++ ">") ++
    (if null op.regions then "" else " (" ++ regions d op.regions ++ ")") ++
    (if null op.attrs then "" else " " ++ showAttr (DictA op.attrs)) ++
    " : (" ++ types op.inputs ++ ") -> " ++ results op.outputs ++ " " ++ location op.loc
    where
      result : (String, Nat) -> String
      result (r, 1) = r ++ " = "
      result (r, n) = r ++ ":" ++ show n ++ " = "

  covering
  regions : Nat -> List Region -> String
  regions d [] = ""
  regions d [r] = region d r
  regions d (r :: rs) = region d r ++ ", " ++ regions d rs

  covering
  region : Nat -> Region -> String
  region d r = "{\n" ++ concat (zipWith (block d) (True :: map (const False) r.blocks) r.blocks) ++ indent d ++ "}"

  ||| A block. The entry block needs its label only when it has arguments or
  ||| is empty.
  covering
  block : Nat -> Bool -> Block -> String
  block d entry b =
    (if entry && null b.args && not (null b.ops) then ""
     else indent d ++ b.label ++
          (if null b.args then "" else "(" ++ joinBy ", " (map (\(v, t) => v ++ ": " ++ showType t) b.args) ++ ")") ++
          ":\n") ++
    concatMap (\o => showOp (S d) o ++ "\n") b.ops

||| A module: its body and attributes.
export covering
showModule : List (String, Attr) -> List MOp -> String
showModule as ops = showOp 0 (MkMOp Nothing "builtin.module" [] [] [] [single [] ops] as [] [] (At noLoc)) ++ "\n"
