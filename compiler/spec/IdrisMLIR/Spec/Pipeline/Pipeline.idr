-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| idris-mlir's pipeline, from the frontend's program to the LLVM dialect,
||| as one list: every pass, in order, with why it is where it is. Its type
||| proves the stages chain (each pass starts at the stage the one before
||| left) and that every pass runs on the op it is anchored on, nested where
||| it may be. The C++ builds the pass manager from the printed list, the
||| registration and each pass's base from the printed records, and the
||| frontend and the harness import it; it is held nowhere else. Nothing
||| chooses among passes: every program runs every one, so what a
||| compilation runs is what the tests run.
|||
||| Acceptance comes before optimization: the program as the frontend wrote
||| it is defunctionalized, its knots refused and its in-place promises
||| decided, all total and with no budget, before any pass that only makes
||| code faster or smaller runs. Where the program holds our ops the
||| e-graph simplifies, as nothing greedy does; after lowering, where only
||| upstream's ops are, nothing simplifies but upstream's own conversions,
||| and LLVM cleans what they leave.
module IdrisMLIR.Spec.Pipeline.Pipeline

import IdrisMLIR.Spec.Core.Text
import IdrisMLIR.Spec.Pipeline.Stage
import IdrisMLIR.Spec.Pipeline.Pass

import Data.List
import Data.List1
import Data.So

%default total

------------------------------------------------------------------------------
-- Upstream's passes the pipeline runs
------------------------------------------------------------------------------

||| Upstream's passes the pipeline names, each run as upstream ships it:
||| none is re-implemented or configured but the schedule's interpreter,
||| which is given the library's entry point.
public export
data UpstreamPass
  = SymbolDCE
  | ScheduleInterpreter
  | LinalgToLoops
  | VectorToSCF
  | ExpandStridedMetadata
  | LowerAffine
  | VectorToLLVM
  | ConvertToLLVM
  | ReconcileUnrealizedCasts

||| The C++ expression that makes the pass: upstream's constructor, or the
||| one hand factory in the pipeline's unit that configures the
||| interpreter.
public export
upstreamMake : UpstreamPass -> String
upstreamMake SymbolDCE = "::mlir::createSymbolDCEPass()"
upstreamMake ScheduleInterpreter = "::idr::scheduleInterpreter()"
upstreamMake LinalgToLoops = "::mlir::createConvertLinalgToLoopsPass()"
upstreamMake VectorToSCF = "::mlir::createConvertVectorToSCFPass()"
upstreamMake ExpandStridedMetadata = "::mlir::memref::createExpandStridedMetadataPass()"
upstreamMake LowerAffine = "::mlir::createLowerAffinePass()"
upstreamMake VectorToLLVM = "::mlir::createConvertVectorToLLVMPass()"
upstreamMake ConvertToLLVM = "::mlir::createConvertToLLVMPass()"
upstreamMake ReconcileUnrealizedCasts = "::mlir::createReconcileUnrealizedCastsPass()"

||| The anchors each may run on.
public export
upstreamAnchors : UpstreamPass -> List Anchor
upstreamAnchors SymbolDCE = [OnProgram, OnModule]
upstreamAnchors ScheduleInterpreter = [OnLoweredFunction]
upstreamAnchors LinalgToLoops = [OnLoweredFunction]
upstreamAnchors VectorToSCF = [OnLoweredFunction]
upstreamAnchors ExpandStridedMetadata = [OnLoweredFunction]
upstreamAnchors LowerAffine = [OnLoweredFunction]
upstreamAnchors VectorToLLVM = [OnModule]
upstreamAnchors ConvertToLLVM = [OnModule]
upstreamAnchors ReconcileUnrealizedCasts = [OnModule]

public export
Eq Anchor where
  OnModule == OnModule = True
  OnProgram == OnProgram = True
  OnFunction == OnFunction = True
  OnLoweredFunction == OnLoweredFunction = True
  _ == _ = False

