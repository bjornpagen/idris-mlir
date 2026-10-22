-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Category 1 of the registry: Idris's own
||| backend contract, which the compiler must implement. None of it is
||| privileged knowledge: Idris requires it of every backend.
|||
||| - The entry convention: the root of a program, and the function it runs.
||| - The IO primitives the libraries declare for backends, keyed by their
|||   `%foreign` spec (their Idris name and type are the shape validated).
||| - Idris's builtins (`PrimFn`) are a closed type the frontend matches on
|||   directly (`Frontend.Translate.primitive`), so they have no entries.
module IdrisMLIR.Registry.Primitives

import IdrisMLIR.Spec.Core.Op as Spec
import IdrisMLIR.Spec.Ops.IO
import IdrisMLIR.Spec.Ops.Platform
import IdrisMLIR.Spec.Runtime.Clocks
import IdrisMLIR.Spec.Ops.Strings
import IdrisMLIR.Spec.Ops.Values
import IdrisMLIR.Registry.Entry
import IdrisMLIR.Registry.Name
import IdrisMLIR.Types

%default total

||| The function a program runs: the user's `main`, which the root runs
||| under `unsafePerformIO` (`programRoot`).
export
programEntry : String
programEntry = "main"

||| The code generator a program is compiled by, as `System.Info.codegen`
||| reports it.
export
codegenName : String
codegenName = "mlir"

------------------------------------------------------------------------------
-- Shapes of the IO contract
------------------------------------------------------------------------------

export
world : Shape
world = Prim WorldP

unit : Shape
unit = Head (Def (MkQName ["Builtin"] "Unit")) []

export
ioRes : Shape -> Shape
ioRes a = Head (Def (MkQName ["PrimIO"] "IORes")) [a]

io : Shape -> Shape
io a = Head (Def (MkQName ["PrimIO"] "IO")) [a]

||| The type of an IO primitive: its arguments, each at quantity ω, then the
||| world, and the `IORes` of its result.
ioType : List Shape -> Shape -> Shape
ioType [] r = Pi M1 world (ioRes r)
ioType (a :: as) r = Pi Mw a (ioType as r)

------------------------------------------------------------------------------
-- The table
------------------------------------------------------------------------------

||| `unsafePerformIO : {0 a : Type} -> IO a -> a`: the root of a program is
||| its code, `unsafePerformIO programEntry`, which translateIOProgram
||| writes.
programRoot : AnyEntry
programRoot = entry (Def (MkQName ["PrimIO"] "unsafePerformIO"))
                      (Coerced (Pi M0 TypeOfTypes (Pi Mw (io Hole) Hole)))
                      ProgramRoot

||| An IO primitive of `Prelude.IO`, by its spec, with the name that
||| declares it and its type.
ioPrimitive : {i, o : Nat} -> Spec -> String -> Shape -> IOAction i o -> AnyEntry
ioPrimitive spec name shape a =
  entry (Foreign spec) (Declared (MkQName ["Prelude", "IO"] name) shape) (IOCall a [])

||| The module of the array primitives, which base declares `%extern`: a
||| backend implements them by name.
arrayPrims : List String
arrayPrims = ["Data", "IOArray", "Prims"]

||| `ArrayData a`, the external type of arrays.
export
arrayData : Shape -> Shape
arrayData a = Head (Def (MkQName arrayPrims "ArrayData")) [a]

||| A primitive on the mutable cells of the module `space` declares,
||| `forall a . ... -> PrimIO r`: its element type is erased, and its world
||| is the last argument.
cellPrimitive : List String -> String -> Shape -> ArrayAccess -> AnyEntry
cellPrimitive space name shape a =
  entry (Def (MkQName space name)) (External (Pi M0 TypeOfTypes shape)) (ArrayCall a)

||| An array primitive of base's `Data.IOArray.Prims`.
arrayPrimitive : String -> Shape -> ArrayAccess -> AnyEntry
arrayPrimitive = cellPrimitive arrayPrims

||| The module of base's references, which declares their primitives
||| `%extern`: a backend implements them by name.
iorefModule : List String
iorefModule = ["Data", "IORef"]

