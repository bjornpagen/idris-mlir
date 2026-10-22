-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The clocks base's `ClockType` names that a program can read, and what a
||| reading is: one op reads a clock of a kind, which the runtime serves with
||| one function per kind over one system call; a reading is an immediate,
||| seconds shifted past the nanoseconds, or a mark for a clock that could
||| not be read, so taking one apart is arithmetic the frontend writes, with
||| no call. The collector's two clocks are no kind: no collector runs, and
||| the frontend writes their reading as the mark.
module IdrisMLIR.Spec.Runtime.Clocks

import IdrisMLIR.Spec.Core.Cpp
import IdrisMLIR.Spec.Core.Enums
import IdrisMLIR.Spec.Core.Text

import Data.List.Elem
import Data.List1

%default total

||| The time since some point in the past, which never runs backwards; the
||| time since the epoch; the CPU time of the process; the CPU time of the
||| calling thread.
public export
data ClockKind = Monotonic | Utc | Process | Thread

public export
clockKindClosed : Closed ClockKind
clockKindClosed = MkClosed
  { name = ident "ClockKind"
  , shape = OneOf
  , every = Monotonic ::: [Utc, Process, Thread]
  , complete = \case
      Monotonic => Here
      Utc => There Here
      Process => There (There Here)
      Thread => There (There (There Here))
  , describe = \case
      Monotonic => MkCase (ident "Monotonic") (word "monotonic" ::: []) (line "the time since some point in the past, which never runs backwards")
      Utc => MkCase (ident "Utc") (word "utc" ::: []) (line "the time since the epoch, 00:00:00 UTC on 1 January 1970")
      Process => MkCase (ident "Process") (word "process" ::: []) (line "the CPU time the process has used")
      Thread => MkCase (ident "Thread") (word "thread" ::: []) (line "the CPU time the calling thread has used")
  , doc = brief (line "a clock a program reads")
  }

||| A reading: the seconds shifted left past this many bits of
||| nanoseconds, which a second's nanoseconds fit.
public export
nanosecondBits : Nat
nanosecondBits = 30

||| The seconds a reading holds are below this, so a reading is positive
||| and the mark below is free; a clock past it reads as the mark.
public export
secondsBits : Nat
secondsBits = 33

||| A clock that could not be read, or whose seconds the reading cannot
||| hold, and the collector's clocks, which never run.
public export
unreadable : Integer
unreadable = -1

||| What the runtime's clock functions are printed: the kinds, and the
||| encoding they write.
public export
clocksHeader : Header
clocksHeader = MkHeader (ident "Clocks")
  [ (Nested (ident "clocks" ::: []),
      [ EnumOf (enumDef clockKindClosed)
      , Scalar (ident "nanosecondBits") Unsigned8 (IntCell (natToInteger nanosecondBits))
          (line "the bits of a reading below its seconds")
      , Scalar (ident "secondsBits") Unsigned8 (IntCell (natToInteger secondsBits))
          (line "the seconds a reading holds are below 2 to this")
      , Scalar (ident "unreadable") Signed64 (IntCell unreadable)
          (line "the reading of a clock that could not be read")
      ])
  ]
  (brief (line "the clocks a program reads, and what a reading is"))
