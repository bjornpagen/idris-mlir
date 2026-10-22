-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| A module as MLIR bytecode, the file the driver reads. One encoding, the
||| same for every module:
||| version 6, the pinned reader's current one; every type, every `idr`
||| attribute, each builtin attribute that holds another, each float (as
||| its bits), each location and each string an entry of its dialect's
||| bytecode encoding (IdrisMLIR.Encoding.*), which refers to what it holds
||| by entry; only an identity layout and `arith`'s and `ub`'s attributes
||| are their text, the bytecode's own fallback, which upstream's parsers
||| read. A data type holds its family's group by entry, so a family is
||| written once however many types apply it;
||| every op name recorded as registered, as it is where the file is read;
||| every op's inherent attributes in its one attribute dictionary, with its
||| discardable ones. Creating an op moves each inherent attribute into its
||| properties (`Operation::setAttrs`), as MLIR's generic text accepts them
||| mixed in, so the writer needs no op's native encoding of its properties
||| and the properties section is empty. That carries every property the
||| Idris side writes: each is an attribute, since the generated builders
||| write no other kind (a property with a default is left at it). The ops
||| that hold the program (the module, the program) and each op of the
||| innermost one's block are isolated, their regions in a section of their
||| own; nothing nested in those is.
|||
||| Numbers are given in first use: of a string by its text, of a dialect by
||| the namespace the specification gives it, which the file spells, of an
||| op name by its dialect and its name there, and of an attribute or a type
||| by what its entry holds, its dialect and its text or its bytes, which
||| hold entry numbers, so an entry is as small as what it holds directly.
||| Bytes are written one by one, so no byte order is assumed. The functions
||| are encoded as Emit finishes each, so no value of the whole module is
||| held.
module IdrisMLIR.MLIR.Bytecode

import IdrisMLIR.Encoding.Builtin
import IdrisMLIR.Encoding.Idr
import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.MLIR
import IdrisMLIR.MLIR.Parts
import IdrisMLIR.Spec.Core.Dialect
import IdrisMLIR.Spec.Core.Enums
import IdrisMLIR.Spec.Core.Text
import IdrisMLIR.Spec.Families.Dialect
import IdrisMLIR.Spec.Families.Group
import IdrisMLIR.Spec.Families.Terms
import IdrisMLIR.Spec.Functions.Termination

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

||| `bs` from `at` in `buf`, in order; the position after them.
setAll : Buffer -> Int -> List Bits8 -> IO Int
setAll buf at [] = pure at
setAll buf at (b :: bs) = do
  setBits8 buf at b
  setAll buf (at + 1) bs

||| Bytes after those written, room made for all of them at once.
bytes : Bytes -> List Bits8 -> W ()
bytes out bs = do
  reserve out (cast (length bs))
  buf <- readIORef out.buffer
  used <- readIORef out.used
  end <- liftIO (setAll buf used bs)
  writeIORef out.used end

byte : Bytes -> Bits8 -> W ()
byte bs b = bytes bs [b]

||| The `n` low bytes of `v`, least significant first.
littleEndian : Nat -> Integer -> List Bits8
littleEndian Z v = []
littleEndian (S n) v = cast (v `mod` 256) :: littleEndian n (v `div` 256)

||| 2 to the `n`.
pow2 : Nat -> Integer
pow2 Z = 1
pow2 (S n) = 2 * pow2 n

||| Each length a PrefixVarInt has below nine bytes, `k`, with the bound its
||| values stay under, 2 to the 7k, and the scale of its `k - 1` zero bits
||| and one, 2 to the k - 1: worked out once.
lengths : List (Nat, Integer, Integer)
lengths = map (\k => (k, pow2 (7 * k), pow2 (minus k 1))) [1 .. 8]

||| A PrefixVarInt: in its first byte, a zero bit for each byte after it,
||| then a one, and the value in the bits left of the `k` bytes, 7 to a
||| byte; a value of 56 bits or more is a zero byte and its eight bytes.
prefixVarInt : Nat -> List Bits8
prefixVarInt n = go lengths
  where
    v : Integer
    v = cast n
    go : List (Nat, Integer, Integer) -> List Bits8
    go [] = 0 :: littleEndian 8 v
    go ((k, bound, scale) :: rest) =
      if v < bound then littleEndian k ((2 * v + 1) * scale) else go rest

||| A zigzagged PrefixVarInt, as MLIR writes a signed one: `n` at least 0
||| as `2n`, a negative `n` as `-2n - 1`, so that a 64-bit value takes 64
||| bits.
signedVarInt : Integer -> List Bits8
signedVarInt n = prefixVarInt (cast (if n >= 0 then 2 * n else -2 * n - 1))

||| The digits of a non-negative integer's decimal print bound its bits: a
||| number of d digits is below 10^d, below 2^(4d). A walk over its bits or
||| its words takes no more steps than that, one per step.
digitBound : Integer -> Nat
digitBound m = 4 * length (show m)

||| The bits a non-negative integer needs: none for zero.
bitLength : Integer -> Nat
bitLength m = go (digitBound m) m
  where
    go : Nat -> Integer -> Nat
    go Z _ = 0
    go (S k) v = if v == 0 then 0 else S (go k (v `div` 2))

||| The words of a non-negative integer, least significant first, up to
||| its highest that is not zero, at least one: upstream's active words.
activeWords : Integer -> List Integer
activeWords m = go (S (digitBound m `div` 64)) m
  where
    go : Nat -> Integer -> List Integer
    go Z _ = []
    go (S k) v = let rest = v `div` pow2 64 in
                 v `mod` pow2 64 :: (if rest == 0 then [] else go k rest)

