-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Category 2 of the registry: ordinary
||| library definitions the compiler treats specially. This is the
||| privileged-knowledge table: each entry makes a definition with a body
||| faster or stricter, never different, and removing one may change speed
||| or which programs are rejected, never a program's result; the few whose
||| body only coerces (`believe_me`) or is a builtin are their contract.
module IdrisMLIR.Registry.Recognized

import IdrisMLIR.Spec.Ops.Bigs
import IdrisMLIR.Registry.Entry
import IdrisMLIR.Registry.Name
import IdrisMLIR.Registry.Primitives
import IdrisMLIR.Spec.Core.Rules
import IdrisMLIR.Spec.Ops.Values
import IdrisMLIR.Types

%default total

||| A world operation of `PrimIO`, reachable only through the program root.
rootOnly : String -> Shape -> AnyEntry
rootOnly name shape = entry (Def (MkQName ["PrimIO"] name)) (Ruled shape) (Forbidden WhereUserCodeNames (Refusal TrustedLibrary))

||| An escape hatch as the user can write it. Idris evaluates
||| `prim__believe_me` applied to a constructor while elaborating, so it can
||| vanish from TT; the source is scanned instead.
spelling : String -> AnyEntry
spelling s = entry (Spelling s) Written (Forbidden WhereUserCodeNames (Refusal EscapeHatch))

||| `Nat`, Prelude's natural.
export
nat : Shape
nat = Head (Def (MkQName ["Prelude", "Types"] "Nat")) []

------------------------------------------------------------------------------
-- The array language
------------------------------------------------------------------------------

||| The module of the array language's types and generating set, in the
||| package `mlir-array`.
export
arrayCore : List String
arrayCore = ["Array", "Core"]

||| A shape: a snoc list of naturals, outermost axis first. The value-array
||| entries pin the shape type, which is how a shape's form is read by the
||| constructors of `SnocList` (`Frontend.Translate.Shapes`).
export
shapeType : Shape
shapeType = Head (Def (MkQName ["Prelude", "Basics"] "SnocList")) [nat]

||| `n` implicit arguments of quantity 0 before `rest`, each of any type.
export
implicits : Nat -> Shape -> Shape
implicits Z rest = rest
implicits (S k) rest = Pi M0 Hole (implicits k rest)

||| An explicit argument at quantity ω.
export
arg : Shape -> Shape -> Shape
arg = Pi Mw

||| The namespace of the linear arrays' functions, inside `Array.Core`,
||| which tells them apart from the arrays' of the same name.
export
larrayCore : List String
larrayCore = arrayCore ++ ["LArray"]

||| A function of the generating set that the library declares `%extern`,
||| by its namespace and name: its own type says what its calls take and
||| give, and its op is its only meaning.
generating : List String -> String -> ArrayPrim -> AnyEntry
generating ns name p = entry (Def (MkQName ns name)) Bodiless (Generating p)

||| A function of the array language that is the identity on its array: a
||| bodiless `%extern` too, since only `Array.Core` sees how an array is held.
identityOn : List String -> String -> AnyEntry
identityOn ns name = entry (Def (MkQName ns name)) Bodiless IdentityOnLastArgument

||| `Array s a`, the array language's value type, at a shape and an element.
export
arrayShape : Shape
arrayShape = Head (Def (MkQName arrayCore "Array")) [Hole, Hole]

||| `LArray s a`, a linear array at a shape and an element.
export
larrayShape : Shape
larrayShape = Head (Def (MkQName arrayCore "LArray")) [Hole, Hole]

||| `Extents s`, a shape at run time.
export
extentsShape : Shape
extentsShape = Head (Def (MkQName (arrayCore ++ ["Extents"]) "Extents")) [Hole]

||| `Index s`, a position in a shape.
export
indexShape : Shape
indexShape = Head (Def (MkQName (arrayCore ++ ["Index"]) "Index")) [Hole]

||| A linear argument.
export
linear : Shape -> Shape -> Shape
linear = Pi M1

||| The functions of the array language's generating set and of its linear
||| arrays that the library declares `%extern`, whose calls are the tensor
||| operations of their sequential meaning, a linear array's on the array
||| its cell holds.
arrayLanguage : List AnyEntry
arrayLanguage =
  [ generating arrayCore "update" AUpdate
  , generating arrayCore "scanLast" AScanLast
  , identityOn arrayCore "nest"
  , generating arrayCore "merge" AMerge
  , generating arrayCore "transpose" ATranspose
  , generating arrayCore "take" ATake
  , generating arrayCore "drop" ADrop
  , generating arrayCore "++" AConcat
  , generating arrayCore "pad" APad
  , generating arrayCore "tabulateIO" ATabulateIO
  , generating larrayCore "withArray" AWithArray
  , generating larrayCore "shape" ALShape
  , generating larrayCore "grow" AGrow ]

------------------------------------------------------------------------------
-- What data promises
------------------------------------------------------------------------------

||| The types of `mlir-linear` and `mlir-array` whose cells are rebuilt in
||| place and held exclusive: a promise of the library's types, which every
||| program that uses them is checked against, never a choice of the
||| command line. A linear array and the growable vector are written in
||| place by the one mechanism the linear list is.
inPlace : List AnyEntry
inPlace =
  [ entry (Def (MkQName ["Linear", "List"] "LList")) (Ruled (Pi Mw TypeOfTypes TypeOfTypes)) InPlaceType
  , entry (Def (MkQName ["Linear", "Nat"] "LNat")) (Ruled TypeOfTypes) InPlaceType
  , entry (Def (MkQName arrayCore "LArray")) (Ruled (Pi M0 shapeType (Pi Mw TypeOfTypes TypeOfTypes))) InPlaceType
  , entry (Def (MkQName ["Linear", "Vec"] "Vec"))
            (Ruled (Pi Mw (Head (Def (MkQName ["Prelude", "Types"] "Nat")) []) (Pi Mw TypeOfTypes TypeOfTypes)))
            InPlaceType ]

