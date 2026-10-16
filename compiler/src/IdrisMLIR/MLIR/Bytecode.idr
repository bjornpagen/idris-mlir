-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| A module as MLIR bytecode, the file the driver reads. One encoding, the
||| same for every module:
||| version 6, the pinned reader's current one; each data type written once,
||| its body in the module's table of data types, attribute entry 0, and
||| every other occurrence of it naming its member there; each type and
||| attribute that can hold a data type an entry of its dialect's bytecode
||| encoding (IdrisMLIR.Encoding.*), which refers to what it holds by
||| entry, and every other entry its text, the bytecode's own fallback;
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
||| Numbers are given in first use: of a string, a dialect and an op name by
||| its text, and of an attribute or a type by what its entry holds, its
||| dialect and its text or its bytes, which hold entry numbers, so an entry
||| is as small as what it holds directly. Bytes are written one by one, so
||| no byte order is assumed. The functions are encoded as Emit finishes
||| each, so no value of the whole module is held.
module IdrisMLIR.MLIR.Bytecode

import IdrisMLIR.Encoding.Builtin
import IdrisMLIR.Encoding.Idr
import IdrisMLIR.MLIR
import IdrisMLIR.MLIR.Parts

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
littleEndian : Nat -> Integer -> List Bits8
littleEndian Z v = []
littleEndian (S n) v = cast (v `mod` 256) :: littleEndian n (v `div` 256)

||| 2 to the `n`.
pow2 : Nat -> Integer
pow2 Z = 1
pow2 (S n) = 2 * pow2 n

||| A PrefixVarInt: in its first byte, a zero bit for each byte after it,
||| then a one, and the value in the bits left of the `k` bytes, 7 to a
||| byte; a value of 56 bits or more is a zero byte and its eight bytes.
prefixVarInt : Nat -> List Bits8
prefixVarInt n = go 1 8
  where
    v : Integer
    v = cast n
    go : (k : Nat) -> (left : Nat) -> List Bits8
    go k Z = 0 :: littleEndian 8 v
    go k (S left) =
      if v < pow2 (7 * k) then littleEndian k ((2 * v + 1) * pow2 (minus k 1))
      else go (S k) left

||| A zigzagged PrefixVarInt, as MLIR writes a signed one: `n` at least 0
||| as `2n`, a negative `n` as `-2n - 1`, so that a 64-bit value takes 64
||| bits.
signedVarInt : Integer -> List Bits8
signedVarInt n = prefixVarInt (cast (if n >= 0 then 2 * n else -2 * n - 1))

varint : Bytes -> Nat -> W ()
varint bs n = traverse_ (byte bs) (prefixVarInt n)

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

Eq Payload where
  Textual a == Textual b = a == b
  Encoded a == Encoded b = a == b
  _ == _ = False

Ord Payload where
  compare (Textual a) (Textual b) = compare a b
  compare (Textual _) (Encoded _) = LT
  compare (Encoded _) (Textual _) = GT
  compare (Encoded a) (Encoded b) = compare a b

||| An attribute or type entry: its dialect's number, and what it holds. It
||| is its own key, so two entries are one exactly when they hold the same.
Entry : Type
Entry = (Nat, Payload)

||| The strings, dialects (by their name's string), op names (by dialect
||| and name), attributes and types (by what their entries hold) of a
||| module, the member of its table each data type is, by name, and the ops
||| of its innermost container's block, encoded.
export
record Writer where
  constructor MkWriter
  stringTable : Numbered String String
  dialectTable : Numbered String Nat
  opNameTable : Numbered String (Nat, Nat)
  attrTable : Numbered Entry Entry
  typeTable : Numbered Entry Entry
  members : SortedMap String Nat
  ||| Those ops, encoded, how many, and how many values they define.
  body : Bytes
  count : IORef Nat
  values : IORef Nat

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

||| A part's bytes, as (1) of the table's layout gives them: a string by
||| its number, given here in its first use.
partBytes : Writer -> Part -> W (List Bits8)
partBytes w (VarInt n) = pure (prefixVarInt n)
partBytes w (SignedVarInt n) = pure (signedVarInt n)
partBytes w (Flag b) = pure [if b then 1 else 0]
partBytes w (Str s) = prefixVarInt <$> stringNumber w s
partBytes w (TypeAt r) = pure (prefixVarInt r.number)
partBytes w (AttrAt r) = pure (prefixVarInt r.number)
partBytes w (OptionalAttrAt Nothing) = pure (prefixVarInt 0)
partBytes w (OptionalAttrAt (Just r)) = pure (prefixVarInt (2 * r.number + 1))

