-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Category 2 of the registry: ordinary
||| library definitions the compiler treats specially. This is the
||| privileged-knowledge table: each entry makes its definition faster or
||| stricter, never different, and removing one may change speed or which
||| programs are rejected, never a program's result.
module IdrisMLIR.Registry.Recognized

import IdrisMLIR.Dialect.Idr
import IdrisMLIR.Registry.Entry
import IdrisMLIR.Registry.Name
import IdrisMLIR.Registry.Primitives
import IdrisMLIR.Syntax.Idr
import IdrisMLIR.Types

%default total

||| `Builtin.Equal` applied to its two types and two sides, which is what
||| `x = y` and `x === y` normalise to.
equal : Shape
equal = Head (Def (MkQName ["Builtin"] "Equal")) [Hole, Hole, Hole, Hole]

||| A rewriting combinator: a type, two erased values and an erased
||| predicate, an erased proof that the values are equal, and the value to
||| rewrite, the one runtime argument, which it returns.
rewriting : Shape
rewriting = Pi M0 TypeOfTypes (Pi M0 Hole (Pi M0 Hole (Pi M0 Hole (Pi M0 equal (Pi M1 Hole Hole)))))

||| `replace` and `rewrite__impl`, which `rewrite` elaborates to.
identity : String -> Entry
identity name = MkEntry (Def (MkQName ["Builtin"] name)) (Typed rewriting) IdentityOnLastArgument [IdentityHook]

||| A world operation of `PrimIO`, reachable only through the program root.
rootOnly : String -> Shape -> Entry
rootOnly name shape = MkEntry (Def (MkQName ["PrimIO"] name)) (Typed shape) (Forbidden WorldUse) [WorldUse]

||| An escape hatch as the user can write it. Idris evaluates
||| `prim__believe_me` applied to a constructor while elaborating, so it can
||| vanish from TT; the source is scanned instead.
spelling : String -> Entry
spelling s = MkEntry (Spelling s) Written (Forbidden EscapeHatch) [EscapeHatch]

------------------------------------------------------------------------------
-- Naturals
------------------------------------------------------------------------------

nat : Shape
nat = Head (Def (MkQName ["Prelude", "Types"] "Nat")) []

bool : Shape
bool = Head (Def (MkQName ["Prelude", "Basics"] "Bool")) []

binary : Shape -> Shape
binary result = Pi Mw nat (Pi Mw nat result)

||| The library function that makes a `Bool` of an `Int`.
intToBool : QName
intToBool = MkQName ["Prelude", "Basics"] "intToBool"

