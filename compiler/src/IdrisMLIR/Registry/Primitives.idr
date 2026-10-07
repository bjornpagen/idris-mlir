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

import IdrisMLIR.Registry.Entry
import IdrisMLIR.Registry.Name
import IdrisMLIR.Rule
import IdrisMLIR.Types

%default total

||| The module Idris takes `main` from when none is named.
export
mainModule : List String
mainModule = ["Main"]

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
ioPrimitive : Spec -> String -> Shape -> IOOp -> Entry
ioPrimitive spec name shape op =
  MkEntry (Foreign spec) (Declared (MkQName ["Prelude", "IO"] name) shape) (IOCall op) [IOPrimitive]

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
arrayPrimitive : String -> Shape -> ArrayOp -> Entry
arrayPrimitive name shape op =
  MkEntry (Def (MkQName arrayPrims name)) (Typed (Pi Q0 TypeOfTypes shape)) (ArrayCall op) [IOPrimitive]

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

||| `AnyPtr`, the type of a file handle.
filePtr : Shape
filePtr = Head (Def (MkQName ["PrimIO"] "AnyPtr")) []

fileVirtual, fileBuffer, fileReadWrite : List String
fileVirtual = ["System", "File", "Virtual"]
fileBuffer = ["System", "File", "Buffer"]
fileReadWrite = ["System", "File", "ReadWrite"]

||| A System.File primitive, declared `%foreign` by its C support spec.
filePrimitive : String -> List String -> String -> Shape -> Hook -> Entry
filePrimitive spec space name shape hook =
  MkEntry (Foreign (MkSpec "C" spec)) (Declared (MkQName space name) shape) hook [IOPrimitive]

preludeTypes : List String
preludeTypes = ["Prelude", "Types"]

||| `List a`.
list : Shape -> Shape
list a = Head (Def (MkQName ["Prelude", "Basics"] "List")) [a]

||| A buffer primitive, declared `%foreign` by its Chez spec.
bufferPrimitive : String -> String -> Shape -> IOOp -> Entry
bufferPrimitive spec name shape op =
  MkEntry (Foreign (MkSpec "scheme" spec)) (Declared (MkQName bufferModule name) shape) (IOCall op) [IOPrimitive]

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

||| A machine word written into a buffer, by its Chez spec.
bufferStore : String -> String -> Shape -> Ty -> Entry
bufferStore spec name shape ty = bufferPrimitive spec name shape (BufferStore ty)

