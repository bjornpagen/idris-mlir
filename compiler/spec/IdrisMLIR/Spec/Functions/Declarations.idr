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
||| A function also carries its signature: grades, index binders, and
||| lifetime parameters, whose kind says whether the function puts into
||| them. A call carries its index arguments, its lifetime operands, and
||| where it stands in its function (`tail`), written with no default by
||| whoever makes the call.
module IdrisMLIR.Spec.Functions.Declarations

import IdrisMLIR.Spec.Core.Vocabulary
import IdrisMLIR.Spec.Effects.Declaration
import IdrisMLIR.Spec.Families.Dialect
import IdrisMLIR.Spec.Control.Flow
import IdrisMLIR.Spec.Functions.Tail
import IdrisMLIR.Spec.Functions.Termination
import IdrisMLIR.Spec.Functions.Parameters

import Data.Fin
import Data.List1
import Data.Vect

%default total

------------------------------------------------------------------------------
-- What a function and a call hold of a run
------------------------------------------------------------------------------

||| The row: a set of atoms, every one when the op is built without it.
rowSlot : AttrKind
rowSlot = AProperty (DefaultedEnumProperty (enumDef atomClosed) "::idr::effects::Row::top()")

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
||| program's root. Its body is one block. Its region verifier checks that
||| its row and record cover what its body does, and where its calls stand.
export
funcOp : Op 0 0 9 1
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
      ]
  , regions = [MkRegion "body" OneRegion (Sized 1)]
  , traits = [AffineScope, IsolatedFromAbove, HasParent ("program" ::: [])]
  , interfaces =
      [ Declares FunctionOpInterfaceI []
      , Declares OpAsmOpInterfaceI ["getDefaultDialect"]
      , Implements erasedBinderInterface ["getBoundSorts"] ]
  , effects = Definition
  , speculation = NotSpeculatable
  , stages = between Higher Owned
  , meaning = NoFold
  , verify = VerifiesRegions
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
      , MkMember OnObject "::idr::Termination" "getTermination" [] ]
  , guards = []
  , specializations = []
  , laws = []
  , doc = MkDoc "a function of the program, with what is known of a run of it"
      """
      Its row, its record per parameter and its termination proof are
      inherent: no pass drops one without changing the op, and only the one
      writer of rows and a clone copying its source write the row and the
      record.
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

||| A call of a function by name, with its callee's row and write part, so
||| upstream's dead code, CSE and sinking read a call alone.
export
callOp : Op 1 1 7 0
callOp = MkOp
  { home = InIdr
  , mnemonic = "call"
  , ins = [MkOperand "args" Variadic (UpstreamType AnyTypeC)]
  , outs = [MkResult "results" Variadic (UpstreamType AnyTypeC)]
  , attrs =
      [ MkAttr "callee" (AnAttribute (UpstreamAttr FlatSymbolRefAttrC) Required)
      , MkAttr "index_args" indexArgs
      , MkAttr "tail" (AProperty (EnumProperty (enumDef tailKindClosed)))
      , MkAttr "row" rowSlot
      , MkAttr "untouched" untouchedSlot
      , MkAttr "arg_attrs" (AnAttribute (UpstreamAttr ArrayAttrC) MayBeAbsent)
      , MkAttr "res_attrs" (AnAttribute (UpstreamAttr ArrayAttrC) MayBeAbsent)
      ]
  , regions = []
  , traits = []
  , interfaces =
      [ Declares CallOpInterfaceI []
      , Declares SymbolUserOpInterfaceI ["verifySymbolUses"]
      , Declares OpAsmOpInterfaceI ["getAsmResultNames"]
      , Implements flowInterface ["getFlowEdges"] ]
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
                          , param "::mlir::TypeRange" "results"
                          , param "::mlir::ValueRange" "args"
                          , param "::idr::TailKind" "tail" ]]
  , defaultBuilders = WithDefaults
  , members =
      [ MkMember OnObject "::mlir::CallInterfaceCallable" "getCallableForCallee" []
      , MkMember OnObject "void" "setCalleeFromCallable"
          [param "::mlir::CallInterfaceCallable" "callee"]
      , MkMember OnObject "::mlir::Operation::operand_range" "getArgOperands" []
      , MkMember OnObject "::mlir::MutableOperandRange" "getArgOperandsMutable" [] ]
  , guards = []
  , specializations = []
  , laws = []
  , doc = MkDoc "a call of a function by name, with its callee's row"
      """
      Built of a callee, it takes the callee's row and write part; its
      symbol-use verifier holds both equal to the callee's, and its operand
      types to the callee's parameters, a lifetime of any kind standing where
      a view is asked. Where it stands is the tail calls' to decide and check.
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
  , attributes := [SomeAttr terminatesAttr, SomeAttr putBoundsAttr]
  , enums := [enumDef tailKindClosed]
  , directives := [proofDirective, boundDirective]
  } nothing
