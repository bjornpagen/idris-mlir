-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Base's surface beyond the Prelude's IO, as runtime primitives: files,
||| directories, the process, the terminal, errors, clocks, and the handles
||| that stand for pointers (System.File, System.Directory, System,
||| System.Term, System.Errno, System.Clock). Each op's one meaning is the
||| runtime function it calls, documented beside that function, for every
||| target. A failing call sets the runtime's saved errno, which
||| idr.io.errno and idr.io.file_errno read.
|||
||| A pointer is a handle, an i64: 0, 1 and 2 the standard streams, -1 null,
||| any other a slot of the runtime's handle table. An OSClock is an i64,
||| seconds << 30 | nanoseconds, or -1 where the clock cannot be read: its
||| queries and the null test are arith over those encodings, which the
||| frontend writes, and a collector's clock, which no program has, is the
||| constant -1. A clock reading is one op over the clocks that exist. A
||| file's times are read at once, as the one OS call gives them, into a
||| file-time handle, base's FileTimePtr; base reads it field by field, one
||| op over the fields, and frees it.
module IdrisMLIR.Spec.Ops.Platform

import IdrisMLIR.Spec.Core.Vocabulary
import IdrisMLIR.Spec.Effects.Declaration
import IdrisMLIR.Spec.Runtime.Clocks
import IdrisMLIR.Spec.Runtime.Endings
import IdrisMLIR.Spec.Ops.Checks
import IdrisMLIR.Spec.Ops.Shapes

import Data.List.Elem
import Data.List1
import Data.So
import Data.Vect

%default total

------------------------------------------------------------------------------
-- The shapes
------------------------------------------------------------------------------

||| A primitive of base's platform: the runtime function `io_<name>` of its
||| operands, its effects as that function has them.
platformOp : {i : Nat} -> {o : Nat} -> (m : Mnemonic) -> (ins : Vect i Operand) -> (outs : Vect o Result)
          -> Declaration i o -> RuntimeCall i o -> Doc
          -> {auto 0 named : So (distinct (groupNames ins outs [] []))}
          -> Op i o 0 0
platformOp m ins outs eff call d = MkOp
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
  }

||| An op of a handle, giving an Int: `fileSize`, `fflush` and their kin.
handleQuery : Mnemonic -> Symbol -> RuntimeMemory -> Doc -> Op 1 1 0 0
handleQuery m s memory d = platformOp m [single "handle" i64] [result "result" i64] (outside memory)
  (MkRuntimeCall s [TakesInt64] (Returns GivesInt64)) d

||| An op of a path, giving an Int: 0 on success, as its C function gives it.
pathOp : Mnemonic -> Symbol -> Doc -> Op 1 1 0 0
pathOp m s d = platformOp m [single "path" strRead] [result "result" i64] (outside Touched)
  (MkRuntimeCall s [TakesStr] (Returns GivesInt64)) d

||| An op of nothing, giving an Int, with the effects `eff`.
reading : Mnemonic -> Symbol -> Declaration 0 1 -> Doc -> Op 0 1 0 0
reading m s eff d = platformOp m [] [result "result" i64] eff
  (MkRuntimeCall s [] (Returns GivesInt64)) d

------------------------------------------------------------------------------
-- Files
------------------------------------------------------------------------------

public export
fileOpen : Op 2 1 0 0
fileOpen = platformOp "io.file_open" [single "path" strRead, single "mode" strRead] [result "file" i64]
  (outside Touched) (MkRuntimeCall "io_file_open" [TakesStr, TakesStr] (Returns GivesInt64))
  (says "opens the file at a path in a mode, as fopen does: a file handle, or null")

public export
fileClose : Op 1 0 0 0
fileClose = platformOp "io.file_close" [single "file" i64] [] (outside Touched)
  (MkRuntimeCall "io_file_close" [TakesInt64] NoResult)
  (says "closes a file and frees its handle")

public export
fileError : Op 1 1 0 0
fileError = handleQuery "io.file_error" "io_file_error" Untouched
  (says "whether a file's stream has an error, as ferror says")

||| The saved errno of the last failing file operation: the runtime's own
||| state, read, and nothing the outside sees.
public export
fileErrno : Op 0 1 0 0
fileErrno = reading "io.file_errno" "io_file_errno" readsRuntimeState
  (says "the saved errno of the last failing file operation")

