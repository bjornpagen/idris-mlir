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

world : Shape
world = Prim WorldP

unit : Shape
unit = Head (Def (MkQName ["Builtin"] "Unit")) []

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
arrayData : Shape -> Shape
arrayData a = Head (Def (MkQName arrayPrims "ArrayData")) [a]

||| An array primitive, `forall a . ... -> PrimIO r`: its element type is
||| erased, and its world is the last argument.
arrayPrimitive : String -> Shape -> ArrayOp -> Entry
arrayPrimitive name shape op =
  MkEntry (Def (MkQName arrayPrims name)) (Typed (Pi Q0 TypeOfTypes shape)) (ArrayCall op) [IOPrimitive]

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

||| A buffer primitive, declared `%foreign` by its Chez spec.
bufferPrimitive : String -> String -> Shape -> IOOp -> Entry
bufferPrimitive spec name shape op =
  MkEntry (Foreign (MkSpec "scheme" spec)) (Declared (MkQName bufferModule name) shape) (IOCall op) [IOPrimitive]

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
  -- base's Data.Buffer, a mutable array of bytes, by the Chez specs it
  -- declares: a new buffer is zero bytes; a byte is read as its Bits8 or as
  -- an Int, and written from either, an Int outside 0 to 255 being a
  -- crash, as Chez's bytevector-u8-set! refuses it; its size is the
  -- array's dimension.
  , MkEntry (Def (MkQName bufferModule "Buffer")) (Typed TypeOfTypes) (ArrayType (Just byte)) [IOPrimitive]
  , bufferPrimitive "blodwen-new-buffer" "prim__newBuffer"
                    (Pi QW int (Pi Q1 world (ioRes buffer))) BufferNew
  , bufferPrimitive "blodwen-buffer-setbyte" "prim__setByte"
                    (Pi QW buffer (Pi QW int (Pi QW int (Pi Q1 world (ioRes unit))))) BufferSet
  , bufferPrimitive "blodwen-buffer-setbyte" "prim__setBits8"
                    (Pi QW buffer (Pi QW int (Pi QW bits8 (Pi Q1 world (ioRes unit))))) (Array SetArray byte)
  , bufferPrimitive "blodwen-buffer-getbyte" "prim__getByte"
                    (Pi QW buffer (Pi QW int (Pi Q1 world (ioRes int)))) BufferGet
  , bufferPrimitive "blodwen-buffer-getbyte" "prim__getBits8"
                    (Pi QW buffer (Pi QW int (Pi Q1 world (ioRes bits8)))) (Array GetArray byte)
  , MkEntry (Foreign (MkSpec "scheme" "blodwen-buffer-size"))
            (Declared (MkQName bufferModule "prim__bufferSize") (Pi QW buffer int))
            (ArraySize (Just byte)) [Primitive]
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
                  (Pi QW filePtr (Pi Q1 world (ioRes int))) (IOCall Eof) ]