------------------------------------------------------------------------------
-- The pipeline's type
------------------------------------------------------------------------------

||| Which anchor's passes may run nested in which: a program's functions in
||| the program, the program in the module, the lowered functions in the
||| module.
public export
data Nests : (inner, outer : Anchor) -> Type where
  FunctionsOfProgram : Nests OnFunction OnProgram
  ProgramOfModule : Nests OnProgram OnModule
  LoweredOfModule : Nests OnLoweredFunction OnModule

||| Whether a pass on `a` may change the program's stage: a function's
||| pass runs beside its siblings, which read the stage, so only a pass on
||| the program or the module may.
public export
mayMove : Anchor -> PassStages -> Bool
mayMove OnProgram _ = True
mayMove OnModule _ = True
mayMove _ (Moves _ _ _) = False
mayMove _ _ = True

||| A pipeline of passes on `a`, from stage `s` to stage `t`.
public export
data Pipeline : (a : Anchor) -> (s, t : Stage) -> Type where
  Done : Pipeline a s s
  Run : (p : Pass) -> (why : Line)
     -> {auto 0 here : p.anchor = a}
     -> {auto 0 starts : So (admits p.stages s)}
     -> {auto 0 still : So (mayMove a p.stages)}
     -> Pipeline a (leaves p.stages s) u -> Pipeline a s u
  RunUpstream : (u : UpstreamPass) -> (why : Line)
     -> {auto 0 placed : So (elem a (upstreamAnchors u))}
     -> Pipeline a s t -> Pipeline a s t
  Nest : (inner : Anchor) -> {auto 0 nests : Nests inner a}
     -> Pipeline inner s t -> Pipeline a t u -> Pipeline a s u

------------------------------------------------------------------------------
-- The passes
------------------------------------------------------------------------------

public export
stat : Ident -> Line -> Line -> Statistic
stat = MkStatistic

||| `idr-target`: the module's target, from the build's target entry. The
||| driver runs it first, and every later step reads the target there.
public export
target : Pass
target = MkPass ("target" ::: []) OnModule AnyStage Apply Keeps [] NoOptions [LoadsLLVM, LoadsDLTI] Registered
  (MkDoc "Give the module its target: triple, CPU, features, data layout"
     "Writes the build's target triple and CPU on the module as its `#llvm.target`, lets LLVM\nfill in the CPU's features and the data layout, and writes the module's target system\nspec: for the device `CPU`, the width in bits of its fixed vector registers. The triple\nand the CPU are the build's target entry; every later step reads them here.")

public export
defunctionalize : Pass
defunctionalize = MkPass ("defunctionalize" ::: []) OnProgram (moves Higher First) Restructure Invalidates
  [ stat "numFamilies" "families" "Closure and memo families declared, one constructor per label" ]
  NoOptions [LoadsUB] Registered
  (MkDoc "Replace every closure and suspension by a constructor of a sum, every force by a call"
     "On the program as the frontend wrote it, before any optimization: the label solve,\ntotal and with no budget, decides what each application can meet; each closure sum is a\nfamily the pass declares, each label a constructor; every apply becomes a dispatch of\ndirect calls and every force a call of its sum's dispatch. Its decision builds the\nprogram graph and derives every function's effect row, callees first.")

public export
knots : Pass
knots = MkPass ("knots" ::: []) OnProgram (At First) Check Keeps [] NoOptions [] Registered
  (MkDoc "Refuse a program whose types let a value reach itself, which counting could never free"
     "Right after defunctionalization, where every closure is a constructor of a sum, so a\nknot of references is a cycle of the type graph; total, with no budget.")

public export
inPlace : Pass
inPlace = MkPass ("in" ::: ["place"]) OnProgram (At First) Apply Edits [] NoOptions [LoadsIdr] Registered
  (MkDoc "Decide every in-place promise on the program as the frontend wrote it"
     "Before any optimization: a function that takes apart a quantity-1 parameter of an\nin-place family and builds one from it rebuilds it. Each obligation becomes the grade\n`unique self` on its parameter and each rebuild a linear token consumed by its rebuild;\na call the exclusivity analysis cannot prove exclusive is refused at the user's call.")

