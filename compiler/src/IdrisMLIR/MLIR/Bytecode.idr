-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| A module as MLIR bytecode, the file the driver reads. One encoding, the
||| same for every module:
||| version 6, the pinned reader's current one; every attribute and type as
||| its text, the bytecode's own fallback, which a recursive data type needs,
||| since its text names itself and no cycle of entries reaches the reader;
||| every op name recorded as not registered, so that the reader takes an
||| op's properties as one dictionary and sets them as the generic text
||| form's parse does, and the writer needs no op's native encoding of its
||| properties. The module op and each op of its block are isolated, their
||| regions in a section of their own; nothing nested is.
|||
||| Numbers are given in first use: of a string, a dialect, an op name, an
||| attribute or a type by its text. Bytes are written one by one, so no
||| byte order is assumed. The ops of the module are encoded as Emit
||| finishes each, so no value of the whole module is held.
module IdrisMLIR.MLIR.Bytecode

import IdrisMLIR.MLIR

import Control.Monad.Error.Either
import Data.Buffer
import Data.IORef
import Data.List
import Data.SnocList
import Data.SortedMap
import Data.String
import System.File
import System.File.Buffer

%default total

||| What the writer does: IO, or the message of what it could not do.
W : Type -> Type
W = EitherT String IO

------------------------------------------------------------------------------
-- Bytes
------------------------------------------------------------------------------

||| A run of bytes that grows as it is written, doubling, so that writing n
||| bytes copies fewer than 2n.
record Bytes where
  constructor MkBytes
  buffer : IORef Buffer
  capacity : IORef Int
  used : IORef Int

newBytes : W Bytes
newBytes = do
  Just b <- newBuffer 1
    | Nothing => throwE "cannot allocate a buffer"
  MkBytes <$> newIORef b <*> newIORef 1 <*> newIORef 0

size : Bytes -> W Int
size bs = readIORef bs.used

||| Room for `n` more bytes.
reserve : Bytes -> Int -> W ()
reserve bs n = do
  cap <- readIORef bs.capacity
  used <- readIORef bs.used
  when (used + n > cap) $ do
    let cap' = max (2 * cap) (used + n)
    old <- readIORef bs.buffer
    Just new <- newBuffer cap'
      | Nothing => throwE "cannot allocate a buffer"
    copyData old 0 used new 0
    writeIORef bs.buffer new
    writeIORef bs.capacity cap'

byte : Bytes -> Bits8 -> W ()
byte bs b = do
  reserve bs 1
  used <- readIORef bs.used
  buf <- readIORef bs.buffer
  setBits8 buf used b
  writeIORef bs.used (used + 1)

||| The `n` low bytes of `v`, least significant first.
littleEndian : Bytes -> Nat -> Integer -> W ()
littleEndian bs Z v = pure ()
littleEndian bs (S n) v = do
  byte bs (cast (v `mod` 256))
  littleEndian bs n (v `div` 256)

||| 2 to the `n`.
pow2 : Nat -> Integer
pow2 Z = 1
pow2 (S n) = 2 * pow2 n

||| A PrefixVarInt: in its first byte, a zero bit for each byte after it,
||| then a one, and the value in the bits left of the `k` bytes, 7 to a
||| byte; a value of 56 bits or more is a zero byte and its eight bytes.
varint : Bytes -> Nat -> W ()
varint bs n = go 1 8
  where
    v : Integer
    v = cast n
    go : (k : Nat) -> (left : Nat) -> W ()
    go k Z = byte bs 0 >> littleEndian bs 8 v
    go k (S left) =
      if v < pow2 (7 * k) then littleEndian bs k ((2 * v + 1) * pow2 (minus k 1))
      else go (S k) left

||| A varint whose low bit is `flag`.
varintFlag : Bytes -> Nat -> Bool -> W ()
varintFlag bs n flag = varint bs (2 * n + (if flag then 1 else 0))