||| A 64-bit word as the signed integer of its bits, as upstream zigzags
||| one.
signedWord : Integer -> Integer
signedWord u = if u >= pow2 63 then u - pow2 64 else u

||| An integer of any size as the dialect's hand codec writes it: its
||| width, the fewest bits that hold it in two's complement, then
||| upstream's integer of that width (`writeAPIntWithKnownWidth`) over its
||| bits read unsigned: a byte up to 8 bits; a zigzagged PrefixVarInt up to
||| 64; past that, how many active words, then each word zigzagged as the
||| signed word of its bits.
integerBytes : Integer -> List Bits8
integerBytes n =
  let width = S (bitLength (if n >= 0 then n else -n - 1))
      bits = if n >= 0 then n else n + pow2 width
  in prefixVarInt width ++ known width bits
  where
    known : Nat -> Integer -> List Bits8
    known width bits =
      if width <= 8 then [cast bits]
      else if width <= 64 then signedVarInt (signedWord bits)
      else let ws = activeWords bits in
           prefixVarInt (length ws) ++ concatMap (signedVarInt . signedWord) ws

varint : Bytes -> Nat -> W ()
varint bs n = bytes bs (prefixVarInt n)

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

||| Things numbered in first use by a key, each with what its entry holds.
record Numbered k p where
  constructor MkNumbered
  numbers : IORef (SortedMap k Nat)
  entries : IORef (SnocList p)
  count : IORef Nat

newNumbered : Ord k => W (Numbered k p)
newNumbered = MkNumbered <$> newIORef SortedMap.empty <*> newIORef [<] <*> newIORef 0

||| The number of `key`, given the first time with the entry `entry` makes.
number : Numbered k p -> k -> W p -> W Nat
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

entriesOf : Numbered k p -> W (List p)
entriesOf t = (<>> []) <$> readIORef t.entries

||| What an attribute or type entry holds: its text, or the bytes its
||| dialect's encoding gives it, which name what it holds by number. The
||| offset section says which.
data Payload = Textual String | Encoded (List Bits8)

||| Bytes in lexicographic order, each compared as a `Bits8`, the order
||| `compare` gives lists, without its comparison passed per element.
compareBytes : List Bits8 -> List Bits8 -> Ordering
compareBytes [] [] = EQ
compareBytes [] (_ :: _) = LT
compareBytes (_ :: _) [] = GT
compareBytes (x :: xs) (y :: ys) = case compare x y of
  EQ => compareBytes xs ys
  o => o

Eq Payload where
  Textual a == Textual b = a == b
  Encoded a == Encoded b = compareBytes a b == EQ
  _ == _ = False

Ord Payload where
  compare (Textual a) (Textual b) = compare a b
  compare (Textual _) (Encoded _) = LT
  compare (Encoded _) (Textual _) = GT
  compare (Encoded a) (Encoded b) = compareBytes a b

||| An attribute or type entry: its dialect's number, and what it holds. It
||| is its own key, so two entries are one exactly when they hold the same.
Entry : Type
Entry = (Nat, Payload)

||| What an attribute's entry is found by: what the entry holds; or a symbol
||| reference's names, whose text is the entry's, made once, the first time
||| it is numbered. Only a symbol reference's text starts with `@`, so a
||| key finds the entry its text would.
data AttrKey = Holding Entry | SymbolKey String (List String)

Eq AttrKey where
  Holding a == Holding b = a == b
  SymbolKey a as == SymbolKey b bs = a == b && as == bs
  _ == _ = False

Ord AttrKey where
  compare (Holding a) (Holding b) = compare a b
  compare (Holding _) (SymbolKey _ _) = LT
  compare (SymbolKey _ _) (Holding _) = GT
  compare (SymbolKey a as) (SymbolKey b bs) = compare (a, as) (b, bs)

||| The strings, dialects (by the namespace the file spells), op names (by
||| that namespace and their name there), attributes and types (by what
||| their entries hold) of a module, and the ops of its innermost
||| container's block, encoded.
export
record Writer where
  constructor MkWriter
  stringTable : Numbered String String
  dialectTable : Numbered String Nat
  opNameTable : Numbered (String, String) (Nat, Nat)
  attrTable : Numbered AttrKey Entry
  typeTable : Numbered Entry Entry
  ||| Those ops, encoded, how many, and how many values they define.
  body : Bytes
  count : IORef Nat
  values : IORef Nat

stringNumber : Writer -> String -> W Nat
stringNumber w s = number w.stringTable s (pure s)

||| The namespace of a dialect, as the file's dialect section spells it.
spelledDialect : Dialect -> String
spelledDialect d = wordText (namespaceWord d)

dialectNumber : Writer -> Dialect -> W Nat
dialectNumber w d = let spelled = spelledDialect d in number w.dialectTable spelled (stringNumber w spelled)

||| An op name's number: its dialect's, and its name's there.
opNameNumber : Writer -> OpName -> W Nat
opNameNumber w o =
  number w.opNameTable (spelledDialect o.dialect, o.name) $
    (,) <$> dialectNumber w o.dialect <*> stringNumber w o.name