||| The line is a string handle the program owns, which base frees through
||| idr.io.handle_free; so are read_chars'.
public export
fileReadLine : Op 1 1 0 0
fileReadLine = handleQuery "io.file_read_line" "io_file_read_line" Touched
  (says "the next line of a file, as a string handle, or null")

public export
fileReadChars : Op 2 1 0 0
fileReadChars = platformOp "io.file_read_chars" [single "max" i64, single "file" i64] [result "chars" i64]
  (outside Touched) (MkRuntimeCall "io_file_read_chars" [TakesInt64, TakesInt64] (Returns GivesInt64))
  (says "at most `max` characters of a file, as a string handle, or null")

public export
fileReadChar : Op 1 1 0 0
fileReadChar = handleQuery "io.file_read_char" "io_file_read_char" Untouched (says "the next character of a file")

public export
fileWriteLine : Op 2 1 0 0
fileWriteLine = platformOp "io.file_write_line" [single "file" i64, single "line" strRead] [result "result" i64]
  (outside Untouched) (MkRuntimeCall "io_file_write_line" [TakesInt64, TakesStr] (Returns GivesInt64))
  (says "writes a string to a file")

public export
fileFlush : Op 1 1 0 0
fileFlush = handleQuery "io.file_flush" "io_file_flush" Untouched (says "writes what is pending of a file, as fflush does")

public export
fileSeekLine : Op 1 1 0 0
fileSeekLine = handleQuery "io.file_seek_line" "io_file_seek_line" Untouched (says "skips a file past its next line")

public export
fileRemove : Op 1 1 0 0
fileRemove = pathOp "io.file_remove" "io_file_remove" (says "removes the file at a path")

public export
fileSize : Op 1 1 0 0
fileSize = handleQuery "io.file_size" "io_file_size" Untouched (says "the size of a file in bytes")

public export
filePoll : Op 1 1 0 0
filePoll = handleQuery "io.file_poll" "io_file_poll" Untouched (says "whether a file has input ready to read")

public export
fileIsTty : Op 1 1 0 0
fileIsTty = handleQuery "io.file_is_tty" "io_file_is_tty" Untouched (says "whether a file is a terminal")

public export
fileChmod : Op 2 1 0 0
fileChmod = platformOp "io.file_chmod" [single "path" strRead, single "mode" i64] [result "result" i64]
  (outside Touched) (MkRuntimeCall "io_file_chmod" [TakesStr, TakesInt64] (Returns GivesInt64))
  (says "sets the mode of the file at a path")

------------------------------------------------------------------------------
-- A file's times
------------------------------------------------------------------------------

||| What base reads of a file's times, one at a time: the access,
||| modification and status change times, each its seconds or its
||| nanoseconds since the epoch, as fstat gives them.
public export
data FileTimeField
  = AccessSeconds | AccessNanoseconds
  | ModifiedSeconds | ModifiedNanoseconds
  | StatusSeconds | StatusNanoseconds

public export
fileTimeFieldClosed : Closed FileTimeField
fileTimeFieldClosed = MkClosed
  { name = ident "FileTimeField"
  , shape = OneOf
  , every =
      AccessSeconds ::: [AccessNanoseconds, ModifiedSeconds, ModifiedNanoseconds, StatusSeconds, StatusNanoseconds]
  , complete = \case
      AccessSeconds => Here
      AccessNanoseconds => There Here
      ModifiedSeconds => There (There Here)
      ModifiedNanoseconds => There (There (There Here))
      StatusSeconds => There (There (There (There Here)))
      StatusNanoseconds => There (There (There (There (There Here))))
  , describe = \case
      AccessSeconds => MkCase (ident "AccessSeconds") (word "atime_sec" ::: []) (line "the seconds of the last access")
      AccessNanoseconds => MkCase (ident "AccessNanoseconds") (word "atime_nsec" ::: []) (line "the nanoseconds of the last access")
      ModifiedSeconds => MkCase (ident "ModifiedSeconds") (word "mtime_sec" ::: []) (line "the seconds of the last modification")
      ModifiedNanoseconds => MkCase (ident "ModifiedNanoseconds") (word "mtime_nsec" ::: []) (line "the nanoseconds of the last modification")
      StatusSeconds => MkCase (ident "StatusSeconds") (word "ctime_sec" ::: []) (line "the seconds of the last status change")
      StatusNanoseconds => MkCase (ident "StatusNanoseconds") (word "ctime_nsec" ::: []) (line "the nanoseconds of the last status change")
  , doc = brief (line "a field of a file's times")
  }

