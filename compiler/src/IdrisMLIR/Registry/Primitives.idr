||| Category 1 of the registry: Idris's own
||| backend contract, which the compiler must implement. None of it is
||| privileged knowledge: Idris requires it of every backend.
|||
||| - The entry convention: the root of a program, and its main module.
||| - The IO primitives the libraries declare for backends, keyed by their
|||   `%foreign` spec (their Idris name and type are the shape validated).
||| - Idris's builtins (`PrimFn`) are a closed type the frontend matches on
|||   directly (`Frontend.Translate.primitive`), so they have no entries.
module IdrisMLIR.Registry.Primitives

import IdrisMLIR.Dialect.Idr
import IdrisMLIR.Registry.Entry
import IdrisMLIR.Registry.Name
import IdrisMLIR.Rule
import IdrisMLIR.Types

%default total

||| The module Idris takes `main` from when none is named.
export
mainModule : List String
mainModule = ["Main"]

||| The name this backend is registered under, which `System.Info.codegen`
||| reports.
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
ioType [] r = Pi Q1 world (ioRes r)
ioType (a :: as) r = Pi QW a (ioType as r)

------------------------------------------------------------------------------
-- The table
------------------------------------------------------------------------------

||| `unsafePerformIO : {0 a : Type} -> IO a -> a`: Idris hands an IO backend
||| `unsafePerformIO main`.
programRoot : Entry
programRoot = MkEntry (Def (MkQName ["PrimIO"] "unsafePerformIO"))
                      (Typed (Pi Q0 TypeOfTypes (Pi QW (io Hole) Hole)))
                      ProgramRoot [ProgramShape]

||| An IO primitive of `Prelude.IO`, by its spec, with the name that
||| declares it and its type.
ioPrimitive : Spec -> String -> Shape -> IdrPrim -> Entry
ioPrimitive spec name shape p =
  MkEntry (Foreign spec) (Declared (MkQName ["Prelude", "IO"] name) shape) (IOCall p []) [IOPrimitive]

||| The module of the array primitives, which base declares `%extern`: a
||| backend implements them by name.
arrayPrims : List String
arrayPrims = ["Data", "IOArray", "Prims"]

||| `ArrayData a`, the external type of arrays.
export
arrayData : Shape -> Shape
arrayData a = Head (Def (MkQName arrayPrims "ArrayData")) [a]

||| An array primitive, `forall a . ... -> PrimIO r`: its element type is
||| erased, and its world is the last argument.
arrayPrimitive : String -> Shape -> IdrPrim -> Entry
arrayPrimitive name shape p =
  MkEntry (Def (MkQName arrayPrims name)) (Typed (Pi Q0 TypeOfTypes shape)) (ArrayCall p) [IOPrimitive]

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
cPrimitive : String -> List String -> String -> Shape -> Hook -> Entry
cPrimitive spec space name shape hook =
  MkEntry (Foreign (MkSpec "C" spec)) (Declared (MkQName space name) shape) hook [IOPrimitive]

||| A primitive of base, declared `%foreign` by its C spec, whose calls are
||| the op of an IO primitive.
cCall : String -> List String -> String -> Shape -> IdrPrim -> Entry
cCall spec space name shape p = cPrimitive spec space name shape (IOCall p [])

preludeTypes : List String
preludeTypes = ["Prelude", "Types"]

||| `List a`.
list : Shape -> Shape
list a = Head (Def (MkQName ["Prelude", "Basics"] "List")) [a]

||| A buffer primitive, declared `%foreign` by its Chez spec.
bufferPrimitive : String -> String -> Shape -> IdrPrim -> Entry
bufferPrimitive spec name shape p =
  MkEntry (Foreign (MkSpec "scheme" spec)) (Declared (MkQName bufferModule name) shape) (IOCall p []) [IOPrimitive]

||| An integer primitive type, as a buffer's load or store names it.
intOf : IntTy -> Shape
intOf t = Prim (IntP t)

||| A double.
dbl : Shape
dbl = Prim DoubleP