||| A part's bytes, as (1) of the table's layout gives them: a string by
||| its number, given here in its first use.
partBytes : Writer -> Part -> W (List Bits8)
partBytes w (VarInt n) = pure (prefixVarInt n)
partBytes w (SignedVarInt n) = pure (signedVarInt n)
partBytes w (IntegerAt n) = pure (integerBytes n)
partBytes w (Flag b) = pure [if b then 1 else 0]
partBytes w (Str s) = prefixVarInt <$> stringNumber w s
partBytes w (TypeAt r) = pure (prefixVarInt r.number)
partBytes w (AttrAt r) = pure (prefixVarInt r.number)
partBytes w (OptionalAttrAt Nothing) = pure (prefixVarInt 0)
partBytes w (OptionalAttrAt (Just r)) = pure (prefixVarInt (2 * r.number + 1))

||| The parts' bytes, in order, each part's before those of the parts after
||| it, so that each byte is copied once.
encoded : Writer -> List Part -> W (List Bits8)
encoded w [] = pure []
encoded w (p :: ps) = (++) <$> partBytes w p <*> encoded w ps

||| A dialect whose types and attributes the handoff encodes natively: ours,
||| whose records the specification prints, and builtin, whose records are
||| upstream's.
data NativeDialect = IdrDialect | BuiltinDialect

||| The specification's dialect of a native one.
dialectOf : NativeDialect -> Dialect
dialectOf IdrDialect = Idr
dialectOf BuiltinDialect = Builtin

||| The type entry of `d` that `parts` encode.
typeEntry : Writer -> NativeDialect -> List Part -> W TypeRef
typeEntry w d parts = do
  e <- (\n, bs => (n, Encoded bs)) <$> dialectNumber w (dialectOf d) <*> encoded w parts
  MkTypeRef <$> number w.typeTable e (pure e)

||| The attribute entry of `d` that `parts` encode.
attrEntry : Writer -> NativeDialect -> List Part -> W AttrRef
attrEntry w d parts = do
  e <- (\n, bs => (n, Encoded bs)) <$> dialectNumber w (dialectOf d) <*> encoded w parts
  MkAttrRef <$> number w.attrTable (Holding e) (pure e)

||| An attribute's entry as its text, of its dialect.
textual : Writer -> MlirAttr -> W Entry
textual w a = (\n => (n, Textual (attrText a))) <$> dialectNumber w (attrDialect a)

||| An attribute's entry as its text: a symbol reference's found by its
||| names, so that its text is made once.
attrTextEntry : Writer -> MlirAttr -> W AttrRef
attrTextEntry w a@(SymbolRefAttr r) = MkAttrRef <$> number w.attrTable (SymbolKey r.root r.nested) (textual w a)
attrTextEntry w a = do
  e <- textual w a
  MkAttrRef <$> number w.attrTable (Holding e) (pure e)

||| A string attribute's entry, builtin's record.
stringAttrNumber : Writer -> String -> W AttrRef
stringAttrNumber w s = attrEntry w BuiltinDialect (encodeStringAttr s)

||| A span of a file, builtin's records: one point (`FileLineColLoc`), or a
||| range (`FileLineColRange`), whose numbers upstream writes by hand
||| (`writeFileLineColRangeLocs`): their count, then the start line and
||| column and the end column, on one line, or the end line and column,
||| across lines; 1-based, as MLIR's text is.
spanNumber : Writer -> String -> Span -> W AttrRef
spanNumber w file s = do
  f <- stringAttrNumber w file
  let sl = number1 s.startLine
      sc = number1 s.startCol
      el = number1 s.endLine
      ec = number1 s.endCol
  attrEntry w BuiltinDialect $
    if sl == el && sc == ec then encodeFileLineColLoc f sl sc
    else if sl == el then [VarInt fileLineColRangeCode, AttrAt f, VarInt 3, VarInt sl, VarInt sc, VarInt ec]
    else [VarInt fileLineColRangeCode, AttrAt f, VarInt 4, VarInt sl, VarInt sc, VarInt el, VarInt ec]
  where
    -- A 0-based line or column as MLIR numbers it, from 1.
    number1 : Int -> Nat
    number1 n = cast (n + 1)

||| Where code is, as a location of builtin's records: a span of a file; or,
||| in no file, `UnknownLoc`, since a location names a file.
placeNumber : Writer -> Located -> W AttrRef
placeNumber w (InModule _ (Just file) s) = spanNumber w file s
placeNumber w (InPackage file s) = spanNumber w file s
placeNumber w (InModule _ Nothing _) = attrEntry w BuiltinDialect encodeUnknownLoc
placeNumber w Unlocated = attrEntry w BuiltinDialect encodeUnknownLoc

||| A location of code from a library whose diagnostics are reported at the
||| user's caller (the registry's *Report at caller* column) fused with the
||| metadata `"library"`; any other as it is.
library : Writer -> Loc -> AttrRef -> W AttrRef
library w l inner =
  if inLibrary l
    then attrEntry w BuiltinDialect (encodeFusedLocWithMetadata [inner] !(stringAttrNumber w "library"))
    else pure inner

||| A name at a span (`NameLoc`), or at another name.
nameNumber : Writer -> Shown -> AttrRef -> W AttrRef
nameNumber w n child = attrEntry w BuiltinDialect (encodeNameLoc !(stringAttrNumber w (show n)) child)

||| A location, builtin's records: a span, or a name at one (`NameLoc`);
||| a binder's is its name fused with its identity, `#idr.binder<@def, i>`,
||| the definition by its symbol, its name at the definition the registry
||| lowered where the binder's op stands.
locationNumber : Writer -> Location -> W AttrRef
locationNumber w (At l) = library w l !(placeNumber w l.located)
locationNumber w (Named n l) = library w l !(nameNumber w n !(placeNumber w l.located))
locationNumber w (Binder n p def k) = do
  named <- case p of
    Spanned l => locationNumber w (Named n l)
    Lowered d l => library w l !(nameNumber w n !(nameNumber w d !(placeNumber w l.located)))
  definition <- attrTextEntry w (SymbolRefAttr (MkSymbolRef def []))
  identity <- attrEntry w IdrDialect (encodeBinderAttr definition k)
  attrEntry w BuiltinDialect (encodeFusedLocWithMetadata [named] identity)