||| `Mut a`, the external type of a reference's one cell.
mut : Shape -> Shape
mut a = Head (Def (MkQName iorefModule "Mut")) [a]

export
int : Shape
int = Prim (IntP IdrisInt)

bits8 : Shape
bits8 = Prim (IntP UInt8)

||| The module of base's buffers, whose `Buffer` is an external type.
bufferModule : List String
bufferModule = ["Data", "Buffer"]

buffer : Shape
buffer = Head (Def (MkQName bufferModule "Buffer")) []

||| A buffer's element.
byte : Ty
byte = IntT UInt8

||| `AnyPtr`, a handle of the runtime's: a standard stream, a file, a
||| directory, a file time or a string, or null. A `FilePtr` and a `DirPtr`
||| are one.
export
anyPtr : Shape
anyPtr = Head (Def (MkQName ["PrimIO"] "AnyPtr")) []

||| `Ptr t`, a handle like `AnyPtr`, whose type argument names what it holds.
export
ptr : Shape -> Shape
ptr t = Head (Def (MkQName ["PrimIO"] "Ptr")) [t]

export
str : Shape
str = Prim StringP

||| `Ptr String`, a string handle, or null.
strPtr : Shape
strPtr = ptr str

fileVirtual, fileBuffer, fileReadWrite, fileHandle, fileError, fileMeta, filePermissions, fileProcess : List String
fileVirtual = ["System", "File", "Virtual"]
fileBuffer = ["System", "File", "Buffer"]
fileReadWrite = ["System", "File", "ReadWrite"]
fileHandle = ["System", "File", "Handle"]
fileError = ["System", "File", "Error"]
fileMeta = ["System", "File", "Meta"]
filePermissions = ["System", "File", "Permissions"]
fileProcess = ["System", "File", "Process"]

||| A primitive of base, declared `%foreign` by its C spec, with the name
||| that declares it and its type.
cPrimitive : String -> List String -> String -> Shape -> Hook Contract -> AnyEntry
cPrimitive spec space name shape hook =
  entry (Foreign (MkSpec "C" spec)) (Declared (MkQName space name) shape) hook

||| A primitive of base, declared `%foreign` by its C spec, whose calls are
||| an IO action.
cCall : {i, o : Nat} -> String -> List String -> String -> Shape -> IOAction i o -> AnyEntry
cCall spec space name shape a = cPrimitive spec space name shape (IOCall a [])

export
preludeTypes : List String
preludeTypes = ["Prelude", "Types"]

||| `List a`.
export
list : Shape -> Shape
list a = Head (Def (MkQName ["Prelude", "Basics"] "List")) [a]

||| A buffer primitive, declared `%foreign` by its Chez spec.
bufferPrimitive : {i, o : Nat} -> String -> String -> Shape -> IOAction i o -> AnyEntry
bufferPrimitive spec name shape a =
  entry (Foreign (MkSpec "scheme" spec)) (Declared (MkQName bufferModule name) shape) (IOCall a [])

||| An integer primitive type, as a buffer's load or store names it.
intOf : IntTy -> Shape
intOf t = Prim (IntP t)

||| A double.
dbl : Shape
dbl = Prim DoubleP

||| A value written at a byte offset: buffer, offset, value, world.
stored : Shape -> Shape
stored val = Pi Mw buffer (Pi Mw int (Pi Mw val (Pi M1 world (ioRes unit))))

||| A value read at a byte offset: buffer, offset, world.
loaded : Shape -> Shape
loaded val = Pi Mw buffer (Pi Mw int (Pi M1 world (ioRes val)))

||| A deprecated `%foreign` buffer name. The text names the replacement.
deprecatedForeign : String -> String -> Shape -> String -> AnyEntry
deprecatedForeign spec name shape replacement =
  entry (Foreign (MkSpec "scheme" spec))
          (Retired (MkQName bufferModule name) shape)
          (Deprecated replacement)