||| A value written at a byte offset: buffer, offset, value, world.
stored : Shape -> Shape
stored val = Pi QW buffer (Pi QW int (Pi QW val (Pi Q1 world (ioRes unit))))

||| A value read at a byte offset: buffer, offset, world.
loaded : Shape -> Shape
loaded val = Pi QW buffer (Pi QW int (Pi Q1 world (ioRes val)))

||| A deprecated `%foreign` buffer name. The text names the replacement.
deprecatedForeign : String -> String -> Shape -> String -> Entry
deprecatedForeign spec name shape replacement =
  MkEntry (Foreign (MkSpec "scheme" spec))
          (Declared (MkQName bufferModule name) shape)
          (Deprecated replacement) [Deprecated]

||| A deprecated buffer definition written in Idris. The shape is a hole:
||| the refusal does not depend on the type, and validation checks that the
||| library still defines the name.
deprecatedDef : String -> String -> Entry
deprecatedDef name replacement =
  MkEntry (Def (MkQName bufferModule name)) (Typed Hole) (Deprecated replacement) [Deprecated]

||| A machine word written into a buffer, by its Chez spec. The word's type
||| is the stored value's, which the call fixes.
bufferStore : String -> String -> Shape -> Entry
bufferStore spec name shape = bufferPrimitive spec name shape BufferStore

||| A machine word read from a buffer, by its Chez spec. The word's type is
||| the result's, which the call fixes.
bufferLoad : String -> String -> Shape -> Entry
bufferLoad spec name shape = bufferPrimitive spec name shape BufferLoad

------------------------------------------------------------------------------
-- Base's surface: files, directories, the process, the terminal, errors,
-- clocks, and the pointers that are handles
------------------------------------------------------------------------------

||| `FileTimePtr`, the handle of a file's times. It is an `AnyPtr`, but base
||| keeps the name private, so a checked type shows the name.
fileTimePtr : Shape
fileTimePtr = Head (Def (MkQName fileMeta "FileTimePtr")) []