||| What the runtime's file-time entries are printed: the fields, in the
||| order a file-time handle holds them, which its entries, one template
||| instantiated per field, read.
public export
fileTimesHeader : Header
fileTimesHeader = MkHeader (ident "FileTimes")
  [ (ident "idr" ::: [ident "files"], [EnumOf (enumDef fileTimeFieldClosed)]) ]
  (brief (line "the fields of a file's times, in the order a file-time handle holds them"))

||| Base's prim__fileTime: a file's times, read at once as the one OS call
||| gives them, into a new file-time handle, which base reads field by field
||| and frees with idr.io.handle_free. Where they cannot be read, every field
||| is -1 and the saved errno says why: base takes an access time that is
||| not positive for a failure and reads it.
public export
fileTime : Op 1 1 0 0
fileTime = platformOp "io.file_time" [single "file" i64] [result "times" i64] (outside Touched)
  (MkRuntimeCall "io_file_time" [TakesInt64] (Returns GivesInt64))
  (says "a file's times, read at once into a new file-time handle")

||| Base's six readers of a file time, which differ only in the field they
||| read, the property `kind`: a read of the runtime's handle table and
||| nothing else. The runtime's entries are one template instantiated per
||| field, `idris_rt_handle_file_time_<field>`, and the lowering calls the
||| one the op's kind names, so no field is passed or tested at run time. A
||| handle that holds no file's times reads as -1; base, whose only
||| file-time handles are its own fileTime's, never asks one.
public export
handleFileTime : Op 1 1 1 0
handleFileTime = MkOp
  { home = InIdr
  , mnemonic = "handle.file_time"
  , ins = [single "times" i64]
  , outs = [result "value" i64]
  , attrs = [property "kind" (EnumProperty (enumDef fileTimeFieldClosed))]
  , regions = []
  , traits = []
  , interfaces = []
  , effects = readsRuntimeState
  , speculation = NotSpeculatable
  , stages = Always
  , meaning =
      CallsRuntimeByCase (enumDef fileTimeFieldClosed)
        (MkRuntimeCall "handle_file_time" [TakesInt64] (Returns GivesInt64))
  , verify = DeclarationOnly
  , format = attrFirst 1 0
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = says "a field of the times a file-time handle holds"
  }

------------------------------------------------------------------------------
-- Directories
------------------------------------------------------------------------------

||| The path is a string handle the program owns, which base's currentDir
||| frees through idr.io.handle_free.
public export
dirCurrent : Op 0 1 0 0
dirCurrent = reading "io.dir_current" "io_dir_current" (outside Touched)
  (says "the current directory's path, as a string handle, or null")

public export
dirChange : Op 1 1 0 0
dirChange = pathOp "io.dir_change" "io_dir_change" (says "makes a path the current directory")

public export
dirCreate : Op 1 1 0 0
dirCreate = pathOp "io.dir_create" "io_dir_create" (says "creates a directory at a path")

public export
dirRemove : Op 1 0 0 0
dirRemove = platformOp "io.dir_remove" [single "path" strRead] [] (outside Touched)
  (MkRuntimeCall "io_dir_remove" [TakesStr] NoResult)
  (says "removes the directory at a path")

public export
dirOpen : Op 1 1 0 0
dirOpen = platformOp "io.dir_open" [single "path" strRead] [result "dir" i64] (outside Touched)
  (MkRuntimeCall "io_dir_open" [TakesStr] (Returns GivesInt64))
  (says "opens the directory at a path: a directory handle, or null")

public export
dirClose : Op 1 0 0 0
dirClose = platformOp "io.dir_close" [single "dir" i64] [] (outside Touched)
  (MkRuntimeCall "io_dir_close" [TakesInt64] NoResult)
  (says "closes a directory, its handle and the entry it last gave")