||| A string's UTF-8 bytes and a NUL.
string : Bytes -> String -> W ()
string bs s = do
  let n = stringByteLength s
  reserve bs (n + 1)
  used <- readIORef bs.used
  buf <- readIORef bs.buffer
  setString buf used s
  writeIORef bs.used (used + n)
  byte bs 0

||| `from`'s bytes after `into`'s.
append : Bytes -> Bytes -> W ()
append into from = do
  n <- size from
  reserve into n
  used <- readIORef into.used
  src <- readIORef from.buffer
  dst <- readIORef into.buffer
  copyData src 0 n dst used
  writeIORef into.used (used + n)

||| A section: its id, no alignment, its length, its bytes.
section : Bytes -> Bits8 -> Bytes -> W ()
section bs code contents = do
  byte bs code
  varint bs (cast !(size contents))
  append bs contents

------------------------------------------------------------------------------
-- Numbering
------------------------------------------------------------------------------

||| Things numbered in first use by their text, each with what its entry
||| holds.
record Numbered p where
  constructor MkNumbered
  numbers : IORef (SortedMap String Nat)
  entries : IORef (SnocList p)
  count : IORef Nat

newNumbered : W (Numbered p)
newNumbered = MkNumbered <$> newIORef SortedMap.empty <*> newIORef [<] <*> newIORef 0

||| The number of `key`, given the first time with the entry `entry` makes.
number : Numbered p -> String -> W p -> W Nat
number t key entry = do
  ns <- readIORef t.numbers
  case lookup key ns of
    Just n => pure n
    Nothing => do
      e <- entry
      n <- readIORef t.count
      writeIORef t.numbers (insert key n ns)
      modifyIORef t.entries (:< e)
      writeIORef t.count (S n)
      pure n

entriesOf : Numbered p -> W (List p)
entriesOf t = (<>> []) <$> readIORef t.entries

||| The strings, dialects (by their name's string), op names (by dialect
||| and name), attributes and types (by dialect and text) of a module, and
||| its top-level ops, encoded.
export
record Writer where
  constructor MkWriter
  stringTable : Numbered String
  dialectTable : Numbered Nat
  opNameTable : Numbered (Nat, Nat)
  attrTable : Numbered (Nat, String)
  typeTable : Numbered (Nat, String)
  ||| The top-level ops, encoded, how many, and how many values they define.
  body : Bytes
  count : IORef Nat
  values : IORef Nat

export
newWriter : IO (Either String Writer)
newWriter = runEitherT $
  MkWriter <$> newNumbered <*> newNumbered <*> newNumbered <*> newNumbered <*> newNumbered
           <*> newBytes <*> newIORef 0 <*> newIORef 0

stringNumber : Writer -> String -> W Nat
stringNumber w s = number w.stringTable s (pure s)

dialectNumber : Writer -> String -> W Nat
dialectNumber w d = number w.dialectTable d (stringNumber w d)

||| An op name's number: its dialect is what precedes its first dot.
opNameNumber : Writer -> String -> W Nat
opNameNumber w name =
  let (dialect, rest) = break (== '.') name in
  number w.opNameTable name $ do
    d <- dialectNumber w dialect
    s <- stringNumber w (pack (drop 1 (unpack rest)))
    pure (d, s)

covering
attrNumber : Writer -> MlirAttr -> W Nat
attrNumber w a =
  let text = attrText a in
  number w.attrTable text ((\d => (d, text)) <$> dialectNumber w (attrDialect a))

covering
typeNumber : Writer -> MlirType -> W Nat
typeNumber w t =
  let text = typeText t in
  number w.typeTable text ((\d => (d, text)) <$> dialectNumber w (typeDialect t))

||| A location is a builtin attribute.
locationNumber : Writer -> Location -> W Nat
locationNumber w at =
  let text = location at in
  number w.attrTable text ((\d => (d, text)) <$> dialectNumber w "builtin")

------------------------------------------------------------------------------
-- Ops and regions
------------------------------------------------------------------------------