||| A deprecated buffer definition written in Idris. The shape is a hole:
||| the refusal does not depend on the type, and validation checks that the
||| library still defines the name.
deprecatedDef : String -> String -> AnyEntry
deprecatedDef name replacement =
  entry (Def (MkQName bufferModule name)) (Ruled Hole) (Deprecated replacement)

||| A machine word written into a buffer, by its Chez spec. The word's type
||| is the stored value's, which the call fixes.
wordStore : String -> String -> Shape -> AnyEntry
wordStore spec name shape = bufferPrimitive spec name shape (Moves StoreWord)

||| A machine word read from a buffer, by its Chez spec. The word's type is
||| the result's, which the call fixes.
wordLoad : String -> String -> Shape -> AnyEntry
wordLoad spec name shape = bufferPrimitive spec name shape (Moves LoadWord)

------------------------------------------------------------------------------
-- Base's surface: files, directories, the process, the terminal, errors,
-- clocks, and the pointers that are handles
------------------------------------------------------------------------------

||| base's System.File. A FilePtr is an AnyPtr, a handle: 0, 1 and 2 are the
||| standard streams, the runtime's own meaning of them, and a file opened is
||| a slot of the runtime's. A file's times are read at once into a
||| file-time handle, and each field read from it. A line or characters read are a string handle,
||| which base frees. `fPoll` declares the C spec of `fileSize`: the declared
||| name picks the entry.
files : List AnyEntry
files =
  [ cPrimitive "idris2_stdin" fileVirtual "prim__stdin" anyPtr (Handle (LInt UInt64 0))
  , cPrimitive "idris2_stdout" fileVirtual "prim__stdout" anyPtr (Handle (LInt UInt64 1))
  , cPrimitive "idris2_stderr" fileVirtual "prim__stderr" anyPtr (Handle (LInt UInt64 2))
  , cCall "idris2_writeBufferData" fileBuffer "prim__writeBufferData"
          (Pi Mw anyPtr (Pi Mw buffer (Pi Mw int (Pi Mw int (Pi M1 world (ioRes int)))))) (Moves WriteBytes)
  , cCall "idris2_readBufferData" fileBuffer "prim__readBufferData"
          (Pi Mw anyPtr (Pi Mw buffer (Pi Mw int (Pi Mw int (Pi M1 world (ioRes int)))))) (Moves ReadBytes)
  , cCall "idris2_eof" fileReadWrite "prim__eof" (Pi Mw anyPtr (Pi M1 world (ioRes int))) (Runs eofOp)
  , cCall "idris2_openFile" fileHandle "prim__open" (ioType [str, str] anyPtr) (Runs fileOpen)
  , cCall "idris2_closeFile" fileHandle "prim__close" (ioType [anyPtr] unit) (Runs fileClose)
  , cCall "idris2_fileError" fileError "prim__error" (ioType [anyPtr] int) (Runs Platform.fileError)
  , cCall "idris2_fileErrno" fileError "prim__fileErrno" (ioType [] int) (Runs fileErrno)
  , cCall "idris2_readLine" fileReadWrite "prim__readLine" (ioType [anyPtr] strPtr) (Runs fileReadLine)
  , cCall "idris2_readChars" fileReadWrite "prim__readChars" (ioType [int, anyPtr] strPtr) (Runs fileReadChars)
  , cCall "fgetc" fileReadWrite "prim__readChar" (ioType [anyPtr] int) (Runs fileReadChar)
  , cCall "idris2_writeLine" fileReadWrite "prim__writeLine" (ioType [anyPtr, str] int) (Runs fileWriteLine)
  , cCall "fflush" fileProcess "prim__flush" (ioType [anyPtr] int) (Runs fileFlush)
  , cCall "idris2_seekLine" fileReadWrite "prim__seekLine" (ioType [anyPtr] int) (Runs fileSeekLine)
  , cCall "idris2_removeFile" fileReadWrite "prim__removeFile" (ioType [str] int) (Runs fileRemove)
  , cCall "idris2_fileSize" fileMeta "prim__fileSize" (ioType [anyPtr] int) (Runs fileSize)
  , cCall "idris2_fileSize" fileMeta "prim__fPoll" (ioType [anyPtr] int) (Runs filePoll)
  , cCall "idris2_fileIsTTY" fileMeta "prim__fileIsTTY" (ioType [anyPtr] int) (Runs fileIsTty)
  , cCall "idris2_fileTime" fileMeta "prim__fileTime" (ioType [anyPtr] anyPtr) (Runs fileTime)
  , cCall "idris2_filetimeAccessTimeSec" fileMeta "prim__filetimeAccessTimeSec" (ioType [anyPtr] int) (ReadsFileTime AccessSeconds)
  , cCall "idris2_filetimeAccessTimeNsec" fileMeta "prim__filetimeAccessTimeNsec" (ioType [anyPtr] int) (ReadsFileTime AccessNanoseconds)
  , cCall "idris2_filetimeModifiedTimeSec" fileMeta "prim__filetimeModifiedTimeSec" (ioType [anyPtr] int) (ReadsFileTime ModifiedSeconds)
  , cCall "idris2_filetimeModifiedTimeNsec" fileMeta "prim__filetimeModifiedTimeNsec" (ioType [anyPtr] int) (ReadsFileTime ModifiedNanoseconds)
  , cCall "idris2_filetimeStatusTimeSec" fileMeta "prim__filetimeStatusTimeSec" (ioType [anyPtr] int) (ReadsFileTime StatusSeconds)
  , cCall "idris2_filetimeStatusTimeNsec" fileMeta "prim__filetimeStatusTimeNsec" (ioType [anyPtr] int) (ReadsFileTime StatusNanoseconds)
  , cCall "idris2_chmod" filePermissions "prim__chmod" (ioType [str, int] int) (Runs fileChmod) ]