||| The entry's name is a string the runtime owns: the next entry replaces
||| it, and closing the directory releases it.
public export
dirEntry : Op 1 1 0 0
dirEntry = handleQuery "io.dir_entry" "io_dir_entry" Touched
  (says "the name of a directory's next entry, as a string handle, or null at its end")

------------------------------------------------------------------------------
-- The process
------------------------------------------------------------------------------

||| The arguments are fixed for the run: reading their number does nothing.
public export
argCount : Op 0 1 0 0
argCount = reading "io.arg_count" "io_arg_count" computes
  (says "the number of the program's arguments, its name included")

public export
arg : Op 1 1 0 0
arg = platformOp "io.arg" [single "index" i64] [result "str" strValue] (builds 0 Untouched)
  (MkRuntimeCall "io_arg" [TakesInt64] (Returns GivesStr))
  (says "the program's argument at an index, a new string")

||| The value is a string the runtime owns: the next environment operation
||| replaces it.
public export
envGet : Op 1 1 0 0
envGet = platformOp "io.env_get" [single "name" strRead] [result "value" i64] (outside Touched)
  (MkRuntimeCall "io_env_get" [TakesStr] (Returns GivesInt64))
  (says "the value of an environment variable, as a string handle, or null")

public export
envPair : Op 1 1 0 0
envPair = platformOp "io.env_pair" [single "index" i64] [result "pair" i64] (outside Touched)
  (MkRuntimeCall "io_env_pair" [TakesInt64] (Returns GivesInt64))
  (says "the environment's `name=value` at an index, as a string handle, or null past its end")

public export
envSet : Op 3 1 0 0
envSet = platformOp "io.env_set" [single "name" strRead, single "value" strRead, single "overwrite" i64]
  [result "result" i64] (outside Touched)
  (MkRuntimeCall "io_env_set" [TakesStr, TakesStr, TakesInt64] (Returns GivesInt64))
  (says "sets an environment variable, unless it is set and `overwrite` is 0")

public export
envUnset : Op 1 1 0 0
envUnset = platformOp "io.env_unset" [single "name" strRead] [result "result" i64] (outside Touched)
  (MkRuntimeCall "io_env_unset" [TakesStr] (Returns GivesInt64))
  (says "removes an environment variable")

public export
sleep : Op 1 0 0 0
sleep = platformOp "io.sleep" [single "seconds" i64] [] (outside Untouched)
  (MkRuntimeCall "io_sleep" [TakesInt64] NoResult) (says "waits a number of seconds")

public export
usleep : Op 1 0 0 0
usleep = platformOp "io.usleep" [single "microseconds" i64] [] (outside Untouched)
  (MkRuntimeCall "io_usleep" [TakesInt64] NoResult) (says "waits a number of microseconds")

public export
time : Op 0 1 0 0
time = reading "io.time" "io_time" (outside Untouched) (says "the seconds since the epoch")

||| The process's id is fixed for the run.
public export
pid : Op 0 1 0 0
pid = reading "io.pid" "io_pid" computes (says "the process's id")

------------------------------------------------------------------------------
-- The terminal
------------------------------------------------------------------------------

public export
termRaw : Op 0 1 0 0
termRaw = reading "io.term_raw" "io_term_raw" (outside Untouched)
  (says "puts the terminal in raw mode: 0 on success")

public export
termReset : Op 0 0 0 0
termReset = platformOp "io.term_reset" [] [] (outside Untouched)
  (MkRuntimeCall "io_term_reset" [] NoResult)
  (says "puts the terminal back in the mode it had before raw mode")

public export
termCols : Op 0 1 0 0
termCols = reading "io.term_cols" "io_term_cols" (outside Untouched) (says "the terminal's number of columns")

public export
termLines : Op 0 1 0 0
termLines = reading "io.term_lines" "io_term_lines" (outside Untouched) (says "the terminal's number of lines")

------------------------------------------------------------------------------
-- Errors
------------------------------------------------------------------------------

public export
errno : Op 0 1 0 0
errno = reading "io.errno" "io_errno" readsRuntimeState (says "the saved errno of the last failing call")

