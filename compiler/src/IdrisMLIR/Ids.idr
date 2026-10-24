-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Identifiers. Each kind of identity is its own type, so a function cannot
||| be named where a family is meant. A function instance is its content;
||| any other identity is a dense number of the table that mints it, once.
||| No identity reaches the output. A name the output carries (a symbol) is
||| derived from the content it names, through XXH3's 128-bit hash where its
||| print loses part of it, never from a number, so the order things are
||| made in cannot reach the output.
module IdrisMLIR.Ids

import IdrisMLIR.Proof.Forms

import Data.Bits
import Data.Fin
import Data.List

%default total

||| A function instance, by its content: the program's root, the one
||| function of no definition; or an instance, its link (what it is an
||| instance of, a definition by its address or a member at a use, and the
||| static arguments the instance is translated at, written out). Requesting an instance derives its
||| identity, so asking twice gives the same one and no table mints it.
||| Its symbol is a column of the instance table, printed once from its key
||| (`Term.keyText`), for MLIR and for readers; nothing compares it.
public export
data FnId = RootFn | InstanceOf (Link Form)

||| A family instance (a type constructor at its keyed parameters), by its
||| place in the program's family table, minted once when the family is
||| first registered. Its identity in the module is its content (the
||| declaration Emit writes); this number only finds it in the table.
public export
record FamilyId where
  constructor MkFamilyId
  index : Nat

||| A group of families declared together (one `#idr.family` attribute), by
||| its place in the program's declaration order, minted once when the
||| groups are declared. Its identity in the module is its content; this
||| number only lets the writer encode that content once, however many
||| types name the group.
public export
record GroupId where
  constructor MkGroupId
  index : Nat

||| A constructor of a family instance of `tags` constructors: the family,
||| and the constructor's position among them, which is Idris's tag for it,
||| so a constructor's identity is read off its family's table at that
||| position and at no other. Its name is printed from the context that
||| declares it (`Con.name`).
public export
record ConId (tags : Nat) where
  constructor MkConId
  family : FamilyId
  index : Fin tags

||| A strongly connected component of Idris's own call graph, whose
||| size-change graphs Idris keeps: by its place in the table of components
||| the translation has checked, minted once per component.
public export
record ComponentId where
  constructor MkComponentId
  index : Nat

||| An Idris name as it is printed: what the compiler reports, never what it
||| compares. It has `Show` and no `Eq`, so code outside the registry can
||| name a definition in a message but cannot key behaviour on it.
export
data Shown = MkShown String

export
shown : String -> Shown
shown = MkShown

export
Show Shown where
  show (MkShown s) = s

||| What a key's print keeps of the instance's identity: all of it, or not
||| all, with the low 64 bits of the identity's hash, which the symbol then
||| carries so that two identities that print alike are two symbols.
public export
data KeyPrint = Whole | Lossy Bits64

||| The positions of a definition an instance keys, up to the last that
||| keys: none, or the positions before the last, each the
||| alpha-normalized text of what it keys or nothing, then the last's text.
||| So no key ends in a position that keys nothing.
public export
data KeyArguments = NoArguments | UpTo (List (Maybe String)) String

||| A key position as the key's text writes it: what it keys, or `-` for a
||| position that keys nothing, which no compile-time value's text is.
export
keyArgument : Maybe String -> String
keyArgument (Just text) = text
keyArgument Nothing = "-"

||| A key's positions as its text writes them, in order.
export
argumentsText : KeyArguments -> List String
argumentsText NoArguments = []
argumentsText (UpTo before final) = foldr (\p, rest => keyArgument p :: rest) [final] before

||| What a function or data instance is an instance of: the definition (its
||| printed full name), the compile-time values it was instantiated at, and
||| what that print keeps of the identity. No attribute holds it: Emit
||| writes `Term.keyText` of it as a function's symbol and a family's
||| label, and the definition's name as a function's `NameLoc`.
public export
record InstanceKey where
  constructor MkInstanceKey
  origin : String
  arguments : KeyArguments
  print : KeyPrint

-- A key compares part by part, so that a table keyed by it holds one entry
-- per key and never by the text the key prints.
export
Eq KeyPrint where
  Whole == Whole = True
  Lossy a == Lossy b = a == b
  _ == _ = False

export
Ord KeyPrint where
  compare Whole Whole = EQ
  compare Whole (Lossy _) = LT
  compare (Lossy _) Whole = GT
  compare (Lossy a) (Lossy b) = compare a b

export
Eq KeyArguments where
  NoArguments == NoArguments = True
  UpTo a x == UpTo b y = a == b && x == y
  _ == _ = False

export
Ord KeyArguments where
  compare NoArguments NoArguments = EQ
  compare NoArguments (UpTo _ _) = LT
  compare (UpTo _ _) NoArguments = GT
  compare (UpTo a x) (UpTo b y) = compare (a, x) (b, y)

export
Eq InstanceKey where
  k == l = k.origin == l.origin && k.arguments == l.arguments && k.print == l.print

export
Ord InstanceKey where
  compare k l = compare (k.origin, k.arguments, k.print) (l.origin, l.arguments, l.print)

export
Eq FnId where
  RootFn == RootFn = True
  InstanceOf a == InstanceOf b = a == b
  _ == _ = False

export
Ord FnId where
  compare RootFn RootFn = EQ
  compare RootFn (InstanceOf _) = LT
  compare (InstanceOf _) RootFn = GT
  compare (InstanceOf a) (InstanceOf b) = compare a b

-- For the compiler's own errors: what a user reads names an instance by
-- its symbol.
export
Show FnId where
  show RootFn = "the root"
  show (InstanceOf l) = "the instance of " ++ show l.head

export Eq FamilyId where a == b = a.index == b.index
export Ord FamilyId where compare a b = compare a.index b.index
export Show FamilyId where show f = "family " ++ show f.index

export Eq GroupId where a == b = a.index == b.index
export Ord GroupId where compare a b = compare a.index b.index

export Eq (ConId tags) where a == b = a.family == b.family && a.index == b.index
export Ord (ConId tags) where compare a b = compare (a.family, a.index) (b.family, b.index)
-- The identity, for the compiler's own errors: what a user or a test reads
-- names a constructor by `Con.name`.
export Show (ConId tags) where show c = show c.family ++ "#" ++ show (finToNat c.index)

export Eq ComponentId where a == b = a.index == b.index
export Ord ComponentId where compare a b = compare a.index b.index

------------------------------------------------------------------------------
-- Names from content
------------------------------------------------------------------------------

||| A word as exactly 16 lowercase hexadecimal digits, most significant
||| first.
export
hex16 : Bits64 -> String
hex16 x = pack (map digit [60, 56, 52, 48, 44, 40, 36, 32, 28, 24, 20, 16, 12, 8, 4, 0])
  where
    -- The digit of the four bits at a shift.
    digit : Fin 64 -> Char
    digit at =
      let d = shiftR x at .&. 0xF in
      if d < 10 then chr (cast d + ord '0') else chr (cast d - 10 + ord 'a')