public export
deduplicate : Pass
deduplicate = MkPass ("deduplicate" ::: []) OnProgram (At First) Restructure Edits
  [ stat "numGroups" "groups" "Classes of identical functions merged"
  , stat "numMerged" "merged" "Duplicate functions erased" ]
  NoOptions [LoadsIdr] Registered
  (MkDoc "Keep one of each class of functions with identical bodies"
     "Once, after acceptance, on the first-order program: partition refinement over upstream's\noperation equivalence, inside call-graph cycles too, each class keeping its first in\nsymbol order.")

public export
contify : Pass
contify = MkPass ("contify" ::: []) OnProgram (At First) Restructure Edits
  [ stat "numContified" "contified" "Functions made join points of their callers" ]
  NoOptions [LoadsIdr] Registered
  (MkDoc "Make each function every call of which returns to one continuation a join point there"
     "Fluet and Weeks on regions: one dominator tree over functions and their return points;\na call it moves out of tail position has its tail fact rewritten by the one definition.")

public export
optimize : Pass
optimize = MkPass ("optimize" ::: []) OnProgram (At First) Restructure Edits
  [ stat "numNodes" "nodes" "Functions made for a specialization key"
  , stat "numRedirected" "redirected" "Calls redirected to a specialization"
  , stat "numInlinedLeaves" "inlined-leaves" "Calls of a final leaf inlined"
  , stat "numConstants" "constants" "Values replaced by a constant" ]
  NoOptions [LoadsIdr, LoadsArith] Registered
  (MkDoc "Specialize each function to completion, bottom-up over the call graph"
     "Specialization by closure label, layout class, hold and lifetime mode, each key\nfinite, with leaf inlining inside; the e-graph simplifies each function as its\ncomponent is taken up.")

public export
inline : Pass
inline = MkPass ("inline" ::: []) OnProgram (At First) Restructure Edits
  [ stat "numInlined" "inlined" "Calls inlined"
  , stat "numCapped" "capped" "Calls kept because inlining would pass the caller's cap" ]
  NoOptions [LoadsIdr] Registered
  (MkDoc "Inline once on the final call graph, the e-graph as the inliner's simplification"
     "Upstream's inliner, its verdict from true call counts; the e-graph simplifies what it\ninlines, where the greedy driver would.")

public export
columns : Pass
columns = MkPass ("columns" ::: []) OnProgram (At First) Restructure Edits [] NoOptions
  [LoadsTensor, LoadsIdr] Registered
  (MkDoc "Hold a tensor of records as one tensor per leaf of the record" "")

public export
simplify : Pass
simplify = MkPass ("simplify" ::: []) OnFunction AnyStage Apply Edits [] NoOptions
  [LoadsIdr, LoadsArith, LoadsUB] Registered
  (MkDoc "Simplify a function on an e-graph over its ops, where our ops are"
     "Rules from the specification applied at insertion, effectful ops in a skeleton\nordered per resource, extraction by cost; a call is deleted or moved only where its\nrow carries neither crash nor divergence. Its budget is nodes per op from the program\nalone: a spent budget leaves the function less simplified, never refused.")

public export
structureLoops : Pass
structureLoops = MkPass ("structure" ::: ["loops"]) OnFunction (At First) Apply Keeps
  [ stat "numParallel" "parallel" "Word ops made parallel linalg ops" ]
  NoOptions [LoadsLinalg, LoadsTensor, LoadsArith] Registered
  (MkDoc "Turn the pure word ops over arrays into linalg ops" "")

