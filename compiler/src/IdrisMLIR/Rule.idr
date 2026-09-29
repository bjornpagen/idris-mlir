||| The reasons the compiler gives for a rejection, as data, so a misspelt
||| reason is a type error, not a wrong message. Each is shown as the short
||| phrase of `unsupported (<phrase>): ...`. The frontend checks most of
||| them; `CompileBudget` comes back from `idris-mlir-cc`, which names it
||| by its phrase (`parseRule`).
module IdrisMLIR.Rule


import Data.List

%default total

public export
data Rule
  = ProgramShape | TrustedLibrary | WorldUse | IOPrimitive
  | ValueType
  | DependentField | DataType
  | DefinitionShape | Match | StaticArgument
  | Polymorphism | Laziness
  | Primitive | StringPrimitive
  | RuntimeClosure
  | EscapeHatch | UserPragma
  | CompiledModule | IdentityHook | HookShape
  | CompileBudget

export
Show Rule where
  show ProgramShape = "program"
  show TrustedLibrary = "library"
  show WorldUse = "world"
  show IOPrimitive = "io primitive"
  show ValueType = "type"
  show DependentField = "dependent field"
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
  show CompiledModule = "compiled module"
  show IdentityHook = "identity hook"
  show HookShape = "hook"
  show CompileBudget = "compile-time budget"

||| Every reason, to read one back from its phrase.
allRules : List Rule
allRules =
  [ ProgramShape, TrustedLibrary, WorldUse, IOPrimitive, ValueType
  , DependentField, DataType, DefinitionShape, Match, StaticArgument
  , Polymorphism, Laziness, Primitive, StringPrimitive, RuntimeClosure
  , EscapeHatch, UserPragma, CompiledModule, IdentityHook, HookShape
  , CompileBudget ]

||| A reason by its phrase, as `idris-mlir-cc` reports it.
export
parseRule : String -> Maybe Rule
parseRule phrase = find (\r => show r == phrase) allRules
