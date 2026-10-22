-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| What LLVM is told of a function from its row: its `memory(...)` and the
||| function attributes a row withholds. One table per atom; a row's facts
||| are the join of its atoms', so what the compiler knows of effects
||| reaches LLVM through one function of the row.
|||
||| Every location is at least read: reuse rebuilds a cell under the same
||| pointer, so two calls LLVM thought touched no memory could merge across
||| that store. A write is a read and a write, since LLVM's write alone makes
||| a first read poison. Neither "none" nor "write" is a value here.
module IdrisMLIR.Spec.Effects.LLVM

import IdrisMLIR.Spec.Core.Text
import IdrisMLIR.Spec.Core.Enums
import IdrisMLIR.Spec.Effects.Atom

import Data.List
import Data.List.Elem
import Data.List1

%default total

||| The memory LLVM tells apart in a function's `memory(...)`.
public export
data Location : Type where
  ||| Memory the function's pointer arguments reach.
  ArgMem : Location
  ||| Memory no pointer of the module reaches: the C library's.
  InaccessibleMem : Location
  ||| The C library's error number.
  ErrnoMem : Location
  ||| Any other memory: the runtime's globals once its code is joined to
  ||| the program's, the allocator's lists.
  Other : Location

public export
locationClosed : Closed Location
locationClosed = MkClosed
  { name = ident "MemoryLocation"
  , shape = OneOf
  , every = ArgMem ::: [InaccessibleMem, ErrnoMem, Other]
  , complete = \case
      ArgMem => Here
      InaccessibleMem => There Here
      ErrnoMem => There (There Here)
      Other => There (There (There Here))
  , describe = \case
      ArgMem => MkCase (ident "ArgMem") (word "argmem" ::: []) (line "memory the function's pointer arguments reach")
      InaccessibleMem => MkCase (ident "InaccessibleMem") (word "inaccessiblemem" ::: []) (line "memory no pointer of the module reaches")
      ErrnoMem => MkCase (ident "ErrnoMem") (word "errnomem" ::: []) (line "the C library's error number")
      Other => MkCase (ident "Other") (word "other" ::: []) (line "any other memory")
  , doc = brief (line "a location of LLVM's memory effects")
  }

||| How a function may touch a location: read it, at the least, or read and
||| write it. The two values LLVM is told of a location; no function is
||| told it touches no memory, or writes without reading.
public export
data Access = ReadOnly | ReadWrite

public export
accessClosed : Closed Access
accessClosed = MkClosed
  { name = ident "MemoryAccess"
  , shape = OneOf
  , every = ReadOnly ::: [ReadWrite]
  , complete = \case
      ReadOnly => Here
      ReadWrite => There Here
  , describe = \case
      ReadOnly => MkCase (ident "ReadOnly") (word "read" ::: []) (line "it may read the location")
      ReadWrite => MkCase (ident "ReadWrite") (word "readwrite" ::: []) (line "it may read and write the location")
  , doc = brief (line "how a function may touch a location")
  }

||| The attributes LLVM is told of a function unless an atom of its row
||| withholds one. No atom withholds `nounwind`: no unwinding exists, a
||| crash ends the process.
public export
data Attribute : Type where
  ||| It returns: withheld by IO, which may block or end by a signal, and
  ||| by every way a run may end or not end.
  WillReturn : Attribute
  ||| It makes progress: withheld by a run that may never end, so LLVM
  ||| deletes an endless loop only where Idris proved there is none.
  MustProgress : Attribute
  ||| It frees nothing it did not acquire: withheld by giving memory back
  ||| and by ending the run, which releases the handle table.
  NoFree : Attribute
  ||| It does not synchronize with another thread: one thread runs a
  ||| program, so no atom withholds it.
  NoSync : Attribute
  ||| It does not unwind.
  NoUnwind : Attribute

public export
attributeClosed : Closed Attribute
attributeClosed = MkClosed
  { name = ident "FunctionAttribute"
  , shape = OneOf
  , every = WillReturn ::: [MustProgress, NoFree, NoSync, NoUnwind]
  , complete = \case
      WillReturn => Here
      MustProgress => There Here
      NoFree => There (There Here)
      NoSync => There (There (There Here))
      NoUnwind => There (There (There (There Here)))
  , describe = \case
      WillReturn => MkCase (ident "WillReturn") (word "willreturn" ::: []) (line "it returns")
      MustProgress => MkCase (ident "MustProgress") (word "mustprogress" ::: []) (line "it makes progress")
      NoFree => MkCase (ident "NoFree") (word "nofree" ::: []) (line "it frees nothing it did not acquire")
      NoSync => MkCase (ident "NoSync") (word "nosync" ::: []) (line "it does not synchronize with another thread")
      NoUnwind => MkCase (ident "NoUnwind") (word "nounwind" ::: []) (line "it does not unwind")
  , doc = brief (line "a function attribute LLVM is told unless a row withholds it")
  }

||| The locations a function holding the atom may write as well as read.
||| Acquiring, giving back and crashing reach the C library's memory and
||| error number; the counts, memo cells and contents a function writes
||| may be its arguments' or anyone's.
public export
writtenLocations : Atom -> List Location
writtenLocations IO = [InaccessibleMem, ErrnoMem, Other]
writtenLocations RuntimeState = []
writtenLocations Exit = [InaccessibleMem, ErrnoMem, Other]
writtenLocations Crash = [InaccessibleMem, ErrnoMem]
writtenLocations Divergence = []
writtenLocations Count = [ArgMem, Other]
writtenLocations MemoState = [ArgMem, Other]
writtenLocations Read = []
writtenLocations Write = [ArgMem, Other]
writtenLocations Alloc = [InaccessibleMem, ErrnoMem, Other]
writtenLocations Free = [ArgMem, InaccessibleMem, ErrnoMem, Other]

||| The attributes a function holding the atom is not told.
public export
withholds : Atom -> List Attribute
withholds IO = [WillReturn]
withholds RuntimeState = []
withholds Exit = [WillReturn, NoFree]
withholds Crash = [WillReturn]
withholds Divergence = [WillReturn, MustProgress]
withholds Count = []
withholds MemoState = []
withholds Read = []
withholds Write = []
withholds Alloc = []
withholds Free = [NoFree]

||| What a write through an exclusive owned parameter, which the row keeps
||| per parameter, does to each location: it writes that argument's memory
||| alone.
public export
parameterAccess : Location -> Access
parameterAccess ArgMem = ReadWrite
parameterAccess InaccessibleMem = ReadOnly
parameterAccess ErrnoMem = ReadOnly
parameterAccess Other = ReadOnly

||| The facts as the C++ reads them, one array per atom.
public export
llvmTable : Table
llvmTable = table atomClosed
  [ MkColumn (ident "atomWrites") (SetColumn (enumDef locationClosed))
      (\a => setCell locationClosed (writtenLocations a)) (line "the locations a function holding the atom may write")
  , MkColumn (ident "atomWithholds") (SetColumn (enumDef attributeClosed))
      (\a => setCell attributeClosed (withholds a)) (line "the attributes a function holding the atom is not told")
  ]

public export
locationTable : Table
locationTable = table locationClosed
  [ MkColumn (ident "parameterAccess") (EnumColumn (enumDef accessClosed))
      (\l => CaseCell (caseRef accessClosed (parameterAccess l)))
      (line "what a write through an exclusive owned parameter does to the location")
  ]