encoded : Writer -> List Part -> W (List Bits8)
encoded w parts = concat <$> traverse (partBytes w) parts

||| A dialect whose types and attributes the handoff encodes natively: its
||| name, and the code a field of the table starts with that is one of its
||| type records written in place.
record Dialect where
  constructor MkDialect
  name : String
  fieldCode : Nat

idrDialect : Dialect
idrDialect = MkDialect "idr" 2

builtinDialect : Dialect
builtinDialect = MkDialect "builtin" 3

||| The type entry of `d` that `parts` encode.
typeEntry : Writer -> Dialect -> List Part -> W TypeRef
typeEntry w d parts = do
  e <- (\n, bs => (n, Encoded bs)) <$> dialectNumber w d.name <*> encoded w parts
  MkTypeRef <$> number w.typeTable e (pure e)

||| The attribute entry of `d` that `parts` encode.
attrEntry : Writer -> Dialect -> List Part -> W AttrRef
attrEntry w d parts = do
  e <- (\n, bs => (n, Encoded bs)) <$> dialectNumber w d.name <*> encoded w parts
  MkAttrRef <$> number w.attrTable e (pure e)

||| A type's entry as its text.
typeTextEntry : Writer -> MlirType -> W TypeRef
typeTextEntry w t = do
  e <- (\n => (n, Textual (typeText t))) <$> dialectNumber w (typeDialect t)
  MkTypeRef <$> number w.typeTable e (pure e)

||| An attribute's entry as its text.
attrTextEntry : Writer -> MlirAttr -> W AttrRef
attrTextEntry w a = do
  e <- (\n => (n, Textual (attrText a))) <$> dialectNumber w (attrDialect a)
  MkAttrRef <$> number w.attrTable e (pure e)

||| A location is a builtin attribute, written as its text.
locationNumber : Writer -> Location -> W AttrRef
locationNumber w at = do
  e <- (\n => (n, Textual (location at))) <$> dialectNumber w builtinDialect.name
  MkAttrRef <$> number w.attrTable e (pure e)

------------------------------------------------------------------------------
-- Types and attributes
------------------------------------------------------------------------------

||| The table of data types is attribute entry 0: numbered before any entry
||| its bodies make (`newWriter`), so that every data type's entry names it.
tableRef : AttrRef
tableRef = MkAttrRef 0

||| The member of the table a data type is, by its name. A name the table
||| does not hold is data the program does not declare, which only a bug of
||| the frontend writes: this lookup is where it is found.
member : Writer -> String -> W Nat
member w name = case lookup name w.members of
  Just k => pure k
  Nothing => throwE ("a data type " ++ name ++ ", which the program does not declare")

||| Where a type is written: an entry of its own, whose records refer to
||| the types they hold by entry; or a field of the table, where a data type
||| is its member and a type that holds one is its record in place.
data Place = InEntry | InTable

||| How a type is written: a data type, as its member of the table; a type
||| of a record of the two dialects' encodings, as that record, each type
||| it holds written as the place says, and whether a data type is below it;
||| any other type, as its text, which holds no data type.
data Native = Member Nat | Record Dialect (List Part) Bool | AsText

||| A record of `d`, from what the one type it holds is written as.
recordOf : Dialect -> (List Part -> List Part) -> (List Part, Bool) -> Native
recordOf d encode (parts, below) = Record d (encode parts) below

||| A dimension of a shaped type as its record gives it: a dynamic one is
||| `ShapedType::kDynamic`.
extent : Dim -> Integer
extent (Static n) = cast n
extent Dynamic = dynamicExtent

