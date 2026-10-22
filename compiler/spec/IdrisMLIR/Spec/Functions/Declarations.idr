-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| A closed program and its functions: `idr.program`, `idr.func`,
||| `idr.call`, `idr.return`, and what each function and each call of it
||| holds of what a run may do.
|||
||| A function's row lives on its op, never in a value's type, since none of
||| its atoms changes how the function is called: the atoms of what a run
||| may do (`row`), the record of what it does through each parameter that
||| admits a part (`untouched`, `bounded`), and Idris's proof that its own
||| loops end (`terminates`). The row is derived from the body's ops by one
||| fold, callees first over the program graph's components, and the
||| function's verifier holds it to cover that fold after every pass; a
||| call keeps a copy of its callee's row and write part, since an op
||| answers MLIR's questions from itself alone, and its symbol-use verifier
||| holds the copy equal. Before the first derivation every function and
||| call claims every atom and every write, which says too much and never
||| too little.
|||
||| A function also carries its signature: grades, index binders, lifetime
||| parameters, whose kind says whether the function puts into them, and
||| the lifetime each scoped parameter and result lives in (`lives_in`); and
||| what it gives back of its arguments (`given_back`), which the optimizer
||| alone proves; and, for a specialized copy, what it is to its origin's
||| recursion (`copy`), which the specializer decides; and the most bytes
||| an active call of it holds that it no longer needs (`frame_bound`),
||| computed from types. A call carries its index arguments, its
||| lifetime operands, its copy of its callee's `lives_in`, and where it
||| stands in its function (`tail_kind`), written with no default by
||| whoever makes the call.
module IdrisMLIR.Spec.Functions.Declarations

import IdrisMLIR.Spec.Core.Vocabulary
import IdrisMLIR.Spec.Effects.Declaration
import IdrisMLIR.Spec.Families.Dialect
import IdrisMLIR.Spec.Control.Flow
import IdrisMLIR.Spec.Lifetimes.Declarations
import IdrisMLIR.Spec.Functions.Tail
import IdrisMLIR.Spec.Functions.Termination
import IdrisMLIR.Spec.Functions.Copy
import IdrisMLIR.Spec.Functions.Parameters
import IdrisMLIR.Spec.Functions.GivenBack
import IdrisMLIR.Spec.Functions.LivesIn

import Data.Fin
import Data.List1
import Data.Vect

%default total

------------------------------------------------------------------------------
-- What a function and a call hold of a run
------------------------------------------------------------------------------

||| A row as the IR holds it, by hand: `effects::Row`, the set of atoms the
||| effect system declares, printed as its atoms' names.
export
rowDirective : Directive
rowDirective = MkDirective
  { name = "Row"
  , args = []
  , doc = brief "a row: the atoms of what a run may do"
  }

||| The row: a set of atoms, every one when the op is built without it, so
||| an op built before any derivation says too much and never too little.
rowSlot : AttrKind
rowSlot = AProperty (HandProperty "::idr::effects::Row" rowDirective "::idr::effects::Row::top()")

||| Where the scoped parameters and results live. Absent, none is scoped.
livesInSlot : AttrKind
livesInSlot = AnAttribute (OurAttr (SomeAttr livesInAttr)) MayBeAbsent

