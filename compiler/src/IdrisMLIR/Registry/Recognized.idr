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
import IdrisMLIR.Spec.Core.Rules
import IdrisMLIR.Spec.Ops.Comparisons
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
identity name = MkEntry (Def (MkQName ["Builtin"] name)) (Typed rewriting) IdentityOnLastArgument

||| A world operation of `PrimIO`, reachable only through the program root.
rootOnly : String -> Shape -> Entry
rootOnly name shape = MkEntry (Def (MkQName ["PrimIO"] name)) (Typed shape) (Forbidden (Refusal TrustedLibrary))

||| An escape hatch as the user can write it. Idris evaluates
||| `prim__believe_me` applied to a constructor while elaborating, so it can
||| vanish from TT; the source is scanned instead.
spelling : String -> Entry
spelling s = MkEntry (Spelling s) Written (Forbidden (Refusal EscapeHatch))

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
natural ns name shape m = MkEntry (Def (MkQName ns name)) (Typed shape) (NatOperation m)

||| The functions on naturals.
naturals : List Entry
naturals =
  [ natural types "natToInteger" (Pi Mw nat (Prim IntegerP)) (Primitive (Op NatToBig BigT))
  , natural types "integerToNat" (Pi Mw (Prim IntegerP) nat) (Primitive (Op NatFromBig NatT))
  , natural types "prim__integerToNat" (Pi Mw (Prim IntegerP) nat) (Primitive (Op NatFromBig NatT))
  , natural types "plus" (binary nat) (Primitive (Op BigAdd NatT))
  , natural types "mult" (binary nat) (Primitive (Op BigMul NatT))
  , natural types "minus" (binary nat) (Clamped (Op BigSub BigT))
  , natural types "equalNat" (binary bool) (Tested CmpPredicate.Eq intToBool)
  , natural types "compareNat" (binary (Head (Def (MkQName ["Prelude", "EqOrd"] "Ordering")) []))
            (OnIntegers (MkQName ["Prelude", "EqOrd"] "compareInteger"))
  , natural ["Data", "Nat"] "lte" (binary bool) (Tested CmpPredicate.Lte intToBool)
  , natural ["Data", "Nat"] "gte" (binary bool) (Tested CmpPredicate.Gte intToBool)
  , natural ["Data", "Nat"] "lt" (binary bool) (Tested CmpPredicate.Lt intToBool)
  , natural ["Data", "Nat"] "gt" (binary bool) (Tested CmpPredicate.Gt intToBool) ]
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

||| `n` implicit arguments of quantity 0 before `rest`, each of any type.
implicits : Nat -> Shape -> Shape
implicits Z rest = rest
implicits (S k) rest = Pi M0 Hole (implicits k rest)

||| An explicit argument at quantity ω.
arg : Shape -> Shape -> Shape
arg = Pi Mw

||| The namespace of the linear arrays' functions, inside `Array.Core`,
||| which tells them apart from the arrays' of the same name.
larrayCore : List String
larrayCore = arrayCore ++ ["LArray"]

||| A function of the generating set, by its namespace and name: a bodiless
||| `%extern`, whose own type says what its calls take and give.
generating : List String -> String -> ArrayPrim -> Entry
generating ns name p = MkEntry (Def (MkQName ns name)) Bodiless (Generating p)

||| A function of the array language that is the identity on its array: a
||| bodiless `%extern` too, since only `Array.Core` sees how an array is held.
identityOn : List String -> String -> Entry
identityOn ns name = MkEntry (Def (MkQName ns name)) Bodiless IdentityOnLastArgument

||| The array language's two value types, whose shape type the entries pin;
||| its generating set and the operations of its linear arrays, whose calls
||| are the tensor operations of their sequential meaning; and base's
||| `natToFinLT` and `finToNat`, the identity on a natural, a `Fin` being
||| one: a coordinate is its natural, so an index's position reads as the
||| index, and a loop over an array computes on words.
arrayLanguage : List Entry
arrayLanguage =
  [ MkEntry (Def (MkQName arrayCore "Array")) (Typed (Pi M0 shapeType (Pi Mw TypeOfTypes TypeOfTypes)))
            ArrayValueType
  , MkEntry (Def (MkQName arrayCore "LArray")) (Typed (Pi M0 shapeType (Pi Mw TypeOfTypes TypeOfTypes)))
            ArrayValueType
  , generating arrayCore "shape" AShape
  , generating arrayCore "tabulate" ATabulate
  , generating arrayCore "!!" AIndex
  , generating arrayCore "update" AUpdate
  , generating arrayCore "foldLast" AFoldLast
  , generating arrayCore "scanLast" AScanLast
  , identityOn arrayCore "nest"
  , identityOn arrayCore "merge"
  , generating arrayCore "reshape" AReshape
  , generating arrayCore "transpose" ATranspose
  , generating arrayCore "take" ATake
  , generating arrayCore "drop" ADrop
  , generating arrayCore "++" AConcat
  , generating arrayCore "pad" APad
  , generating arrayCore "tabulateIO" ATabulateIO
  , generating larrayCore "withArray" AWithArray
  , generating larrayCore "read" ARead
  , generating larrayCore "write" AWrite
  , identityOn larrayCore "freeze"
  , generating larrayCore "thaw" AThaw
  , generating larrayCore "shape" ALShape
  , generating larrayCore "grow" AGrow
  , MkEntry (Def (MkQName ["Data", "Fin"] "natToFinLT"))
            (Typed (arg nat (implicits 2 (Head (Def (MkQName ["Data", "Fin"] "Fin")) [Hole]))))
            IdentityOnLastArgument
  , MkEntry (Def (MkQName ["Data", "Fin"] "finToNat"))
            (Typed (implicits 1 (arg (Head (Def (MkQName ["Data", "Fin"] "Fin")) [Hole]) nat)))
            IdentityOnLastArgument ]

