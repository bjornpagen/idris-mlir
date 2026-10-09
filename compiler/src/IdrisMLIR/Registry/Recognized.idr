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
import IdrisMLIR.Rule
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
rewriting = Pi Q0 TypeOfTypes (Pi Q0 Hole (Pi Q0 Hole (Pi Q0 Hole (Pi Q0 equal (Pi Q1 Hole Hole)))))

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
binary result = Pi QW nat (Pi QW nat result)

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
  [ natural types "natToInteger" (Pi QW nat (Prim IntegerP)) (Primitive (Op NatToBig))
  , natural types "integerToNat" (Pi QW (Prim IntegerP) nat) (Primitive (Op NatFromBig))
  , natural types "prim__integerToNat" (Pi QW (Prim IntegerP) nat) (Primitive (Op NatFromBig))
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
-- Index spaces of the in-house array library
------------------------------------------------------------------------------

||| A loop over an array's index space, by its name in `Linear.Array`: the
||| library's definition is the loop in Idris, and the compiler's op is the
||| same loop as one linalg operation.
indexSpace : String -> Shape -> IdrRegionPrim -> Entry
indexSpace name shape p =
  MkEntry (Def (MkQName ["Linear", "Array"] name)) (Typed shape) (ArrayLoop p) [HookShape]

||| The two loops: `prim__generate : forall a . Int -> (Int -> a) -> PrimIO
||| (ArrayData a)` and `prim__foldl : forall a, b . ArrayData a -> b -> (b
||| -> Int -> a -> b) -> PrimIO b`.
indexSpaces : List Entry
indexSpaces =
  [ indexSpace "prim__generate"
      (Pi Q0 TypeOfTypes (Pi QW int (Pi QW (Pi QW int Hole) (Pi Q1 world (ioRes (arrayData Hole))))))
      ArrayGenerate
  , indexSpace "prim__foldl"
      (Pi Q0 TypeOfTypes (Pi Q0 TypeOfTypes
        (Pi QW (arrayData Hole) (Pi QW Hole (Pi QW (Pi QW Hole (Pi QW int (Pi QW Hole Hole)))
          (Pi Q1 world (ioRes Hole)))))))
      ArrayFold ]

------------------------------------------------------------------------------
-- Pointers and the exit
------------------------------------------------------------------------------

||| A cast between pointers, `prim__castPtr : AnyPtr -> Ptr t` or
||| `prim__forgetPtr : Ptr t -> AnyPtr`: a pointer is a handle whatever it
||| points to, so the cast is the identity on its one runtime argument.
pointerCast : String -> Shape -> Entry
pointerCast name shape =
  MkEntry (Def (MkQName ["PrimIO"] name)) (Typed (Pi Q0 TypeOfTypes shape)) IdentityOnLastArgument [IdentityHook]

||| `exitWith : HasIO io => ExitCode -> io a`, at its two erased types, its
||| `HasIO` and the status. Its body gives the action of `prim__exit` any
||| result by `believe_me`; its calls are the exit, which does not return.
exitWith : Entry
exitWith = MkEntry (Def (MkQName ["System"] "exitWith"))
                   (Typed (Pi Q0 Hole (Pi Q0 Hole (Pi QW Hole (Pi QW exitCode Hole)))))
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
  naturals ++ indexSpaces ++ outsideLanguage ++
  [ identity "replace"
  , identity "rewrite__impl"
  , pointerCast "prim__castPtr" (Pi QW anyPtr (ptr Hole))
  , pointerCast "prim__forgetPtr" (Pi QW (ptr Hole) anyPtr)
  , exitWith
  , rootOnly "unsafePerformIO" (Pi Q0 TypeOfTypes (Pi QW (Head (Def (MkQName ["PrimIO"] "IO")) [Hole]) Hole))
  , rootOnly "unsafeCreateWorld" (Pi Q0 TypeOfTypes (Pi Q1 (Pi Q1 (Prim WorldP) Hole) Hole))
  , rootOnly "unsafeDestroyWorld" (Pi Q0 TypeOfTypes (Pi Q1 (Prim WorldP) (Pi QW Hole Hole)))
  , spelling "prim__believe_me"
  , spelling "prim__crash"
  , spelling "believe_me"
  , spelling "idris_crash"
  -- A trusted library may crash with a string (Data.Buffer.getNat's
  -- corrupt length). The spelling above still rejects it in user source,
  -- and a user definition that reaches the function is rejected because
  -- the reach is not from a trusted definition.
  , MkEntry (Def (MkQName ["Builtin"] "idris_crash")) (Typed Hole) LibraryCrash [] ]
