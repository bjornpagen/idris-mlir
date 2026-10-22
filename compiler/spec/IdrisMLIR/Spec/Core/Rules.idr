-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The rules a refusal of a program names, indexed by the kind of program
||| each refuses, so a refusal of one kind cannot be given a rule of
||| another: a megamorphic construct, whose choices at a site no
||| compile-time analysis bounds; a construct outside the language this
||| compiler compiles, or one a total analysis proves the program cannot
||| meet (a knot counting could never free, an in-place promise shared);
||| and a program Idris itself rejects. No limit of the compiler's is a
||| kind: a limit is lifted by a representation, never refused. Each rule
||| carries the phrase a refusal is shown with and where it is decided. The
||| frontend and the harness import this; the C++ reads the printed enum and
||| its tables; a refusal is an op of the module whose rule is a property.
module IdrisMLIR.Spec.Core.Rules

import IdrisMLIR.Spec.Core.Text
import IdrisMLIR.Spec.Core.Enums

import Data.List.Elem
import Data.List1

%default total

public export
data Category = Megamorphic | OutsideLanguage | UserError

||| Where a rule is decided: by the frontend, reading the program as Idris
||| checked it, or by a total analysis of the pipeline over the first-order
||| program, before any optimization.
public export
data Scope = Frontend | Pipeline