||| The text of an error number, the C library's, the same at every call: a
||| new string, and no IO.
public export
errorText : Op 1 1 0 0
errorText = MkOp
  { home = InIdr
  , mnemonic = "str.of_errno"
  , ins = [single "code" i64]
  , outs = [result "str" strValue]
  , attrs = []
  , regions = []
  , traits = []
  , interfaces = []
  , effects = builds 0 Untouched
  , speculation = AlwaysSpeculatable
  , stages = Always
  , meaning = CallsRuntime (MkRuntimeCall "io_strerror" [TakesInt64] (Returns GivesStr))
  , verify = DeclarationOnly
  , format = plain 1
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = says "the text of an error number, a new string"
  }

------------------------------------------------------------------------------
-- Clocks
------------------------------------------------------------------------------

||| A reading of one of the clocks that exist, the property `kind`: an
||| OSClock, or -1 where the clock cannot be read. Time moves, and a failure
||| saves errno, so a reading is IO. The runtime's entries are one template
||| instantiated per kind, `idris_rt_io_clock_<kind>`, and the lowering calls
||| the one the op's kind names, so no kind is passed or tested at run time.
public export
clock : Op 0 1 1 0
clock = MkOp
  { home = InIdr
  , mnemonic = "io.clock"
  , ins = []
  , outs = [result "reading" i64]
  , attrs = [property "kind" (EnumProperty (enumDef clockKindClosed))]
  , regions = []
  , traits = []
  , interfaces = []
  , effects = outside Untouched
  , speculation = NotSpeculatable
  , stages = Always
  , meaning = CallsRuntimeByCase (enumDef clockKindClosed) (MkRuntimeCall "io_clock" [] (Returns GivesInt64))
  , verify = DeclarationOnly
  , format = Declared [ValueOf (AttrRef 0), AttrDict]
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = says "a reading of a clock, or -1 where it cannot be read"
  }

------------------------------------------------------------------------------
-- Handles
------------------------------------------------------------------------------

||| Base's getString: the string a string handle holds, with a reference of
||| its own. It reads the handle table, below the guard that the handle
||| holds a string, which crashes where it does not; the result's count is
||| written, nothing acquired.
public export
handleString : Op 1 1 0 0
handleString = MkOp
  { home = InIdr
  , mnemonic = "handle.string"
  , ins = [single "handle" i64]
  , outs = [result "str" strValue]
  , attrs = []
  , regions = []
  , traits = []
  , interfaces = []
  , effects = Executes [OnState Read RuntimeState, OnValues Write Count (Results 0)] [] Covered Untouched
  , speculation = NotSpeculatable
  , stages = Always
  , meaning = CallsRuntime (MkRuntimeCall "handle_string" [TakesInt64] (Returns GivesStr))
  , verify = DeclarationOnly
  , format = plain 1
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = [MkGuard holdsStringOp [0] NotAString]
  , specializations = []
  , laws = []
  , doc = says "the string a string handle holds, with a reference of its own"
  }

||| Base's free of a pointer: a program-owned string handle's string loses
||| its reference; a string the runtime owns stays.
public export
handleFree : Op 1 0 0 0
handleFree = platformOp "io.handle_free" [single "handle" i64] [] (outside Touched)
  (MkRuntimeCall "io_handle_free" [TakesInt64] NoResult) (says "releases a handle's slot")

public export
platformOps : List AnyOp
platformOps =
  [ SomeOp fileOpen, SomeOp fileClose, SomeOp fileError, SomeOp fileErrno, SomeOp fileReadLine
  , SomeOp fileReadChars, SomeOp fileReadChar, SomeOp fileWriteLine, SomeOp fileFlush
  , SomeOp fileSeekLine, SomeOp fileRemove, SomeOp fileSize, SomeOp filePoll, SomeOp fileIsTty
  , SomeOp fileTime, SomeOp handleFileTime, SomeOp fileChmod, SomeOp dirCurrent, SomeOp dirChange
  , SomeOp dirCreate, SomeOp dirRemove, SomeOp dirOpen, SomeOp dirClose, SomeOp dirEntry, SomeOp argCount
  , SomeOp arg, SomeOp envGet, SomeOp envPair, SomeOp envSet, SomeOp envUnset, SomeOp sleep
  , SomeOp usleep, SomeOp time, SomeOp pid, SomeOp termRaw, SomeOp termReset, SomeOp termCols
  , SomeOp termLines, SomeOp errno, SomeOp errorText, SomeOp clock, SomeOp handleString
  , SomeOp handleFree ]
