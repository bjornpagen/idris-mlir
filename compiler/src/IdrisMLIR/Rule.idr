||| The reasons the frontend gives for a rejection, as data, so a misspelt
||| reason is a type error, not a wrong message. Each is shown as the short
||| phrase of `unsupported (<phrase>): ...`, and only shown: the pipeline
||| rejects with phrases of its own, which it prints itself.
module IdrisMLIR.Rule

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
  | CompiledModule | IdentityHook | HookShape
  | CompileBudget
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
  show CompiledModule = "compiled module"
  show IdentityHook = "identity hook"
  show HookShape = "hook"
  show CompileBudget = "compile-time budget"
  show Deprecated = "deprecated"