||| The positions, among the parameters (or a call's operands) that admit a
||| write part, of those the function never writes through: increasing,
||| none twice, none negative. Absent, nothing is known untouched.
untouchedSlot : AttrKind
untouchedSlot =
  AnAttribute (Confined (UpstreamAttr DenseI32ArrayAttrC) (NonNegativeArray ::: [StrictlySortedArray]))
              MayBeAbsent

||| The put parameters with a bound. Absent, none has one.
boundedSlot : AttrKind
boundedSlot = AnAttribute (OurAttr (SomeAttr putBoundsAttr)) MayBeAbsent

||| Idris's proof that the function's own loops end. Absent, there is none.
terminatesSlot : AttrKind
terminatesSlot = AnAttribute (OurAttr (SomeAttr terminatesAttr)) MayBeAbsent

||| The most bytes an active call of the function holds that it no longer
||| needs where memory may be acquired, computed from types, which the
||| checked runtime holds each call to. Held as the count itself, so a pass
||| on a worker sets it and makes no attribute; zero when the op is built
||| without it, since before counting no call holds a cell it no longer
||| needs.
frameBoundSlot : AttrKind
frameBoundSlot = AProperty (CountProperty 0)

------------------------------------------------------------------------------
-- idr.program
------------------------------------------------------------------------------

||| The closed program: its functions, every one defined, and the one that
||| runs it, a property of the program, so a function's visibility is read
||| from it and never stored; and the stage the pipeline has brought it to,
||| said once, so no pass finds it by walking the functions. Its region
||| verifier checks the root and runs the program's rules after every op of
||| it is verified, on one thread.
export
programOp : Op 0 0 3 1
programOp = MkOp
  { home = InIdr
  , mnemonic = "program"
  , ins = []
  , outs = []
  , attrs =
      [ MkAttr "sym_name" (AnAttribute (UpstreamAttr SymbolNameAttrC) Required)
      , MkAttr "root" (AnAttribute (UpstreamAttr FlatSymbolRefAttrC) Required)
      , MkAttr "stage" (AProperty (EnumProperty (enumDef stageClosed)))
      ]
  , regions = [MkRegion "body" OneRegion (Sized 1)]
  , traits = [SymbolTable, IsolatedFromAbove, SingleBlock, NoTerminator, SymbolOp]
  , interfaces = []
  , effects = Definition
  , speculation = NotSpeculatable
  , stages = Always
  , meaning = NoFold
  , verify = VerifiesOpAndRegions
  , format = Declared
      [ ValueOf (AttrRef 0), Lit "root", Lit "(", ValueOf (AttrRef 1), Lit ")"
      , Lit "stage", Lit "(", ValueOf (AttrRef 2), Lit ")"
      , AttrDictWithKeyword, ValueOf (RegionRef 0) ]
  , builders = [MkBuilder [ param "::llvm::StringRef" "name"
                          , param "::llvm::StringRef" "root"
                          , param "::idr::Stage" "stage" ]]
  , defaultBuilders = DeclaredOnly
  , members =
      [ MkMember OnObject "FuncOp" "lookupRoot" []
      , MkMember OnObject "::mlir::SymbolTable::Visibility" "getVisibility" []
      , MkMember OnObject "void" "setVisibility"
          [param "::mlir::SymbolTable::Visibility" "visibility"] ]
  , guards = []
  , specializations = []
  , laws = []
  , doc = MkDoc "a closed program: its functions, its root and its stage"
      """
      The one program of its module, the closed world every pass reads. Its
      parent is the module; its first op of that block is it.
      """
  }

------------------------------------------------------------------------------
-- idr.func
------------------------------------------------------------------------------

||| A function of the program and what is known of a run of it. Its
||| visibility is no fact of its own: it is public exactly when it is its
||| program's root. Its body is one block. Its verifier checks that its
||| record, its `lives_in` and its `given_back` name only what its signature
||| has; its region verifier, that its row and record cover what its body
||| does, and where its calls stand. It states its parameters' lifetimes.
||| Inserting and erasing parameters and results are its own implementations
||| of the function interface's methods, so whoever edits its signature,
||| through the op or the interface, moves what it states by position with
||| the positions.
export
funcOp : Op 0 0 13 1
funcOp = MkOp
  { home = InIdr
  , mnemonic = "func"
  , ins = []
  , outs = []
  , attrs =
      [ MkAttr "sym_name" (AnAttribute (UpstreamAttr SymbolNameAttrC) Required)
      , MkAttr "function_type" (AnAttribute (UpstreamAttr TypeAttrC) Required)
      , MkAttr "arg_attrs" (AnAttribute (UpstreamAttr ArrayAttrC) MayBeAbsent)
      , MkAttr "res_attrs" (AnAttribute (UpstreamAttr ArrayAttrC) MayBeAbsent)
      , MkAttr "binders" indexBinders
      , MkAttr "row" rowSlot
      , MkAttr "untouched" untouchedSlot
      , MkAttr "bounded" boundedSlot
      , MkAttr "terminates" terminatesSlot
      , MkAttr "lives_in" livesInSlot
      , MkAttr "given_back" (AnAttribute (OurAttr (SomeAttr givenBackAttr)) MayBeAbsent)
      , MkAttr "copy" (AnAttribute (EnumAttrOf (enumDef copyKindClosed)) MayBeAbsent)
      , MkAttr "frame_bound" frameBoundSlot
      ]
  , regions = [MkRegion "body" OneRegion (Sized 1)]
  , traits = [AffineScope, IsolatedFromAbove, HasParent ("program" ::: [])]
  , interfaces =
      [ Declares FunctionOp []
      , Declares OpAsm ["getDefaultDialect"]
      , Implements erasedBinderInterface ["getBoundSorts"]
      , Implements statesLifetime ["getStatedLifetime", "setStatedLifetime"] ]
  , effects = Definition
  , speculation = NotSpeculatable
  , stages = between Higher Owned
  , meaning = NoFold
  , verify = VerifiesOpAndRegions
  , format = HandFormat
  , builders = []
  , defaultBuilders = WithDefaults
  , members =
      [ MkMember OnObject "::mlir::Region *" "getCallableRegion" []
      , MkMember OnObject "::llvm::ArrayRef<::mlir::Type>" "getArgumentTypes" []
      , MkMember OnObject "::llvm::ArrayRef<::mlir::Type>" "getResultTypes" []
      , MkMember OnObject "::mlir::Type" "cloneTypeWith"
          [param "::mlir::TypeRange" "inputs", param "::mlir::TypeRange" "results"]
      , MkMember OnObject "bool" "isExternal" []
      , MkMember OnObject "ProgramOp" "getProgram" []
      , MkMember OnObject "bool" "isRoot" []
      , MkMember OnObject "::mlir::SymbolTable::Visibility" "getVisibility" []
      , MkMember OnObject "void" "setVisibility"
          [param "::mlir::SymbolTable::Visibility" "visibility"]
      , MkMember OnObject "::idr::Termination" "getTermination" []
      , MkMember OnObject "::mlir::LogicalResult" "insertArguments"
          [ param "::llvm::ArrayRef<unsigned>" "indices", param "::mlir::TypeRange" "types"
          , param "::llvm::ArrayRef<::mlir::DictionaryAttr>" "attrs"
          , param "::llvm::ArrayRef<::mlir::Location>" "locs" ]
      , MkMember OnObject "::mlir::LogicalResult" "insertResults"
          [ param "::llvm::ArrayRef<unsigned>" "indices", param "::mlir::TypeRange" "types"
          , param "::llvm::ArrayRef<::mlir::DictionaryAttr>" "attrs" ]
      , MkMember OnObject "::mlir::LogicalResult" "eraseArguments"
          [param "const ::llvm::BitVector &" "arguments"]
      , MkMember OnObject "::mlir::LogicalResult" "eraseResults"
          [param "const ::llvm::BitVector &" "results"] ]
  , guards = []
  , specializations = []
  , laws = []
  , doc = MkDoc "a function of the program, with what is known of a run of it"
      """
      Its row, its record per parameter, its termination proof, where its
      scoped values live, what it gives back, what kind of copy it is and
      its frame bound are inherent: no pass drops one without changing the
      op. Only the one writer of rows and a clone copying its source write
      the row and the record; only the optimizer writes what it gives back
      and what copy it is.
      """
  }

------------------------------------------------------------------------------
-- idr.call
------------------------------------------------------------------------------

||| A call's effects: its row's ordering atoms and a write on each operand
||| its callee writes through (`Summarized`), the consumption of each owned
||| operand, and a fresh identity for each result something reads the
||| identity of.
callEffects : Declaration 1 1
callEffects = Executes [] [Summarized, Consumes FZ, NewIdentity FZ] Covered Untouched

||| A call of a function by name, with its callee's result types, row,
||| write part and `lives_in`, so upstream's dead code, CSE and sinking, and
||| a pass on the caller, read a call alone: a result's grade says what the
||| callee's signature says of it. It states its scoped results' lifetimes.
export
callOp : Op 1 1 8 0
callOp = MkOp
  { home = InIdr
  , mnemonic = "call"
  , ins = [MkOperand "args" Variadic (UpstreamType AnyTypeC)]
  , outs = [MkResult "results" Variadic (UpstreamType AnyTypeC)]
  , attrs =
      [ MkAttr "callee" (AnAttribute (UpstreamAttr FlatSymbolRefAttrC) Required)
      , MkAttr "index_args" indexArgs
      , MkAttr "tail_kind" (AProperty (EnumProperty (enumDef tailKindClosed)))
      , MkAttr "row" rowSlot
      , MkAttr "untouched" untouchedSlot
      , MkAttr "lives_in" livesInSlot
      , MkAttr "arg_attrs" (AnAttribute (UpstreamAttr ArrayAttrC) MayBeAbsent)
      , MkAttr "res_attrs" (AnAttribute (UpstreamAttr ArrayAttrC) MayBeAbsent)
      ]
  , regions = []
  , traits = []
  , interfaces =
      [ Declares CallOp []
      , Declares SymbolUser ["verifySymbolUses"]
      , Implements flowInterface ["getFlowEdges"]
      , Implements statesLifetime ["getStatedLifetime", "setStatedLifetime"] ]
  , effects = callEffects
  , speculation = Conditionally
  , stages = between Higher Owned
  , meaning = NoFold
  , verify = VerifiesOp
  , format = Declared
      [ ValueOf (AttrRef 0), Lit "(", ValueOf (OperandRef 0), Lit ")", PropDict, AttrDict
      , Lit ":", FunctionalType (OfGroup (OperandRef 0)) (OfGroup (ResultRef 0)) ]
  , builders = [MkBuilder [ param "FuncOp" "callee"
                          , param "::idr::IndexArgsAttr" "indexArgs"
                          , param "::mlir::ValueRange" "args"
                          , param "::idr::TailKind" "tail" ]]
  , defaultBuilders = WithDefaults
  , members =
      [ MkMember OnObject "::mlir::CallInterfaceCallable" "getCallableForCallee" []
      , MkMember OnObject "void" "setCalleeFromCallable"
          [param "::mlir::CallInterfaceCallable" "callee"]
      , MkMember OnObject "::mlir::Operation::operand_range" "getArgOperands" []
      , MkMember OnObject "::mlir::MutableOperandRange" "getArgOperandsMutable" []
      , MkMember OnObject "void" "copyCallee" [param "FuncOp" "callee"] ]
  , guards = []
  , specializations = []
  , laws = []
  , doc = MkDoc "a call of a function by name, with its callee's row"
      """
      Built of a callee, it takes the callee's result types at its index
      arguments, row, write part and lives_in, and takes them again when the
      callee's change; its symbol-use verifier holds the four equal to the
      callee's, and its operand types to the callee's parameters, a lifetime
      of any kind standing where a view is asked. Where it stands is the
      tail calls' to decide and check; a tail call's callee takes as many
      cursors as its caller and gives back the same result components.
      """
  }

------------------------------------------------------------------------------
-- idr.return
------------------------------------------------------------------------------

||| Ends a function's one block, unless the body never returns and ends in
||| an op with no successor.
export
returnOp : Op 1 0 0 0
returnOp = MkOp
  { home = InIdr
  , mnemonic = "return"
  , ins = [MkOperand "operands" Variadic (UpstreamType AnyTypeC)]
  , outs = []
  , attrs = []
  , regions = []
  , traits = [HasParent ("func" ::: []), ReturnLike, Terminator]
  , interfaces = [Implements flowInterface ["getFlowEdges"]]
  , effects = Executes [] [Consumes FZ] Covered Untouched
  , speculation = AlwaysSpeculatable
  , stages = between Higher Owned
  , meaning = NoFold
  , verify = VerifiesOp
  , format = Declared
      [ AttrDict, OptionalGroup [] (ValueOf (OperandRef 0)) [Lit ":", TypeOf (OfGroup (OperandRef 0))] ]
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = brief "returns from a function"
  }

------------------------------------------------------------------------------
-- The area
------------------------------------------------------------------------------

export
declarations : Declarations
declarations =
  { ops := [SomeOp programOp, SomeOp funcOp, SomeOp callOp, SomeOp returnOp]
  , attributes :=
      [ SomeAttr terminatesAttr, SomeAttr putBoundsAttr, SomeAttr livesInAttr
      , SomeAttr givenBackEntryAttr, SomeAttr givenBackAttr ]
  , enums := [enumDef tailKindClosed, enumDef copyKindClosed]
  } nothing
