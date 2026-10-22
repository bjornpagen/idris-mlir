-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| What the Prelude's IO does, and its buffers. No world reaches the IR:
||| IO is ordered by declared effects alone, each op reading and writing
||| the outside, one ordered state, so two IO ops never cross and an unused
||| one stays. A trusted library's IO run for a pure value is a region op,
||| `io.unsafe_run`, whose effects are its region's, so they happen where
||| the value is demanded. Output of a number composes its show and one
||| output of a string, the runtime's put and show sharing one formatter
||| each, and writing a built string writes its pieces (a rule).
|||
||| A buffer op acts on its buffer's own memory, which it names, and does
||| no IO: a buffer is the program's memory, written while shared.
module IdrisMLIR.Spec.Ops.IO

import IdrisMLIR.Spec.Core.Vocabulary
import IdrisMLIR.Spec.Effects.Declaration
import IdrisMLIR.Spec.Runtime.Endings
import IdrisMLIR.Spec.Ops.Shapes
import IdrisMLIR.Spec.Ops.Checks

import Data.List1
import Data.So
import Data.Vect

%default total

------------------------------------------------------------------------------
-- Output and input
------------------------------------------------------------------------------

||| An IO op of the runtime's function `io_<name>`, its results' types the
||| ones their constraints fix.
ioOp : {i : Nat} -> {o : Nat} -> (m : Mnemonic) -> (ins : Vect i Operand) -> (outs : Vect o Result)
    -> Declaration i o -> RuntimeCall i o -> Doc
    -> {auto 0 named : So (distinct (groupNames ins outs [] []))}
    -> Op i o 0 0
ioOp m ins outs eff call d = MkOp
  { home = InIdr
  , mnemonic = m
  , ins = ins
  , outs = outs
  , attrs = []
  , regions = []
  , traits = []
  , interfaces = []
  , effects = eff
  , speculation = NotSpeculatable
  , stages = Always
  , meaning = CallsRuntime call
  , verify = DeclarationOnly
  , format = plain i
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = d
  , typing = fixedTypes outs
  }

||| A string's UTF-8 to standard output, through the output buffer, in
||| order with every other write to it.
public export
putStrOp : Op 1 0 0 0
putStrOp = ioOp "io.put_str" [single "str" strRead] [] (outside Untouched)
  (MkRuntimeCall "io_put_str" [TakesStr] NoResult)
  (says "writes a string to standard output")

||| The UTF-8 encoding of a character, a Unicode scalar value: the Prelude's
||| putCharOp, and what writing a one-character string writes.
public export
putCharOp : Op 1 0 0 0
putCharOp = ioOp "io.put_char" [single "ch" i32] [] (outside Untouched)
  (MkRuntimeCall "io_put_char" [TakesInt32] NoResult)
  (says "writes a character to standard output")

||| The Prelude's getChar: a byte of input.
public export
getByteOp : Op 0 1 0 0
getByteOp = ioOp "io.get_byte" [] [result "ch" i32] (outside Untouched)
  (MkRuntimeCall "io_get_byte" [] (Returns GivesInt32))
  (says "reads a byte of standard input")

||| The Prelude's getLineOp: a line of input, a new string.
public export
getLineOp : Op 0 1 0 0
getLineOp = ioOp "io.get_line" [] [result "str" strValue] (outsideBuilding 0 Touched)
  (MkRuntimeCall "io_get_line" [] (Returns GivesStr))
  (says "reads a line of standard input")

||| A transfer of the bytes [offset, offset + count) of a buffer between it
||| and a handle: IO, and the buffer's own memory read (to a handle) or
||| written (from one). The range lies in the buffer, which `check.range`
||| guards: the frontend gives it the buffer's length as its size.
transfer : Mnemonic -> (k : Kind) -> Symbol -> Doc
        -> {auto 0 admitted : AdmitsKind Contents k}
        -> {auto 0 names : Names {i = 4} {o = 1} k (Operands 1)}
        -> Op 4 1 0 0
transfer m k s d = ioOp m
  [single "handle" i64, single "buffer" byteBuffer, single "offset" i64, single "count" i64]
  [result "moved" i64]
  (Executes [OnState Read IO, OnState Write IO, OnValues k Contents (Operands 1)] [] Covered Untouched)
  (MkRuntimeCall s [TakesInt64, TakesBuffer, TakesInt64, TakesInt64] (Returns GivesInt64))
  d