||| base's System.File. A FilePtr is an AnyPtr, a handle: 0, 1 and 2 are the
||| standard streams, the runtime's own meaning of them, and a file opened is
||| a slot of the runtime's. A line or characters read are a string handle,
||| which base frees. `fPoll` declares the C spec of `fileSize`: the declared
||| name picks the entry.
files : List Entry
files =
  [ cPrimitive "idris2_stdin" fileVirtual "prim__stdin" anyPtr (Handle (LInt UInt64 0))
  , cPrimitive "idris2_stdout" fileVirtual "prim__stdout" anyPtr (Handle (LInt UInt64 1))
  , cPrimitive "idris2_stderr" fileVirtual "prim__stderr" anyPtr (Handle (LInt UInt64 2))
  , cCall "idris2_writeBufferData" fileBuffer "prim__writeBufferData"
          (Pi QW anyPtr (Pi QW buffer (Pi QW int (Pi QW int (Pi Q1 world (ioRes int)))))) WriteBytes
  , cCall "idris2_readBufferData" fileBuffer "prim__readBufferData"
          (Pi QW anyPtr (Pi QW buffer (Pi QW int (Pi QW int (Pi Q1 world (ioRes int)))))) ReadBytes
  , cCall "idris2_eof" fileReadWrite "prim__eof" (Pi QW anyPtr (Pi Q1 world (ioRes int))) Eof
  , cCall "idris2_openFile" fileHandle "prim__open" (ioType [str, str] anyPtr) FileOpen
  , cCall "idris2_closeFile" fileHandle "prim__close" (ioType [anyPtr] unit) FileClose
  , cCall "idris2_fileError" fileError "prim__error" (ioType [anyPtr] int) FileError
  , cCall "idris2_fileErrno" fileError "prim__fileErrno" (ioType [] int) FileErrno
  , cCall "idris2_readLine" fileReadWrite "prim__readLine" (ioType [anyPtr] strPtr) FileReadLine
  , cCall "idris2_readChars" fileReadWrite "prim__readChars" (ioType [int, anyPtr] strPtr) FileReadChars
  , cCall "fgetc" fileReadWrite "prim__readChar" (ioType [anyPtr] int) FileReadChar
  , cCall "idris2_writeLine" fileReadWrite "prim__writeLine" (ioType [anyPtr, str] int) FileWriteLine
  , cCall "fflush" fileProcess "prim__flush" (ioType [anyPtr] int) FileFlush
  , cCall "idris2_seekLine" fileReadWrite "prim__seekLine" (ioType [anyPtr] int) FileSeekLine
  , cCall "idris2_removeFile" fileReadWrite "prim__removeFile" (ioType [str] int) FileRemove
  , cCall "idris2_fileSize" fileMeta "prim__fileSize" (ioType [anyPtr] int) FileSize
  , cCall "idris2_fileSize" fileMeta "prim__fPoll" (ioType [anyPtr] int) FilePoll
  , cCall "idris2_fileIsTTY" fileMeta "prim__fileIsTTY" (ioType [anyPtr] int) FileIsTty
  , cCall "idris2_fileTime" fileMeta "prim__fileTime" (ioType [anyPtr] fileTimePtr) FileTime
  , cCall "idris2_filetimeAccessTimeSec" fileMeta "prim__filetimeAccessTimeSec"
          (ioType [fileTimePtr] int) FileAtimeSec
  , cCall "idris2_filetimeAccessTimeNsec" fileMeta "prim__filetimeAccessTimeNsec"
          (ioType [fileTimePtr] int) FileAtimeNsec
  , cCall "idris2_filetimeModifiedTimeSec" fileMeta "prim__filetimeModifiedTimeSec"
          (ioType [fileTimePtr] int) FileMtimeSec
  , cCall "idris2_filetimeModifiedTimeNsec" fileMeta "prim__filetimeModifiedTimeNsec"
          (ioType [fileTimePtr] int) FileMtimeNsec
  , cCall "idris2_filetimeStatusTimeSec" fileMeta "prim__filetimeStatusTimeSec"
          (ioType [fileTimePtr] int) FileCtimeSec
  , cCall "idris2_filetimeStatusTimeNsec" fileMeta "prim__filetimeStatusTimeNsec"
          (ioType [fileTimePtr] int) FileCtimeNsec
  , cCall "idris2_chmod" filePermissions "prim__chmod" (ioType [str, int] int) FileChmod ]

directory : List String
directory = ["System", "Directory"]

||| base's System.Directory. A DirPtr is an AnyPtr, a handle. The current
||| directory's path is a string handle base frees; an entry's name is one
||| the runtime keeps until the next entry or the directory's close.
directories : List Entry
directories =
  [ cCall "idris2_currentDirectory" directory "prim__currentDir" (ioType [] strPtr) DirCurrent
  , cCall "idris2_changeDir" directory "prim__changeDir" (ioType [str] int) DirChange
  , cCall "idris2_createDir" directory "prim__createDir" (ioType [str] int) DirCreate
  , cCall "idris2_openDir" directory "prim__openDir" (ioType [str] anyPtr) DirOpen
  , cCall "idris2_closeDir" directory "prim__closeDir" (ioType [anyPtr] unit) DirClose
  , cCall "idris2_removeDir" directory "prim__removeDir" (ioType [str] unit) DirRemove
  , cCall "idris2_nextDirEntry" directory "prim__dirEntry" (ioType [anyPtr] strPtr) DirEntry ]

system : List String
system = ["System"]

||| base's System: the arguments, the environment, sleeping, the time, the
||| process's id and its exit. A variable's value and an environment pair
||| are string handles the runtime keeps until the next environment
||| operation; base never frees them.
process : List Entry
process =
  [ cCall "idris2_getArgCount" system "prim__getArgCount" (ioType [] int) ArgCount
  , cCall "idris2_getArg" system "prim__getArg" (ioType [int] str) Arg
  , cCall "getenv" system "prim__getEnv" (ioType [str] strPtr) EnvGet
  , cCall "idris2_getEnvPair" system "prim__getEnvPair" (ioType [int] strPtr) EnvPair
  , cCall "idris2_setenv" system "prim__setEnv" (ioType [str, str, int] int) EnvSet
  , cCall "idris2_unsetenv" system "prim__unsetEnv" (ioType [str] int) EnvUnset
  , cCall "idris2_sleep" system "prim__sleep" (ioType [int] unit) Sleep
  , cCall "idris2_usleep" system "prim__usleep" (ioType [int] unit) Usleep
  , cCall "idris2_time" system "prim__time" (ioType [] int) Time
  , cCall "idris2_getPID" system "prim__getPID" (ioType [] int) Pid
  , cCall "exit" system "prim__exit" (ioType [int] unit) Exit ]