public export
data Rule : Category -> Type where
  ||| A type in a run-time position, chosen by a run-time value.
  ValueType : Rule Megamorphic
  DependentField : Rule Megamorphic
  ||| A recursion that builds its type or dictionary deeper at each call.
  Polymorphism : Rule Megamorphic
  ||| A closure whose label set no analysis bounds.
  RuntimeClosure : Rule Megamorphic
  ProgramShape : Rule OutsideLanguage
  TrustedLibrary : Rule OutsideLanguage
  DataType : Rule OutsideLanguage
  DefinitionShape : Rule OutsideLanguage
  Match : Rule OutsideLanguage
  Primitive : Rule OutsideLanguage
  StringPrimitive : Rule OutsideLanguage
  ||| `%foreign`, an extern exported as C, a C calling convention: there is
  ||| no C interop.
  EscapeHatch : Rule OutsideLanguage
  UserPragma : Rule OutsideLanguage
  ||| Threads: no scheduler, and shared mutable state the counting heap
  ||| does not have.
  Threads : Rule OutsideLanguage
  ||| A collector finalizer: release is counting's, nothing runs at a
  ||| collection.
  Finalizer : Rule OutsideLanguage
  ||| Raw memory (`System.FFI`'s `malloc` and kin).
  RawPointer : Rule OutsideLanguage
  ||| A signal handler, which runs an effect at a time no order names.
  Signal : Rule OutsideLanguage
  ||| Process creation.
  Process : Rule OutsideLanguage
  CompiledModule : Rule OutsideLanguage
  HookShape : Rule OutsideLanguage
  ||| A name Idris has deprecated; the message names its replacement.
  Deprecated : Rule OutsideLanguage
  ||| A call the exclusivity analysis cannot prove exclusive where the
  ||| in-place promise needs its value's own cells alone.
  Uniqueness : Rule OutsideLanguage
  ||| A reference knot counting could never free.
  Cycle : Rule OutsideLanguage
  ||| A runtime the compiler cannot link as it is.
  Runtime : Rule OutsideLanguage
  ||| A program Idris does not elaborate; the refusal carries Idris's own
  ||| message.
  Elaboration : Rule UserError

||| A rule of any category, the one closed set the C++ enum is printed
||| from.
public export
data SomeRule : Type where
  Refusal : {c : Category} -> Rule c -> SomeRule

public export
category : SomeRule -> Category
category (Refusal {c} _) = c

||| The words a refusal by the rule is shown with: `unsupported (<phrase>)`.
public export
phrase : Rule c -> List1 Word
phrase ValueType = word "type" ::: []
phrase DependentField = word "dependent" ::: [word "field"]
phrase Polymorphism = word "polymorphism" ::: []
phrase RuntimeClosure = word "runtime" ::: [word "closure"]
phrase ProgramShape = word "program" ::: []
phrase TrustedLibrary = word "library" ::: []
phrase DataType = word "data" ::: [word "type"]
phrase DefinitionShape = word "definition" ::: []
phrase Match = word "match" ::: []
phrase Primitive = word "primitive" ::: []
phrase StringPrimitive = word "string" ::: [word "primitive"]
phrase EscapeHatch = word "escape" ::: [word "hatch"]
phrase UserPragma = word "pragma" ::: []
phrase Threads = word "threads" ::: []
phrase Finalizer = word "finalizer" ::: []
phrase RawPointer = word "raw" ::: [word "pointer"]
phrase Signal = word "signal" ::: []
phrase Process = word "process" ::: []
phrase CompiledModule = word "compiled" ::: [word "module"]
phrase HookShape = word "hook" ::: []
phrase Deprecated = word "deprecated" ::: []
phrase Uniqueness = word "uniqueness" ::: []
phrase Cycle = word "cycle" ::: []
phrase Runtime = word "runtime" ::: []
phrase Elaboration = word "elaboration" ::: []

public export
scope : Rule c -> Scope
scope Uniqueness = Pipeline
scope Cycle = Pipeline
scope _ = Frontend

public export
ruleName : Rule c -> Ident
ruleName ValueType = ident "ValueType"
ruleName DependentField = ident "DependentField"
ruleName Polymorphism = ident "Polymorphism"
ruleName RuntimeClosure = ident "RuntimeClosure"
ruleName ProgramShape = ident "ProgramShape"
ruleName TrustedLibrary = ident "TrustedLibrary"
ruleName DataType = ident "DataType"
ruleName DefinitionShape = ident "DefinitionShape"
ruleName Match = ident "Match"
ruleName Primitive = ident "Primitive"
ruleName StringPrimitive = ident "StringPrimitive"
ruleName EscapeHatch = ident "EscapeHatch"
ruleName UserPragma = ident "UserPragma"
ruleName Threads = ident "Threads"
ruleName Finalizer = ident "Finalizer"
ruleName RawPointer = ident "RawPointer"
ruleName Signal = ident "Signal"
ruleName Process = ident "Process"
ruleName CompiledModule = ident "CompiledModule"
ruleName HookShape = ident "HookShape"
ruleName Deprecated = ident "Deprecated"
ruleName Uniqueness = ident "Uniqueness"
ruleName Cycle = ident "Cycle"
ruleName Runtime = ident "Runtime"
ruleName Elaboration = ident "Elaboration"

public export
categoryClosed : Closed Category
categoryClosed = MkClosed
  { name = ident "RuleCategory"
  , shape = OneOf
  , every = Megamorphic ::: [OutsideLanguage, UserError]
  , complete = \case
      Megamorphic => Here
      OutsideLanguage => There Here
      UserError => There (There Here)
  , describe = \case
      Megamorphic => MkCase (ident "Megamorphic") (word "megamorphic" ::: []) (line "a construct whose choices at a site no compile-time analysis bounds")
      OutsideLanguage => MkCase (ident "OutsideLanguage") (word "outside" ::: [word "the", word "language"]) (line "a construct outside the language, or one a total analysis proves the program cannot meet")
      UserError => MkCase (ident "UserError") (word "user" ::: [word "error"]) (line "a program Idris itself rejects")
  , doc = brief (line "the kind of program a refusal names")
  }

public export
scopeClosed : Closed Scope
scopeClosed = MkClosed
  { name = ident "RuleScope"
  , shape = OneOf
  , every = Frontend ::: [Pipeline]
  , complete = \case
      Frontend => Here
      Pipeline => There Here
  , describe = \case
      Frontend => MkCase (ident "Frontend") (word "frontend" ::: []) (line "decided by the frontend, on the program as Idris checked it")
      Pipeline => MkCase (ident "Pipeline") (word "pipeline" ::: []) (line "decided by a total analysis on the first-order program, before any optimization")
  , doc = brief (line "where a rule is decided")
  }

||| Every rule, in declaration order: the printed enum's order.
public export
everyRule : List1 SomeRule
everyRule =
  Refusal ValueType :::
  [ Refusal DependentField, Refusal Polymorphism
  , Refusal RuntimeClosure, Refusal ProgramShape
  , Refusal TrustedLibrary, Refusal DataType, Refusal DefinitionShape
  , Refusal Match, Refusal Primitive, Refusal StringPrimitive
  , Refusal EscapeHatch, Refusal UserPragma, Refusal Threads
  , Refusal Finalizer, Refusal RawPointer, Refusal Signal, Refusal Process
  , Refusal CompiledModule, Refusal HookShape, Refusal Deprecated
  , Refusal Uniqueness, Refusal Cycle, Refusal Runtime, Refusal Elaboration
  ]

||| The position of each rule in everyRule, by case: the list's order.
public export
ruleIn : (r : SomeRule) -> Elem r (forget everyRule)
ruleIn (Refusal ValueType) = Here
ruleIn (Refusal DependentField) = There Here
ruleIn (Refusal Polymorphism) = There (There Here)
ruleIn (Refusal RuntimeClosure) = There (There (There Here))
ruleIn (Refusal ProgramShape) = There (There (There (There Here)))
ruleIn (Refusal TrustedLibrary) = There (There (There (There (There Here))))
ruleIn (Refusal DataType) = There (There (There (There (There (There Here)))))
ruleIn (Refusal DefinitionShape) = There (There (There (There (There (There (There Here))))))
ruleIn (Refusal Match) = There (There (There (There (There (There (There (There Here)))))))
ruleIn (Refusal Primitive) = There (There (There (There (There (There (There (There (There Here))))))))
ruleIn (Refusal StringPrimitive) = There (There (There (There (There (There (There (There (There (There Here)))))))))
ruleIn (Refusal EscapeHatch) = There (There (There (There (There (There (There (There (There (There (There Here))))))))))
ruleIn (Refusal UserPragma) = There (There (There (There (There (There (There (There (There (There (There (There Here)))))))))))
ruleIn (Refusal Threads) = There (There (There (There (There (There (There (There (There (There (There (There (There Here))))))))))))
ruleIn (Refusal Finalizer) = There (There (There (There (There (There (There (There (There (There (There (There (There (There Here)))))))))))))
ruleIn (Refusal RawPointer) = There (There (There (There (There (There (There (There (There (There (There (There (There (There (There Here))))))))))))))
ruleIn (Refusal Signal) = There (There (There (There (There (There (There (There (There (There (There (There (There (There (There (There Here)))))))))))))))
ruleIn (Refusal Process) = There (There (There (There (There (There (There (There (There (There (There (There (There (There (There (There (There Here))))))))))))))))
ruleIn (Refusal CompiledModule) = There (There (There (There (There (There (There (There (There (There (There (There (There (There (There (There (There (There Here)))))))))))))))))
ruleIn (Refusal HookShape) = There (There (There (There (There (There (There (There (There (There (There (There (There (There (There (There (There (There (There Here))))))))))))))))))
ruleIn (Refusal Deprecated) = There (There (There (There (There (There (There (There (There (There (There (There (There (There (There (There (There (There (There (There Here)))))))))))))))))))
ruleIn (Refusal Uniqueness) = There (There (There (There (There (There (There (There (There (There (There (There (There (There (There (There (There (There (There (There (There Here))))))))))))))))))))
ruleIn (Refusal Cycle) = There (There (There (There (There (There (There (There (There (There (There (There (There (There (There (There (There (There (There (There (There (There Here)))))))))))))))))))))
ruleIn (Refusal Runtime) = There (There (There (There (There (There (There (There (There (There (There (There (There (There (There (There (There (There (There (There (There (There (There Here))))))))))))))))))))))
ruleIn (Refusal Elaboration) = There (There (There (There (There (There (There (There (There (There (There (There (There (There (There (There (There (There (There (There (There (There (There (There Here)))))))))))))))))))))))

public export
ruleClosed : Closed SomeRule
ruleClosed = MkClosed
  { name = ident "Rule"
  , shape = OneOf
  , every = everyRule
  , complete = ruleIn
  , describe = describeRule
  , doc = brief (line "the rule a refusal of a program names")
  }
  where
    describeRule : SomeRule -> Case
    describeRule (Refusal r) = MkCase (ruleName r) (phrase r) (line "a rule of the language this compiler compiles")

||| The rules' facts the C++ reads: each rule's category and scope.
public export
ruleTable : Table
ruleTable = table ruleClosed
  [ MkColumn (ident "categoryOf") (EnumColumn (enumDef categoryClosed))
      (\r => CaseCell (caseRef categoryClosed (category r))) (line "the kind of program the rule refuses")
  , MkColumn (ident "scopeOf") (EnumColumn (enumDef scopeClosed))
      (\r => CaseCell (caseRef scopeClosed (scopeOfSome r))) (line "where the rule is decided")
  ]
  where
    scopeOfSome : SomeRule -> Scope
    scopeOfSome (Refusal r) = scope r
