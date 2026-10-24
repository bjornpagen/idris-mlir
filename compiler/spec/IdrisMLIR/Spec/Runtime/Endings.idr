-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| How a compiled program ends, once: every ending, the status a parent
||| reads of it, and the closed sets its messages name. The runtime is
||| printed its tables (the causes' and internal errors' phrases, the fixed
||| statuses, each ending's way out and what it writes first) and ends a
||| process by them alone; the frontend writes a cause on each crash site
||| and guard; the harness reads a case's expected ending as an `Ending`,
||| never as text parsed back. A parent sees an exit status of eight bits
||| or a signal, so an `exit` of any other status is a crash of its cause at
||| the exit's site, and an `Exited` holds a status by its type.
module IdrisMLIR.Spec.Runtime.Endings

import IdrisMLIR.Spec.Core.Cpp
import IdrisMLIR.Spec.Core.Enums
import IdrisMLIR.Spec.Core.Text

import Data.Fin
import Data.List.Elem
import Data.List1

%default total

------------------------------------------------------------------------------
-- Causes
------------------------------------------------------------------------------

||| What a partial primitive's guard found false, or the case the
||| frontend's default arm stands for: the closed set every crash site of a
||| program names. A cause is a value, passed to the runtime as its
||| position; its phrase is the runtime's table, so no program carries the
||| text of a cause and no two programs can spell one differently.
public export
data Cause
  = DivisionByZero
  | IndexOutOfBounds
  | StringIndexOutOfRange
  | HeadOfEmptyString
  | TailOfEmptyString
  | ByteRangeOutsideBuffer
  | NonFiniteCast
  | NotAString
  | NoClauseMatched
  | SuspensionForcedItself
  | ExitStatusOutOfRange

||| Whether a cause's message names the function its site lies in: a
||| missing clause is the function's, which the phrase then names; every
||| other cause is said by its site alone.
public export
data Naming = SiteAlone | WithFunction

public export
naming : Cause -> Naming
naming NoClauseMatched = WithFunction
naming _ = SiteAlone

public export
causeClosed : Closed Cause
causeClosed = MkClosed
  { name = ident "CrashCause"
  , shape = OneOf
  , every =
      DivisionByZero :::
      [ IndexOutOfBounds, StringIndexOutOfRange, HeadOfEmptyString, TailOfEmptyString
      , ByteRangeOutsideBuffer, NonFiniteCast, NotAString, NoClauseMatched
      , SuspensionForcedItself, ExitStatusOutOfRange ]
  , complete = \case
      DivisionByZero => Here
      IndexOutOfBounds => There Here
      StringIndexOutOfRange => There (There Here)
      HeadOfEmptyString => There (There (There Here))
      TailOfEmptyString => There (There (There (There Here)))
      ByteRangeOutsideBuffer => There (There (There (There (There Here))))
      NonFiniteCast => There (There (There (There (There (There Here)))))
      NotAString => There (There (There (There (There (There (There Here))))))
      NoClauseMatched => There (There (There (There (There (There (There (There Here)))))))
      SuspensionForcedItself => There (There (There (There (There (There (There (There (There Here))))))))
      ExitStatusOutOfRange => There (There (There (There (There (There (There (There (There (There Here)))))))))
  , describe = \case
      DivisionByZero => MkCase (ident "DivisionByZero") (word "division_by_zero" ::: []) (line "division by zero")
      IndexOutOfBounds => MkCase (ident "IndexOutOfBounds") (word "index_out_of_bounds" ::: []) (line "array index out of bounds")
      StringIndexOutOfRange => MkCase (ident "StringIndexOutOfRange") (word "string_index_out_of_range" ::: []) (line "string index out of range")
      HeadOfEmptyString => MkCase (ident "HeadOfEmptyString") (word "head_of_empty_string" ::: []) (line "head of an empty string")
      TailOfEmptyString => MkCase (ident "TailOfEmptyString") (word "tail_of_empty_string" ::: []) (line "tail of an empty string")
      ByteRangeOutsideBuffer => MkCase (ident "ByteRangeOutsideBuffer") (word "byte_range_outside_buffer" ::: []) (line "a byte range outside the buffer")
      NonFiniteCast => MkCase (ident "NonFiniteCast") (word "non_finite_cast" ::: []) (line "cast of a non-finite Double")
      NotAString => MkCase (ident "NotAString") (word "not_a_string" ::: []) (line "a pointer read as a string holds none")
      NoClauseMatched => MkCase (ident "NoClauseMatched") (word "no_clause_matched" ::: []) (line "no clause matched in")
      SuspensionForcedItself => MkCase (ident "SuspensionForcedItself") (word "suspension_forced_itself" ::: []) (line "a suspension forced itself")
      ExitStatusOutOfRange => MkCase (ident "ExitStatusOutOfRange") (word "exit_status_out_of_range" ::: []) (line "exit status outside 0 to 255")
  , doc = brief (line "what a crash site of a program found false")
  }

public export
namingClosed : Closed Naming
namingClosed = MkClosed
  { name = ident "CauseNaming"
  , shape = OneOf
  , every = SiteAlone ::: [WithFunction]
  , complete = \case
      SiteAlone => Here
      WithFunction => There Here
  , describe = \case
      SiteAlone => MkCase (ident "SiteAlone") (word "site_alone" ::: []) (line "said by its site alone")
      WithFunction => MkCase (ident "WithFunction") (word "with_function" ::: []) (line "its phrase followed by the function its site lies in")
  , doc = brief (line "whether a cause's message names its site's function")
  }

||| The causes as the runtime reads them: each one's phrase, the text after
||| its site, and whether the function's name follows it.
public export
causeTable : Table
causeTable = table causeClosed
  [ MkColumn (ident "causePhrase") TextColumn
      (\c => TextCell (lineText (causeClosed.describe c).doc)) (line "what the message says after the site")
  , MkColumn (ident "causeNaming") (EnumColumn (enumDef namingClosed))
      (\c => CaseCell (caseRef namingClosed (naming c))) (line "whether the site's function follows the phrase")
  ]

------------------------------------------------------------------------------
-- What cannot run, and the program's own bugs
------------------------------------------------------------------------------

||| Why this machine cannot run the program at all, said before it runs:
||| its processor lacks a feature the program was compiled to use, or its
||| page is not the one the runtime was built for.
public export
data Unrunnable = MissingFeatures | WrongPage

public export
unrunnableClosed : Closed Unrunnable
unrunnableClosed = MkClosed
  { name = ident "Unrunnable"
  , shape = OneOf
  , every = MissingFeatures ::: [WrongPage]
  , complete = \case
      MissingFeatures => Here
      WrongPage => There Here
  , describe = \case
      MissingFeatures => MkCase (ident "MissingFeatures") (word "missing_features" ::: []) (line "the processor lacks a feature the program was compiled to use")
      WrongPage => MkCase (ident "WrongPage") (word "wrong_page" ::: []) (line "the system's page is not the one the runtime was built for")
  , doc = brief (line "why a machine cannot run the program")
  }

||| A bug of the compiler's or the runtime's, found as the program runs:
||| never the program's fault, so never a crash of its own. The stack
||| reaching its guard, which the compiler sized from every frame; in the
||| checked runtime, cells still live when the program returns, a count
||| operation on a cell that died, and a call that held more bytes it no
||| longer needs than the bound the compiler computed for its function; the
||| allocator's own fatal error; a library's hardening check.
public export
data Internal
  = StackExhausted
  | CellsLeaked
  | CountOfDeadCell
  | FrameBoundExceeded
  | AllocatorFailed
  | LibraryFailed

public export
internalClosed : Closed Internal
internalClosed = MkClosed
  { name = ident "Internal"
  , shape = OneOf
  , every = StackExhausted ::: [CellsLeaked, CountOfDeadCell, FrameBoundExceeded, AllocatorFailed, LibraryFailed]
  , complete = \case
      StackExhausted => Here
      CellsLeaked => There Here
      CountOfDeadCell => There (There Here)
      FrameBoundExceeded => There (There (There Here))
      AllocatorFailed => There (There (There (There Here)))
      LibraryFailed => There (There (There (There (There Here))))
  , describe = \case
      StackExhausted => MkCase (ident "StackExhausted") (word "stack_exhausted" ::: []) (line "the stack is exhausted")
      CellsLeaked => MkCase (ident "CellsLeaked") (word "cells_leaked" ::: []) (line "cells live at the end:")
      CountOfDeadCell => MkCase (ident "CountOfDeadCell") (word "count_of_dead_cell" ::: []) (line "a count operation on a cell that died")
      FrameBoundExceeded => MkCase (ident "FrameBoundExceeded") (word "frame_bound_exceeded" ::: []) (line "a call held more bytes it no longer needs than its bound:")
      AllocatorFailed => MkCase (ident "AllocatorFailed") (word "allocator_failed" ::: []) (line "the allocator failed:")
      LibraryFailed => MkCase (ident "LibraryFailed") (word "library_failed" ::: []) (line "a library check failed:")
  , doc = brief (line "a bug of the compiler's or the runtime's, found as the program runs")
  }

||| The internal errors as the runtime reads them: each one's phrase, which
||| the detail its ending carries (a count; the function, what it held and
||| its bound; the allocator's or the library's own text) follows.
public export
internalTable : Table
internalTable = table internalClosed
  [ MkColumn (ident "internalPhrase") TextColumn
      (\i => TextCell (lineText (internalClosed.describe i).doc)) (line "what the message says after `internal error: `")
  ]

------------------------------------------------------------------------------
-- Endings and statuses
------------------------------------------------------------------------------

||| What a crash is of: a cause of the closed set, or the text a trusted
||| library gave `idris_crash`. Each is said at its site, which every crash
||| has.
public export
data Crash = Failed Cause | Said

||| Every way a compiled program ends. The program returns from `main`,
||| exits with a status it may report, or crashes at a site; or the machine
||| ends it: out of memory (no site, since the language promises nothing of
||| which allocation meets it), unable to run it, a reader of its output
||| gone, or a bug of the compiler's or the runtime's.
public export
data Ending
  = Returned
  | Exited (Fin 256)
  | Crashed Crash
  | OutOfMemory
  | CannotRun Unrunnable
  | Piped
  | InternalError Internal

||| The statuses an ending gives that no program chooses: each is the
||| ending's own, and no two are one.
public export
data Fixed = ReturnedStatus | CrashedStatus | OutOfMemoryStatus | CannotRunStatus

public export
code : Fixed -> Fin 256
code ReturnedStatus = 0
code CrashedStatus = 1
code OutOfMemoryStatus = 111
code CannotRunStatus = 126

||| No two fixed statuses are one, so a parent tells the endings apart by
||| status where no exit chose the same.
export
codeInjective : (a, b : Fixed) -> code a = code b -> a = b
codeInjective ReturnedStatus ReturnedStatus _ = Refl
codeInjective CrashedStatus CrashedStatus _ = Refl
codeInjective OutOfMemoryStatus OutOfMemoryStatus _ = Refl
codeInjective CannotRunStatus CannotRunStatus _ = Refl
codeInjective ReturnedStatus CrashedStatus Refl impossible
codeInjective ReturnedStatus OutOfMemoryStatus Refl impossible
codeInjective ReturnedStatus CannotRunStatus Refl impossible
codeInjective CrashedStatus ReturnedStatus Refl impossible
codeInjective CrashedStatus OutOfMemoryStatus Refl impossible
codeInjective CrashedStatus CannotRunStatus Refl impossible
codeInjective OutOfMemoryStatus ReturnedStatus Refl impossible
codeInjective OutOfMemoryStatus CrashedStatus Refl impossible
codeInjective OutOfMemoryStatus CannotRunStatus Refl impossible
codeInjective CannotRunStatus ReturnedStatus Refl impossible
codeInjective CannotRunStatus CrashedStatus Refl impossible
codeInjective CannotRunStatus OutOfMemoryStatus Refl impossible

||| The signals an ending raises, after its message: an internal error
||| aborts, so a parent and a bug report see the compiler's bug as such; a
||| reader gone ends the process by the signal Unix tools die of, with no
||| message and every other file written.
public export
data Signal = Abort | BrokenPipe

||| How a parent sees the end: an exit status, or a signal.
public export
data Status = Code (Fin 256) | Raised Signal

||| What an ending writes before it says anything. Everything the program
||| wrote: standard output's pending bytes, then its files, closed; a crash
||| too, as its order with output says. Standard output's pending bytes
||| alone, for an internal error, which may be met in a signal handler: the
||| runtime's own output buffer is kept safe to write there, and no stream
||| of the C library may be touched. Nothing, for a machine that cannot run
||| the program: it has written nothing, and only code compiled for the
||| target's baseline may run, which the code that writes is not.
public export
data Writes = WritesEverything | WritesOutput | WritesNothing

||| The endings that leave by a status no program chooses: one case per way
||| the runtime ends so, the detail it holds at run time (a cause, a site, a
||| text) dropped.
public export
data FixedEnding
  = EndsReturned
  | EndsFailed
  | EndsSaid
  | EndsOutOfMemory
  | EndsUnrunnable Unrunnable

||| The ending whose status the program chose: base's `exit`.
public export
data ChosenEnding = EndsExited

||| The endings that leave by a signal: a reader of an output gone, or a bug
||| of the compiler's or the runtime's.
public export
data SignalEnding = EndsPiped | EndsInternal Internal

||| How an ending leaves the process: by a status no program chooses, by the
||| status the program chose, or by a signal. Each way's endings are a closed
||| set of their own, so the runtime's ending names its case in its way's
||| set, and a fact of one way (its fixed status, its signal) is a column of
||| that set alone, never a column every ending carries and only some read.
public export
data Way = ByFixed FixedEnding | ByChoice ChosenEnding (Fin 256) | BySignal SignalEnding

public export
way : Ending -> Way
way Returned = ByFixed EndsReturned
way (Exited n) = ByChoice EndsExited n
way (Crashed (Failed _)) = ByFixed EndsFailed
way (Crashed Said) = ByFixed EndsSaid
way OutOfMemory = ByFixed EndsOutOfMemory
way (CannotRun u) = ByFixed (EndsUnrunnable u)
way Piped = BySignal EndsPiped
way (InternalError i) = BySignal (EndsInternal i)

public export
fixedStatus : FixedEnding -> Fixed
fixedStatus EndsReturned = ReturnedStatus
fixedStatus EndsFailed = CrashedStatus
fixedStatus EndsSaid = CrashedStatus
fixedStatus EndsOutOfMemory = OutOfMemoryStatus
fixedStatus (EndsUnrunnable _) = CannotRunStatus

public export
signalOf : SignalEnding -> Signal
signalOf EndsPiped = BrokenPipe
signalOf (EndsInternal _) = Abort

||| What a parent sees of an ending, read off its way.
public export
status : Ending -> Status
status e = case way e of
  ByFixed f => Code (code (fixedStatus f))
  ByChoice _ n => Code n
  BySignal s => Raised (signalOf s)

public export
fixedWrites : FixedEnding -> Writes
fixedWrites EndsReturned = WritesEverything
fixedWrites EndsFailed = WritesEverything
fixedWrites EndsSaid = WritesEverything
fixedWrites EndsOutOfMemory = WritesEverything
fixedWrites (EndsUnrunnable _) = WritesNothing

public export
chosenWrites : ChosenEnding -> Writes
chosenWrites EndsExited = WritesEverything

public export
signalWrites : SignalEnding -> Writes
signalWrites EndsPiped = WritesEverything
signalWrites (EndsInternal _) = WritesOutput

public export
fixedClosed : Closed Fixed
fixedClosed = MkClosed
  { name = ident "FixedStatus"
  , shape = OneOf
  , every = ReturnedStatus ::: [CrashedStatus, OutOfMemoryStatus, CannotRunStatus]
  , complete = \case
      ReturnedStatus => Here
      CrashedStatus => There Here
      OutOfMemoryStatus => There (There Here)
      CannotRunStatus => There (There (There Here))
  , describe = \case
      ReturnedStatus => MkCase (ident "Returned") (word "returned" ::: []) (line "the program returned from main")
      CrashedStatus => MkCase (ident "Crashed") (word "crashed" ::: []) (line "the program crashed at a site")
      OutOfMemoryStatus => MkCase (ident "OutOfMemory") (word "out_of_memory" ::: []) (line "the machine ran out of memory")
      CannotRunStatus => MkCase (ident "CannotRun") (word "cannot_run" ::: []) (line "this machine cannot run the program")
  , doc = brief (line "the exit statuses no program chooses")
  }

||| The fixed statuses as the runtime and the harness read them.
public export
statusTable : Table
statusTable = table fixedClosed
  [ MkColumn (ident "statusCode") Unsigned8
      (\f => IntCell (finToInteger (code f))) (line "the exit status a parent reads")
  ]

public export
signalClosed : Closed Signal
signalClosed = MkClosed
  { name = ident "EndingSignal"
  , shape = OneOf
  , every = Abort ::: [BrokenPipe]
  , complete = \case
      Abort => Here
      BrokenPipe => There Here
  , describe = \case
      Abort => MkCase (ident "Abort") (word "abort" ::: []) (line "SIGABRT, after the message: a bug of the compiler's or the runtime's")
      BrokenPipe => MkCase (ident "BrokenPipe") (word "broken_pipe" ::: []) (line "SIGPIPE, with no message: a reader of the output went away")
  , doc = brief (line "the signals an ending raises")
  }

public export
writesClosed : Closed Writes
writesClosed = MkClosed
  { name = ident "Writes"
  , shape = OneOf
  , every = WritesEverything ::: [WritesOutput, WritesNothing]
  , complete = \case
      WritesEverything => Here
      WritesOutput => There Here
      WritesNothing => There (There Here)
  , describe = \case
      WritesEverything => MkCase (ident "Everything") (word "everything" ::: []) (line "standard output's pending bytes, then the program's files, closed")
      WritesOutput => MkCase (ident "OutputOnly") (word "output_only" ::: []) (line "standard output's pending bytes alone, as a signal handler may write them")
      WritesNothing => MkCase (ident "Nothing") (word "nothing" ::: []) (line "nothing: a machine that cannot run the program, which has written nothing")
  , doc = brief (line "what an ending writes before it says anything")
  }

public export
fixedEndingClosed : Closed FixedEnding
fixedEndingClosed = MkClosed
  { name = ident "FixedEnding"
  , shape = OneOf
  , every =
      EndsReturned :::
      ([EndsFailed, EndsSaid, EndsOutOfMemory]
       ++ map EndsUnrunnable (forget unrunnableClosed.every))
  , complete = \case
      EndsReturned => Here
      EndsFailed => There Here
      EndsSaid => There (There Here)
      EndsOutOfMemory => There (There (There Here))
      EndsUnrunnable u => There (There (There (There (elemMap EndsUnrunnable (unrunnableClosed.complete u)))))
  , describe = \case
      EndsReturned => MkCase (ident "Returned") (word "returned" ::: []) (line "the program returned from main")
      EndsFailed => MkCase (ident "Failed") (word "failed" ::: []) (line "a crash of a cause of the closed set, at its site")
      EndsSaid => MkCase (ident "Said") (word "said" ::: []) (line "a crash of the text a trusted library gave idris_crash, at its site")
      EndsOutOfMemory => MkCase (ident "OutOfMemory") (word "out_of_memory" ::: []) (line "the machine ran out of memory")
      EndsUnrunnable u => unrunnableClosed.describe u
  , doc = brief (line "the endings that leave by a status no program chooses")
  }

public export
chosenEndingClosed : Closed ChosenEnding
chosenEndingClosed = MkClosed
  { name = ident "ChosenEnding"
  , shape = OneOf
  , every = EndsExited ::: []
  , complete = \case
      EndsExited => Here
  , describe = \case
      EndsExited => MkCase (ident "Exited") (word "exited" ::: []) (line "the program ended itself with a status a parent reads")
  , doc = brief (line "the ending whose status the program chose")
  }

public export
signalEndingClosed : Closed SignalEnding
signalEndingClosed = MkClosed
  { name = ident "SignalEnding"
  , shape = OneOf
  , every = EndsPiped ::: map EndsInternal (forget internalClosed.every)
  , complete = \case
      EndsPiped => Here
      EndsInternal i => There (elemMap EndsInternal (internalClosed.complete i))
  , describe = \case
      EndsPiped => MkCase (ident "Piped") (word "piped" ::: []) (line "a reader of one of the program's outputs went away")
      EndsInternal i => internalClosed.describe i
  , doc = brief (line "the endings that leave by a signal")
  }

||| The endings that leave by a fixed status, as the runtime reads them: the
||| status, and what each writes first.
public export
fixedEndingTable : Table
fixedEndingTable = table fixedEndingClosed
  [ MkColumn (ident "fixedStatus") (EnumColumn (enumDef fixedClosed))
      (\f => CaseCell (caseRef fixedClosed (fixedStatus f))) (line "the status a parent reads")
  , MkColumn (ident "fixedWrites") (EnumColumn (enumDef writesClosed))
      (\f => CaseCell (caseRef writesClosed (fixedWrites f))) (line "what the ending writes before it says anything")
  ]

||| The ending whose status the program chose, as the runtime reads it: what
||| it writes first; its status is its own.
public export
chosenEndingTable : Table
chosenEndingTable = table chosenEndingClosed
  [ MkColumn (ident "chosenWrites") (EnumColumn (enumDef writesClosed))
      (\c => CaseCell (caseRef writesClosed (chosenWrites c))) (line "what the ending writes before it says anything")
  ]

||| The endings that leave by a signal, as the runtime reads them: the
||| signal, and what each writes first.
public export
signalEndingTable : Table
signalEndingTable = table signalEndingClosed
  [ MkColumn (ident "signalOf") (EnumColumn (enumDef signalClosed))
      (\s => CaseCell (caseRef signalClosed (signalOf s))) (line "the signal the ending raises")
  , MkColumn (ident "signalWrites") (EnumColumn (enumDef writesClosed))
      (\s => CaseCell (caseRef writesClosed (signalWrites s))) (line "what the ending writes before it says anything")
  ]

||| What the runtime is printed: the causes, the internal errors, the fixed
||| statuses, why a machine cannot run a program, the signals, what an ending
||| writes first, and the endings of each way out, each with what the
||| runtime reads of it. In a namespace of their own, apart from
||| the dialect's enum of causes, which an op's site holds: both are printed
||| from the one closed set, so their cases are one list.
public export
endingsHeader : Header
endingsHeader = MkHeader (ident "Endings")
  [ (Nested (ident "endings" ::: []),
      [ EnumOf (enumDef namingClosed)
      , TableOf causeTable
      , TableOf internalTable
      , TableOf statusTable
      , EnumOf (enumDef unrunnableClosed)
      , EnumOf (enumDef signalClosed)
      , EnumOf (enumDef writesClosed)
      , TableOf fixedEndingTable
      , TableOf chosenEndingTable
      , TableOf signalEndingTable
      ])
  ]
  (brief (line "how a compiled program ends, as the runtime reads it"))