||| Bytes of a buffer to a handle: 1 is standard output, through the output
||| buffer and in order with every other write to it; 2 is standard error;
||| any other a file the program opened. Gives the count written.
public export
writeBytesOp : Op 4 1 0 0
writeBytesOp = transfer "io.write_bytes" Read "io_write_bytes" (says "writes bytes of a buffer to a handle")

||| Bytes from a handle into a buffer: 0 is standard input, through the
||| runtime's input buffer, any other a file the program opened. Gives the
||| count read, 0 at the end of input.
public export
readBytesOp : Op 4 1 0 0
readBytesOp = transfer "io.read_bytes" Write "io_read_bytes" (says "reads bytes from a handle into a buffer")

||| 1 once a read on the handle met the end of its input, as C's feof
||| reports it, else 0.
public export
eofOp : Op 1 1 0 0
eofOp = ioOp "io.eof" [single "handle" i64] [result "ended" i64] (outside Untouched)
  (MkRuntimeCall "io_eof" [TakesInt64] (Returns GivesInt64))
  (says "whether a read on a handle met the end of its input")

||| How many processors are online, -1 where the system does not say.
public export
nProcessorsOp : Op 0 1 0 0
nProcessorsOp = ioOp "io.n_processors" [] [result "count" i64] (outside Untouched)
  (MkRuntimeCall "io_n_processors" [] (Returns GivesInt64))
  (says "how many processors are online")

------------------------------------------------------------------------------
-- The end of a run, and IO run for a value
------------------------------------------------------------------------------

||| Writes pending output and ends the process with a status, normally: an
||| IO action that never returns, not a crash and not a divergence. A
||| status no parent can read, outside 0 to 255, is a crash at the exit's
||| site, so it writes the crash too, and carries its site.
public export
exitOp : Op 1 0 1 0
exitOp = MkOp
  { home = InIdr
  , mnemonic = "io.exit"
  , ins = [single "status" i64]
  , outs = []
  , attrs = [attr "site" (OurAttr (SomeAttr siteAttr))]
  , regions = []
  , traits = [Terminator]
  , interfaces = []
  , effects =
      Executes [OnState Read IO, OnState Write IO, OnState Write Exit, OnState Write Crash] []
        Covered Untouched
  , speculation = NotSpeculatable
  , stages = Always
  , meaning = CallsRuntime (MkRuntimeCall "exit" [TakesInt64] NeverReturns)
  , verify = DeclarationOnly
  , format = Declared [ValueOf (OperandRef 0), Lit "at", ValueOf (AttrRef 0), AttrDict]
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = says "writes pending output and ends the process with a status; does not return"
  }

export
0 exitStops : Stops (effects IO.exitOp)
exitStops = StopsByExit

||| A trusted library's IO action run for a pure value (`unsafePerformIO`):
||| its region, one block ending in `idr.yield`, runs where the op stands,
||| and its effects are its region's, so the function that demands the
||| value carries them in its row and orders them with every other effect.
||| No world is forged: the effects order it. Nothing runs at its end but
||| the handing on of its results, so a break crosses it: a jump from its
||| region to a join point around it, and frames splitting a call on its
||| function's own cycle inside it, whose continuation is the code after
||| it. Lowered to a region run once, which keeps such a jump.
public export
unsafeRun : Op 0 1 0 1
unsafeRun = MkOp
  { home = InIdr
  , mnemonic = "io.unsafe_run"
  , ins = []
  , outs = [results "results" (UpstreamType AnyTypeC)]
  , attrs = []
  , regions = [sized "body" 1]
  , traits = [SingleBlock, PropagateControlFlowBreak, HasNestedTerminator ("yield" ::: [])]
  , interfaces = [Declares RegionBranch ["getSuccessorRegions"]]
  , effects = Executes [] [] Recursive Untouched
  , speculation = RecursivelySpeculatable
  , stages = Always
  , meaning = NoFold
  , verify = DeclarationOnly
  , format = Declared [Regions, AttrDict, Lit ":", TypeOf OfResults]
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = says "runs a trusted library's IO action for a pure value where the value is demanded"
  }

------------------------------------------------------------------------------
-- Buffers
------------------------------------------------------------------------------