||| The terminal: System's raw mode and System.Term's size.
terminal : List Entry
terminal =
  [ cCall "idris2_enableRawMode" system "prim__enableRawMode" (ioType [] int) TermRaw
  , cCall "idris2_resetRawMode" system "prim__resetRawMode" (ioType [] unit) TermReset
  , cCall "idris2_setupTerm" term "prim__setupTerm" (ioType [] unit) TermSetup
  , cCall "idris2_getTermCols" term "prim__getTermCols" (ioType [] int) TermCols
  , cCall "idris2_getTermLines" term "prim__getTermLines" (ioType [] int) TermLines ]
  where
    term : List String
    term = ["System", "Term"]

||| base's System.Errno: the saved errno of the last failing call, and an
||| error number's text.
errors : List Entry
errors =
  [ cCall "idris2_getErrno" errno "prim__getErrno" (ioType [] int) Errno
  , cCall "idris2_strerror" errno "prim__strerror" (ioType [int] str) Strerror ]
  where
    errno : List String
    errno = ["System", "Errno"]

clockModule : List String
clockModule = ["System", "Clock"]

||| `OSClock`, a clock reading.
osClock : Shape
osClock = Head (Def (MkQName clockModule "OSClock")) []

||| A clock primitive of base's System.Clock, by its Chez spec: a clock
||| declares no C one.
clockPrimitive : String -> String -> Shape -> IdrPrim -> Entry
clockPrimitive spec name shape p =
  MkEntry (Foreign (MkSpec "scheme" spec)) (Declared (MkQName clockModule name) shape) (IOCall p []) [IOPrimitive]

||| base's System.Clock. An OSClock is a machine word, a reading or the
||| invalid one, so a reading allocates nothing. No collector runs, so the
||| two collector clocks are never valid.
clocks : List Entry
clocks =
  [ MkEntry (Def (MkQName clockModule "OSClock")) (Typed TypeOfTypes) WordType [IOPrimitive]
  , clockPrimitive "blodwen-clock-time-monotonic" "prim__clockTimeMonotonic" (ioType [] osClock) ClockMonotonic
  , clockPrimitive "blodwen-clock-time-utc" "prim__clockTimeUtc" (ioType [] osClock) ClockUtc
  , clockPrimitive "blodwen-clock-time-process" "prim__clockTimeProcess" (ioType [] osClock) ClockProcess
  , clockPrimitive "blodwen-clock-time-thread" "prim__clockTimeThread" (ioType [] osClock) ClockThread
  , clockPrimitive "blodwen-clock-time-gccpu" "prim__clockTimeGcCpu" (ioType [] osClock) ClockGcCpu
  , clockPrimitive "blodwen-clock-time-gcreal" "prim__clockTimeGcReal" (ioType [] osClock) ClockGcReal
  , clockPrimitive "blodwen-is-time?" "prim__osClockValid" (ioType [osClock] int) ClockValid
  , clockPrimitive "blodwen-clock-second" "prim__osClockSecond" (ioType [osClock] (intOf UInt64)) ClockSecond
  , clockPrimitive "blodwen-clock-nanosecond" "prim__osClockNanosecond"
                   (ioType [osClock] (intOf UInt64)) ClockNanosecond ]