------------------------------------------------------------------------------
-- What data promises
------------------------------------------------------------------------------

||| Base's list, a sum whose nil and cons the string builders take apart:
||| its kind is the registry's, never guessed from its shape; its nil and
||| its cons are its constructors of no field and of two.
baseList : List Entry
baseList =
  [ MkEntry (Def (MkQName ["Prelude", "Basics"] "List")) (Typed (Pi Mw TypeOfTypes TypeOfTypes)) ListType ]

||| The types of `mlir-linear` and `mlir-array` whose cells are rebuilt in
||| place and held exclusive: a promise of the library's types, which every
||| program that uses them is checked against, never a choice of the
||| command line. A linear array and the growable vector are written in
||| place by the one mechanism the linear list is.
inPlace : List Entry
inPlace =
  [ MkEntry (Def (MkQName ["Linear", "List"] "LList")) (Typed (Pi Mw TypeOfTypes TypeOfTypes)) InPlaceType
  , MkEntry (Def (MkQName ["Linear", "Nat"] "LNat")) (Typed TypeOfTypes) InPlaceType
  , MkEntry (Def (MkQName arrayCore "LArray")) (Typed (Pi M0 shapeType (Pi Mw TypeOfTypes TypeOfTypes))) InPlaceType
  , MkEntry (Def (MkQName ["Linear", "Vec"] "Vec"))
            (Typed (Pi Mw (Head (Def (MkQName ["Prelude", "Types"] "Nat")) []) (Pi Mw TypeOfTypes TypeOfTypes)))
            InPlaceType ]

------------------------------------------------------------------------------
-- Pointers and the exit
------------------------------------------------------------------------------

||| A cast between pointers, `prim__castPtr : AnyPtr -> Ptr t` or
||| `prim__forgetPtr : Ptr t -> AnyPtr`: a pointer is a handle whatever it
||| points to, so the cast is the identity on its one runtime argument.
pointerCast : String -> Shape -> Entry
pointerCast name shape =
  MkEntry (Def (MkQName ["PrimIO"] name)) (Typed (Pi M0 TypeOfTypes shape)) IdentityOnLastArgument

||| `exitWith : HasIO io => ExitCode -> io a`, at its two erased types, its
||| `HasIO` and the status. Its body gives the action of `prim__exit` any
||| result by `believe_me`; its calls are the exit, which does not return.
exitWith : Entry
exitWith = MkEntry (Def (MkQName ["System"] "exitWith"))
                   (Typed (Pi M0 Hole (Pi M0 Hole (Pi Mw Hole (Pi Mw exitCode Hole)))))
                   (Exits Exit)
  where
    exitCode : Shape
    exitCode = Head (Def (MkQName ["System"] "ExitCode")) []

------------------------------------------------------------------------------
-- Outside the language
------------------------------------------------------------------------------

||| A definition the language this compiler implements does not include.
||| The refusal does not depend on the type, so the shape is a hole:
||| validation checks that the library still defines it.
ruledOut : List String -> String -> SomeRule -> Entry
ruledOut ns name rule =
  MkEntry (Def (MkQName ns name)) (Typed Hole) (Forbidden rule)

||| Threads: `Prelude.IO`'s `fork` and `threadWait` and the primitives they
||| call, and all of `System.Concurrency`, whose every public function calls
||| the primitive of its name (`makeMutex` calls `prim__makeMutex`).
threads : List Entry
threads =
  map (\n => ruledOut ["Prelude", "IO"] n (Refusal Threads))
      ["fork", "prim__fork", "threadWait", "prim__threadWait"] ++
  concatMap (\n => [ruledOut concurrency n Threads, ruledOut concurrency ("prim__" ++ n) (Refusal Threads)])
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
processes : List Entry
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
outsideLanguage : List Entry
outsideLanguage =
  threads ++
  map (\n => ruledOut ["Prelude", "IO"] n (Refusal Finalizer)) ["onCollect", "onCollectAny"] ++
  map (\n => ruledOut ["System", "FFI"] n (Refusal RawPointer)) ["prim__malloc", "malloc"] ++
  signals ++ processes

||| The table.
export
recognized : List Entry
recognized =
  naturals ++ arrayLanguage ++ baseList ++ inPlace ++ outsideLanguage ++
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
  , MkEntry (Def (MkQName ["Builtin"] "idris_crash")) (Typed Hole) LibraryCrash ]
