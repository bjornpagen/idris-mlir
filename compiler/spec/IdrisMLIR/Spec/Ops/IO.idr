-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| What the Prelude's IO does, and its buffers. No world reaches the IR:
||| IO is ordered by declared effects alone, each op reading and writing
||| the outside, one ordered state, so two IO ops never cross and an unused
||| one stays. Output of a number composes its show and one output of a
||| string, the runtime's put and show sharing one formatter each, and
||| writing a built string writes its pieces (a rule).
|||
||| A buffer op acts on its buffer's own memory, which it names, and does
||| no IO: a buffer is the program's memory, written while shared.
module IdrisMLIR.Spec.Ops.IO

import IdrisMLIR.Spec.Core.Vocabulary
import IdrisMLIR.Spec.Effects.Declaration
import IdrisMLIR.Spec.Runtime.Endings
import IdrisMLIR.Spec.Ops.Shapes

import Data.List1
-- `ioOp`'s and `bufferOp`'s automatic proofs are searched where they are written.
import public Data.So
import Data.Vect

%default total

------------------------------------------------------------------------------
-- Output and input
------------------------------------------------------------------------------

||| An IO op of a runtime function (`io_<name>`, or the exit's `exit`), its
||| operands as the function takes them, its results as it gives them, their
||| types the ones their constraints fix.
public export
ioOp : {i : Nat} -> {o : Nat} -> (m : Mnemonic) -> (f : RuntimeFunction i o)
    -> Declaration i o -> Doc
    -> {auto 0 named : So (distinct (groupNames (operandsOf f) (resultsOf f) [] []))}
    -> Op i o 0 0
ioOp m f eff d = MkOp
  { home = InIdr
  , mnemonic = m
  , ins = operandsOf f
  , outs = resultsOf f
  , attrs = []
  , regions = []
  , traits = []
  , interfaces = []
  , effects = eff
  , speculation = NotSpeculatable
  , stages = Always
  , meaning = CallsRuntime f
  , verify = DeclarationOnly
  , format = plain i
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = d
  , typing = fixedTypes (resultsOf f)
  }

||| A string's UTF-8 to standard output, through the output buffer, in
||| order with every other write to it. Writing the string is all it does
||| with it, so a chain of single uses ends at it, as at a match.
public export
putStrOp : Op 1 0 0 0
putStrOp =
  { traits := [OurTrait eliminatesOperand] }
  (ioOp "io.put_str" (MkRuntimeFunction "io_put_str" [str "str"] NoResult) (outside Untouched)
    (says "writes a string to standard output"))

||| The UTF-8 encoding of a character, a Unicode scalar value: the Prelude's
||| putCharOp, and what writing a one-character string writes.
public export
putCharOp : Op 1 0 0 0
putCharOp = ioOp "io.put_char" (MkRuntimeFunction "io_put_char" [word32 "ch"] NoResult) (outside Untouched)
  (says "writes a character to standard output")

||| The Prelude's getChar: a byte of input.
public export
getByteOp : Op 0 1 0 0
getByteOp = ioOp "io.get_byte" (MkRuntimeFunction "io_get_byte" [] (returnsWord32 "ch")) (outside Untouched)
  (says "reads a byte of standard input")

||| The Prelude's getLineOp: a line of input, a new string.
public export
getLineOp : Op 0 1 0 0
getLineOp = ioOp "io.get_line" (MkRuntimeFunction "io_get_line" [] (returnsStr "str")) (outsideBuilding 0 Touched)
  (says "reads a line of standard input")

||| A transfer of the bytes [offset, offset + count) of a buffer between it
||| and a handle: IO, and the buffer's own memory read (to a handle) or
||| written (from one). The range lies in the buffer, which `check.range`
||| guards: the frontend gives it the buffer's length as its size.
public export
transfer : Mnemonic -> (k : Kind) -> Symbol -> Doc
        -> {auto 0 admitted : AdmitsKind Contents k}
        -> {auto 0 names : Names {i = 4} {o = 1} k (Operands 1)}
        -> Op 4 1 0 0
transfer m k s d = ioOp m
  (MkRuntimeFunction s [word64 "handle", buffer "buffer", word64 "offset", word64 "count"] (returnsWord64 "moved"))
  (Executes [OnState Read IO, OnState Write IO, OnValues k Contents (Operands 1)] [] Covered Untouched)
  d

||| Bytes of a buffer to a handle: a StandardStream's, standard output's
||| through the output buffer and in order with every other write to it,
||| or a file's the program opened. Gives the count written.
public export
writeBytesOp : Op 4 1 0 0
writeBytesOp = transfer "io.write_bytes" Read "io_write_bytes" (says "writes bytes of a buffer to a handle")

||| Bytes from a handle into a buffer: standard input's, through the
||| runtime's input buffer, or a file's the program opened. Gives the count
||| read, 0 at the end of input.
public export
readBytesOp : Op 4 1 0 0
readBytesOp = transfer "io.read_bytes" Write "io_read_bytes" (says "reads bytes from a handle into a buffer")

||| 1 once a read on the handle met the end of its input, as C's feof
||| reports it, else 0.
public export
eofOp : Op 1 1 0 0
eofOp = ioOp "io.eof" (MkRuntimeFunction "io_eof" [word64 "handle"] (returnsWord64 "ended")) (outside Untouched)
  (says "whether a read on a handle met the end of its input")

||| How many processors are online, -1 where the system does not say.
public export
nProcessorsOp : Op 0 1 0 0
nProcessorsOp = ioOp "io.n_processors" (MkRuntimeFunction "io_n_processors" [] (returnsWord64 "count"))
  (outside Untouched)
  (says "how many processors are online")

------------------------------------------------------------------------------
-- The end of a run
------------------------------------------------------------------------------

||| Writes pending output and ends the process with a status, normally: an
||| IO action that never returns, not a crash and not a divergence. A
||| status no parent can read, outside 0 to 255, is its guard's crash at
||| the exit's site, so the exit itself is total and its function is given
||| the byte its guard bounds.
public export
exitOp : Op 1 0 0 0
exitOp =
  { traits := [Terminator]
  , guards := [MkGuard Byte [0] ExitStatusOutOfRange] }
  (ioOp "io.exit" (MkRuntimeFunction "exit" [exitByte "status"] NeverReturns)
    (Executes [OnState Read IO, OnState Write IO, OnState Write Exit] [] Covered Untouched)
    (says "writes pending output and ends the process with a status; does not return"))

export
0 exitStops : Stops (effects IO.exitOp)
exitStops = StopsByExit

------------------------------------------------------------------------------
-- Buffers
------------------------------------------------------------------------------

||| A buffer op: its buffers' own memory, no IO. Its span lies in the
||| buffer, which `check.range` guards before it: the frontend gives the
||| guard the bytes the op moves and the buffer's length.
public export
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
bufferCopy = bufferOp "buffer.copy" (operandsOf runtime) (resultsOf runtime)
  (Executes [OnValues Read Contents (Operands 0), OnValues Write Contents (Operands 3)] [] Covered Untouched)
  (CallsRuntime runtime)
  (says "bytes copied from one buffer into another")
  where
    runtime : RuntimeFunction 5 0
    runtime = MkRuntimeFunction "io_buffer_copy"
      [buffer "src", word64 "src_offset", word64 "len", buffer "dst", word64 "dst_offset"] NoResult

||| A string's UTF-8 written at an offset: its byte length, interior zeros
||| included.
public export
bufferSetString : Op 3 0 0 0
bufferSetString = bufferOp "buffer.set_string" (operandsOf runtime) (resultsOf runtime)
  (Executes [OnValues Write Contents (Operands 0)] [] Covered Untouched)
  (CallsRuntime runtime)
  (says "a string's bytes written into a buffer")
  where
    runtime : RuntimeFunction 3 0
    runtime = MkRuntimeFunction "io_buffer_set_string" [buffer "buffer", word64 "offset", str "str"] NoResult

||| A buffer's bytes read as a new string, ill-formed UTF-8 replaced as the
||| runtime replaces it.
public export
bufferGetString : Op 3 1 0 0
bufferGetString = bufferOp "buffer.get_string" (operandsOf runtime) (resultsOf runtime)
  (Executes [OnValues Read Contents (Operands 0)] [Acquires 0] Covered Untouched)
  (CallsRuntime runtime)
  (says "a buffer's bytes read as a string")
  where
    runtime : RuntimeFunction 3 1
    runtime = MkRuntimeFunction "io_buffer_get_string" [buffer "buffer", word64 "offset", word64 "len"]
      (returnsStr "str")

public export
ioOps : List AnyOp
ioOps =
  [ SomeOp putStrOp, SomeOp putCharOp, SomeOp getByteOp, SomeOp getLineOp, SomeOp writeBytesOp
  , SomeOp readBytesOp, SomeOp eofOp, SomeOp nProcessorsOp, SomeOp exitOp
  , SomeOp bufferLoad, SomeOp bufferStore, SomeOp bufferCopy, SomeOp bufferSetString
  , SomeOp bufferGetString ]
