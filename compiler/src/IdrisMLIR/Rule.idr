||| The reasons the compiler gives for a rejection, as data, so a misspelt
||| reason is a type error, not a wrong message. Each is shown as the short
||| phrase of `unsupported (<phrase>): ...`. The frontend checks most of
||| them; `CompileBudget`, `Layout`, `Laziness`, `RuntimeClosure`, `Cycle`
||| and `Uniqueness` also come back from `idris-mlir-cc`, which names them by
||| their phrases (`parseRule`). Any other error of `idris-mlir-cc` is the
||| compiler's own, never a rejection.
module IdrisMLIR.Rule


import Data.List

%default total

public export
data Rule
  = ProgramShape | TrustedLibrary | WorldUse | IOPrimitive
  | ValueType
  | DependentField | DictionaryField | DataType
  | DefinitionShape | Match | StaticArgument
  | Polymorphism | Laziness
  | Primitive | StringPrimitive
  | RuntimeClosure
  | EscapeHatch | UserPragma
  | ||| Threads (`fork`, `threadWait`): no scheduler, and shared mutable
    ||| state the counting heap does not have.
    Threads
  | ||| A collector finalizer (`onCollect`). Release is the counting walk;
    ||| nothing runs at collection.
    Finalizer
  | ||| Raw memory (`System.FFI`'s `malloc` and its kin). A pointer of base
    ||| is a handle of the runtime's, and references the compiler keeps are
    ||| heap values it accounts for.
    RawPointer
  | ||| A signal handler, which runs an effect at a time the world does not
    ||| name.
    Signal
  | ||| Process creation (`system`, `popen`), outside the language for now.
    Process
  | ||| A mutable cell whose type can reach itself: counting would leak the
    ||| knot.
    Cycle
  | ||| A value passed shared where a promise asked for it exclusive
    ||| (`--demand-in-place`).
    Uniqueness
  | CompiledModule | IdentityHook | HookShape
  | CompileBudget | Layout
  | ||| A name Idris has deprecated. The message names its replacement.
    Deprecated

export
Show Rule where
  show ProgramShape = "program"
  show TrustedLibrary = "library"
  show WorldUse = "world"
  show IOPrimitive = "io primitive"
  show ValueType = "type"
  show DependentField = "dependent field"
  show DictionaryField = "dictionary field"
  show DataType = "data type"
  show DefinitionShape = "definition"
  show Match = "match"
  show StaticArgument = "static argument"
  show Polymorphism = "polymorphism"
  show Laziness = "laziness"
  show Primitive = "primitive"
  show StringPrimitive = "string primitive"
  show RuntimeClosure = "runtime closure"
  show EscapeHatch = "escape hatch"
  show UserPragma = "pragma"
  show Threads = "threads"
  show Finalizer = "finalizer"
  show RawPointer = "raw pointer"
  show Signal = "signal"
  show Process = "process"
  show Cycle = "cycle"
  show Uniqueness = "uniqueness"
  show CompiledModule = "compiled module"
  show IdentityHook = "identity hook"
  show HookShape = "hook"
  show CompileBudget = "compile-time budget"
  show Layout = "layout"
  show Deprecated = "deprecated"

||| Every reason, to read one back from its phrase.
allRules : List Rule
allRules =
  [ ProgramShape, TrustedLibrary, WorldUse, IOPrimitive, ValueType
  , DependentField, DictionaryField, DataType, DefinitionShape, Match, StaticArgument
  , Polymorphism, Laziness, Primitive, StringPrimitive, RuntimeClosure
  , EscapeHatch, UserPragma, Threads, Finalizer, RawPointer
  , Signal, Process, Cycle, Uniqueness
  , CompiledModule, IdentityHook, HookShape
  , CompileBudget, Layout, Deprecated ]

||| A reason by its phrase, as `idris-mlir-cc` reports it.
export
parseRule : String -> Maybe Rule
parseRule phrase = find (\r => show r == phrase) allRules