||| A buffer op: its buffers' own memory, no IO. Its span lies in the
||| buffer, which `check.range` guards before it: the frontend gives the
||| guard the bytes the op moves and the buffer's length.
bufferOp : {i : Nat} -> {o : Nat} -> (m : Mnemonic) -> (ins : Vect i Operand) -> (outs : Vect o Result)
        -> Declaration i o -> Meaning i o -> Doc
        -> {auto 0 named : So (distinct (groupNames ins outs [] []))}
        -> Op i o 0 0
bufferOp m ins outs eff meaning d = MkOp
  { home = InIdr
  , mnemonic = m
  , ins = ins
  , outs = outs
  , attrs = []
  , regions = []
  , traits = []
  , interfaces = []
  , effects = eff
  , speculation = NotSpeculatable
  , stages = Always
  , meaning = meaning
  , verify = DeclarationOnly
  , format = plain i
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = d
  }

machineWord : TypeC
machineWord = AnyOfTypes (UpstreamType I8C ::: [UpstreamType I16C, UpstreamType I32C, UpstreamType I64C, f64])
  "a machine word: an integer of 8, 16, 32 or 64 bits, or a Double"

||| A machine word of a buffer at a byte offset, read by the target's own
||| load at alignment 1: the machine's endianness, any offset. Not a
||| runtime call: the value's width is the op's type.
public export
bufferLoad : Op 2 1 0 0
bufferLoad = bufferOp "buffer.load" [single "buffer" byteBuffer, single "offset" i64] [result "value" machineWord]
  (Executes [OnValues Read Contents (Operands 0)] [] Covered Untouched) NoFold
  (says "a machine word read from a buffer at a byte offset")

public export
bufferStore : Op 3 0 0 0
bufferStore = bufferOp "buffer.store" [single "buffer" byteBuffer, single "offset" i64, single "value" machineWord] []
  (Executes [OnValues Write Contents (Operands 0)] [] Covered Untouched) NoFold
  (says "a machine word written into a buffer at a byte offset")

||| Bytes copied from one buffer into another, which may overlap: memmove.
public export
bufferCopy : Op 5 0 0 0
bufferCopy = bufferOp "buffer.copy"
  [ single "src" byteBuffer, single "src_offset" i64, single "len" i64, single "dst" byteBuffer
  , single "dst_offset" i64 ] []
  (Executes [OnValues Read Contents (Operands 0), OnValues Write Contents (Operands 3)] [] Covered Untouched)
  (CallsRuntime (MkRuntimeCall "io_buffer_copy" [TakesBuffer, TakesInt64, TakesInt64, TakesBuffer, TakesInt64] NoResult))
  (says "bytes copied from one buffer into another")

||| A string's UTF-8 written at an offset: its byte length, interior zeros
||| included.
public export
bufferSetString : Op 3 0 0 0
bufferSetString = bufferOp "buffer.set_string" [single "buffer" byteBuffer, single "offset" i64, single "str" strRead] []
  (Executes [OnValues Write Contents (Operands 0)] [] Covered Untouched)
  (CallsRuntime (MkRuntimeCall "io_buffer_set_string" [TakesBuffer, TakesInt64, TakesStr] NoResult))
  (says "a string's bytes written into a buffer")

||| A buffer's bytes read as a new string, ill-formed UTF-8 replaced as the
||| runtime replaces it.
public export
bufferGetString : Op 3 1 0 0
bufferGetString = bufferOp "buffer.get_string" [single "buffer" byteBuffer, single "offset" i64, single "len" i64]
  [result "str" strValue]
  (Executes [OnValues Read Contents (Operands 0)] [Acquires 0] Covered Untouched)
  (CallsRuntime (MkRuntimeCall "io_buffer_get_string" [TakesBuffer, TakesInt64, TakesInt64] (Returns GivesStr)))
  (says "a buffer's bytes read as a string")

public export
ioOps : List AnyOp
ioOps =
  [ SomeOp putStrOp, SomeOp putCharOp, SomeOp getByteOp, SomeOp getLineOp, SomeOp writeBytesOp
  , SomeOp readBytesOp, SomeOp eofOp, SomeOp nProcessorsOp, SomeOp exitOp, SomeOp unsafeRun
  , SomeOp bufferLoad, SomeOp bufferStore, SomeOp bufferCopy, SomeOp bufferSetString
  , SomeOp bufferGetString ]