directory : List String
directory = ["System", "Directory"]

||| base's System.Directory. A DirPtr is an AnyPtr, a handle. The current
||| directory's path is a string handle base frees; an entry's name is one
||| the runtime keeps until the next entry or the directory's close.
directories : List AnyEntry
directories =
  [ cCall "idris2_currentDirectory" directory "prim__currentDir" (ioType [] strPtr) (Runs dirCurrent)
  , cCall "idris2_changeDir" directory "prim__changeDir" (ioType [str] int) (Runs dirChange)
  , cCall "idris2_createDir" directory "prim__createDir" (ioType [str] int) (Runs dirCreate)
  , cCall "idris2_openDir" directory "prim__openDir" (ioType [str] anyPtr) (Runs dirOpen)
  , cCall "idris2_closeDir" directory "prim__closeDir" (ioType [anyPtr] unit) (Runs dirClose)
  , cCall "idris2_removeDir" directory "prim__removeDir" (ioType [str] unit) (Runs dirRemove)
  , cCall "idris2_nextDirEntry" directory "prim__dirEntry" (ioType [anyPtr] strPtr) (Runs dirEntry) ]

system : List String
system = ["System"]

||| base's System: the arguments, the environment, sleeping, the time, the
||| process's id and its exit. A variable's value and an environment pair
||| are string handles the runtime keeps until the next environment
||| operation; base never frees them.
process : List AnyEntry
process =
  [ cCall "idris2_getArgCount" system "prim__getArgCount" (ioType [] int) (Runs argCount)
  , cCall "idris2_getArg" system "prim__getArg" (ioType [int] str) (Runs arg)
  , cCall "getenv" system "prim__getEnv" (ioType [str] strPtr) (Runs envGet)
  , cCall "idris2_getEnvPair" system "prim__getEnvPair" (ioType [int] strPtr) (Runs envPair)
  , cCall "idris2_setenv" system "prim__setEnv" (ioType [str, str, int] int) (Runs envSet)
  , cCall "idris2_unsetenv" system "prim__unsetEnv" (ioType [str] int) (Runs envUnset)
  , cCall "idris2_sleep" system "prim__sleep" (ioType [int] unit) (Runs sleep)
  , cCall "idris2_usleep" system "prim__usleep" (ioType [int] unit) (Runs usleep)
  , cCall "idris2_time" system "prim__time" (ioType [] int) (Runs time)
  , cCall "idris2_getPID" system "prim__getPID" (ioType [] int) (Runs pid)
  , cCall "exit" system "prim__exit" (ioType [int] unit) Exits ]