-- Every recursion is on a part of the type or attribute written, through
-- mutual helpers for lists, as `typesText` is, so that totality holds.
mutual
  ||| The one switch over the kinds of type: how `t` is written in `place`.
  native : Writer -> Place -> MlirType -> W Native
  native w pl (Idr (DataType name) _) = Member <$> member w name
  native w pl (Idr (QType q p v) _) = recordOf idrDialect (encodeQType q p) <$> held w pl v
  native w pl (Idr (FnType sig) _) = recordOf idrDialect encodeFnType <$> heldSignature w pl sig
  native w pl (Idr (LazyType v) _) = recordOf idrDialect encodeLazyType <$> held w pl v
  native w pl (Idr (BoxType v) _) = recordOf idrDialect encodeBoxType <$> held w pl v
  native w pl (Idr (DestType v) _) = recordOf idrDialect encodeDestType <$> held w pl v
  native w pl (FunctionType sig) = recordOf builtinDialect id <$> functionType w pl sig
  native w pl (RankedTensorType ds e) =
    recordOf builtinDialect (encodeRankedTensorType (map extent ds)) <$> held w pl e
  -- Upstream has a record for a memref in the default memory space and one
  -- for a memref in another; each names its identity layout.
  native w pl (MemRefType ds e Nothing) = do
    layout <- attrTextEntry w (IdentityMap (length ds))
    recordOf builtinDialect (\x => encodeMemRefType (map extent ds) x layout) <$> held w pl e
  native w pl (MemRefType ds e (Just space)) = do
    s <- attrNumber w space
    layout <- attrTextEntry w (IdentityMap (length ds))
    recordOf builtinDialect (\x => encodeMemRefTypeWithMemSpace s (map extent ds) x layout) <$> held w pl e
  native w pl _ = pure AsText

  ||| A type's entry. A data type's names the table and its member.
  export
  typeNumber : Writer -> MlirType -> W TypeRef
  typeNumber w t = case !(native w InEntry t) of
    Member k => typeEntry w idrDialect (encodeDataType tableRef k)
    Record d parts _ => typeEntry w d parts
    AsText => typeTextEntry w t

  ||| A type as a field of the table, and whether a data type is at or
  ||| below it: a data type is its member; a type that holds one is its
  ||| record in place, of its dialect's code; any other is its entry.
  field : Writer -> MlirType -> W (List Part, Bool)
  field w t = case !(native w InTable t) of
    Member k => pure ([VarInt 1, VarInt k], True)
    Record d parts True => pure (VarInt d.fieldCode :: parts, True)
    _ => (\r => ([VarInt 0, TypeAt r], False)) <$> typeNumber w t

  ||| A type a record holds, written as `place` says.
  held : Writer -> Place -> MlirType -> W (List Part, Bool)
  held w InEntry t = (\r => ([TypeAt r], False)) <$> typeNumber w t
  held w InTable t = field w t

  heldAll : Writer -> Place -> List MlirType -> W (List (List Part, Bool))
  heldAll w pl [] = pure []
  heldAll w pl (t :: ts) = (::) <$> held w pl t <*> heldAll w pl ts

  ||| A builtin function type's record, from its signature.
  functionType : Writer -> Place -> Signature MlirType -> W (List Part, Bool)
  functionType w pl (MkSignature ins outs) = do
    is <- heldAll w pl ins
    os <- heldAll w pl outs
    pure (encodeFunctionType (map fst is) (map fst os), any snd is || any snd os)

  ||| A builtin function type's entry, from its signature.
  functionEntry : Writer -> Signature MlirType -> W TypeRef
  functionEntry w sig = typeEntry w builtinDialect (fst !(functionType w InEntry sig))

  ||| The builtin function type a closure's record holds, written as `held`
  ||| writes a type. The generated `FnType` holds its signature, not that
  ||| type, so this is `held` of the function type, on the signature, which
  ||| is the part the recursion is on.
  heldSignature : Writer -> Place -> Signature MlirType -> W (List Part, Bool)
  heldSignature w InEntry sig = (\r => ([TypeAt r], False)) <$> functionEntry w sig
  heldSignature w InTable sig = do
    (parts, below) <- functionType w InTable sig
    if below then pure (VarInt builtinDialect.fieldCode :: parts, True)
      else (\r => ([VarInt 0, TypeAt r], False)) <$> functionEntry w sig

  ||| An attribute's entry: an array, a dictionary and a type, which can
  ||| hold a data type, are builtin's records; every other is its text.
  attrNumber : Writer -> MlirAttr -> W AttrRef
  attrNumber w (ArrayAttr as) = do
    rs <- attrNumbers w as
    attrEntry w builtinDialect (encodeArrayAttr rs)
  attrNumber w (DictionaryAttr es) = do
    rs <- namedNumbers w es
    attrEntry w builtinDialect (encodeDictionaryAttr rs)
  attrNumber w (TypeAttr t) = do
    r <- typeNumber w t
    attrEntry w builtinDialect (encodeTypeAttr [TypeAt r])
  attrNumber w a = attrTextEntry w a

  attrNumbers : Writer -> List MlirAttr -> W (List AttrRef)
  attrNumbers w [] = pure []
  attrNumbers w (a :: as) = (::) <$> attrNumber w a <*> attrNumbers w as

  ||| A dictionary's entries, each its name, a string, and its value, in the
  ||| op's order: the reader sorts them, as the parser does.
  namedNumbers : Writer -> List (String, MlirAttr) -> W (List (AttrRef, AttrRef))
  namedNumbers w [] = pure []
  namedNumbers w ((name, a) :: es) =
    (\n, v, rest => (n, v) :: rest) <$> attrTextEntry w (StringAttr name) <*> attrNumber w a <*> namedNumbers w es