||| The values in scope, by SSA name, with their numbers.
Scope : Type
Scope = SortedMap String Nat

||| The values a region defines directly: its block's arguments, then its
||| ops' results in order.
definedIn : Region -> Nat
definedIn r = length r.arguments + sum (map (\s => length s.op.results) r.statements)

||| The scope inside a region whose values start at `base`.
bindRegion : Scope -> Nat -> Region -> Scope
bindRegion scope base r =
  let args = map (.value.name) r.arguments
      withArgs = foldl (\m, (n, i) => insert n i m) scope (zip args [base .. base + length args])
  in bindStatements withArgs (base + length args) r.statements
  where
    bindStatements : Scope -> Nat -> List Statement -> Scope
    bindStatements m next [] = m
    bindStatements m next (s :: ss) =
      let names = boundNames s
          m' = foldl (\acc, (n, i) => insert n i acc) m (zip names [next .. next + length names])
      in bindStatements m' (next + length s.op.results) ss

||| The bits of an op's mask, one for each part it has.
hasAttrs, hasResults, hasOperands, hasRegions, hasProperties : Nat
hasAttrs = 1
hasResults = 2
hasOperands = 4
hasRegions = 16
hasProperties = 64

||| The bit `b` of a mask when a part is present.
bit : Bool -> Nat -> Nat
bit present b = if present then b else 0

mutual
  ||| An op up to its regions: its name, the mask of its parts, its
  ||| location, its attributes and properties as a dictionary each, its
  ||| result types and its operands' numbers.
  covering
  encodeHead : Writer -> Bytes -> Scope -> Statement -> W ()
  encodeHead w out scope (MkStatement _ o at) = do
    varint out !(opNameNumber w o.name)
    byte out (cast (bit (not (null o.attributes)) hasAttrs + bit (not (null o.results)) hasResults
                    + bit (not (null o.operands)) hasOperands + bit (not (null o.regions)) hasRegions
                    + bit (not (null o.properties)) hasProperties))
    varint out !(locationNumber w at)
    unless (null o.attributes) $ do
      n <- attrNumber w (DictionaryAttr o.attributes)
      varint out n
    unless (null o.properties) $ do
      n <- attrNumber w (DictionaryAttr o.properties)
      varint out n
    unless (null o.results) $ do
      varint out (length o.results)
      traverse_ (\t => varint out !(typeNumber w t)) o.results
    unless (null o.operands) $ do
      varint out (length o.operands)
      traverse_ (operand out scope) o.operands

  covering
  operand : Bytes -> Scope -> Value -> W ()
  operand out scope v = case lookup v.name scope of
    Just n => varint out n
    Nothing => throwE ("an operand " ++ v.name ++ " that nothing in scope defines")

  ||| An op nested in a region, its regions inline, their values after
  ||| every value of the regions around them (`base`).
  covering
  encodeNested : Writer -> Bytes -> Scope -> Nat -> Statement -> W ()
  encodeNested w out scope base s = do
    encodeHead w out scope s
    unless (null s.op.regions) $ do
      varintFlag out (length s.op.regions) False
      traverse_ (encodeRegion w out scope base) s.op.regions

  ||| A region of one block, its values from `base`.
  covering
  encodeRegion : Writer -> Bytes -> Scope -> Nat -> Region -> W ()
  encodeRegion w out scope base r = do
    let n = definedIn r
        inner = bindRegion scope base r
    varint out 1
    varint out n
    varintFlag out (length r.statements) (not (null r.arguments))
    unless (null r.arguments) $ do
      varint out (length r.arguments)
      traverse_ (\a => do varintFlag out !(typeNumber w a.value.type) True
                          varint out !(locationNumber w a.at)) r.arguments
      byte out 0
    traverse_ (encodeNested w out inner (base + n)) r.statements