||| A function on naturals, at its name in `ns`, and what it means. These
||| are the functions Idris's own backends compute on the representation of
||| `Nat` instead of by their unary recursions (the Prelude's `natHack`), and
||| `Data.Nat`'s tests, which are `compareNat` in another form.
natural : List String -> String -> Shape -> NatMeaning -> Entry
natural ns name shape m = MkEntry (Def (MkQName ns name)) (Typed shape) (NatOperation m) [HookShape]

||| The functions on naturals.
naturals : List Entry
naturals =
  [ natural types "natToInteger" (Pi Mw nat (Prim IntegerP)) (Primitive (Op NatToBig))
  , natural types "integerToNat" (Pi Mw (Prim IntegerP) nat) (Primitive (Op NatFromBig))
  , natural types "prim__integerToNat" (Pi Mw (Prim IntegerP) nat) (Primitive (Op NatFromBig))
  , natural types "plus" (binary nat) (Primitive (Op BigAdd))
  , natural types "mult" (binary nat) (Primitive (Op BigMul))
  , natural types "minus" (binary nat) (Clamped (Op BigSub))
  , natural types "equalNat" (binary bool) (Tested CEq intToBool)
  , natural types "compareNat" (binary (Head (Def (MkQName ["Prelude", "EqOrd"] "Ordering")) []))
            (OnIntegers (MkQName ["Prelude", "EqOrd"] "compareInteger"))
  , natural ["Data", "Nat"] "lte" (binary bool) (Tested CLte intToBool)
  , natural ["Data", "Nat"] "gte" (binary bool) (Tested CGte intToBool)
  , natural ["Data", "Nat"] "lt" (binary bool) (Tested CLt intToBool)
  , natural ["Data", "Nat"] "gt" (binary bool) (Tested CGt intToBool) ]
  where
    types : List String
    types = ["Prelude", "Types"]

------------------------------------------------------------------------------
-- The array language
------------------------------------------------------------------------------

||| The module of the array language's types and generating set, in the
||| package `mlir-array`.
arrayCore : List String
arrayCore = ["Array", "Core"]

||| A shape: a snoc list of naturals, outermost axis first. The value-array
||| entries pin the shape type, which is how a shape's form is read by the
||| constructors of `SnocList` (`Frontend.Translate.Shapes`).
export
shapeType : Shape
shapeType = Head (Def (MkQName ["Prelude", "Basics"] "SnocList")) [nat]

||| A head of the array language applied to its two arguments, every one a
||| hole: validation checks the head, the handler reads the types.
arr, larr : Shape
arr = Head (Def (MkQName arrayCore "Array")) [Hole, Hole]
larr = Head (Def (MkQName arrayCore "LArray")) [Hole, Hole]

ext, idx, cell : Shape
ext = Head (Def (MkQName (arrayCore ++ ["Extents"]) "Extents")) [Hole]
idx = Head (Def (MkQName (arrayCore ++ ["Index"]) "Index")) [Hole]
cell = Head (Def (MkQName (arrayCore ++ ["Cell"]) "Cell")) [Hole]

||| `n` implicit arguments of quantity 0 before `rest`, each of any type.
implicits : Nat -> Shape -> Shape
implicits Z rest = rest
implicits (S k) rest = Pi M0 Hole (implicits k rest)

||| An explicit argument at quantity ω, and one at quantity 1.
arg, lin : Shape -> Shape -> Shape
arg = Pi Mw
lin = Pi M1

||| A function of the generating set, by its name in `Array.Core`.
generating : String -> Shape -> ArrayPrim -> Entry
generating name shape p = MkEntry (Def (MkQName arrayCore name)) (Typed shape) (Generating p) [HookShape]

||| A function of the array language that is the identity on its array.
identityOn : String -> Shape -> Entry
identityOn name shape = MkEntry (Def (MkQName arrayCore name)) (Typed shape) IdentityOnLastArgument [IdentityHook]

||| The array language's two value types, its generating set and the
||| operations of its linear arrays, whose calls are the tensor operations
||| of their sequential meaning; and base's `natToFinLT`, the identity on
||| its natural, a `Fin` being one.
arrayLanguage : List Entry
arrayLanguage =
  [ MkEntry (Def (MkQName arrayCore "Array")) (Typed (Pi M0 shapeType (Pi Mw TypeOfTypes TypeOfTypes)))
            ArrayValueType [HookShape]
  , MkEntry (Def (MkQName arrayCore "LArray")) (Typed (Pi M0 shapeType (Pi Mw TypeOfTypes TypeOfTypes)))
            ArrayValueType [HookShape]
  , generating "shape" (implicits 2 (arg arr ext)) AShape
  , generating "tabulate" (implicits 2 (arg ext (arg (arg idx Hole) arr))) ATabulate
  , generating "!!" (implicits 2 (arg arr (arg idx Hole))) AIndex
  , generating "update" (implicits 2 (arg arr (arg idx (arg Hole arr)))) AUpdate
  , generating "foldLast" (implicits 4 (arg (arg Hole (arg Hole Hole)) (arg arr (arg arr arr)))) AFoldLast
  , generating "scanLast" (implicits 4 (arg (arg Hole (arg Hole Hole)) (arg arr (arg arr arr)))) AScanLast
  , identityOn "nest" (implicits 3 (arg cell (arg arr arr)))
  , identityOn "merge" (implicits 3 (arg ext (arg arr arr)))
  , generating "reshape" (implicits 3 (arg ext (Pi M0 Hole (arg arr arr)))) AReshape
  , generating "take" (implicits 3 (arg nat (Pi M0 Hole (arg arr arr)))) ATake
  , generating "drop" (implicits 3 (arg nat (Pi M0 Hole (arg arr arr)))) ADrop
  , generating "++" (implicits 4 (arg arr (arg arr arr))) AConcat
  , generating "pad" (implicits 3 (arg nat (arg nat (arg Hole (arg arr arr))))) APad
  , generating "withArray" (implicits 3 (arg ext (arg Hole (arg (lin larr Hole) Hole)))) AWithArray
  , generating "read" (implicits 2 (lin larr (arg idx Hole))) ARead
  , generating "write" (implicits 2 (lin larr (arg idx (arg Hole larr)))) AWrite
  , identityOn "freeze" (implicits 2 (lin larr Hole))
  , generating "thaw" (implicits 3 (arg arr (arg (lin larr Hole) Hole))) AThaw
  , generating "lshape" (implicits 2 (lin larr Hole)) ALShape
  , generating "grow" (implicits 3 (arg nat (arg Hole (lin larr larr)))) AGrow
  , generating "tabulateIO" (implicits 2 (arg ext (arg (arg idx Hole) Hole))) ATabulateIO
  , MkEntry (Def (MkQName ["Data", "Fin"] "natToFinLT"))
            (Typed (arg nat (implicits 2 (Head (Def (MkQName ["Data", "Fin"] "Fin")) [Hole]))))
            IdentityOnLastArgument [IdentityHook] ]

------------------------------------------------------------------------------
-- What data plays and promises
------------------------------------------------------------------------------

||| The list's nil and cons, which the string builders take apart: their
||| role is the registry's, never guessed from their shape.
listRoles : List Entry
listRoles =
  [ MkEntry (Def (MkQName ["Prelude", "Basics"] "Nil")) (Typed (implicits 1 (list Hole))) (Plays ListNil) [HookShape]
  , MkEntry (Def (MkQName ["Prelude", "Basics"] "::")) (Typed (implicits 1 (arg Hole (arg (list Hole) (list Hole)))))
            (Plays ListCons) [HookShape] ]
  where
    list : Shape -> Shape
    list a = Head (Def (MkQName ["Prelude", "Basics"] "List")) [a]

||| The types of `mlir-linear` whose cells are rebuilt in place and held
||| exclusive: a promise of the library's types, which every program that
||| uses them is checked against, never a choice of the command line.
inPlace : List Entry
inPlace =
  [ MkEntry (Def (MkQName ["Linear", "List"] "LList")) (Typed (Pi Mw TypeOfTypes TypeOfTypes))
            (Promises InPlace) [HookShape]
  , MkEntry (Def (MkQName ["Linear", "Nat"] "LNat")) (Typed TypeOfTypes) (Promises InPlace) [HookShape] ]

------------------------------------------------------------------------------
-- Pointers and the exit
------------------------------------------------------------------------------

||| A cast between pointers, `prim__castPtr : AnyPtr -> Ptr t` or
||| `prim__forgetPtr : Ptr t -> AnyPtr`: a pointer is a handle whatever it
||| points to, so the cast is the identity on its one runtime argument.
pointerCast : String -> Shape -> Entry
pointerCast name shape =
  MkEntry (Def (MkQName ["PrimIO"] name)) (Typed (Pi M0 TypeOfTypes shape)) IdentityOnLastArgument [IdentityHook]

||| `exitWith : HasIO io => ExitCode -> io a`, at its two erased types, its
||| `HasIO` and the status. Its body gives the action of `prim__exit` any
||| result by `believe_me`; its calls are the exit, which does not return.
exitWith : Entry
exitWith = MkEntry (Def (MkQName ["System"] "exitWith"))
                   (Typed (Pi M0 Hole (Pi M0 Hole (Pi Mw Hole (Pi Mw exitCode Hole)))))
                   (Exits Exit) [IOPrimitive]
  where
    exitCode : Shape
    exitCode = Head (Def (MkQName ["System"] "ExitCode")) []

------------------------------------------------------------------------------
-- Outside the language
------------------------------------------------------------------------------

||| A definition the language this compiler implements does not include.
||| The refusal does not depend on the type, so the shape is a hole:
||| validation checks that the library still defines it.
ruledOut : List String -> String -> Rule -> Entry
ruledOut ns name rule =
  MkEntry (Def (MkQName ns name)) (Typed Hole) (Forbidden rule) [rule]

||| Threads: `Prelude.IO`'s `fork` and `threadWait` and the primitives they
||| call, and all of `System.Concurrency`, whose every public function calls
||| the primitive of its name (`makeMutex` calls `prim__makeMutex`).
threads : List Entry
threads =
  map (\n => ruledOut ["Prelude", "IO"] n Threads)
      ["fork", "prim__fork", "threadWait", "prim__threadWait"] ++
  concatMap (\n => [ruledOut concurrency n Threads, ruledOut concurrency ("prim__" ++ n) Threads])
      [ "setThreadData", "getThreadData", "getThreadId"
      , "makeMutex", "mutexAcquire", "mutexRelease"
      , "makeCondition", "conditionWait", "conditionWaitTimeout", "conditionSignal", "conditionBroadcast"
      , "makeSemaphore", "semaphorePost", "semaphoreWait"
      , "makeBarrier", "barrierWait"
      , "makeChannel", "channelGet", "channelGetNonBlocking", "channelGetWithTimeout", "channelPut" ]
  where
    concurrency : List String
    concurrency = ["System", "Concurrency"]

||| Signal handlers: `System.Signal`'s primitives (the signal numbers, and
||| the handling and sending of signals) and its public functions.
signals : List Entry
signals =
  map (\n => ruledOut signal ("prim__" ++ n) Signal)
      [ "sighup", "sigint", "sigabrt", "sigquit", "sigill", "sigsegv", "sigtrap", "sigfpe"
      , "sigusr1", "sigusr2", "ignoreSignal", "defaultSignal", "collectSignal"
      , "handleNextCollectedSignal", "sendSignal", "raiseSignal" ] ++
  map (\n => ruledOut signal n Signal)
      [ "signalCode", "toSignal", "ignoreSignal", "defaultSignal", "collectSignal"
      , "handleNextCollectedSignal", "handleManyCollectedSignals", "raiseSignal" ] ++
  [ruledOut (signal ++ ["Posix"]) "sendSignal" Signal]
  where
    signal : List String
    signal = ["System", "Signal"]