------------------------------------------------------------------------------
-- What a match assumes
------------------------------------------------------------------------------

||| Idris's equality, `Equal : forall a, b . a -> b -> Type`, a builtin
||| whose one constructor, matched on an erased proof, is its meaning: its
||| two sides are equal where the match holds.
equality : AnyEntry
equality = entry (Def (MkQName ["Builtin"] "Equal"))
                 (External (Pi M0 TypeOfTypes (Pi M0 TypeOfTypes (Pi Mw Hole (Pi Mw Hole TypeOfTypes)))))
                 EqualityType

------------------------------------------------------------------------------
-- Pointers and the exit
------------------------------------------------------------------------------

||| A cast between pointers, `prim__castPtr : AnyPtr -> Ptr t` or
||| `prim__forgetPtr : Ptr t -> AnyPtr`: a pointer is a handle whatever it
||| points to, so the cast is the identity on its one runtime argument.
pointerCast : String -> Shape -> AnyEntry
pointerCast name shape =
  entry (Def (MkQName ["PrimIO"] name)) (Coerced (Pi M0 TypeOfTypes shape)) IdentityOnLastArgument

||| `exitWith : HasIO io => ExitCode -> io a`, at its two erased types, its
||| `HasIO` and the status. Its body gives the action of `prim__exit` any
||| result by `believe_me`; its calls are the exit, which does not return.
exitWith : AnyEntry
exitWith = entry (Def (MkQName ["System"] "exitWith"))
                   (Coerced (Pi M0 Hole (Pi M0 Hole (Pi Mw Hole (Pi Mw exitCode Hole)))))
                   Exits
  where
    exitCode : Shape
    exitCode = Head (Def (MkQName ["System"] "ExitCode")) []

------------------------------------------------------------------------------
-- Outside the language
------------------------------------------------------------------------------

||| A definition the language this compiler implements does not include.
||| The refusal does not depend on the type, so the shape is a hole:
||| validation checks that the library still defines it.
ruledOut : List String -> String -> SomeRule -> AnyEntry
ruledOut ns name rule =
  entry (Def (MkQName ns name)) (Ruled Hole) (Forbidden WhereverReached rule)

||| Threads: `Prelude.IO`'s `fork` and `threadWait` and the primitives they
||| call, and all of `System.Concurrency`, whose every public function calls
||| the primitive of its name (`makeMutex` calls `prim__makeMutex`).
threads : List AnyEntry
threads =
  map (\n => ruledOut ["Prelude", "IO"] n (Refusal Threads))
      ["fork", "prim__fork", "threadWait", "prim__threadWait"] ++
  concatMap (\n => [ruledOut concurrency n (Refusal Threads), ruledOut concurrency ("prim__" ++ n) (Refusal Threads)])
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
signals : List AnyEntry
signals =
  map (\n => ruledOut signal ("prim__" ++ n) (Refusal Signal))
      [ "sighup", "sigint", "sigabrt", "sigquit", "sigill", "sigsegv", "sigtrap", "sigfpe"
      , "sigusr1", "sigusr2", "ignoreSignal", "defaultSignal", "collectSignal"
      , "handleNextCollectedSignal", "sendSignal", "raiseSignal" ] ++
  map (\n => ruledOut signal n (Refusal Signal))
      [ "signalCode", "toSignal", "ignoreSignal", "defaultSignal", "collectSignal"
      , "handleNextCollectedSignal", "handleManyCollectedSignals", "raiseSignal" ] ++
  [ruledOut (signal ++ ["Posix"]) "sendSignal" (Refusal Signal)]
  where
    signal : List String
    signal = ["System", "Signal"]

||| Process creation: `System`'s `system` and the functions that run a
||| command, and `System.File.Process`'s pipes, `popen` and `popen2`, with
||| the primitives they call. The module's `fflush` is a file's.
processes : List AnyEntry
processes =
  map (\n => ruledOut ["System"] n (Refusal Process)) ["prim__system", "system", "run", "runProcessingOutput"] ++
  map (\n => ruledOut ["System", "Escaped"] n (Refusal Process)) ["system", "run", "runProcessingOutput"] ++
  map (\n => ruledOut pipes n (Refusal Process))
      [ "prim__popen", "prim__pclose", "prim__popen2", "prim__popen2WaitByPid"
      , "prim__popen2WaitByHandler", "prim__popen2ChildPid", "prim__popen2ChildHandler"
      , "prim__popen2FileIn", "prim__popen2FileOut", "popen", "pclose", "popen2", "popen2Wait" ] ++
  map (\n => ruledOut (pipes ++ ["Escaped"]) n (Refusal Process)) ["popen", "popen2"]
  where
    pipes : List String
    pipes = ["System", "File", "Process"]

||| What the language this compiler implements does not include, by name, so
||| that a program is refused where it uses it: threads, collector
||| finalizers, raw memory (`System.FFI`'s `malloc`), signal handlers and
||| process creation.
outsideLanguage : List AnyEntry
outsideLanguage =
  threads ++
  map (\n => ruledOut ["Prelude", "IO"] n (Refusal Finalizer)) ["onCollect", "onCollectAny"] ++
  map (\n => ruledOut ["System", "FFI"] n (Refusal RawPointer)) ["prim__malloc", "malloc"] ++
  signals ++ processes

||| The table.
export
recognized : List AnyEntry
recognized =
  arrayLanguage ++ inPlace ++ outsideLanguage ++
  [ equality
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
  , entry (Def (MkQName ["Builtin"] "idris_crash")) (External Hole) LibraryCrash ]
