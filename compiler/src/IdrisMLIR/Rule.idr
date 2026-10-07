||| The reasons the compiler gives for a rejection, as data, so a misspelt
||| reason is a type error, not a wrong message. Each is shown as the short
||| phrase of `unsupported (<phrase>): ...`. The frontend checks most of
||| them; `CompileBudget` and `Layout` also come back from `idris-mlir-cc`,
||| which names them by their phrases (`parseRule`). Any other error of
||| `idris-mlir-cc` is the compiler's own, never a rejection.
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
  | ||| A raw pointer, or a value read through one (`getEnv`). References
    ||| the compiler keeps are heap values it accounts for.
    RawPointer
  | CompiledModule | IdentityHook | HookShape
  | CompileBudget | Layout

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
  show CompiledModule = "compiled module"
  show IdentityHook = "identity hook"
  show HookShape = "hook"
  show CompileBudget = "compile-time budget"
  show Layout = "layout"

||| Every reason, to read one back from its phrase.
allRules : List Rule
allRules =
  [ ProgramShape, TrustedLibrary, WorldUse, IOPrimitive, ValueType
  , DependentField, DictionaryField, DataType, DefinitionShape, Match, StaticArgument
  , Polymorphism, Laziness, Primitive, StringPrimitive, RuntimeClosure
  , EscapeHatch, UserPragma, Threads, Finalizer, RawPointer
  , CompiledModule, IdentityHook, HookShape
  , CompileBudget, Layout ]

||| A reason by its phrase, as `idris-mlir-cc` reports it.
export
parseRule : String -> Maybe Rule
parseRule phrase = find (\r => show r == phrase) allRules