||| Process creation: `System`'s `system` and the functions that run a
||| command, and `System.File.Process`'s pipes, `popen` and `popen2`, with
||| the primitives they call. The module's `fflush` is a file's.
processes : List Entry
processes =
  map (\n => ruledOut ["System"] n Process) ["prim__system", "system", "run", "runProcessingOutput"] ++
  map (\n => ruledOut ["System", "Escaped"] n Process) ["system", "run", "runProcessingOutput"] ++
  map (\n => ruledOut pipes n Process)
      [ "prim__popen", "prim__pclose", "prim__popen2", "prim__popen2WaitByPid"
      , "prim__popen2WaitByHandler", "prim__popen2ChildPid", "prim__popen2ChildHandler"
      , "prim__popen2FileIn", "prim__popen2FileOut", "popen", "pclose", "popen2", "popen2Wait" ] ++
  map (\n => ruledOut (pipes ++ ["Escaped"]) n Process) ["popen", "popen2"]
  where
    pipes : List String
    pipes = ["System", "File", "Process"]

||| What the language this compiler implements does not include, by name, so
||| that a program is refused where it uses it: threads, collector
||| finalizers, raw memory (`System.FFI`'s `malloc`), signal handlers and
||| process creation.
outsideLanguage : List Entry
outsideLanguage =
  threads ++
  map (\n => ruledOut ["Prelude", "IO"] n Finalizer) ["onCollect", "onCollectAny"] ++
  map (\n => ruledOut ["System", "FFI"] n RawPointer) ["prim__malloc", "malloc"] ++
  signals ++ processes

||| The table.
export
recognized : List Entry
recognized =
  naturals ++ arrayLanguage ++ listRoles ++ inPlace ++ outsideLanguage ++
  [ identity "replace"
  , identity "rewrite__impl"
  , pointerCast "prim__castPtr" (Pi Mw anyPtr (ptr Hole))
  , pointerCast "prim__forgetPtr" (Pi Mw (ptr Hole) anyPtr)
  , exitWith
  , rootOnly "unsafePerformIO" (Pi M0 TypeOfTypes (Pi Mw (Head (Def (MkQName ["PrimIO"] "IO")) [Hole]) Hole))
  , rootOnly "unsafeCreateWorld" (Pi M0 TypeOfTypes (Pi M1 (Pi M1 (Prim WorldP) Hole) Hole))
  , rootOnly "unsafeDestroyWorld" (Pi M0 TypeOfTypes (Pi M1 (Prim WorldP) (Pi Mw Hole Hole)))
  , spelling "prim__believe_me"
  , spelling "prim__crash"
  , spelling "believe_me"
  , spelling "idris_crash"
  -- A trusted library may crash with a string (Data.Buffer.getNat's
  -- corrupt length). The spelling above still rejects it in user source,
  -- and a user definition that reaches the function is rejected because
  -- the reach is not from a trusted definition.
  , MkEntry (Def (MkQName ["Builtin"] "idris_crash")) (Typed Hole) LibraryCrash [] ]