||| The terminal: System's raw mode and System.Term's size.
terminal : List AnyEntry
terminal =
  [ cCall "idris2_enableRawMode" system "prim__enableRawMode" (ioType [] int) (Runs termRaw)
  , cCall "idris2_resetRawMode" system "prim__resetRawMode" (ioType [] unit) (Runs termReset)
  , cCall "idris2_setupTerm" term "prim__setupTerm" (ioType [] unit) DoesNothing
  , cCall "idris2_getTermCols" term "prim__getTermCols" (ioType [] int) (Runs termCols)
  , cCall "idris2_getTermLines" term "prim__getTermLines" (ioType [] int) (Runs termLines) ]
  where
    term : List String
    term = ["System", "Term"]

||| base's System.Errno: the saved errno of the last failing call, and an
||| error number's text.
errors : List AnyEntry
errors =
  [ cCall "idris2_getErrno" errnoModule "prim__getErrno" (ioType [] int) (Runs errno)
  , cCall "idris2_strerror" errnoModule "prim__strerror" (ioType [int] str) (Runs errorText) ]
  where
    errnoModule : List String
    errnoModule = ["System", "Errno"]

clockModule : List String
clockModule = ["System", "Clock"]

||| `OSClock`, a clock reading.
osClock : Shape
osClock = Head (Def (MkQName clockModule "OSClock")) []

||| A clock primitive of base's System.Clock, by its Chez spec: a clock
||| declares no C one.
clockPrimitive : {i : Nat} -> String -> String -> Shape -> IOAction i 1 -> AnyEntry
clockPrimitive spec name shape a =
  entry (Foreign (MkSpec "scheme" spec)) (Declared (MkQName clockModule name) shape) (IOCall a [])

||| base's System.Clock. An OSClock is a machine word, a reading or the
||| mark of an unread clock, so a reading allocates nothing, and taking one
||| apart is arithmetic on its encoding. No collector runs, so the two
||| collector clocks read as the mark.
clocks : List AnyEntry
clocks =
  [ entry (Def (MkQName clockModule "OSClock")) (External TypeOfTypes) WordType
  , clockPrimitive "blodwen-clock-time-monotonic" "prim__clockTimeMonotonic" (ioType [] osClock) (ReadsClock Monotonic)
  , clockPrimitive "blodwen-clock-time-utc" "prim__clockTimeUtc" (ioType [] osClock) (ReadsClock Utc)
  , clockPrimitive "blodwen-clock-time-process" "prim__clockTimeProcess" (ioType [] osClock) (ReadsClock Process)
  , clockPrimitive "blodwen-clock-time-thread" "prim__clockTimeThread" (ioType [] osClock) (ReadsClock Thread)
  , clockPrimitive "blodwen-clock-time-gccpu" "prim__clockTimeGcCpu" (ioType [] osClock) NeverRead
  , clockPrimitive "blodwen-clock-time-gcreal" "prim__clockTimeGcReal" (ioType [] osClock) NeverRead
  , clockPrimitive "blodwen-is-time?" "prim__osClockValid" (ioType [osClock] int) (Queries Valid)
  , clockPrimitive "blodwen-clock-second" "prim__osClockSecond" (ioType [osClock] (intOf UInt64)) (Queries Seconds)
  , clockPrimitive "blodwen-clock-nanosecond" "prim__osClockNanosecond"
                   (ioType [osClock] (intOf UInt64)) (Queries Nanoseconds) ]