public export
bufferize : Pass
bufferize = MkPass ("bufferize" ::: []) OnProgram (At First) Restructure Edits
  [ stat "numAllocs" "allocs" "Buffers allocated"
  , stat "numInPlace" "in-place" "Tensor operands bufferized in place"
  , stat "numCopies" "copies" "Tensor operands bufferized out of place" ]
  NoOptions [LoadsBufferization, LoadsMemRef, LoadsTensor] Registered
  (MkDoc "Put every array in a buffer, in place wherever its grade allows"
     "Upstream's One-Shot over graded tensors: a quantity-1 array is updated in place, read\nfrom its grade, never searched for links.")

public export
accumulate : Pass
accumulate = MkPass ("accumulate" ::: []) OnProgram (At First) Restructure Edits
  [ stat "numFunctions" "functions" "Functions given an accumulator clone"
  , stat "numTails" "tails" "Self calls combined by an associative operation made tail calls" ]
  NoOptions [] Registered
  (MkDoc "Make a recursion combined in a tail by an exactly associative operation a tail call with an accumulator" "")

public export
rcCells : Pass
rcCells = MkPass ("rc" ::: ["cells"]) OnFunction (At First) Apply Keeps
  [ stat "numCells" "cells" "Constructors of a cell made its allocation and initialization" ]
  NoOptions [LoadsIdr] Registered
  (MkDoc "Make each constructor of a cell the cell's allocation and its initialization" "")

public export
lifetimes : Pass
lifetimes = MkPass ("lifetimes" ::: []) OnProgram (moves First Graded) Restructure Edits
  [ stat "numLifetimes" "lifetimes" "Lifetimes opened" ]
  NoOptions [LoadsIdr] Registered
  (MkDoc "Decide every lifetime: its opener, its kind, the signatures and the copies by mode"
     "One decide step, callees first: every lifetime is born decided, its kind what it is at\nrun time and its opener where its memory comes from, each with its proof that it keeps\nthe frame limit; a cell no proof covers stays counted.")

public export
rcBorrows : Pass
rcBorrows = MkPass ("rc" ::: ["borrows"]) OnProgram (At Graded) Decide Keeps
  [ stat "numBorrowed" "borrowed" "Parameters borrowed" ]
  NoOptions [LoadsIdr] Registered
  (MkDoc "Write into every signature which parameters are borrowed"
     "One backward marking over the closed program within the frame limit: a parameter is\nborrowed only where every call lets it be.")

public export
rcPlace : Pass
rcPlace = MkPass ("rc" ::: ["place"]) OnFunction (At Graded) Apply Keeps
  [ stat "numDups" "dups" "References duplicated"
  , stat "numDrops" "drops" "References dropped" ]
  NoOptions [LoadsIdr] Registered
  (MkDoc "Place every duplicate and drop at its value's last use, and specialize drops" "")

public export
rcExclusive : Pass
rcExclusive = MkPass ("rc" ::: ["exclusive"]) OnProgram (moves Graded Owned) Restructure Edits
  [ stat "numExclusive" "exclusive" "Values that hold the only reference to their cells"
  , stat "numContexts" "contexts" "Calling contexts the marking solved"
  , stat "numCopies" "copies" "Grade copies made for a reached context"
  , stat "numRounds" "rounds" "Rounds of the marking to its fixpoint" ]
  NoOptions [LoadsIdr, LoadsUB] Registered
  (MkDoc "Prove which values hold the only reference to their cells, and commit it to grades"
     "The marking over the program graph, by context mask, with one grade copy per reached\nkey; every reference is counted from here on.")

public export
rcReuse : Pass
rcReuse = MkPass ("rc" ::: ["reuse"]) OnFunction (At Owned) Apply Keeps
  [ stat "numReuses" "reuses" "Cells recycled from a dead value" ]
  NoOptions [LoadsIdr] Registered
  (MkDoc "Recycle each dead cell into a construction its size fits, guided by the drops placed" "")