||| The pointers. `AnyPtr` and `Ptr t` are machine words, which only the
||| runtime's handles inhabit: no address reaches a program, since user code
||| declares no foreign function. So base's pointer operations are handle
||| operations: null is all ones, a string handle's string is read with a
||| reference of its own, and System.FFI's `free` releases a handle's slot.
handles : List Entry
handles =
  [ MkEntry (Def (MkQName ["PrimIO"] "AnyPtr")) (Typed TypeOfTypes) WordType [IOPrimitive]
  , MkEntry (Def (MkQName ["PrimIO"] "Ptr")) (Typed (Pi QW TypeOfTypes TypeOfTypes)) WordType [IOPrimitive]
  , MkEntry (Foreign (MkSpec "C" "idris2_isNull"))
            (Declared (MkQName ["PrimIO"] "prim__nullAnyPtr") (Pi QW anyPtr int))
            (IOCall HandleIsNull []) [Primitive]
  , MkEntry (Foreign (MkSpec "C" "idris2_getNull"))
            (Declared (MkQName ["PrimIO"] "prim__getNullAnyPtr") anyPtr)
            (Handle (LInt UInt64 18446744073709551615)) [Primitive]
  , MkEntry (Foreign (MkSpec "C" "idris2_getString"))
            (Declared (MkQName ["Prelude", "IO"] "prim__getString") (Pi QW strPtr str))
            (IOCall HandleString []) [Primitive]
  , cCall "idris2_free" ["System", "FFI"] "prim__free" (ioType [anyPtr] unit) HandleFree ]

||| The module of the in-house string iterator, whose primitives read a
||| string by byte offset.
iteratorModule : List String
iteratorModule = ["Linear", "String", "Iterator"]

||| A pure primitive of the string iterator, declared `%extern` by name: a
||| string, a byte offset, and what the op gives there.
iteratorPrimitive : String -> Shape -> IdrPrim -> Entry
iteratorPrimitive name result p =
  MkEntry (Def (MkQName iteratorModule name)) (Typed (Pi QW str (Pi QW int result))) (IOCall p []) [Primitive]

||| The in-house string iterator's primitives. An offset is any Int: each
||| op means something at every one, so its calls have no guard.
iterators : List Entry
iterators =
  [ iteratorPrimitive "prim__scalarAt" (Prim CharP) StrScalarAt
  , iteratorPrimitive "prim__scalarEnd" int StrScalarEnd
  , iteratorPrimitive "prim__dropBytes" str StrDropBytes ]