||| The pointers. `AnyPtr` and `Ptr t` are machine words, which only the
||| runtime's handles inhabit: no address reaches a program, since user code
||| declares no foreign function. So base's pointer operations are handle
||| operations: null is all ones, a string handle's string is read with a
||| reference of its own, and System.FFI's `free` releases a handle's slot.
handles : List AnyEntry
handles =
  [ entry (Def (MkQName ["PrimIO"] "AnyPtr")) (External TypeOfTypes) WordType
  , entry (Def (MkQName ["PrimIO"] "Ptr")) (External (Pi Mw TypeOfTypes TypeOfTypes)) WordType
  , entry (Foreign (MkSpec "C" "idris2_isNull"))
            (Declared (MkQName ["PrimIO"] "prim__nullAnyPtr") (Pi Mw anyPtr int))
            (PrimCall (Compare Values.Eq (SIntegral (SInt UInt64))) [LInt UInt64 18446744073709551615])
  , entry (Foreign (MkSpec "C" "idris2_getNull"))
            (Declared (MkQName ["PrimIO"] "prim__getNullAnyPtr") anyPtr)
            (Handle (LInt UInt64 18446744073709551615))
  , entry (Foreign (MkSpec "C" "idris2_getString"))
            (Declared (MkQName ["Prelude", "IO"] "prim__getString") (Pi Mw strPtr str))
            (PureCall handleString [])
  , cCall "idris2_free" ["System", "FFI"] "prim__free" (ioType [anyPtr] unit) (Runs handleFree) ]

||| The module of the in-house string iterator, whose primitives read a
||| string by byte offset.
export
iteratorModule : List String
iteratorModule = ["Linear", "String", "Iterator"]

||| A pure primitive of the string iterator, declared `%extern` by name: a
||| string, a byte offset, and what the op gives there.
iteratorPrimitive : {i : Nat} -> String -> Shape -> Spec.Op i 1 0 0 -> AnyEntry
iteratorPrimitive name result p =
  entry (Def (MkQName iteratorModule name)) (External (Pi Mw str (Pi Mw int result))) (PureCall p [])

||| The in-house string iterator's primitives. An offset is any Int: each
||| op means something at every one, so its calls have no guard. The step
||| past a character, `scalarBytes`, is a definition with a body, the byte
||| length of the character's own string, which is its meaning on the stock
||| host too; its entry is the faster lowering, the op that gives that
||| length without building the string.
iterators : List AnyEntry
iterators =
  [ iteratorPrimitive "prim__scalarAt" (Prim CharP) strScalarAt
  , iteratorPrimitive "prim__dropBytes" str strDropBytes ]