------------------------------------------------------------------------------
-- Types and attributes
------------------------------------------------------------------------------

||| How a type is written: a type of a record of the two dialects'
||| encodings, as that record, each type it holds by its entry. Every type
||| the frontend writes has a record.
data Native = Record NativeDialect (List Part)

||| A record of `d`, from the parts of the one type it holds.
recordOf : NativeDialect -> (List Part -> List Part) -> List Part -> Native
recordOf d encode parts = Record d (encode parts)

||| A dimension of a shaped type as its record gives it: a dynamic one is
||| `ShapedType::kDynamic`.
extent : Dim -> Integer
extent (Static n) = cast n
extent Dynamic = dynamicExtent

||| 2 to the `n`, as a double, exactly: a power of two in range is a
||| double.
twoTo : Nat -> Double
twoTo Z = 1.0
twoTo (S n) = 2.0 * twoTo n

||| The exponent and significand of a finite positive double: the `e` with
||| `2^e <= x < 2^(e+1)`, found by halving or doubling, each exact, from
||| below 2^1024 and at least 2^-1074; and `x / 2^e`. A double has 2098
||| binary exponents, so each search ends within that many steps.
binade : Double -> (Integer, Double)
binade x = if x >= 1.0 then down 1024 x 0 else up 1075 x 0
  where
    down : Nat -> Double -> Integer -> (Integer, Double)
    down Z y e = (e, y)
    down (S k) y e = if y >= 2.0 then down k (y / 2.0) (e + 1) else (e, y)
    up : Nat -> Double -> Integer -> (Integer, Double)
    up Z y e = (e, y)
    up (S k) y e = if y < 1.0 then up k (y * 2.0) (e - 1) else (e, y)

||| A double's IEEE 754 binary64 bits, read as a signed 64-bit integer as
||| MLIR's reader takes a float of 64 bits (`readAPIntWithKnownWidth`): its
||| sign, biased exponent and fraction, computed exactly in the double's own
||| arithmetic (scaling by powers of two loses nothing), so the value that
||| crosses is the one the program wrote, on either host, with no decimal
||| text between.
export
doubleBits : Double -> Integer
doubleBits d =
  if d /= d then 0x7FF8000000000000
  else if d == 1.0 / 0.0 then 0x7FF0000000000000
  else if d == -1.0 / 0.0 then signedOf 0xFFF0000000000000
  else if d == 0.0 then (if 1.0 / d < 0.0 then signedOf 0x8000000000000000 else 0)
  else let sign = if d < 0.0 then 0x8000000000000000 else 0
           x = abs d
           (e, m) = binade x
       in signedOf (sign + magnitude e m x)
  where
    signedOf : Integer -> Integer
    signedOf u = if u >= 0x8000000000000000 then u - 0x10000000000000000 else u
    -- A normal double's fraction is its significand's 52 bits past the
    -- leading one; a subnormal's is the value in units of 2^-1074.
    magnitude : Integer -> Double -> Double -> Integer
    magnitude e m x =
      if e >= -1022
        then (e + 1023) * 0x10000000000000 + cast {to = Integer} ((m - 1.0) * twoTo 52)
        else cast {to = Integer} (x * twoTo 1074)

||| An array of values a wire lays out, as the dialect's C++ reads one: its
||| count, then each value's parts. The families' parameters still take
||| their parts laid out, so the writer lays out the array the wire's codec
||| reads.
arrayParts : (a -> List Part) -> List a -> List Part
arrayParts parts xs = VarInt (length xs) :: concatMap parts xs

||| A termination proof, as the dialect's hand codec reads it: zero for a
||| made function's acyclicity, else one more than the component Idris
||| proved it in.
proofParts : Proof -> List Part
proofParts MadeAcyclic = [VarInt 0]
proofParts (ProvedIn c) = [VarInt (S c)]