||| The table: Idris's backend contract as the compiler implements it.
export
primitives : List Entry
primitives =
  [ programRoot
  , ioPrimitive (MkSpec "C" "idris2_putStr") "prim__putStr"
                (Pi QW (Prim StringP) (Pi Q1 world (ioRes unit))) PutStr
  , ioPrimitive (MkSpec "C" "putchar") "prim__putChar"
                (Pi QW (Prim CharP) (Pi Q1 world (ioRes unit))) PutChar
  -- The Prelude's getChar reads one byte.
  , ioPrimitive (MkSpec "C" "getchar") "prim__getChar"
                (Pi Q1 world (ioRes (Prim CharP))) GetByte
  -- The Prelude's getLine: a line without its end, "" at the end of input.
  , ioPrimitive (MkSpec "C" "idris2_getStr") "prim__getStr"
                (Pi Q1 world (ioRes (Prim StringP))) GetLine
  , MkEntry (Def (MkQName arrayPrims "ArrayData")) (Typed (Pi QW TypeOfTypes TypeOfTypes))
            (ArrayType Nothing) [IOPrimitive]
  , arrayPrimitive "prim__newArray"
                   (Pi QW int (Pi QW Hole (Pi Q1 world (ioRes (arrayData Hole))))) ArrayNew
  , arrayPrimitive "prim__arrayGet"
                   (Pi QW (arrayData Hole) (Pi QW int (Pi Q1 world (ioRes Hole)))) ArrayGet
  , arrayPrimitive "prim__arraySet"
                   (Pi QW (arrayData Hole) (Pi QW int (Pi QW Hole (Pi Q1 world (ioRes unit))))) ArraySet
  -- The length of an array, which the backend contract lacks: the in-house
  -- linear array library declares it by Chez's spec, `vector-length` of the
  -- vector `ArrayData` is there (after the erased type argument Chez passes
  -- a Scheme foreign function), and the compiler gives that spec its one
  -- meaning, the memref's dimension.
  , MkEntry (Foreign (MkSpec "scheme" "(lambda (ty v) (vector-length v))"))
            (Declared (MkQName ["Linear", "Array"] "prim__arraySize")
                      (Pi Q0 TypeOfTypes (Pi QW (arrayData Hole) int)))
            (ArraySize Nothing) [Primitive]
  -- base's Data.Buffer is an array of bytes. A new one is a new array, of
  -- zero bytes: the fill is the zero byte, which base's call does not
  -- pass. Its size is the array's length. A byte is that element
  -- (setBits8, getBits8). A wider value is the target's own load or store
  -- of those bytes, so the endianness is the machine's. setByte, getByte
  -- and bufferData are deprecated names: a program that calls one is
  -- rejected, and the message names the replacement. They share Chez's
  -- byte spec with the Bits8 operations; the declared name picks the entry.
  , MkEntry (Def (MkQName bufferModule "Buffer")) (Typed TypeOfTypes) (ArrayType (Just byte)) [IOPrimitive]
  , MkEntry (Foreign (MkSpec "scheme" "blodwen-new-buffer"))
            (Declared (MkQName bufferModule "prim__newBuffer") (Pi QW int (Pi Q1 world (ioRes buffer))))
            (IOCall ArrayNew [LInt UInt8 0]) [IOPrimitive]
  , deprecatedForeign "blodwen-buffer-setbyte" "prim__setByte"
                      (Pi QW buffer (Pi QW int (Pi QW int (Pi Q1 world (ioRes unit)))))
                      "setByte is deprecated; use setBits8"
  , deprecatedDef "setByte" "setByte is deprecated; use setBits8"
  , bufferPrimitive "blodwen-buffer-setbyte" "prim__setBits8"
                    (Pi QW buffer (Pi QW int (Pi QW bits8 (Pi Q1 world (ioRes unit))))) ArraySet
  , deprecatedForeign "blodwen-buffer-getbyte" "prim__getByte"
                      (Pi QW buffer (Pi QW int (Pi Q1 world (ioRes int))))
                      "getByte is deprecated; use getBits8"
  , deprecatedDef "getByte" "getByte is deprecated; use getBits8"
  , bufferPrimitive "blodwen-buffer-getbyte" "prim__getBits8"
                    (Pi QW buffer (Pi QW int (Pi Q1 world (ioRes bits8)))) ArrayGet
  , MkEntry (Foreign (MkSpec "scheme" "blodwen-buffer-size"))
            (Declared (MkQName bufferModule "prim__bufferSize") (Pi QW buffer int))
            (ArraySize (Just byte)) [Primitive]
  , bufferStore "blodwen-buffer-setbits16" "prim__setBits16" (stored (intOf UInt16))
  , bufferLoad "blodwen-buffer-getbits16" "prim__getBits16" (loaded (intOf UInt16))
  , bufferStore "blodwen-buffer-setbits32" "prim__setBits32" (stored (intOf UInt32))
  , bufferLoad "blodwen-buffer-getbits32" "prim__getBits32" (loaded (intOf UInt32))
  , bufferStore "blodwen-buffer-setbits64" "prim__setBits64" (stored (intOf UInt64))
  , bufferLoad "blodwen-buffer-getbits64" "prim__getBits64" (loaded (intOf UInt64))
  , bufferStore "blodwen-buffer-setint8" "prim__setInt8" (stored (intOf SInt8))
  , bufferLoad "blodwen-buffer-getint8" "prim__getInt8" (loaded (intOf SInt8))
  , bufferStore "blodwen-buffer-setint16" "prim__setInt16" (stored (intOf SInt16))
  , bufferLoad "blodwen-buffer-getint16" "prim__getInt16" (loaded (intOf SInt16))
  , bufferStore "blodwen-buffer-setint32" "prim__setInt32" (stored (intOf SInt32))
  , bufferLoad "blodwen-buffer-getint32" "prim__getInt32" (loaded (intOf SInt32))
  , bufferStore "blodwen-buffer-setint64" "prim__setInt64" (stored (intOf SInt64))
  , bufferLoad "blodwen-buffer-getint64" "prim__getInt64" (loaded (intOf SInt64))
  , bufferStore "blodwen-buffer-setint" "prim__setInt" (stored int)
  , bufferLoad "blodwen-buffer-getint" "prim__getInt" (loaded int)
  , bufferStore "blodwen-buffer-setdouble" "prim__setDouble" (stored dbl)
  , bufferLoad "blodwen-buffer-getdouble" "prim__getDouble" (loaded dbl)
  , MkEntry (Foreign (MkSpec "scheme" "blodwen-stringbytelen"))
            (Declared (MkQName bufferModule "stringByteLength") (Pi QW (Prim StringP) int))
            (IOCall StrBytesLength []) [Primitive]
  , bufferPrimitive "blodwen-buffer-setstring" "prim__setString"
                    (Pi QW buffer (Pi QW int (Pi QW (Prim StringP) (Pi Q1 world (ioRes unit)))))
                    BufferSetString
  , bufferPrimitive "blodwen-buffer-getstring" "prim__getString"
                    (Pi QW buffer (Pi QW int (Pi QW int (Pi Q1 world (ioRes (Prim StringP))))))
                    BufferGetString
  , bufferPrimitive "blodwen-buffer-copydata" "prim__copyData"
                    (Pi QW buffer (Pi QW int (Pi QW int (Pi QW buffer (Pi QW int (Pi Q1 world (ioRes unit)))))))
                    BufferCopy
  , deprecatedDef "bufferData" "bufferData is deprecated; use bufferData'"
  -- Strings built from lists. The Prelude's pack is strCons by strCons, a
  -- string per character, and its own %transform runs fastPack in its
  -- place at runtime, as fastConcat for concat over a list of strings and
  -- fastUnpack for unpack: the stock backends build the string once. The
  -- one meaning of pack and fastPack is the string of the list's
  -- characters, of fastConcat the concatenation, each built once
  -- (idr.str.pack, idr.str.concat); fastUnpack stands for unpack, a loop
  -- already.
  , MkEntry (Def (MkQName preludeTypes "pack"))
            (Typed (Pi QW (list (Prim CharP)) (Prim StringP))) (Builds StrPack) [Primitive]
  , MkEntry (Foreign (MkSpec "scheme" "string-pack"))
            (Declared (MkQName preludeTypes "fastPack") (Pi QW (list (Prim CharP)) (Prim StringP)))
            (Builds StrPack) [Primitive]
  , MkEntry (Foreign (MkSpec "scheme" "string-concat"))
            (Declared (MkQName preludeTypes "fastConcat") (Pi QW (list (Prim StringP)) (Prim StringP)))
            (Builds StrConcat) [Primitive]
  , MkEntry (Foreign (MkSpec "scheme" "string-unpack"))
            (Declared (MkQName preludeTypes "fastUnpack") (Pi QW (Prim StringP) (list (Prim CharP))))
            (Alias (MkQName preludeTypes "unpack")) [Primitive]
  -- System.Info. The operating system and the backend name are strings the
  -- compiler substitutes: the first is the target triple's, the second the
  -- name this backend is registered under. The processor count is read when
  -- the program asks. The C spec names that one operation; a C spec the
  -- registry does not list stays rejected.
  , MkEntry (Def (MkQName ["System", "Info"] "prim__os"))
            (Typed (Prim StringP)) (SystemInfo TargetOs) [Primitive]
  , MkEntry (Def (MkQName ["System", "Info"] "prim__codegen"))
            (Typed (Prim StringP)) (SystemInfo BackendName) [Primitive]
  , MkEntry (Foreign (MkSpec "C" "idris2_getNProcessors"))
            (Declared (MkQName ["System", "Info"] "prim__getNProcessors")
                      (Pi Q1 world (ioRes int)))
            (IOCall NProcessors []) [IOPrimitive] ] ++
  files ++ directories ++ process ++ terminal ++ errors ++ clocks ++ handles ++ iterators