public export
rcExpand : Pass
rcExpand = MkPass ("rc" ::: ["expand"]) OnFunction (At Owned) Apply Keeps [] NoOptions
  [LoadsIdr, LoadsSCF] Registered
  (MkDoc "Expand each take into its two-region uniqueness match, folded by grade" "")

public export
trmc : Pass
trmc = MkPass ("trmc" ::: []) OnProgram (At Owned) Restructure Edits
  [ stat "numFunctions" "functions" "Functions given a destination-passing clone"
  , stat "numTails" "tails" "Contexts around a self call that became tail calls" ]
  NoOptions [] Registered
  (MkDoc "Make each recursion that returns its own result inside a context a loop with a destination" "")

public export
frames : Pass
frames = MkPass ("frames" ::: []) OnProgram (At Owned) Restructure Edits
  [ stat "numFunctions" "functions" "Functions given a run and a resume"
  , stat "numFrames" "frames" "Calls whose rest became a frame" ]
  NoOptions [LoadsUB] Registered
  (MkDoc "Keep every recursion on a call cycle on typed frame stacks, never the native stack"
     "One linear, uncounted, contiguous stack per awaited result: every non-tail call of a\ncomponent pushes its rest as a frame, so the native stack holds only acyclic depth.")

public export
tailLoops : Pass
tailLoops = MkPass ("tail" ::: ["loops"]) OnFunction (At Owned) Apply Keeps
  [ stat "numLoops" "loops" "Functions whose self tail calls became a loop" ]
  NoOptions [LoadsSCF, LoadsUB] Registered
  (MkDoc "Turn self tail calls into loops" "")

public export
narrow : Pass
narrow = MkPass ("narrow" ::: []) OnProgram (At Owned) Restructure Edits
  [ stat "numVersioned" "versioned" "Loops versioned on a small descending natural" ]
  NoOptions [LoadsArith, LoadsSCF] Registered
  (MkDoc "Make the bigs and naturals proved to fit a small plain words" "")

public export
narrowWords : Pass
narrowWords = MkPass ("narrow" ::: ["words"]) OnFunction (At Owned) Apply Keeps [] NoOptions
  [LoadsArith, LoadsUB] Registered
  (MkDoc "Make the bigs and naturals of one function proved to fit a small words" "")

public export
orderedLoops : Pass
orderedLoops = MkPass ("ordered" ::: ["loops"]) OnFunction (At Owned) Apply Keeps [] NoOptions
  [LoadsSCF, LoadsArith, LoadsMemRef] Registered
  (MkDoc "Lower each generating op still in the IR to its ordered loop nest"
     "Right before the lowering, on the buffer forms counting ran on: each generating op\nbecomes `scf.for` loops through upstream's tiling interface.")

public export
lowerRuntime : Pass
lowerRuntime = MkPass ("lower" ::: ["runtime"]) OnProgram (At Owned) Apply Keeps [] NoOptions
  [LoadsLLVM] Registered
  (MkDoc "Declare every runtime function the program's ops call, once" "")

public export
lowerStatics : Pass
lowerStatics = MkPass ("lower" ::: ["statics"]) OnProgram (At Owned) Apply Keeps [] NoOptions
  [LoadsLLVM] Registered
  (MkDoc "Make every static datum the program's constants need, once" "")

public export
lower : Pass
lower = MkPass ("lower" ::: []) OnProgram (moves Owned Lowered) Restructure Invalidates [] NoOptions
  [LoadsArith, LoadsSCF, LoadsUB, LoadsLLVM, LoadsCF, LoadsMath, LoadsMemRef, LoadsAffine] Registered
  (MkDoc "Lower each function to the LLVM dialect: llvm.func, llvm.call, llvm.return built directly"
     "Each function on its own, in parallel: every idr op and type takes its runtime layout,\nthe join ops lower with upstream's SCF patterns in one conversion, a call in tail\nposition becomes a musttail call under tailcc, and a function's row becomes LLVM's\nattributes.")

