-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| A pass, as the pipeline and its registration read it: its name, the op
||| it runs on, the stages it requires and leaves, its kind (decide, apply,
||| restructure, or check), what it does to the program graph, its counters,
||| the actions it takes, the atoms it may add to a function's row, and the
||| dialects it loads. Only a test's checks are options: nothing selects how
||| a program is compiled. Its C++ base, its constructor and its
||| registration are printed from this.
module IdrisMLIR.Spec.Pipeline.Pass

import IdrisMLIR.Spec.Core.Text
import IdrisMLIR.Spec.Effects.Atom
import IdrisMLIR.Spec.Pipeline.Stage

import Data.List
import Data.List1
-- `moves`'s automatic `LT` proof is searched where the call is written.
import public Data.Nat

%default total

||| What a pass runs on: the module, the program, one of its functions in
||| parallel with the others, or one lowered function after the program is
||| taken apart.
public export
data Anchor = OnModule | OnProgram | OnFunction | OnLoweredFunction

||| The anchor's C++ class.
public export
anchorClass : Anchor -> String
anchorClass OnModule = "::mlir::ModuleOp"
anchorClass OnProgram = "::idr::ProgramOp"
anchorClass OnFunction = "::idr::FuncOp"
anchorClass OnLoweredFunction = "::mlir::LLVM::LLVMFuncOp"

||| Which of the threading's three steps a pass is, or a check: a decide
||| step computes a whole-program answer, makes serially every type and
||| attribute it needs, and runs the apply group the pipeline pairs it with
||| nested in itself; an apply step rewrites functions in parallel, from
||| its own facts or, in a decide step's group, from that step's answer; a
||| restructure step changes the program's shape; a check changes nothing
||| and refuses a program or fails a test.
public export
data PassKind = Decide | Apply | Restructure | Check

||| What a pass does to the program graph the analyses share: keeps it,
||| edits it through its editor, or leaves it to be built again.
public export
data GraphEffect = Keeps | Edits | Invalidates

||| The stages a pass requires and leaves: any, leaving the stage it found;
||| one, which it keeps; or one it requires and a later one it sets. A pass
||| that runs at any stage but sets one cannot be written.
public export
data PassStages : Type where
  AnyStage : PassStages
  At : Stage -> PassStages
  Moves : (from, to : Stage) -> (0 later : LT (rank from) (rank to)) -> PassStages

public export
moves : (from, to : Stage) -> {auto 0 later : LT (rank from) (rank to)} -> PassStages
moves f t = Moves f t later

||| The stage a pass requires, if one.
public export
requires : PassStages -> Maybe Stage
requires AnyStage = Nothing
requires (At s) = Just s
requires (Moves f _ _) = Just f

||| The stage a pass leaves a program at, from the one it found.
public export
leaves : PassStages -> Stage -> Stage
leaves AnyStage s = s
leaves (At s) _ = s
leaves (Moves _ t _) _ = t

||| Whether a pass may run on a program at `s`.
public export
admits : PassStages -> Stage -> Bool
admits AnyStage _ = True
admits (At s) t = rank s == rank t
admits (Moves f _ _) t = rank f == rank t

||| A counter a pass reports: its member's name, its argument and what it
||| counts.
public export
record Statistic where
  constructor MkStatistic
  name : Ident
  argument : Line
  doc : Line

||| A transform a pass takes as an action of MLIR's action framework: its
||| tag after `idr-` (`optimize-node` is `idr-optimize-node`), by which a
||| profile lists it and a debug counter skips it, and what its unit is.
||| Only a transform is one: a skipped one leaves the IR as it was, and
||| valid, so a solve's unit never is.
public export
record Action where
  constructor MkAction
  tag : List1 Word
  doc : Line

||| The action's tag as MLIR's action framework reads it.
public export
actionTag : Action -> String
actionTag a = "idr-" ++ concat (intersperse "-" (map wordText (forget a.tag)))

||| The dialects a pass may create ops of, which its registration loads.
public export
data Loads
  = LoadsIdr | LoadsArith | LoadsMath | LoadsUB | LoadsLLVM | LoadsDLTI
  | LoadsSCF | LoadsCF | LoadsTensor | LoadsLinalg | LoadsBufferization
  | LoadsMemRef | LoadsAffine | LoadsVector

public export
loadsClass : Loads -> String
loadsClass LoadsIdr = "::idr::IdrDialect"
loadsClass LoadsArith = "::mlir::arith::ArithDialect"
loadsClass LoadsMath = "::mlir::math::MathDialect"
loadsClass LoadsUB = "::mlir::ub::UBDialect"
loadsClass LoadsLLVM = "::mlir::LLVM::LLVMDialect"
loadsClass LoadsDLTI = "::mlir::DLTIDialect"
loadsClass LoadsSCF = "::mlir::scf::SCFDialect"
loadsClass LoadsCF = "::mlir::cf::ControlFlowDialect"
loadsClass LoadsTensor = "::mlir::tensor::TensorDialect"
loadsClass LoadsLinalg = "::mlir::linalg::LinalgDialect"
loadsClass LoadsBufferization = "::mlir::bufferization::BufferizationDialect"
loadsClass LoadsMemRef = "::mlir::memref::MemRefDialect"
loadsClass LoadsAffine = "::mlir::affine::AffineDialect"
loadsClass LoadsVector = "::mlir::vector::VectorDialect"

||| A pass's options: none, or a test's list of properties to check, which
||| selects no behaviour of a compilation.
public export
data Options = NoOptions | Holds

||| How a pass is made: by its generated constructor, registered with the
||| others; or, for a step one pass runs inside another or the pipeline
||| runs around a nest, by a hand factory in a namespace given what its
||| maker holds, never registered.
public export
data Construction = Registered | MadeBy CppName (List Ident)

public export
record Pass where
  constructor MkPass
  ||| The pass's argument without its `idr-` prefix: `rc-cells` is
  ||| `idr-rc-cells`, its record `IdrRcCells`, its constructor
  ||| `createIdrRcCells`.
  name : List1 Word
  anchor : Anchor
  stages : PassStages
  kind : PassKind
  graph : GraphEffect
  statistics : List Statistic
  actions : List Action
  ||| The atoms a pass on functions may add to its function's row and its
  ||| calls': the pipeline widens every row by them before the nest the
  ||| pass runs in and writes the rows after it, so each function's row
  ||| covers its body while its siblings run. A pass on the program or the
  ||| module that adds effects writes the rows itself and adds none here.
  adds : List Atom
  options : Options
  loads : List Loads
  construction : Construction
  doc : Doc

||| The pass's command-line argument.
public export
passArgument : Pass -> String
passArgument p = "idr-" ++ concat (intersperse "-" (map wordText (forget p.name)))

||| The pass's record and class stem: `IdrRcCells`.
public export
passRecord : Pass -> String
passRecord p = "Idr" ++ concat (map camel (forget p.name))