||| An op isolated from what holds it: its regions in a section of their
||| own, their values from 0, nothing outside in scope.
covering
encodeIsolated : Writer -> Bytes -> Statement -> W ()
encodeIsolated w out s = do
  encodeHead w out SortedMap.empty s
  unless (null s.op.regions) $ do
    varintFlag out (length s.op.regions) True
    regions <- newBytes
    traverse_ (encodeRegion w regions SortedMap.empty 0) s.op.regions
    section out 4 regions

||| Encodes one top-level op of the module, isolated, after those before
||| it. Its results, if any, are no value another top-level op uses.
export covering
writeTopLevel : Writer -> Statement -> IO (Either String ())
writeTopLevel w s = runEitherT $ do
  encodeIsolated w w.body s
  modifyIORef w.count S
  modifyIORef w.values (+ length s.op.results)

------------------------------------------------------------------------------
-- The file
------------------------------------------------------------------------------

||| Consecutive entries of one dialect: each run with its dialect.
runs : List (Nat, a) -> List (Nat, List a)
runs [] = []
runs ((d, x) :: rest) = case runs rest of
  (d', xs) :: more => if d == d' then (d, x :: xs) :: more else (d, [x]) :: (d', xs) :: more
  [] => [(d, [x])]

||| The attribute or type entries: their texts, and the offset section's
||| groups of their sizes.
covering
entryTexts : Bytes -> Bytes -> List (Nat, String) -> W ()
entryTexts texts offsets entries = do
  traverse_ (\(_, t) => string texts t) entries
  traverse_ (\(d, ts) => do
               varint offsets d
               varint offsets (length ts)
               traverse_ (\t => varintFlag offsets (cast (stringByteLength t + 1)) False) ts)
            (runs entries)

writeBytes : File -> Bytes -> W ()
writeBytes h bs = do
  n <- size bs
  buf <- readIORef bs.buffer
  Right () <- writeBufferData h buf 0 n
    | Left (e, _) => throwE ("writing the module: " ++ show e)
  pure ()

||| Writes the file: the header, then the IR (the module op `m` at `at`,
||| whose one region holds the ops given to `writeTopLevel`, in order; `m`'s
||| own region holds none), the attributes and types, the dialects and op
||| names, the strings, and the properties, which no op holds natively.
export covering
finish : Writer -> File -> Location -> Op -> IO (Either String ())
finish w h at m = runEitherT $ do
  let [MkRegion [] []] = m.regions
    | _ => throwE "the module op holds a region of its own ops"
  -- The IR: the top-level block, holding the module op.
  ir <- newBytes
  varintFlag ir 1 False
  encodeHead w ir SortedMap.empty (MkStatement Nothing m at)
  varintFlag ir 1 True
  region <- newBytes
  varint region 1
  varint region !(readIORef w.values)
  varintFlag region !(readIORef w.count) False
  append region w.body
  section ir 4 region
  -- What the IR numbered, now complete.
  attrs <- entriesOf w.attrTable
  types <- entriesOf w.typeTable
  texts <- newBytes
  offsets <- newBytes
  varint offsets (length attrs)
  varint offsets (length types)
  entryTexts texts offsets attrs
  entryTexts texts offsets types
  ops <- entriesOf w.opNameTable
  dialects <- entriesOf w.dialectTable
  ds <- newBytes
  varint ds (length dialects)
  traverse_ (\s => varintFlag ds s False) dialects
  varint ds (length ops)
  traverse_ (\(d, ns) => do
               varint ds d
               varint ds (length ns)
               traverse_ (\s => varintFlag ds s False) ns)
            (runs ops)
  strings <- entriesOf w.stringTable
  ss <- newBytes
  varint ss (length strings)
  traverse_ (\s => varint ss (cast (stringByteLength s + 1))) (reverse strings)
  traverse_ (string ss) strings
  file <- newBytes
  traverse_ (byte file) [0x4D, 0x4C, 0xEF, 0x52]
  varint file 6
  string file "idris-mlir"
  section file 4 ir
  section file 3 offsets
  section file 2 texts
  section file 1 ds
  section file 0 ss
  section file 8 !newBytes
  writeBytes h file