||| The table: Idris's backend contract as the compiler implements it.
export
primitives : List AnyEntry
primitives =
  [ programRoot
  , ioPrimitive (MkSpec "C" "idris2_putStr") "prim__putStr"
                (Pi Mw (Prim StringP) (Pi M1 world (ioRes unit))) (Runs putStrOp)
  , ioPrimitive (MkSpec "C" "putchar") "prim__putChar"
                (Pi Mw (Prim CharP) (Pi M1 world (ioRes unit))) (Runs putCharOp)
  -- The Prelude's getChar reads one byte.
  , ioPrimitive (MkSpec "C" "getchar") "prim__getChar"
                (Pi M1 world (ioRes (Prim CharP))) (Runs getByteOp)
  -- The Prelude's getLine: a line without its end, "" at the end of input.
  , ioPrimitive (MkSpec "C" "idris2_getStr") "prim__getStr"
                (Pi M1 world (ioRes (Prim StringP))) (Runs getLineOp)
  , entry (Def (MkQName arrayPrims "ArrayData")) (External (Pi Mw TypeOfTypes TypeOfTypes))
            (OrderedArrayType Elements Nothing)
  , arrayPrimitive "prim__newArray"
                   (Pi Mw int (Pi Mw Hole (Pi M1 world (ioRes (arrayData Hole))))) NewArray
  , arrayPrimitive "prim__arrayGet"
                   (Pi Mw (arrayData Hole) (Pi Mw int (Pi M1 world (ioRes Hole)))) GetElement
  , arrayPrimitive "prim__arraySet"
                   (Pi Mw (arrayData Hole) (Pi Mw int (Pi Mw Hole (Pi M1 world (ioRes unit))))) SetElement
  -- An IORef is an array of no dimension: `Mut a` is `memref<E>`, its one
  -- element the value, made, read and written through the world as an
  -- array's elements are, with no size and no index. Control.Monad.ST's
  -- references are IORefs, run by base's unsafePerformIO.
  , entry (Def (MkQName iorefModule "Mut")) (External (Pi Mw TypeOfTypes TypeOfTypes))
            (OrderedArrayType Cell Nothing)
  , cellPrimitive iorefModule "prim__newIORef" (Pi Mw Hole (Pi M1 world (ioRes (mut Hole)))) NewArray
  , cellPrimitive iorefModule "prim__readIORef" (Pi Mw (mut Hole) (Pi M1 world (ioRes Hole))) GetElement
  , cellPrimitive iorefModule "prim__writeIORef"
                  (Pi Mw (mut Hole) (Pi Mw Hole (Pi M1 world (ioRes unit)))) SetElement
  -- base's Data.Buffer is an array of bytes. A new one is a new array, of
  -- zero bytes: the fill is the zero byte, which base's call does not
  -- pass. Its size is the array's length. A byte is that element
  -- (setBits8, getBits8). A wider value is the target's own load or store
  -- of those bytes, so the endianness is the machine's. setByte, getByte
  -- and bufferData are deprecated names: a program that calls one is
  -- rejected, and the message names the replacement. They share Chez's
  -- byte spec with the Bits8 operations; the declared name picks the entry.
  , entry (Def (MkQName bufferModule "Buffer")) (External TypeOfTypes) (OrderedArrayType Elements (Just byte))
  , entry (Foreign (MkSpec "scheme" "blodwen-new-buffer"))
            (Declared (MkQName bufferModule "prim__newBuffer") (Pi Mw int (Pi M1 world (ioRes buffer))))
            (IOCall (Accesses NewArray 1) [LInt UInt8 0])
  , deprecatedForeign "blodwen-buffer-setbyte" "prim__setByte"
                      (Pi Mw buffer (Pi Mw int (Pi Mw int (Pi M1 world (ioRes unit)))))
                      "setByte is deprecated; use setBits8"
  , deprecatedDef "setByte" "setByte is deprecated; use setBits8"
  , bufferPrimitive "blodwen-buffer-setbyte" "prim__setBits8"
                    (Pi Mw buffer (Pi Mw int (Pi Mw bits8 (Pi M1 world (ioRes unit))))) (Accesses SetElement 1)
  , deprecatedForeign "blodwen-buffer-getbyte" "prim__getByte"
                      (Pi Mw buffer (Pi Mw int (Pi M1 world (ioRes int))))
                      "getByte is deprecated; use getBits8"
  , deprecatedDef "getByte" "getByte is deprecated; use getBits8"
  , bufferPrimitive "blodwen-buffer-getbyte" "prim__getBits8"
                    (Pi Mw buffer (Pi Mw int (Pi M1 world (ioRes bits8)))) (Accesses GetElement 1)
  , entry (Foreign (MkSpec "scheme" "blodwen-buffer-size"))
            (Declared (MkQName bufferModule "prim__bufferSize") (Pi Mw buffer int))
            (PrimCall (ArrayLength byte) [])
  , wordStore "blodwen-buffer-setbits16" "prim__setBits16" (stored (intOf UInt16))
  , wordLoad "blodwen-buffer-getbits16" "prim__getBits16" (loaded (intOf UInt16))
  , wordStore "blodwen-buffer-setbits32" "prim__setBits32" (stored (intOf UInt32))
  , wordLoad "blodwen-buffer-getbits32" "prim__getBits32" (loaded (intOf UInt32))
  , wordStore "blodwen-buffer-setbits64" "prim__setBits64" (stored (intOf UInt64))
  , wordLoad "blodwen-buffer-getbits64" "prim__getBits64" (loaded (intOf UInt64))
  , wordStore "blodwen-buffer-setint8" "prim__setInt8" (stored (intOf SInt8))
  , wordLoad "blodwen-buffer-getint8" "prim__getInt8" (loaded (intOf SInt8))
  , wordStore "blodwen-buffer-setint16" "prim__setInt16" (stored (intOf SInt16))
  , wordLoad "blodwen-buffer-getint16" "prim__getInt16" (loaded (intOf SInt16))
  , wordStore "blodwen-buffer-setint32" "prim__setInt32" (stored (intOf SInt32))
  , wordLoad "blodwen-buffer-getint32" "prim__getInt32" (loaded (intOf SInt32))
  , wordStore "blodwen-buffer-setint64" "prim__setInt64" (stored (intOf SInt64))
  , wordLoad "blodwen-buffer-getint64" "prim__getInt64" (loaded (intOf SInt64))
  , wordStore "blodwen-buffer-setint" "prim__setInt" (stored int)
  , wordLoad "blodwen-buffer-getint" "prim__getInt" (loaded int)
  , wordStore "blodwen-buffer-setdouble" "prim__setDouble" (stored dbl)
  , wordLoad "blodwen-buffer-getdouble" "prim__getDouble" (loaded dbl)
  , entry (Foreign (MkSpec "scheme" "blodwen-stringbytelen"))
            (Declared (MkQName bufferModule "stringByteLength") (Pi Mw (Prim StringP) int))
            (PureCall strBytesLength [])
  , bufferPrimitive "blodwen-buffer-setstring" "prim__setString"
                    (Pi Mw buffer (Pi Mw int (Pi Mw (Prim StringP) (Pi M1 world (ioRes unit)))))
                    (Moves SetString)
  , bufferPrimitive "blodwen-buffer-getstring" "prim__getString"
                    (Pi Mw buffer (Pi Mw int (Pi Mw int (Pi M1 world (ioRes (Prim StringP))))))
                    (Moves GetString)
  , bufferPrimitive "blodwen-buffer-copydata" "prim__copyData"
                    (Pi Mw buffer (Pi Mw int (Pi Mw int (Pi Mw buffer (Pi Mw int (Pi M1 world (ioRes unit)))))))
                    (Moves CopyBytes)
  , deprecatedDef "bufferData" "bufferData is deprecated; use bufferData'"
  -- Strings built from lists. The Prelude's pack is strCons by strCons, a
  -- string per character, and its own %transform runs fastPack in its
  -- place at runtime, as fastConcat for concat over a list of strings and
  -- fastUnpack for unpack: the stock backends build the string once. The
  -- one meaning of pack and fastPack is the string of the list's
  -- characters, of fastConcat the concatenation, each built once
  -- (idr.str.pack, idr.str.concat); fastUnpack stands for unpack, a loop
  -- already.
  , entry (Foreign (MkSpec "scheme" "string-pack"))
            (Declared (MkQName preludeTypes "fastPack") (Pi Mw (list (Prim CharP)) (Prim StringP)))
            (Builds strPack)
  , entry (Foreign (MkSpec "scheme" "string-concat"))
            (Declared (MkQName preludeTypes "fastConcat") (Pi Mw (list (Prim StringP)) (Prim StringP)))
            (Builds strConcat)
  , entry (Foreign (MkSpec "scheme" "string-unpack"))
            (Declared (MkQName preludeTypes "fastUnpack") (Pi Mw (Prim StringP) (list (Prim CharP))))
            (Alias (MkQName preludeTypes "unpack"))
  -- System.Info. The operating system and the backend name are strings the
  -- compiler substitutes: the first is the target triple's, the second the
  -- name this backend is registered under. The processor count is read when
  -- the program asks. The C spec names that one operation; a C spec the
  -- registry does not list stays rejected.
  , entry (Def (MkQName ["System", "Info"] "prim__os"))
            (External (Prim StringP)) (SystemInfo TargetOs)
  , entry (Def (MkQName ["System", "Info"] "prim__codegen"))
            (External (Prim StringP)) (SystemInfo BackendName)
  , entry (Foreign (MkSpec "C" "idris2_getNProcessors"))
            (Declared (MkQName ["System", "Info"] "prim__getNProcessors")
                      (Pi M1 world (ioRes int)))
            (IOCall (Runs nProcessorsOp) []) ] ++
  files ++ directories ++ process ++ terminal ++ errors ++ clocks ++ handles ++ iterators