public export
lowerControl : Pass
lowerControl = MkPass ("lower" ::: ["control"]) OnLoweredFunction AnyStage Restructure Keeps [] NoOptions
  [LoadsCF, LoadsSCF, LoadsLLVM] Registered
  (MkDoc "Lower the join points and every structured op left to blocks, in one conversion"
     "Upstream's scf patterns and the join points' on upstream's own target, so a jump nested\nin a match is a branch by then and an irreducible group lowers with no run-time\nselector: the one place blocks appear.")

public export
entry : Pass
entry = MkPass ("entry" ::: []) OnModule (At Lowered) Restructure Invalidates [] NoOptions
  [LoadsLLVM] Registered
  (MkDoc "Take the program apart: its functions into the module, its root the module's entry" "")

public export
narrowLanes : Pass
narrowLanes = MkPass ("narrow" ::: ["lanes"]) OnLoweredFunction AnyStage Apply Keeps
  [ stat "numNarrowed" "narrowed" "Vectorized loops given a 32-bit version" ]
  NoOptions [LoadsArith, LoadsSCF, LoadsVector] Registered
  (MkDoc "Run the integer lanes of each vectorized loop in 32 bits under a bound on the sizes" "")

public export
tailCalls : Pass
tailCalls = MkPass ("tail" ::: ["calls"]) OnModule AnyStage Apply Keeps [] NoOptions
  [LoadsLLVM] Registered
  (MkDoc "End each musttail call's block with the return of its results"
     "After the conversion to LLVM: the materialization of the tail fact each call already\ncarries; LLVM's verifier is the last check.")

public export
expect : Pass
expect = MkPass ("expect" ::: []) OnModule AnyStage Check Keeps [] Holds
  [LoadsIdr, LoadsArith, LoadsMath, LoadsUB, LoadsMemRef, LoadsTensor, LoadsSCF] Registered
  (MkDoc "Check named properties of the module, and change nothing"
     "A test's check: each property in `holds` reports every place it fails, and the pass\nfails if any does.")

||| The steps of idr-optimize's run that are passes, made by its factories
||| from what one run holds; never registered.
public export
redirect : Pass
redirect = MkPass ("redirect" ::: []) OnFunction AnyStage Apply Edits [] NoOptions []
  (MadeBy (ident "idr" ::: [ident "specialize", ident "createRedirect"]) [ident "schedule", ident "nodes", ident "redirected"])
  (MkDoc "Call the specialization each call's key names"
     "The first step of each round of idr-optimize's inner pipeline, so a combinator called on\nknown closures is a call of its copy before the e-graph sees the caller.")

public export
inlineLeaves : Pass
inlineLeaves = MkPass ("inline" ::: ["leaves"]) OnFunction AnyStage Apply Edits [] NoOptions []
  (MadeBy (ident "idr" ::: [ident "inlining", ident "createInlineLeaves"]) [ident "schedule", ident "inlined"])
  (MkDoc "Inline each call of a final callee whose body is a leaf"
     "The second step of idr-optimize's inner pipeline, while the caller stays within its cap.")

public export
constants : Pass
constants = MkPass ("constants" ::: []) OnFunction AnyStage Apply Keeps [] NoOptions []
  (MadeBy (ident "idr" ::: [ident "optimize", ident "createConstants"]) [ident "schedule", ident "constants"])
  (MkDoc "Propagate constants through one function, calls through their callees' summaries" "")

||| Every pass, registered or made inside another, in the order their
||| records are printed.
public export
passes : List Pass
passes =
  [ target, defunctionalize, knots, inPlace, deduplicate, contify, optimize, inline
  , columns, simplify, structureLoops, bufferize, accumulate, rcCells, lifetimes
  , rcBorrows, rcPlace, rcExclusive, rcReuse, rcExpand, trmc, frames, tailLoops
  , narrow, narrowWords, orderedLoops, lowerRuntime, lowerStatics, lower, entry, narrowLanes, lowerControl
  , tailCalls, expect, redirect, inlineLeaves, constants ]

