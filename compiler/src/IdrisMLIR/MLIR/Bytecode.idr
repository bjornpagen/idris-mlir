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
||| its position in the specification's closed set, of an op name by its
||| dialect's position and its name there, and of an attribute or a type
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

||| The strings, dialects (by their position among the specification's),
||| op names (by their dialect's position and their name there), attributes
||| and types (by what their entries hold) of a module, and the ops of its
||| innermost container's block, encoded.
export
record Writer where
  constructor MkWriter
  stringTable : Numbered String String
  dialectTable : Numbered Nat Nat
  opNameTable : Numbered (Nat, String) (Nat, Nat)
  attrTable : Numbered AttrKey Entry
  typeTable : Numbered Entry Entry
  ||| Those ops, encoded, how many, and how many values they define.
  body : Bytes
  count : IORef Nat
  values : IORef Nat
  ||| Eight bytes, in which a float is stored to read its bits back.
  word : Buffer

stringNumber : Writer -> String -> W Nat
stringNumber w s = number w.stringTable s (pure s)

||| A dialect's number, given in its first use with its entry: the string
||| of its namespace, which the file's dialect section spells.
dialectNumber : Writer -> Dialect -> W Nat
dialectNumber w d = number w.dialectTable (position dialectClosed d) (stringNumber w (wordText (namespaceWord d)))

||| An op name's number: its dialect's, and its name's there.
opNameNumber : Writer -> OpName -> W Nat
opNameNumber w o =
  number w.opNameTable (position dialectClosed o.dialect, o.name) $
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

||| Where code is, as a location of builtin's records: a span of a file; a
||| span of a module the session never read, as the location gives it, the
||| module's name standing for its file (`Text.placeText`); or, in no file,
||| `UnknownLoc`, since a location names a file.
placeNumber : Writer -> Located -> W AttrRef
placeNumber w (InModule _ (Just file) s) = spanNumber w file s
placeNumber w (InUnreadModule m s) = spanNumber w (show m) s
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

||| An Idris name at a span (`NameLoc`): a named location's records, and
||| those of a binder at a span, which is its name there.
namedNumber : Writer -> Shown -> Loc -> W AttrRef
namedNumber w n l = library w l !(nameNumber w n !(placeNumber w l.located))

||| A location, builtin's records: a span, or a name at one (`NameLoc`);
||| a binder's is its name fused with its identity, `#idr.binder<@def, i>`,
||| the definition by its symbol, its name at the definition the registry
||| lowered where the binder's op stands.
locationNumber : Writer -> Location -> W AttrRef
locationNumber w (At l) = library w l !(placeNumber w l.located)
locationNumber w (Named n l) = namedNumber w n l
locationNumber w (Binder n p def k) = do
  named <- case p of
    Spanned l => namedNumber w n l
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

||| A double's IEEE 754 binary64 bits, read as a signed 64-bit integer as
||| MLIR's reader takes a float of 64 bits (`readAPIntWithKnownWidth`): the
||| double stored in the writer's word and the word loaded back, base's
||| buffer operations, whose one meaning is the runtime's on either host.
||| The store and the load are in the same byte order, the machine's, so
||| the order cancels and never reaches the file. Every double crosses as
||| the program holds it, the infinities, a NaN with its sign and payload,
||| negative zero and the subnormals among them, with no arithmetic, no
||| exact number and no decimal text between.
doubleBits : Writer -> Double -> W Integer
doubleBits w d = do
  setDouble w.word 0 d
  cast <$> getInt64 w.word 0

||| A type a record holds, as the record lays it out: its entry.
typePart : TypeRef -> List Part
typePart r = [TypeAt r]

-- The layers of the `idr` dialect's types and attributes that hold no type
-- and no attribute, at the types of what the writer has numbered.

numberKind : LifetimeKindOf MlirType MlirAttr -> LifetimeKindOf TypeRef AttrRef
numberKind (LifetimeKindOfView MkLifetimeKindView) = LifetimeKindOfView MkLifetimeKindView
numberKind (LifetimeKindOfRoom MkLifetimeKindRoom) = LifetimeKindOfRoom MkLifetimeKindRoom
numberKind (LifetimeKindOfCursor MkLifetimeKindCursor) = LifetimeKindOfCursor MkLifetimeKindCursor
numberKind (LifetimeKindOfHome (MkLifetimeKindHome site)) = LifetimeKindOfHome (MkLifetimeKindHome site)

numberTermination : TerminationProof MlirType MlirAttr -> TerminationProof TypeRef AttrRef
numberTermination (TerminationProofComponent (MkComponentProof c)) = TerminationProofComponent (MkComponentProof c)
numberTermination (TerminationProofAcyclic MkAcyclicProof) = TerminationProofAcyclic MkAcyclicProof

numberPutBound : PutBound MlirType MlirAttr -> PutBound TypeRef AttrRef
numberPutBound (MkPutBound p n) = MkPutBound p n

numberLivesIn : LivesIn MlirType MlirAttr -> LivesIn TypeRef AttrRef
numberLivesIn (MkLivesIn v l) = MkLivesIn v l

numberOutlives : Outlives MlirType MlirAttr -> Outlives TypeRef AttrRef
numberOutlives (MkOutlives longer shorter) = MkOutlives longer shorter

-- The writer numbers what a type or an attribute holds by matching each
-- layer it holds them in, the `idr` dialect's printed layers
-- (IdrisMLIR.Encoding.Idr, .Wire) among them, numbering each type and
-- attribute the match takes out, in the layer's order, before the layer's
-- own entry. Each walk is called only on a part of the value matched, so
-- every one ends, and Idris checks it: its totality checker follows a
-- recursion into what a match takes apart, and loses it in a traversal
-- given the numbering as a function. So the walk is written here, a clause
-- per constructor, and a constructor or a field the specification adds is
-- a missing clause or a type error here until the walk numbers it.
mutual
  ||| The one switch over the kinds of type: how `t` is written. An `idr`
  ||| type is the specification's encoding of it, what it holds by its
  ||| entries.
  native : Writer -> MlirType -> W Native
  native w (Idr t) = Record IdrDialect . encodeIdrType <$> numberIdrType w t
  native w (FunctionType (MkSignature ins outs)) =
    (\is, os => Record BuiltinDialect (encodeFunctionType (map typePart is) (map typePart os)))
      <$> typeNumbers w ins <*> typeNumbers w outs
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
  native w MlirType.TokenType = pure (Record BuiltinDialect IdrisMLIR.Encoding.Builtin.encodeTokenType)

  ||| A type's entry.
  export
  typeNumber : Writer -> MlirType -> W TypeRef
  typeNumber w t = case !(native w t) of
    Record d parts => typeEntry w d parts

  ||| Types' entries, in order.
  typeNumbers : Writer -> List MlirType -> W (List TypeRef)
  typeNumbers w [] = pure []
  typeNumbers w (t :: ts) = (::) <$> typeNumber w t <*> typeNumbers w ts

  ||| A type a record holds, laid out: its entry.
  held : Writer -> MlirType -> W (List Part)
  held w t = typePart <$> typeNumber w t

  ||| An `idr` type, each type and attribute it holds numbered.
  numberIdrType : Writer -> IdrType MlirType MlirAttr -> W (IdrType TypeRef AttrRef)
  numberIdrType w (DataType g m is r bs) =
    DataType <$> attrNumber w g <*> pure m <*> numberTermNodes w is <*> numberOptional w r <*> numberTermNodes w bs
  numberIdrType w (SelfType m is) = SelfType m <$> numberTermNodes w is
  numberIdrType w (GradedType u h c) = GradedType u h <$> typeNumber w c
  numberIdrType w (LifetimeType k) = pure (LifetimeType (numberKind k))
  numberIdrType w (LifetimePackageType p hs) = LifetimePackageType p <$> typeNumbers w hs
  numberIdrType w StrType = pure StrType
  numberIdrType w BigType = pure BigType
  numberIdrType w (NatType is) = NatType <$> numberTermNodes w is
  numberIdrType w (CellType v) = CellType <$> typeNumber w v
  numberIdrType w (ReuseTokenType ss) = ReuseTokenType <$> typeNumbers w ss
  numberIdrType w (FnType ins outs) = FnType <$> typeNumbers w ins <*> typeNumbers w outs
  numberIdrType w (LazyType v) = LazyType <$> typeNumber w v
  numberIdrType w (DestType v) = DestType <$> typeNumber w v

  ||| An index term's node, the attribute it holds numbered.
  numberTermNode : Writer -> TermNode MlirType MlirAttr -> W (TermNode TypeRef AttrRef)
  numberTermNode w (TermNodeNatural v) = pure (TermNodeNatural v)
  numberTermNode w (TermNodeLevel v) = pure (TermNodeLevel v)
  numberTermNode w (TermNodeSuccessor v) = pure (TermNodeSuccessor v)
  numberTermNode w (TermNodeLiteral a) = TermNodeLiteral <$> attrNumber w a
  numberTermNode w (TermNodeConstructor a m v n) = (\a' => TermNodeConstructor a' m v n) <$> numberOptional w a
  numberTermNode w TermNodeOpaque = pure TermNodeOpaque

  ||| An index term's nodes, in order.
  numberTermNodes : Writer -> List (TermNode MlirType MlirAttr) -> W (List (TermNode TypeRef AttrRef))
  numberTermNodes w [] = pure []
  numberTermNodes w (n :: ns) = (::) <$> numberTermNode w n <*> numberTermNodes w ns

  ||| The sort of an index binder, the attribute it holds numbered.
  numberSort : Writer -> SortOf MlirType MlirAttr -> W (SortOf TypeRef AttrRef)
  numberSort w SortOfNatSort = pure SortOfNatSort
  numberSort w SortOfTypeSort = pure SortOfTypeSort
  numberSort w SortOfOpaqueSort = pure SortOfOpaqueSort
  numberSort w (SortOfScalarSort a) = SortOfScalarSort <$> attrNumber w a
  numberSort w (SortOfFamilySort a m) = (\a' => SortOfFamilySort a' m) <$> numberOptional w a

  numberSorts : Writer -> List (SortOf MlirType MlirAttr) -> W (List (SortOf TypeRef AttrRef))
  numberSorts w [] = pure []
  numberSorts w (s :: ss) = (::) <$> numberSort w s <*> numberSorts w ss

  ||| A constructor's declaration, its sorts, equation and fields numbered.
  numberCtor : Writer -> CtorDecl MlirType MlirAttr -> W (CtorDecl TypeRef AttrRef)
  numberCtor w (MkCtorDecl l bs eq fs) =
    MkCtorDecl l <$> numberSorts w bs <*> numberTermNodes w eq <*> typeNumbers w fs

  numberCtors : Writer -> List (CtorDecl MlirType MlirAttr) -> W (List (CtorDecl TypeRef AttrRef))
  numberCtors w [] = pure []
  numberCtors w (c :: cs) = (::) <$> numberCtor w c <*> numberCtors w cs

  ||| A label's declaration, its function, sorts, equation and fields
  ||| numbered.
  numberLabel : Writer -> LabelDecl MlirType MlirAttr -> W (LabelDecl TypeRef AttrRef)
  numberLabel w (MkLabelDecl l f bs eq fs) =
    MkLabelDecl l <$> attrNumber w f <*> numberSorts w bs <*> numberTermNodes w eq <*> typeNumbers w fs

  numberLabels : Writer -> List (LabelDecl MlirType MlirAttr) -> W (List (LabelDecl TypeRef AttrRef))
  numberLabels w [] = pure []
  numberLabels w (l :: ls) = (::) <$> numberLabel w l <*> numberLabels w ls

  numberMemoLabels : Writer -> List (MemoLabelDecl MlirType MlirAttr) -> W (List (MemoLabelDecl TypeRef AttrRef))
  numberMemoLabels w [] = pure []
  numberMemoLabels w (MkMemoLabelDecl mode l :: ls) = (::) <$> (MkMemoLabelDecl mode <$> numberLabel w l) <*> numberMemoLabels w ls

  ||| A data member of a family, its location, sorts and constructors
  ||| numbered.
  numberDataMember : Writer -> DataMember MlirType MlirAttr -> W (DataMember TypeRef AttrRef)
  numberDataMember w (MkDataMember l p loc is cs) =
    MkDataMember l p <$> attrNumber w loc <*> numberSorts w is <*> numberCtors w cs

  ||| A member of a family, of its kind, what it holds numbered.
  numberMember : Writer -> MemberOf MlirType MlirAttr -> W (MemberOf TypeRef AttrRef)
  numberMember w (MemberOfData d) = MemberOfData <$> numberDataMember w d
  numberMember w (MemberOfClosures (MkClosuresMember l is ls)) =
    (\is', ls' => MemberOfClosures (MkClosuresMember l is' ls')) <$> numberSorts w is <*> numberLabels w ls
  numberMember w (MemberOfMemo (MkMemoMember l is ls f)) =
    (\is', ls', f' => MemberOfMemo (MkMemoMember l is' ls' f'))
      <$> numberSorts w is <*> numberMemoLabels w ls <*> typeNumber w f
  numberMember w (MemberOfFrames (MkFramesMember l cs)) = MemberOfFrames . MkFramesMember l <$> numberCtors w cs

  numberMembers : Writer -> List (MemberOf MlirType MlirAttr) -> W (List (MemberOf TypeRef AttrRef))
  numberMembers w [] = pure []
  numberMembers w (m :: ms) = (::) <$> numberMember w m <*> numberMembers w ms

  ||| An attribute a layer may leave out: its entry, when it is there.
  numberOptional : Writer -> Maybe MlirAttr -> W (Maybe AttrRef)
  numberOptional w Nothing = pure Nothing
  numberOptional w (Just a) = Just <$> attrNumber w a

  ||| An attribute's entry: an array, a dictionary, a type, a string and a
  ||| float are builtin's records, every `idr` attribute the dialect's, the
  ||| specification's encoding of it, what it holds by its entries; an
  ||| identity layout and the spelled upstream attributes are their text.
  attrNumber : Writer -> MlirAttr -> W AttrRef
  attrNumber w (ArrayAttr as) = do
    rs <- attrNumbers w as
    attrEntry w BuiltinDialect (encodeArrayAttr rs)
  attrNumber w (DictionaryAttr es) = do
    rs <- numberEntries w es
    attrEntry w BuiltinDialect (encodeDictionaryAttr rs)
  attrNumber w (TypeAttr t) = do
    r <- typeNumber w t
    attrEntry w BuiltinDialect (encodeTypeAttr [TypeAt r])
  attrNumber w (StringAttr s) = stringAttrNumber w s
  -- A float of 64 bits crosses as its bits, as a signed integer of its
  -- width, which is how upstream's reader takes it.
  attrNumber w (FloatAttr d t) = do
    r <- typeNumber w t
    bits <- doubleBits w d
    attrEntry w BuiltinDialect [VarInt floatAttrCode, TypeAt r, SignedVarInt bits]
  attrNumber w (Idr a) = attrEntry w IdrDialect . encodeIdrAttr =<< numberIdrAttr w a
  attrNumber w (LocAttr l) = locationNumber w l
  attrNumber w a = attrTextEntry w a

  ||| Attributes' entries, in order.
  attrNumbers : Writer -> List MlirAttr -> W (List AttrRef)
  attrNumbers w [] = pure []
  attrNumbers w (a :: as) = (::) <$> attrNumber w a <*> attrNumbers w as

  ||| A dictionary's entries, each its name, a string, and its value, in the
  ||| op's order: the reader sorts them, as the parser does.
  numberEntries : Writer -> List (String, MlirAttr) -> W (List (AttrRef, AttrRef))
  numberEntries w [] = pure []
  numberEntries w ((name, a) :: es) =
    (\n, r, rs => (n, r) :: rs) <$> stringAttrNumber w name <*> attrNumber w a <*> numberEntries w es

  ||| An `idr` attribute, each type and attribute it holds numbered.
  numberIdrAttr : Writer -> IdrAttr MlirType MlirAttr -> W (IdrAttr TypeRef AttrRef)
  numberIdrAttr w (BinderAttr d i) = (\d' => BinderAttr d' i) <$> attrNumber w d
  numberIdrAttr w (TerminatesAttr t) = pure (TerminatesAttr (numberTermination t))
  numberIdrAttr w (PutBoundsAttr bs) = pure (PutBoundsAttr (map numberPutBound bs))
  numberIdrAttr w (LivesInAttr ps rs bs) =
    pure (LivesInAttr (map numberLivesIn ps) (map numberLivesIn rs) (map numberOutlives bs))
  numberIdrAttr w (GivenBackEntryAttr r rfs a afs) = pure (GivenBackEntryAttr r rfs a afs)
  numberIdrAttr w (GivenBackAttr es) = GivenBackAttr <$> attrNumbers w es
  numberIdrAttr w (ExtentAttr sd p a t) = ExtentAttr sd p a <$> numberTermNodes w t
  numberIdrAttr w (ExtentsAttr es) = ExtentsAttr <$> attrNumbers w es
  numberIdrAttr w (FamilyAttr ms) = FamilyAttr <$> numberMembers w ms
  numberIdrAttr w (IndexBindersAttr ss) = IndexBindersAttr <$> numberSorts w ss
  numberIdrAttr w (IndexArgsAttr ts c) = (\ts' => IndexArgsAttr ts' c) <$> numberTermNodes w ts
  numberIdrAttr w (EquationAttr l r) = EquationAttr <$> numberTermNodes w l <*> numberTermNodes w r
  numberIdrAttr w (ConAttr d cs s) = (\d', cs' => ConAttr d' cs' s) <$> typeNumber w d <*> attrNumbers w cs
  numberIdrAttr w MutableAttr = pure MutableAttr
  numberIdrAttr w (SiteAttr f l c fn) = pure (SiteAttr f l c fn)
  numberIdrAttr w (BigAttr v) = pure (BigAttr v)
  numberIdrAttr w (ClosureAttr f cs) = ClosureAttr <$> attrNumber w f <*> attrNumber w cs

------------------------------------------------------------------------------
-- The writer
------------------------------------------------------------------------------

||| Room for one 64-bit word.
newWord : W Buffer
newWord = do
  Just b <- newBuffer 8
    | Nothing => throwE "cannot allocate a buffer"
  pure b

||| A writer of a module, nothing numbered yet.
export
newWriter : IO (Either String Writer)
newWriter = runEitherT $
  MkWriter <$> newNumbered <*> newNumbered <*> newNumbered <*> newNumbered <*> newNumbered
           <*> newBytes <*> newIORef 0 <*> newIORef 0 <*> newWord

------------------------------------------------------------------------------
-- Ops and regions
------------------------------------------------------------------------------

||| The values in scope, by their identities, with their numbers.
Scope : Type
Scope = SortedMap ValueId Nat

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
    Nothing => throwE "an operand that nothing in scope defines"

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
export
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
export
finish : Writer -> File -> List Container -> IO (Either String ())
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