------------------------------------------------------------------------------
-- The table of data types
------------------------------------------------------------------------------

||| Each data type's member of the table, by name: its place in it. Two of
||| one name are a bug of the frontend, which names each instance once.
membersOf : List (String, a) -> W (SortedMap String Nat)
membersOf = go 0 SortedMap.empty
  where
    go : Nat -> SortedMap String Nat -> List (String, a) -> W (SortedMap String Nat)
    go k m [] = pure m
    go k m ((name, _) :: rest) = case lookup name m of
      Just _ => throwE ("two data types are named " ++ name)
      Nothing => go (S k) (insert name k m) rest

||| A constructor of a body: its name, its role, whether every force runs
||| it, the function a label names, and its fields.
ctorParts : Writer -> IdrCtor MlirType -> W (List Part)
ctorParts w c = do
  fn <- traverse (\f => attrNumber w (SymbolRefAttr (MkSymbolRef f []))) c.fn
  fields <- traverse (\t => fst <$> field w t) c.fields
  pure ([Str c.name, VarInt (ctorRoleValue c.role), Flag c.byName, OptionalAttrAt fn, VarInt (length fields)]
        ++ concat fields)

||| A body: its kind of sum, its constructors in tag order, and the Idris
||| instance it is of.
bodyParts : Writer -> IdrSum MlirType -> W (List Part)
bodyParts w s = do
  ctors <- traverse (ctorParts w) s.ctors
  inst <- traverse (\(origin, args) => attrNumber w (idr (InstanceAttr origin (map StringAttr args)))) s.instanceOf
  pure ([VarInt (sumKindValue s.kind), VarInt (length ctors)] ++ concat ctors ++ [OptionalAttrAt inst])

||| A writer of a module whose data types are `datas`, in order, each its
||| name and body: the table, attribute entry 0, written first, its fields
||| numbered as they are met, each data type its member by its place in
||| `datas`.
export
newWriter : List (String, IdrSum MlirType) -> IO (Either String Writer)
newWriter datas = runEitherT $ do
  members <- membersOf datas
  w <- MkWriter <$> newNumbered <*> newNumbered <*> newNumbered <*> newNumbered <*> newNumbered
                <*> pure members <*> newBytes <*> newIORef 0 <*> newIORef 0
  -- Entry 0 is the table's (`tableRef`): numbered before its bodies number
  -- what they hold, and put first once they are written.
  writeIORef w.attrTable.count 1
  bodies <- traverse (bodyParts w . snd) datas
  idr <- dialectNumber w idrDialect.name
  table <- encoded w ([VarInt dataTableCode, VarInt (length datas)] ++ map (Str . fst) datas ++ concat bodies)
  modifyIORef w.attrTable.entries ([< (idr, Encoded table)] ++)
  pure w

------------------------------------------------------------------------------
-- Ops and regions
------------------------------------------------------------------------------

||| The values in scope, by SSA name, the only identity a value has in
||| `IdrisMLIR.MLIR`, with their numbers.
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

  ||| A region of one block, its values from `base`.
  encodeRegion : Writer -> Bytes -> Scope -> Nat -> Region -> W ()
  encodeRegion w out scope base r@(MkRegion arguments statements) = do
    let n = definedIn r
        inner = bindRegion scope base r
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
payload out (Encoded bs) = True <$ traverse_ (byte out) bs

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
  traverse_ (byte file) [0x4D, 0x4C, 0xEF, 0x52]
  varint file 6
  string file "idris-mlir"
  section file 4 ir
  section file 3 offsets
  section file 2 payloads
  section file 1 ds
  section file 0 ss
  section file 8 !newBytes
  writeBytes h file