-- Every recursion is on a part of the type or attribute written, through
-- mutual helpers for lists and for each value a wire lays out, so that
-- totality holds: the wire's generated traversals take the numbering as a
-- function, through which no host can see the recursion end.
mutual
  ||| The one switch over the kinds of type: how `t` is written.
  native : Writer -> MlirType -> W Native
  native w (Idr t) = Record IdrDialect <$> idrType w t
  native w (IdrHand t) = Record IdrDialect <$> handType w t
  native w (FunctionType sig) = recordOf BuiltinDialect id <$> functionType w sig
  native w (RankedTensorType ds e) =
    recordOf BuiltinDialect (encodeRankedTensorType (map extent ds)) <$> held w e
  -- Upstream has a record for a memref in the default memory space and one
  -- for a memref in another; each names its identity layout.
  native w (MemRefType ds e Nothing) = do
    layout <- attrTextEntry w (IdentityMap (length ds))
    recordOf BuiltinDialect (\x => encodeMemRefType (map extent ds) x layout) <$> held w e
  native w (MemRefType ds e (Just space)) = do
    s <- attrNumber w space
    layout <- attrTextEntry w (IdentityMap (length ds))
    recordOf BuiltinDialect (\x => encodeMemRefTypeWithMemSpace s (map extent ds) x layout) <$> held w e
  -- Upstream packs a signless integer type's width with its signedness,
  -- 0, in the two low bits (`IntegerType`'s bytecode record).
  native w (IntegerType n) = pure (Record BuiltinDialect [VarInt integerTypeCode, VarInt (4 * n)])
  native w F64Type = pure (Record BuiltinDialect encodeFloat64Type)
  native w IndexType = pure (Record BuiltinDialect encodeIndexType)
  native w NoneType = pure (Record BuiltinDialect encodeNoneType)

  ||| An `idr` type the specification's encoders lay out whole: each type
  ||| it holds by its entry, a hand-coded parameter's parts as they are.
  ||| The frontend makes the hand-coded types typed (`handType`); the
  ||| clauses for the generated constructors that hold such parts are the
  ||| sum's, which this writer covers whole.
  idrType : Writer -> IdrType MlirType MlirAttr -> W (List Part)
  idrType w (CellType v) = encodeCellType <$> typeNumber w v
  idrType w (TokenType vs) = encodeTokenType <$> typeNumbers w vs
  idrType w (GradedType u h c) = encodeGradedType u h <$> typeNumber w c
  idrType w (LifetimeType k) = pure (encodeLifetimeType k)
  idrType w (LifetimePackageType p hs) = encodeLifetimePackageType p <$> typeNumbers w hs
  idrType w (DestType v) = encodeDestType <$> typeNumber w v
  idrType w StrType = pure encodeStrType
  idrType w BigType = pure encodeBigType
  idrType w (NatType i) = encodeNatType <$> nodesNumbered w i
  idrType w (FnType ins outs) = encodeFnType <$> typeNumbers w ins <*> typeNumbers w outs
  idrType w (LazyType v) = encodeLazyType <$> typeNumber w v
  idrType w (DataType g m is r bs) = pure (encodeDataType g m is r bs)
  idrType w (SelfType m is) = pure (encodeSelfType m is)

  ||| A hand-coded `idr` type: what it holds numbered, then its parts laid
  ||| out as the wire's codecs read them (IdrisMLIR.Encoding.Wire): a family
  ||| and a refinement as the attribute or none, terms as their array. A data
  ||| type's one constructor's undetermined binders are never the frontend's
  ||| to state: a case binds them as index variables of its region.
  handType : Writer -> HandType MlirType MlirAttr -> W (List Part)
  handType w (DataOf g m is r) = do
    g' <- attrNumber w g
    is' <- nodesNumbered w is
    r' <- maybeAttrNumber w r
    pure (encodeDataType [AttrAt g'] m (arrayParts partsTermNode is') [OptionalAttrAt r'] (arrayParts partsTermNode []))
  handType w (SelfOf m is) = encodeSelfType m . arrayParts partsTermNode <$> nodesNumbered w is

  ||| A type's entry.
  export
  typeNumber : Writer -> MlirType -> W TypeRef
  typeNumber w t = case !(native w t) of
    Record d parts => typeEntry w d parts

  ||| A type a record holds: its entry.
  held : Writer -> MlirType -> W (List Part)
  held w t = (\r => [TypeAt r]) <$> typeNumber w t

  heldAll : Writer -> List MlirType -> W (List (List Part))
  heldAll w [] = pure []
  heldAll w (t :: ts) = (::) <$> held w t <*> heldAll w ts

  ||| A builtin function type's record, from its signature.
  functionType : Writer -> Signature MlirType -> W (List Part)
  functionType w (MkSignature ins outs) = encodeFunctionType <$> heldAll w ins <*> heldAll w outs

  ||| The types of a list, each by its entry.
  typeNumbers : Writer -> List MlirType -> W (List TypeRef)
  typeNumbers w [] = pure []
  typeNumbers w (t :: ts) = (::) <$> typeNumber w t <*> typeNumbers w ts

  ||| An optional attribute's entry.
  maybeAttrNumber : Writer -> Maybe MlirAttr -> W (Maybe AttrRef)
  maybeAttrNumber w Nothing = pure Nothing
  maybeAttrNumber w (Just a) = Just <$> attrNumber w a

  ||| Index term nodes, each literal and group by its entry.
  nodesNumbered : Writer -> List (TermNode MlirType MlirAttr) -> W (List (TermNode TypeRef AttrRef))
  nodesNumbered w [] = pure []
  nodesNumbered w (n :: ns) = (::) <$> node n <*> nodesNumbered w ns
    where
      node : TermNode MlirType MlirAttr -> W (TermNode TypeRef AttrRef)
      node (TermNodeNatural k) = pure (TermNodeNatural k)
      node (TermNodeLevel k) = pure (TermNodeLevel k)
      node (TermNodeSuccessor k) = pure (TermNodeSuccessor k)
      node (TermNodeLiteral a) = TermNodeLiteral <$> attrNumber w a
      node (TermNodeConstructor g m t k) = (\g' => TermNodeConstructor g' m t k) <$> maybeAttrNumber w g
      node TermNodeOpaque = pure TermNodeOpaque

  ||| Index terms, each its nodes numbered.
  termsNumbered : Writer -> List (List (TermNode MlirType MlirAttr)) -> W (List (List (TermNode TypeRef AttrRef)))
  termsNumbered w [] = pure []
  termsNumbered w (t :: ts) = (::) <$> nodesNumbered w t <*> termsNumbered w ts

  ||| Sorts, each scalar's type attribute and member's group by its entry.
  sortsNumbered : Writer -> List (SortOf MlirType MlirAttr) -> W (List (SortOf TypeRef AttrRef))
  sortsNumbered w [] = pure []
  sortsNumbered w (x :: xs) = (::) <$> sort x <*> sortsNumbered w xs
    where
      sort : SortOf MlirType MlirAttr -> W (SortOf TypeRef AttrRef)
      sort SortOfNatSort = pure SortOfNatSort
      sort SortOfTypeSort = pure SortOfTypeSort
      sort SortOfOpaqueSort = pure SortOfOpaqueSort
      sort (SortOfScalarSort a) = SortOfScalarSort <$> attrNumber w a
      sort (SortOfFamilySort g m) = (\g' => SortOfFamilySort g' m) <$> maybeAttrNumber w g

  ||| Constructors, what each holds by its entry.
  ctorsNumbered : Writer -> List (CtorDecl MlirType MlirAttr) -> W (List (CtorDecl TypeRef AttrRef))
  ctorsNumbered w [] = pure []
  ctorsNumbered w (MkCtorDecl l bs eq fs :: cs) =
    (\bs', eq', fs', rest => MkCtorDecl l bs' eq' fs' :: rest)
      <$> sortsNumbered w bs <*> nodesNumbered w eq <*> typeNumbers w fs <*> ctorsNumbered w cs

  ||| Data members, what each holds by its entry.
  membersNumbered : Writer -> List (DataMember MlirType MlirAttr) -> W (List (DataMember TypeRef AttrRef))
  membersNumbered w [] = pure []
  membersNumbered w (MkDataMember l p loc is cs :: ms) =
    (\loc', is', cs', rest => MkDataMember l p loc' is' cs' :: rest)
      <$> attrNumber w loc <*> sortsNumbered w is <*> ctorsNumbered w cs <*> membersNumbered w ms

  ||| An attribute's entry: an array, a dictionary, a type, a string and a
  ||| float are builtin's records, every `idr` attribute the dialect's; an
  ||| identity layout and `arith`'s and `ub`'s attributes are their text.
  attrNumber : Writer -> MlirAttr -> W AttrRef
  attrNumber w (ArrayAttr as) = do
    rs <- attrNumbers w as
    attrEntry w BuiltinDialect (encodeArrayAttr rs)
  attrNumber w (DictionaryAttr es) = do
    rs <- namedNumbers w es
    attrEntry w BuiltinDialect (encodeDictionaryAttr rs)
  attrNumber w (TypeAttr t) = do
    r <- typeNumber w t
    attrEntry w BuiltinDialect (encodeTypeAttr [TypeAt r])
  attrNumber w (StringAttr s) = stringAttrNumber w s
  -- A float of 64 bits crosses as its bits, as a signed integer of its
  -- width, which is how upstream's reader takes it.
  attrNumber w (FloatAttr d t) = do
    r <- typeNumber w t
    attrEntry w BuiltinDialect [VarInt floatAttrCode, TypeAt r, SignedVarInt (doubleBits d)]
  attrNumber w (Idr a) = attrEntry w IdrDialect !(idrAttr w a)
  attrNumber w (IdrHand a) = attrEntry w IdrDialect !(handAttr w a)
  attrNumber w (LocAttr l) = locationNumber w l
  attrNumber w a = attrTextEntry w a

  ||| An `idr` attribute the specification's encoders lay out whole: each
  ||| type and attribute it holds by its entry, a hand-coded parameter's
  ||| parts as they are. The frontend makes the hand-coded attributes typed
  ||| (`handAttr`).
  idrAttr : Writer -> IdrAttr MlirType MlirAttr -> W (List Part)
  idrAttr w (BinderAttr d i) = (\d' => encodeBinderAttr d' i) <$> attrNumber w d
  idrAttr w MutableAttr = pure encodeMutableAttr
  -- A put bound, a scoped value's lifetime and a bound between lifetimes
  -- hold numbers alone, the same values at any types and attributes.
  idrAttr w (PutBoundsAttr bs) = pure (encodePutBoundsAttr (map (\(MkPutBound p n) => MkPutBound p n) bs))
  idrAttr w (GivenBackEntryAttr r rfs a afs) = pure (encodeGivenBackEntryAttr r rfs a afs)
  idrAttr w (GivenBackAttr es) = encodeGivenBackAttr <$> attrNumbers w es
  idrAttr w (LivesInAttr ps rs bs) =
    pure (encodeLivesInAttr (map livesIn ps) (map livesIn rs) (map (\(MkOutlives a b) => MkOutlives a b) bs))
    where
      livesIn : LivesIn MlirType MlirAttr -> LivesIn TypeRef AttrRef
      livesIn (MkLivesIn v l) = MkLivesIn v l
  idrAttr w (TerminatesAttr p) = pure (encodeTerminatesAttr p)
  idrAttr w (SiteAttr file line column function) = pure (encodeSiteAttr file line column function)
  idrAttr w (FamilyAttr ms) = pure (encodeFamilyAttr ms)
  idrAttr w (IndexBindersAttr ss) = pure (encodeIndexBindersAttr ss)
  idrAttr w (IndexArgsAttr ts n) = pure (encodeIndexArgsAttr ts n)
  idrAttr w (EquationAttr l r) = pure (encodeEquationAttr l r)
  idrAttr w (ConAttr d cs spine) = (\cs' => encodeConAttr d cs' spine) <$> attrNumbers w cs
  idrAttr w (BigAttr n) = pure (encodeBigAttr n)

  ||| A hand-coded `idr` attribute: what it holds numbered, then its parts
  ||| laid out as the wire's codecs read them (IdrisMLIR.Encoding.Wire): a
  ||| group's members as an array of members, each a data member; the terms
  ||| a call gives, their nodes in order, and how many terms they are.
  handAttr : Writer -> HandAttr MlirType MlirAttr -> W (List Part)
  handAttr w (FamilyOf ms) = encodeFamilyAttr . arrayParts (partsMemberOf . MemberOfData) <$> membersNumbered w ms
  handAttr w (BindersOf ss) = encodeIndexBindersAttr . arrayParts partsSortOf <$> sortsNumbered w ss
  handAttr w (ArgsOf ts) =
    (\ns => encodeIndexArgsAttr (arrayParts partsTermNode (concat ns)) (length ts)) <$> termsNumbered w ts
  handAttr w (EquationOf lhs rhs) =
    (\l, r => encodeEquationAttr (arrayParts partsTermNode l) (arrayParts partsTermNode r))
      <$> nodesNumbered w lhs <*> nodesNumbered w rhs
  handAttr w (TerminatesOf p) = pure (encodeTerminatesAttr (proofParts p))

  attrNumbers : Writer -> List MlirAttr -> W (List AttrRef)
  attrNumbers w [] = pure []
  attrNumbers w (a :: as) = (::) <$> attrNumber w a <*> attrNumbers w as

  ||| A dictionary's entries, each its name, a string, and its value, in the
  ||| op's order: the reader sorts them, as the parser does.
  namedNumbers : Writer -> List (String, MlirAttr) -> W (List (AttrRef, AttrRef))
  namedNumbers w [] = pure []
  namedNumbers w ((name, a) :: es) =
    (\n, v, rest => (n, v) :: rest) <$> stringAttrNumber w name <*> attrNumber w a <*> namedNumbers w es

------------------------------------------------------------------------------
-- The writer
------------------------------------------------------------------------------

||| A writer of a module, nothing numbered yet.
export
newWriter : IO (Either String Writer)
newWriter = runEitherT $
  MkWriter <$> newNumbered <*> newNumbered <*> newNumbered <*> newNumbered <*> newNumbered
           <*> newBytes <*> newIORef 0 <*> newIORef 0

------------------------------------------------------------------------------
-- Ops and regions
------------------------------------------------------------------------------

||| The values in scope, by SSA name, the only identity a value has in
||| `IdrisMLIR.MLIR`, with their numbers.
Scope : Type
Scope = SortedMap String Nat

||| The values a block defines directly: its arguments, then its ops'
||| results in order.
definedIn : List Argument -> List Statement -> Nat
definedIn arguments statements = length arguments + sum (map (\s => length s.op.results) statements)

||| The scope inside a block whose values start at `base`.
bindRegion : Scope -> Nat -> List Argument -> List Statement -> Scope
bindRegion scope base arguments statements =
  let args = map (.value.name) arguments
      withArgs = foldl (\m, (n, i) => insert n i m) scope (zip args [base .. base + length args])
  in bindStatements withArgs (base + length args) statements
  where
    bindStatements : Scope -> Nat -> List Statement -> Scope
    bindStatements m next [] = m
    bindStatements m next (s :: ss) =
      let names = boundNames s
          m' = foldl (\acc, (n, i) => insert n i acc) m (zip names [next .. next + length names])
      in bindStatements m' (next + length s.op.results) ss

||| The bits of an op's mask, one for each part it has.
hasAttrs, hasResults, hasOperands, hasRegions : Nat
hasAttrs = 1
hasResults = 2
hasOperands = 4
hasRegions = 16

||| The bit `b` of a mask when a part is present.
bit : Bool -> Nat -> Nat
bit present b = if present then b else 0

mutual
  ||| An op up to its regions: its name, the mask of its parts, its
  ||| location, its inherent and discardable attributes as one dictionary,
  ||| its result types and its operands' numbers.
  encodeHead : Writer -> Bytes -> Scope -> Statement -> W ()
  encodeHead w out scope (MkStatement _ o at) = do
    let attributes = o.properties ++ o.attributes
    varint out !(opNameNumber w o.name)
    byte out (cast (bit (not (null attributes)) hasAttrs + bit (not (null o.results)) hasResults
                    + bit (not (null o.operands)) hasOperands + bit (not (null o.regions)) hasRegions))
    loc <- locationNumber w at
    varint out loc.number
    unless (null attributes) $ do
      d <- attrNumber w (DictionaryAttr attributes)
      varint out d.number
    unless (null o.results) $ do
      varint out (length o.results)
      traverse_ (\t => do r <- typeNumber w t
                          varint out r.number) o.results
    unless (null o.operands) $ do
      varint out (length o.operands)
      traverse_ (operand out scope) o.operands

  operand : Bytes -> Scope -> Value -> W ()
  operand out scope v = case lookup v.name scope of
    Just n => varint out n
    Nothing => throwE ("an operand " ++ v.name ++ " that nothing in scope defines")

  ||| An op nested in a region, its regions inline, their values after
  ||| every value of the regions around them (`base`).
  encodeNested : Writer -> Bytes -> Scope -> Nat -> Statement -> W ()
  encodeNested w out scope base s@(MkStatement _ (MkOp _ _ _ regions _ _) _) = do
    encodeHead w out scope s
    unless (null regions) $ do
      varintFlag out (length regions) False
      encodeRegions w out scope base regions

  ||| Regions, in order, each as `encodeRegion` writes it.
  encodeRegions : Writer -> Bytes -> Scope -> Nat -> List Region -> W ()
  encodeRegions w out scope base [] = pure ()
  encodeRegions w out scope base (r :: rs) = do
    encodeRegion w out scope base r
    encodeRegions w out scope base rs

  ||| A region: of no blocks, or of one block, its values from `base`.
  encodeRegion : Writer -> Bytes -> Scope -> Nat -> Region -> W ()
  encodeRegion w out scope base NoBlocks = varint out 0
  encodeRegion w out scope base (MkRegion arguments statements) = do
    let n = definedIn arguments statements
        inner = bindRegion scope base arguments statements
    varint out 1
    varint out n
    varintFlag out (length statements) (not (null arguments))
    unless (null arguments) $ do
      varint out (length arguments)
      traverse_ (\a => do t <- typeNumber w a.value.type
                          varintFlag out t.number True
                          loc <- locationNumber w a.at
                          varint out loc.number) arguments
      byte out 0
    encodeStatements w out inner (base + n) statements

  ||| A region's ops, in order, each as `encodeNested` writes it.
  encodeStatements : Writer -> Bytes -> Scope -> Nat -> List Statement -> W ()
  encodeStatements w out scope base [] = pure ()
  encodeStatements w out scope base (s :: ss) = do
    encodeNested w out scope base s
    encodeStatements w out scope base ss

||| An op isolated from what holds it: its regions in a section of their
||| own, their values from 0, nothing outside in scope.
encodeIsolated : Writer -> Bytes -> Statement -> W ()
encodeIsolated w out s@(MkStatement _ (MkOp _ _ _ rs _ _) _) = do
  encodeHead w out SortedMap.empty s
  unless (null rs) $ do
    varintFlag out (length rs) True
    regions <- newBytes
    encodeRegions w regions SortedMap.empty 0 rs
    section out 4 regions

||| Encodes one op of the innermost container's block (`finish`), isolated,
||| after those before it. Its results, if any, are no value another of
||| those ops uses.
export writeTopLevel : Writer -> Statement -> IO (Either String ())
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

||| An entry's bytes after `out`'s, and whether its dialect's encoding made
||| them.
payload : Bytes -> Payload -> W Bool
payload out (Textual s) = False <$ string out s
payload out (Encoded bs) = True <$ bytes out bs

||| The attribute or type entries, after `payloads`, and the offset
||| section's groups of their sizes, each flagged when it is custom.
entries : Bytes -> Bytes -> List Entry -> W ()
entries payloads offsets es =
  traverse_ (\(d, ps) => do
               varint offsets d
               varint offsets (length ps)
               traverse_ (\p => do
                            before <- size payloads
                            custom <- payload payloads p
                            after <- size payloads
                            varintFlag offsets (cast (after - before)) custom) ps)
            (runs es)

writeBytes : File -> Bytes -> W ()
writeBytes h bs = do
  n <- size bs
  buf <- readIORef bs.buffer
  Right () <- writeBufferData h buf 0 n
    | Left (e, _) => throwE ("writing the module: " ++ show e)
  pure ()

||| An op that holds others in its one region, which the writer fills: the
||| op given that region, and its location.
public export
Container : Type
Container = (Location, Region -> Op)

mutual
  ||| The ops of a block: the first container, its region holding the
  ||| rest, or, past the last container, the ops given to `writeTopLevel`.
  ||| A container is isolated, its region in a section of its own, whose
  ||| values are its block's: the next container's results, or those ops'.
  block : Writer -> Bytes -> List Container -> W ()
  block w out [] = do
    varintFlag out !(readIORef w.count) False
    append out w.body
  block w out ((at, make) :: rest) = do
    varintFlag out 1 False
    encodeHead w out SortedMap.empty (MkStatement Nothing (make (MkRegion [] [])) at)
    varintFlag out 1 True
    region <- newBytes
    varint region 1
    varint region !(defined w rest)
    block w region rest
    section out 4 region

  ||| The values the region of a container defines directly.
  defined : Writer -> List Container -> W Nat
  defined w [] = readIORef w.values
  defined w ((_, make) :: _) = pure (length (make (MkRegion [] [])).results)

||| Writes the file: the header, then the IR, whose top-level block holds
||| the first of `containers`, each holding the next and the last the ops
||| given to `writeTopLevel`, in order; then the attributes and types, the
||| dialects and op names, the strings, and the properties, which no op
||| holds natively.
export finish : Writer -> File -> List Container -> IO (Either String ())
finish w h containers = runEitherT $ do
  ir <- newBytes
  block w ir containers
  -- What the IR numbered, now complete.
  attrs <- entriesOf w.attrTable
  types <- entriesOf w.typeTable
  payloads <- newBytes
  offsets <- newBytes
  varint offsets (length attrs)
  varint offsets (length types)
  entries payloads offsets attrs
  entries payloads offsets types
  ops <- entriesOf w.opNameTable
  dialects <- entriesOf w.dialectTable
  ds <- newBytes
  varint ds (length dialects)
  traverse_ (\s => varintFlag ds s False) dialects
  varint ds (length ops)
  traverse_ (\(d, ns) => do
               varint ds d
               varint ds (length ns)
               traverse_ (\s => varintFlag ds s True) ns)
            (runs ops)
  strings <- entriesOf w.stringTable
  ss <- newBytes
  varint ss (length strings)
  traverse_ (\s => varint ss (cast (stringByteLength s + 1))) (reverse strings)
  traverse_ (string ss) strings
  file <- newBytes
  bytes file [0x4D, 0x4C, 0xEF, 0x52]
  varint file 6
  string file "idris-mlir"
  section file 4 ir
  section file 3 offsets
  section file 2 payloads
  section file 1 ds
  section file 0 ss
  section file 8 !newBytes
  writeBytes h file