------------------------------------------------------------------------------
-- The pipeline
------------------------------------------------------------------------------

||| The program's functions, simplified where our ops are.
public export
simplified : Line -> Pipeline OnProgram s u -> Pipeline OnProgram s u
simplified why rest = Nest OnFunction (Run simplify why Done) rest

||| The program's passes, from the frontend's program to the lowered one.
public export
programPipeline : Pipeline OnProgram Higher Lowered
programPipeline =
  Run defunctionalize "acceptance first: every closure a constructor, every force a call, on the program as written" $
  Run knots "where every closure is a constructor, a knot of references is a cycle of the type graph" $
  Run inPlace "the in-place promise read off the program before any optimization can move it" $
  Run deduplicate "once, on the first-order program, after acceptance, so no merge changes a verdict" $
  Run contify "while each continuation still returns to the one place it was made for" $
  Run optimize "each function once, after its callees are final" $
  Run inline "once, on the final call graph, with true call counts" $
  Run contify "again, where inlining made new join points" $
  RunUpstream SymbolDCE "the functions the optimizer left no use of" $
  Run columns "a tensor of records becomes its columns on the optimized bodies" $
  simplified "what the columns leave for folding" $
  Nest OnFunction (Run structureLoops "on final bodies, the pure word ops become linalg" Done) $
  Run bufferize "before counting, which sees buffers" $
  simplified "what bufferization leaves" $
  Run accumulate "while a self call's result is still the operand of the operation a tail returns" $
  Nest OnFunction (Run rcCells "memory explicit: each constructor of a cell its allocation and initialization" Done) $
  Run lifetimes "every lifetime decided before a reference is counted" $
  Run rcBorrows "the conventions of every parameter, from the closed program" $
  Nest OnFunction (Run rcPlace "drops first, at last use" Done) $
  Run rcExclusive "on the references placement made" $
  Nest OnFunction (Run rcReuse "reuse guided by the drops placed and the exclusivity proved" Done) $
  Nest OnFunction (Run rcExpand "the take's expansion, counting's last step" Done) $
  RunUpstream SymbolDCE "the grade copies no call kept" $
  Run trmc "after counting, which held the scrutinee's token across the self call" $
  Run frames "after counting and TRMC, so reuse tokens ride in frames" $
  Nest OnFunction (Run tailLoops "after frames, a self tail call a loop" Done) $
  Run narrow "after counting, whose counts of the bigs it proves small it removes" $
  Nest OnFunction (Run orderedLoops "the generating ops as loops, right before the lowering" Done) $
  Run lowerRuntime "every runtime function declared before any function is lowered" $
  Run lowerStatics "every static datum made before any function is lowered" $
  Run lower "each function to the LLVM dialect" $
  Done

||| The whole pipeline, on the module that holds the program.
public export
pipeline : Pipeline OnModule Higher Lowered
pipeline =
  Nest OnProgram programPipeline $
  Run entry "the program taken apart, its root the module's entry" $
  Nest OnLoweredFunction
    ( RunUpstream ScheduleInterpreter "each loop over an array on the target's vector lanes" $
      Run narrowLanes "the integer lanes in 32 bits under a bound on the sizes" $
      RunUpstream LinalgToLoops "the loops the schedule left" $
      RunUpstream VectorToSCF "transfers of a rank above one to loops of 1-D ones" $
      RunUpstream ExpandStridedMetadata "views to offsets" $
      RunUpstream LowerAffine "the affine arithmetic of the offsets" $
      Run lowerControl "the join points and the loops upstream's lowering made, to blocks, in one conversion" $
      Done ) $
  RunUpstream VectorToLLVM "the vector ops, with their pre-lowering" $
  RunUpstream ConvertToLLVM "everything else" $
  RunUpstream ReconcileUnrealizedCasts "the casts the conversions left" $
  Run tailCalls "on the final control flow, each musttail call's block ended by its return" $
  Done