||| A machine word read from a buffer, by its Chez spec.
bufferLoad : String -> String -> Shape -> Ty -> Entry
bufferLoad spec name shape ty = bufferPrimitive spec name shape (BufferLoad ty)

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
                   (Pi QW int (Pi QW Hole (Pi Q1 world (ioRes (arrayData Hole))))) NewArray
  , arrayPrimitive "prim__arrayGet"
                   (Pi QW (arrayData Hole) (Pi QW int (Pi Q1 world (ioRes Hole)))) GetArray
  , arrayPrimitive "prim__arraySet"
                   (Pi QW (arrayData Hole) (Pi QW int (Pi QW Hole (Pi Q1 world (ioRes unit))))) SetArray
  -- The length of an array, which the backend contract lacks: the in-house
  -- linear array library declares it by Chez's spec, `vector-length` of the
  -- vector `ArrayData` is there (after the erased type argument Chez passes
  -- a Scheme foreign function), and the compiler gives that spec its one
  -- meaning, the memref's dimension.
  , MkEntry (Foreign (MkSpec "scheme" "(lambda (ty v) (vector-length v))"))
            (Declared (MkQName ["Linear", "Array"] "prim__arraySize")
                      (Pi Q0 TypeOfTypes (Pi QW (arrayData Hole) int)))
            (ArraySize Nothing) [Primitive]
  -- base's Data.Buffer is an array of bytes. Its size is the array's
  -- length. A byte is that element (setBits8, getBits8). A wider value is
  -- the target's own load or store of those bytes, so the endianness is
  -- the machine's, as Chez's native-endianness is. setByte, getByte and
  -- bufferData are deprecated names: a program that calls one is rejected,
  -- and the message names the replacement. They share Chez's byte spec
  -- with the Bits8 operations; the declared name picks the entry.
  , MkEntry (Def (MkQName bufferModule "Buffer")) (Typed TypeOfTypes) (ArrayType (Just byte)) [IOPrimitive]
  , bufferPrimitive "blodwen-new-buffer" "prim__newBuffer"
                    (Pi QW int (Pi Q1 world (ioRes buffer))) BufferNew
  , deprecatedForeign "blodwen-buffer-setbyte" "prim__setByte"
                      (Pi QW buffer (Pi QW int (Pi QW int (Pi Q1 world (ioRes unit)))))
                      "setByte is deprecated; use setBits8"
  , deprecatedDef "setByte" "setByte is deprecated; use setBits8"
  , bufferPrimitive "blodwen-buffer-setbyte" "prim__setBits8"
                    (Pi QW buffer (Pi QW int (Pi QW bits8 (Pi Q1 world (ioRes unit))))) (Array SetArray byte)
  , deprecatedForeign "blodwen-buffer-getbyte" "prim__getByte"
                      (Pi QW buffer (Pi QW int (Pi Q1 world (ioRes int))))
                      "getByte is deprecated; use getBits8"
  , deprecatedDef "getByte" "getByte is deprecated; use getBits8"
  , bufferPrimitive "blodwen-buffer-getbyte" "prim__getBits8"
                    (Pi QW buffer (Pi QW int (Pi Q1 world (ioRes bits8)))) (Array GetArray byte)
  , MkEntry (Foreign (MkSpec "scheme" "blodwen-buffer-size"))
            (Declared (MkQName bufferModule "prim__bufferSize") (Pi QW buffer int))
            (ArraySize (Just byte)) [Primitive]
  , bufferStore "blodwen-buffer-setbits16" "prim__setBits16" (stored (intOf UInt16)) (IntT UInt16)
  , bufferLoad "blodwen-buffer-getbits16" "prim__getBits16" (loaded (intOf UInt16)) (IntT UInt16)
  , bufferStore "blodwen-buffer-setbits32" "prim__setBits32" (stored (intOf UInt32)) (IntT UInt32)
  , bufferLoad "blodwen-buffer-getbits32" "prim__getBits32" (loaded (intOf UInt32)) (IntT UInt32)
  , bufferStore "blodwen-buffer-setbits64" "prim__setBits64" (stored (intOf UInt64)) (IntT UInt64)
  , bufferLoad "blodwen-buffer-getbits64" "prim__getBits64" (loaded (intOf UInt64)) (IntT UInt64)
  , bufferStore "blodwen-buffer-setint8" "prim__setInt8" (stored (intOf SInt8)) (IntT SInt8)
  , bufferLoad "blodwen-buffer-getint8" "prim__getInt8" (loaded (intOf SInt8)) (IntT SInt8)
  , bufferStore "blodwen-buffer-setint16" "prim__setInt16" (stored (intOf SInt16)) (IntT SInt16)
  , bufferLoad "blodwen-buffer-getint16" "prim__getInt16" (loaded (intOf SInt16)) (IntT SInt16)
  , bufferStore "blodwen-buffer-setint32" "prim__setInt32" (stored (intOf SInt32)) (IntT SInt32)
  , bufferLoad "blodwen-buffer-getint32" "prim__getInt32" (loaded (intOf SInt32)) (IntT SInt32)
  , bufferStore "blodwen-buffer-setint64" "prim__setInt64" (stored (intOf SInt64)) (IntT SInt64)
  , bufferLoad "blodwen-buffer-getint64" "prim__getInt64" (loaded (intOf SInt64)) (IntT SInt64)
  , bufferStore "blodwen-buffer-setint" "prim__setInt" (stored int) (IntT IdrisInt)
  , bufferLoad "blodwen-buffer-getint" "prim__getInt" (loaded int) (IntT IdrisInt)
  , bufferStore "blodwen-buffer-setdouble" "prim__setDouble" (stored dbl) DoubleT
  , bufferLoad "blodwen-buffer-getdouble" "prim__getDouble" (loaded dbl) DoubleT
  , MkEntry (Foreign (MkSpec "scheme" "blodwen-stringbytelen"))
            (Declared (MkQName bufferModule "stringByteLength") (Pi QW (Prim StringP) int))
            StrBytes [Primitive]
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
  -- base's System.File on the standard streams: a FilePtr is an AnyPtr,
  -- a machine word, which only the three handles inhabit, the runtime's
  -- own meaning of them; the byte transfers of System.File.Buffer; and
  -- whether a read met the end of input.
  , MkEntry (Def (MkQName ["PrimIO"] "AnyPtr")) (Typed TypeOfTypes) WordType [IOPrimitive]
  , filePrimitive "idris2_stdin" fileVirtual "prim__stdin" filePtr (Handle (LInt UInt64 0))
  , filePrimitive "idris2_stdout" fileVirtual "prim__stdout" filePtr (Handle (LInt UInt64 1))
  , filePrimitive "idris2_stderr" fileVirtual "prim__stderr" filePtr (Handle (LInt UInt64 2))
  , filePrimitive "idris2_writeBufferData" fileBuffer "prim__writeBufferData"
                  (Pi QW filePtr (Pi QW buffer (Pi QW int (Pi QW int (Pi Q1 world (ioRes int))))))
                  (IOCall WriteBytes)
  , filePrimitive "idris2_readBufferData" fileBuffer "prim__readBufferData"
                  (Pi QW filePtr (Pi QW buffer (Pi QW int (Pi QW int (Pi Q1 world (ioRes int))))))
                  (IOCall ReadBytes)
  , filePrimitive "idris2_eof" fileReadWrite "prim__eof"
                  (Pi QW filePtr (Pi Q1 world (ioRes int))) (IOCall Eof)
  -- Strings built from lists. The Prelude's pack is strCons by strCons, a
  -- string per character, and its own %transform runs fastPack in its
  -- place at runtime, as fastConcat for concat over a list of strings and
  -- fastUnpack for unpack: the stock backends build the string once. The
  -- one meaning of pack and fastPack is the string of the list's
  -- characters, of fastConcat the concatenation, each built once
  -- (idr.str.pack, idr.str.concat); fastUnpack stands for unpack, a loop
  -- already.
  , MkEntry (Def (MkQName preludeTypes "pack"))
            (Typed (Pi QW (list (Prim CharP)) (Prim StringP))) (Builds Pack) [Primitive]
  , MkEntry (Foreign (MkSpec "scheme" "string-pack"))
            (Declared (MkQName preludeTypes "fastPack") (Pi QW (list (Prim CharP)) (Prim StringP)))
            (Builds Pack) [Primitive]
  , MkEntry (Foreign (MkSpec "scheme" "string-concat"))
            (Declared (MkQName preludeTypes "fastConcat") (Pi QW (list (Prim StringP)) (Prim StringP)))
            (Builds Concat) [Primitive]
  , MkEntry (Foreign (MkSpec "scheme" "string-unpack"))
            (Declared (MkQName preludeTypes "fastUnpack") (Pi QW (Prim StringP) (list (Prim CharP))))
            (Alias (MkQName preludeTypes "unpack")) [Primitive] ]
