-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| What a handle is. Base's pointers are handles of the runtime's one
||| table, so no address reaches a program: a handle is a word of 64 bits,
||| a signed integer to the dialect and to the runtime, unsigned to a
||| program. A program holds handles it never opened: null, which numbers
||| no slot, and the standard streams, the table's first slots, which it is
||| made with and never frees. The runtime's table and the frontend's
||| constants both read them here, so neither restates the other, and the
||| null test is arithmetic over the null handle, with no call.
module IdrisMLIR.Spec.Runtime.Handles

import IdrisMLIR.Spec.Core.Cpp
import IdrisMLIR.Spec.Core.Enums
import IdrisMLIR.Spec.Core.Text

import Data.List.Elem
import Data.List1

%default total

||| The bits of a handle.
public export
handleBits : Nat
handleBits = 64

||| How many values a word of this many bits holds.
public export
wordValues : Nat -> Integer
wordValues Z = 1
wordValues (S n) = 2 * wordValues n

||| The handle that numbers no slot, as a program's unsigned word reads it:
||| every bit set, so no table, however far it grows, has its slot.
public export
nullWord : Integer
nullWord = wordValues handleBits - 1

||| The same bits as the dialect's i64 and the runtime's `int64_t` read
||| them, in two's complement.
public export
nullHandle : Integer
nullHandle = nullWord - wordValues handleBits

||| The standard streams, the table's first slots in this order: standard
||| input, output and error.
public export
data StandardStream = StandardInput | StandardOutput | StandardError

public export
standardStreamClosed : Closed StandardStream
standardStreamClosed = MkClosed
  { name = ident "StandardStream"
  , shape = OneOf
  , every = StandardInput ::: [StandardOutput, StandardError]
  , complete = \case
      StandardInput => Here
      StandardOutput => There Here
      StandardError => There (There Here)
  , describe = \case
      StandardInput => MkCase (ident "Input") (word "input" ::: []) (line "standard input, which the program reads")
      StandardOutput => MkCase (ident "Output") (word "output" ::: []) (line "standard output, which the program writes")
      StandardError => MkCase (ident "Error") (word "error" ::: []) (line "standard error, where the program writes what went wrong")
  , doc = brief (line "a standard stream, whose handle is its place among them")
  }

||| A standard stream's handle: its place in the table, which is its place
||| in the set, so a case's number in C++ is its handle too.
public export
standardHandle : StandardStream -> Integer
standardHandle s = natToInteger (position standardStreamClosed s)

||| What the runtime's handle table is printed: the null handle, and the
||| standard streams, whose cases number their slots.
public export
handlesHeader : Header
handlesHeader = MkHeader (ident "Handles")
  [ (Nested (ident "handles" ::: []),
      [ EnumOf (enumDef standardStreamClosed)
      , Scalar (ident "nullHandle") Signed64 (IntCell nullHandle)
          (line "the handle that numbers no slot, every bit set")
      ])
  ]
  (brief (line "the handles a program holds without opening one"))
