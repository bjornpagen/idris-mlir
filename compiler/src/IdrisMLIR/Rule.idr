||| The reasons the compiler gives for a rejection, as data, so a misspelt
||| reason is a type error, not a wrong message. Each is shown as the short
||| phrase of `unsupported (<phrase>): ...`. The frontend checks most of
||| them; the ones checked on the optimized module (`RuntimeInteger`,
||| `RuntimeData`, `StringPrimitive`, `RuntimeClosure`, `RuntimeLazy`,
||| `RuntimeString`, `GrowingSpecialization`), `Evaluation` and
||| `CompileBudget` come back from `idris-mlir-cc`, which names them by their
||| phrase (`parseRule`).
module IdrisMLIR.Rule


import Data.List

%default total

public export
data Rule
  = ProgramShape | TrustedLibrary | WorldUse | IOPrimitive
  | ValueType | RuntimeInteger
  | DependentField | RuntimeData | DataType
  | DefinitionShape | Match | StaticArgument
  | Polymorphism | Laziness
  | Primitive | StringPrimitive
  | RuntimeClosure | RuntimeLazy | RuntimeString | GrowingSpecialization
  | EscapeHatch | UserPragma
  | CompiledModule | IdentityHook | HookShape
  | Evaluation | CompileBudget

export
Show Rule where
  show ProgramShape = "program"
  show TrustedLibrary = "library"
  show WorldUse = "world"
  show IOPrimitive = "io primitive"
  show ValueType = "type"
  show RuntimeInteger = "runtime integer"
  show DependentField = "dependent field"
  show RuntimeData = "runtime data"
  show DataType = "data type"
  show DefinitionShape = "definition"
  show Match = "match"
  show StaticArgument = "static argument"
  show Polymorphism = "polymorphism"
  show Laziness = "laziness"
  show Primitive = "primitive"
  show StringPrimitive = "string primitive"
  show RuntimeClosure = "runtime closure"
  show RuntimeLazy = "runtime lazy value"
  show RuntimeString = "runtime string"
  show GrowingSpecialization = "growing specialization"
  show EscapeHatch = "escape hatch"
  show UserPragma = "pragma"
  show CompiledModule = "compiled module"
  show IdentityHook = "identity hook"
  show HookShape = "hook"
  show Evaluation = "compile-time evaluation"
  show CompileBudget = "compile-time budget"

||| Every reason, to read one back from its phrase.
allRules : List Rule
allRules =
  [ ProgramShape, TrustedLibrary, WorldUse, IOPrimitive, ValueType, RuntimeInteger
  , DependentField, RuntimeData, DataType, DefinitionShape, Match, StaticArgument
  , Polymorphism, Laziness, Primitive, StringPrimitive
  , RuntimeClosure, RuntimeLazy, RuntimeString, GrowingSpecialization
  , EscapeHatch, UserPragma, CompiledModule, IdentityHook, HookShape, Evaluation
  , CompileBudget ]

||| A reason by its phrase, as `idris-mlir-cc` reports it.
export
parseRule : String -> Maybe Rule
parseRule phrase = find (\r => show r == phrase) allRules
