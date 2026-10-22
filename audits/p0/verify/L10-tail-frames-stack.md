<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# L10: tail calls, frames, the stack

Lane L10 of the P0 verification swarm. Rulings in scope: D30, D31, D32,
D33, D34; coordinator decisions C4 and C5 (the stack's sizes). HEAD
`e96bb991` at start (2026-10-21T21:31Z) and at finish; the tree read as
it stands, dirty with the coordinator's P0 work. Nothing built, run or
type-checked. Grounds: *read* (path:line at HEAD, or the pinned tree
`.toolchain/llvm-project` at 7208ba24), *measured* (a `grep`/`wc` named
beside it), *recalled* (not in `sources/`, not re-read), *conjecture*,
*derivation* (follows from the cited facts), *decision* (a ruling Dn or
Cn). Paths under `foreign/idr/` drop that prefix; `llvm/…` and `mlir/…`
are the pinned tree.

Read for this file: the representation-first skill and AGENTS.md whole;
the proposal whole; `audits/p0/10-tail.md` whole; 13 (the stack, threads,
the pipeline); 18 (the stack, the runner, oom-4, oom-7); 21 (16005000,
P-10); `design/match-and-counting.md` §5.3 (option 6, the `musttail`
row), §6, §7, §8, §9; G's DP-38. Code: `lib/Transforms/Tail/` whole,
`lib/Conversion/{TailCalls,TailCallPlan,TailPosition,Frame,PassThroughMemory,ReturnRegisters}.cpp`
and their headers, `lib/IR/Tail.cpp` and `include/idr/IR/Tail.h`,
`include/idr/Transforms/Tail.h`, `lib/Transforms/Stack/Stack.cpp`,
`lib/Analysis/Recursion.cpp`, `lib/Analysis/Ownership/Borrows.cpp:225-245`,
`lib/IR/Lifetimes.cpp:50-75`, `lib/IR/Func/Inliner.cpp` (head),
`lib/Driver/{Artifacts,LinkRuntime}.cpp` (code generation, the runtime's
bitcode), `runtime/Start/{Runner,Entry}.cpp`, `Start.h`,
`runtime/Platform/Posix/{Stacks,Memory}.cpp`, `include/idr/Support/Stack.h`,
`PINS.md:585-605`, `upstream/30-aarch64-sibcall-callee-pop/`,
`upstream/10-recursive-attribute-parser/README.md`; in the pinned LLVM,
`llvm/docs/LangRef.md` (the `tailcc` and `musttail` rules),
`llvm/docs/CodeGenerator.md` (tail call section), `llvm/lib/IR/Verifier.cpp`
(`verifyMustTailCall`), AArch64's and x86-64's call lowering, the stack
size reporting of `PrologEpilogInserter` and `AsmPrinter`; in MLIR, every
recursion named in §1 D33. The wave-1 lane `5.3-llvm.md` has no tail-call
material (*measured*: `grep -n -i "tail\|musttail" wave1/5.3-llvm.md`); the
`musttail` material the dispatch points to is match-and-counting §5.3's
option 6 and §9 step 7, read.

## 1. Verification

Each claim: verdict, evidence, and one class (defect confirmed in the
source; structural incompleteness; integration mismatch; unverified
behaviour; optional simplification).

### D30: proper tail calls

1. **"Every call of the program in tail position, on a cycle or not, is a
   jump: a loop, a join point, or `musttail` with `tailcc`."** *Holds* as
   the design. Today only a tail call whose caller and callee share a
   cycle is made `musttail` (*read*: `TailCallPlan.cpp:118-127`, the
   cycle condition `cycles.together(fn, callee)` at :123;
   `TailCalls.cpp:11-17` says a call between cycles "is left an ordinary
   call"). *Structural incompleteness* of today's code against the ruling.

2. **"Every call is direct … so nothing stands between a tail call and
   its guarantee."** *Holds with a correction*: no indirection stands in
   the way, but five passes and one representation do, each able to turn
   a call in tail position into a call that returns to its caller:
   - idr-returned-arguments drops a result of a tail callee without
     dropping the matching result of its caller, which puts a use of the
     argument after the call (*read*: `ReturnedArguments.cpp:59-82`, no
     test of tail position; the replacement at :77-78). *Defect confirmed
     in the source*; counterexample in §4 I-2.
   - Borrow inference makes a parameter owned at a tail call only when
     caller and callee share a cycle (*read*: `Borrows.cpp:236-241`), so a
     tail call off any cycle may pass an owned value to a borrowed
     parameter, and the caller's drop then follows the call. *Integration
     mismatch* with D30 (§4 I-3).
   - The stack inference keeps off the frame only what a tail call *on
     its caller's cycle* takes (*read*: `Stack.cpp:229-241`), so an off-cycle
     tail call may take a stack cell, which `musttail` forbids (LangRef:
     "the callee does not access any value derived from the caller's stack
     frame", `llvm/docs/LangRef.md:14105-14111`). *Integration mismatch*
     (§4 I-4).
   - idr-tail-loops' general loop writes "this tail returns" as an `i1`
     flag and a poisoned half in an `scf.while` payload (*read*:
     `Loop.cpp:7-14, 77-111`), so no structural reading can see that a
     non-self call before such a yield is in tail position; today's
     second definition exists to decide that flag on the LLVM CFG
     ("past conditions the path decides (the exit flag a loop's tail
     passes as a constant)", `TailCalls.cpp:30-38`; the walk,
     `TailPosition.cpp:209-238`). *Structural incompleteness*; the seam is
     L09's (the recursive join point replaces the payload).
   - The lowering's call op: `func.call` holds `callee`, operands,
     argument and result attributes and `no_inline`, nothing else
     (*read*: `mlir/include/mlir/Dialect/Func/IR/FuncOps.td:52-58`), and
     `convert-func-to-llvm` carries only discardable attributes onto
     `llvm.call` (*read*: `mlir/lib/Conversion/FuncToLLVM/FuncToLLVM.cpp:603-611`);
     a fact in a discardable attribute is forbidden (AGENTS.md). Today
     `idr.call` becomes `func.call` (*read*: `FuncToFunc.cpp:54`). *Integration
     mismatch*; G's DP-38 ("our function and call ops stay … lowered onto
     `llvm.call`", *read*: `synthesis/G-coordinator-decisions.md:194-206`)
     is the seam, not yet folded into §3.
   - "A runtime op is a primitive, not a call of the program" *holds*: the
     runtime's ABI header has one function-pointer parameter, the
     runner's (*measured*: `grep -n "(\*" runtime/idris_rt.h`, one hit,
     `:311`), so no runtime entry calls program code and no cycle runs
     through a C frame of ours.

3. **"One fact per call: decided once, held on the call, verified, and
   lowered to `llvm.call`'s tail kind; every pass obeys it."** *Holds with
   a correction* on the verifier's shape and the fact's direction:
   - `llvm.call` has the carrier, `tail_call_kind`, an inherent
     attribute (*read*: `mlir/include/mlir/Dialect/LLVMIR/LLVMOps.td:2571-2592`).
   - A check run by each call's own verifier must climb the chain of tail
     matches, O(depth) per call per verification; a generated `else if`
     ladder of d branches nests d matches (D33's own example), so the
     verification after every pass is O(d²) on it (*derivation* from
     `IR/Tail.cpp:23-35`, whose climb this is). The verifier is instead
     `idr.func`'s region verifier, one top-down walk per function
     (iterative), plus the call's `verifySymbolUses` for the callee's
     result types.
   - The fact is an obligation, not a mirror: `tail` implies the shape (the
     results pass unchanged to the function's return); the shape does not
     imply `tail`. Held both ways it would be derivable from the shape and
     "a copy kept in step by a verifier" (AGENTS.md). It is not derivable
     in general: a pass that inserts an op after the call destroys the
     shape, and the property is what makes that a verifier error instead
     of a silent loss; and after lowering the shape is a CFG path, which
     is exactly the walk D30 deletes.
   - The builders take the kind with no default (§2.1), so a pass that
     creates a call cannot forget it. Sites that build `idr.call` today: 15
     in 8 files (*measured*: `grep -rn "CallOp::create\|replaceOpWithNewOp<CallOp>" lib | grep -v "func::\|LLVM::"`),
     plus the frontend's builder (`compiler/src/IdrisMLIR/Dialect/Idr.idr:236-240`)
     and the inliner (`lib/IR/Func/Inliner.cpp`).

4. **"The stack inference puts no cell in a frame a tail call may reach;
   a result returned through memory forwards the caller's own slot."**
   *Holds with a correction*. The forwarding exists (*read*:
   `PassThroughMemory.cpp:61-72`, the tail call passes its caller's `out`).
   The first half is today two analyses that must agree, kept in step by
   comments (`Stack.cpp:33-40`; `TailCalls.cpp:47-52`) and re-checked
   conservatively by a points-to walk (`Frame.cpp:28-61`) whose `leaked`
   flag makes every call of a function frame-bound once one frame pointer
   is stored anywhere (`Frame.cpp:53-55`). Under D40 it is one type rule on
   the call: a `tail` call's operands carry no lifetime that ends with
   this call (`frame`, or a lifetime bound inside the function), which the
   stack inference must honour and the verifier checks; `Frame.cpp` goes
   (§4 I-4). *Optional simplification* that becomes required once every
   tail call is `musttail`.

5. **"A failure is a compiler bug, an internal error, never a silent call
   and never a refusal; it never rests on a budget."** *Holds*. Two LLVM
   paths must end there too: LLVM's verifier rejects a malformed
   `musttail` (*read*: `llvm/lib/IR/Verifier.cpp:4392-4464`), and code
   generation calls `report_fatal_error("failed to perform tail call
   elimination on a call site marked musttail")` when it cannot
   (`llvm/lib/Target/AArch64/AArch64ISelLowering.cpp:10535-10537`;
   `llvm/lib/Target/X86/X86ISelLoweringCall.cpp:2172-2174`). Both are
   reached only through a compiler bug once §2.1's rules hold; the
   driver's LLVM fatal-error handler must map them to D37's
   internal-error ending (*conjecture* that it does not today: not
   searched).

6. **"Deleted: the four deciders of tail position (`IR/Tail.cpp`'s climb,
   `TailPosition.cpp`'s walk, the stack pass's and frames' and TRMC's own
   readings), idr-tail-calls' cycle condition and its silent fallback
   (`numFrameBound`, `TailCallPlan.cpp:108-113`)."** *Holds with a
   correction* on the list. There are two *definitions* of tail position
   (`IR/Tail.cpp:23-35`; `TailPosition.cpp:283-330`) and four *deciders*
   of "a tail call on its caller's cycle": `Borrows.cpp:236-237`,
   `Stack.cpp:233-234`, `Recursion.cpp:33-35`, `TailCallPlan.cpp:106, 123`
   (10 §3.1). Frames, TRMC, accumulation and tail loops read the first
   definition; they are readers, not deciders. Readers of either
   definition or of the cycle test span 19 files (*measured*:
   `grep -rnE "inTailPosition\(|endsTail\(|passesOnPrevious\(|tailMatch\(|forTails\(|reachesTailCall\(|inTailPositionModuloContext\(|loopsInFrame\(|\.together\(" lib include | cut -d: -f1 | sort -u`).
   `Recursion` loses its only reader too (§1 D32 item 8). The fallback is
   as cited (*read*: `TailCallPlan.cpp:108-113`, counted at
   `TailCalls.cpp:142`, reported only as a statistic, `Passes.td:887`).

7. **"Cost to measure, never a reason to weaken: `tailcc` on every
   function of the program that only the module's calls reach."**
   *Holds*. The cost on x86-64: a `tailcc` callee pops its stack argument
   area, aligned with an extra slot even when empty, which every caller
   takes back (*read*: `TailCalls.cpp:21-24`). Second cost, not in D30:
   `upstream/30-aarch64-sibcall-callee-pop` (a `tailcc` function with
   stack arguments that makes a sibling call to a C function returns with
   its argument area still on the stack; *read*: its README) reaches every
   such function once every internal function is `tailcc`; the patch and
   its test stay. Taking D30 literally also deletes the plan: a function's
   convention becomes a fact of its own kind (internal, so `tailcc`), not
   of its callers (§4 I-1).

8. **LLVM's real constraints, per target** (the obligation's checklist;
   each *read*):

   | constraint | source | what our side guarantees |
   | --- | --- | --- |
   | the call immediately precedes `ret`, which returns the call's value or nothing | `LangRef.md:14179-14182`; `Verifier.cpp:4411-4415` | the materialization step (§2.1) splits the block after the call and returns its results, sound because the verified property says the path returns them unchanged |
   | caller's and callee's return types identical, even under `tailcc` (only *parameters* may differ) | `Verifier.cpp:4400-4401`, checked before the `tailcc` branch; `LangRef.md:14196-14200` | `verifySymbolUses` on a `tail` call: the callee's results equal the caller's modulo grades with no run-time form; frames' runs and resumes all return nothing (§2.3) |
   | calling conventions equal | `Verifier.cpp:4404-4406`; x86 `X86ISelLoweringCall.cpp:2148-2152` | every internal function `tailcc`; every call of one carries `tailcc` (`TailCalls.cpp:109-121` does this today) |
   | no varargs | `LangRef.md:14184-14186`; `Verifier.cpp:4437-4439` | `idr.func` has no variadic form |
   | under `tailcc` no `inalloca`, `inreg`, `swifterror`, `preallocated`, `byref` on either side | `Verifier.cpp:4357-4369, 4418-4434` | the lowering emits none (*measured*: `grep -rn "byval\|sret\|inreg" lib include`, nothing) |
   | AArch64: a caller with any `byval` parameter makes no tail call, even under `tailcc` | `AArch64ISelLowering.cpp:10086-10093`, before the guarantee at :10114-10115 | no `byval` on internal functions, by the closed set of argument attributes the lowering writes |
   | the return not demoted to a hidden `sret` pointer | `LangRef.md:14187`; the demotion makes codegen's tail test fail | results that do not fit the return registers go through an explicit `noalias` pointer (`PassThroughMemory.cpp:49-59`), the fit asked of the target (`ReturnRegisters.cpp:54-74`, `CanLowerReturn` under `CallingConv::Tail`) |
   | x86-64 PIC: tail calls only to module-local callees (for non-guaranteed TCO) | `CodeGenerator.md:1787-1788` | tail callees are private, address never taken |
   | AArch64 GlobalISel cannot lower a `musttail` it rejects and falls back | `llvm/lib/Target/AArch64/GISel/AArch64CallLowering.cpp:1426-1431` | nothing: SelectionDAG then decides |
   | SME streaming changes forbid TCO | `AArch64ISelLowering.cpp:10059-10067` | no SME attributes are emitted |

   Pointer-to-frame: covered by item 4. Nothing here is per-target in our
   code: each target's answer is LLVM's (the fit question asks the
   target's own lowering).

### D31: typed frame stacks

1. **"idr-frames rebuilt as a typed, linear, uncounted, contiguous stack
   of frames."** *Holds* as the design; today a frame is a counted heap
   cell of a per-component data type (*read*: `Frames.cpp:166-167`, the
   push an `idr.con` of the stack box; `FramesTypes.cpp:23-41`).
   *Structural incompleteness.*

2. **"One stack per result type (lane 10 D2), so a frame of the wrong
   type is unrepresentable."** *Holds with a correction*: one stack
   *type* per awaited result type, over one physical stack per thread.
   Separate physical stacks per type would also be correct (the frame on
   top of the logical stack awaits T, every frame pushed after it has been
   popped, so it is the top of T's stack: *derivation*), but would cost a
   top pointer per type and lose D31's "contiguous". The precision is in
   the type: today's single stack type makes each resume enumerate every
   frame and put `ub.unreachable` in those of another type (*read*:
   `Frames.cpp:229-240`), R·(F+1) regions for R result types and F
   frames, and each member's `fromAnswer` R cases (`FramesTypes.cpp:84-94`).
   §2.3 makes the stack a D48 family indexed by the awaited type, so the
   resume's match has only the frames that await its type.

3. **"The per-pair clone (the 43 GB wall, 16005000) has nothing to do."**
   *Holds*: 16005000 already made one run per member and one resume per
   result type (*read*: 10 §3.1, `git show 16005000` cited there); the
   residue is the impossible regions of item 2.

4. **"Each frame pushed once and popped by one resume, so never counted
   (D10)."** *Holds only once the stack is linear*. Today the stack is an
   unrestricted box (*read*: `Frames.cpp:217, 277`), so a field popped
   from it is bound at quantity ω (`Grades.h:193-200`: a field of a value
   used many times is used many times), and each held value is then
   re-entered at its own quantity by `heldAs` (`Frames.cpp:243-244`;
   `Grades.h:202-204`: "entered into a linear type"); the answer is
   re-entered the same way (`FramesTypes.cpp:91`). A quantity Idris proved
   is dropped at the push and re-asserted at the pop with nothing checking
   that the frame kept it. *Defect confirmed in the source* (a QTT fact
   lost and forged); §3.

5. **"A push a bump and stores, a pop a bump, chunks given back as it
   shrinks."** *Holds with two corrections*: a pop is a bump and one
   predictable compare against the chunk's base (the alternative, a guard
   page per chunk and a fault per crossing, puts a signal on the boundary
   and a second fault kind in the handler); and one emptied chunk is kept
   as a spare, else a push and pop alternating at a boundary cost an
   allocator call each (*derivation*). §2.3.

6. **"A frame an escaped join point (D19), reuse tokens carried in it."**
   *Integration mismatch with today's pipeline*: a reuse token exists only
   after counting, and frames runs before it (*read*:
   `Pipeline.cpp:122-128`). Corrected in §4 I-7: frames runs after
   counting and TRMC, where a token live across a framed call is a held
   value like any other, and D24's promise survives a non-tail rebuild
   across a cycle.

7. **"It transforms the call's continuation, never the monad's binds."**
   *Holds* (*read*: `Frames.cpp:5-17`, the rest of a call's block).

8. **"Its three silent gaps close by representation: frames hold several
   results and values of any type; a component's members share one
   row."** *Holds with a correction*. The three are, *read*:
   `FramesPlan.cpp:151` (a member with other than one result: the whole
   component keeps its calls), `:170-171` (a result type no constructor
   field may hold, `isFieldType`), `:157-160` (members whose `effects`
   differ). The third is not a gap to close but a dead branch to delete:
   under D22 a call carries its callee's row, and on a cycle each member
   reaches every other, so each row contains every other and all are
   equal (*derivation*). And there are four more silent gaps D31 does not
   name, each a stack growth with no word said (*read*): a block whose
   rest calls a member again in non-tail position gets no frame
   (`FramesPlan.cpp:87-99`, `callsAgain`); only sites in tail blocks are
   looked at (`framesFrom`, `:108-118`); only sites with one result
   (`:61`); only calls of closure labels (`:64`, "a recursion over data
   keeps its calls", `Frames.cpp:48-49`), the last by design until D32.
   Each closes under D32's construction (§2.3, §4 I-8). P-10 of lane 21 is
   the second gap.

9. **"A failure is an internal error."** *Holds*; today each gap is
   silent (no remark, no statistic: *read*, the three returns cited).

10. **"Not promised: constant memory for the nesting."** *Holds*.

### D32: the native stack small and statically bounded

1. **"Every recursion on a call cycle keeps its depth on D31's typed
   frame stacks: a non-tail call on a cycle pushes its rest as a
   frame."** *Holds* as the design; it requires frames to reach every
   region op that can hold a non-tail call on a cycle, not only today's
   first closure run of a tail block (item 8 of D31). The ops: matches,
   join points, and, depending on the pipeline position, loops and the
   array generating ops (a recursion through a generator's body). §2.3
   gives the construction. *Structural incompleteness.*

2. **"The native stack then holds only the program's acyclic call
   depth."** *Holds under five conditions*, each named: (a) no runtime
   entry calls program code (*read*, D30 item 2); (b) every program call
   is direct (D30; *decision*); (c) LLVM's optimizer introduces no call
   cycle (*recalled*: no LLVM pass adds recursion); (d) the runtime's own
   bitcode, which is linked into the program's module (*read*:
   `LinkRuntime.cpp:3-4`), has an acyclic call graph (*unverified
   behaviour*: measurement in §2.4 step 1); (e) external code (GMP, the C
   library) recurses to a bounded depth (*unverified*: GMP's
   divide-and-conquer multiplication recurses on operand size, *recalled*).
   §2.4 turns (b)-(d) into a check when the program is built.

3. **"Its size is a static fact: the longest acyclic path of the call
   graph, weighted by each function's frame size as code generation
   reports it."** *Holds with corrections*:
   - In-process, code generation reports a frame's size only through
     `DiagnosticInfoStackSize`, which `PrologEpilogInserter` emits for a
     function whose frame exceeds its `"warn-stack-size"` attribute
     (*read*: `llvm/lib/CodeGen/PrologEpilogInserter.cpp:286-308`;
     `llvm/include/llvm/IR/DiagnosticInfo.h:503-516`, a typed
     `getStackSize()`). The `.stack_sizes` section is ELF only (*read*:
     `llvm/lib/MC/MCObjectFileInfo.cpp:1273-1277`, null for other formats,
     so nothing on macOS), and `-fstack-usage` writes text to be parsed
     back (`llvm/lib/CodeGen/AsmPrinter/AsmPrinter.cpp:1740-1752`), which
     AGENTS.md forbids. So the threshold is set to 0 on every function and
     the diagnostics are collected.
   - That size excludes what the call itself pushes: the return address on
     x86-64, the target's local area offset (*read*:
     `llvm/lib/Target/X86/X86FrameLowering.cpp:76-77`, −8;
     `llvm/lib/Target/AArch64/AArch64FrameLowering.h:36`, 0), read from
     `TargetFrameLowering::getOffsetOfLocalArea()`, never a constant of
     ours; and the outgoing argument area of a function that sets up calls
     with pushes (`X86FrameLowering.cpp:90-94`: no reserved call frame
     then), bounded soundly by the largest argument list among its calls.
   - "The call graph" is the final LLVM module's, after LLVM's
     optimizations, with `musttail` edges replacing rather than adding;
     and the step checks that no other edge lies inside a strongly
     connected component, which turns any frames miss into an internal
     error when the program is built, not when it runs. §2.4.
   - *Unverified*: the guard is also crossed by code generation's own
     library calls (`memcpy`, compiler-rt builtins) that are not calls in
     the IR; they are leaves, inside the external margin (§2.4 step 4).

4. **"With a margin for the runtime's and the C library's own frames."**
   *Holds with a correction*: the runtime's frames are not a margin; they
   are computed, since its bitcode is in the module (item 2(d)). The
   margin is for external code only: the C library, GMP, compiler-rt; and
   the host's thread overhead, which glibc takes from the top of a
   caller-provided stack (its thread descriptor and static TLS) and whose
   floor is `PTHREAD_STACK_MIN` (*recalled*: glibc places both at the top
   of a stack given by `pthread_attr_setstack`; arm64 glibc's minimum is
   128 KiB). On Linux the program links with immediate binding, so the
   dynamic linker's lazy resolver, which saves the vector state on the
   current stack, never runs on it (*recalled*). §2.4 steps 4-6.

5. **"Computed when the program is built, small, and the runner reserves
   that."** *Holds*; the seam is how the number reaches the runner: the
   bins are compiled before the sizes are known (*read*:
   `Artifacts.cpp:156-163, 190-200`), so the bound is one constant object
   compiled after them, which `idris_rt_start` reads (§2.4 step 7).

6. **"No frame is larger than the guard, checked when built."** *Holds*;
   the guard is address space only, so sizing it to the largest frame
   costs nothing committed. With stack probes on every function we
   compile (18 T-STK1), a frame larger than one page could not skip a
   one-page guard anyway; the check stays as the guard's definition.

7. **"Reaching the guard is an internal error."** *Holds*; today the
   fault is a crash named "stack exhausted", status 1 (*read*:
   `runtime/Start/Entry.cpp:79-82`). It becomes D37's internal-error
   ending (seam with L11).

8. **"Costs, measured as it is built: recursion over data pays a frame's
   dispatch instead of a native return."** *Holds*; the measurement is
   in §4 I-8. A side effect: the stack inference's smaller budget for
   recursive functions (*read*: `Stack.cpp:78-80, 310`, 64 bytes against
   1024) exists because a recursive function's frames stack natively; under
   D32 they do not, so the budget and its one reader of `Recursion` go
   (*measured*: `grep -rn "Recursion>\|recursion\.recursive" lib include`,
   one reader, `Stack.cpp:288, 310`).

9. **"Replaces 1445d894's 64 GiB reservation."** *Holds*: `Runner.cpp:39-44`
   reserves 2^36 bytes (*read*); `PINS.md:596-597` says 2^40 (stale, as
   lane 13 DP-39 said).

### D33: the compiler's own tools keep a small stack

1. **"Our C++ is iterative (worklists, never recursion on the input's
   size)."** *Refuted for this lane's code today*: recursion on match
   nesting depth in `IR/Tail.cpp:23-35` (`endsTail` and `inTailPosition`
   call each other up the chain), `TailLoops.cpp:57-79` (`forTails`,
   `reachesTailCall`), `FramesPlan.cpp:108-118` (`framesFrom`),
   `Frames.cpp:96-104` (`answerTails`), `Trmc.cpp:152-206`
   (`rewriteClone`, `contextsOf`), `Loop.cpp:77-111` (`rewriteTail`); on
   def-chain length in `AccumulatorPlan.cpp:110-119` (`dependsOnSelfCall`).
   *Defect confirmed in the source* against the ruling. Lane 10's
   replacement for the last, `getBackwardSlice`, is itself recursive
   (*read*: `mlir/lib/Analysis/SliceAnalysis.cpp:110-188`).

2. **"MLIR's deepest recursion is measured on the stage-1 module and on
   deep-nesting fixtures (S1)."** *Unverified behaviour*: the measurement
   to take is in §4 I-12.

3. **"A recursion that scales with the input (`walk`, the verifier, the
   printer and parser, region utilities on nesting depth) is fixed
   upstream by patch, as `upstream/10-recursive-attribute-parser` already
   is."** *Refuted in two parts, holds in the rest*:
   - `upstream/10` has no patch: its README's section "Why there is no
     patch" says the fix is "a change of design across the parser, the
     printer and the sub-element walks, which needs upstream's agreement
     before code", and PINS.md says "There is no patch … this code stays
     until upstream has it" (*read*: `PINS.md:600-605`). The patch is the
     work D33 now orders, not a precedent.
   - The verifier is already iterative at the pin: a worklist of
     operations and blocks, and another for dominance (*read*:
     `mlir/lib/IR/Verifier.cpp:413-457, 524-556`). It leaves the list.
   - The list, corrected, every item *read* unless marked:
     `detail::walk` (`mlir/lib/IR/Visitors.cpp:21-60`, the base of every
     `walk`, ours included); the printer (`mlir/lib/IR/AsmPrinter.cpp:3981-4007`,
     a region prints its blocks, a block its operations); the parser
     (`mlir/lib/AsmParser/Parser.cpp:1275, 2298-2312`); the attribute
     parser, printer and alias collection, `AttrTypeWalker` and
     `AttrTypeReplacer` (upstream/10's README, `AttributeParser.cpp:74-85`,
     `AsmPrinter.cpp:949-951, 2485-2489` as it cites them); the bytecode
     writer (`mlir/lib/Bytecode/Writer/BytecodeWriter.cpp:999-1102`);
     `Operation::clone` and `Region::cloneInto` (`mlir/lib/IR/Operation.cpp:721-746`,
     `mlir/lib/IR/Region.cpp:76`), which frames, TRMC, specialization and
     inlining call; `dropAllReferences` (`Operation.cpp:577-585`,
     `Region.cpp:181-184`) and destruction (*conjecture*: by the same
     shape); region dead-code removal (`mlir/lib/Transforms/Utils/RegionUtils.cpp:371-401`);
     `DeadCodeAnalysis::initializeRecursively`
     (`mlir/lib/Analysis/DataFlow/DeadCodeAnalysis.cpp:256`); call graph
     construction (`mlir/lib/Analysis/CallGraph.cpp:74-96`); slices
     (`SliceAnalysis.cpp:29-66, 110-188`); `Liveness` through `walk`
     (`mlir/lib/Analysis/Liveness.cpp:126-130`). Not on it: the bytecode
     reader (a region stack, `mlir/lib/Bytecode/Reader/BytecodeReader.cpp:1664-1669`)
     and SSA numbering (an explicit naming-context stack,
     `AsmPrinter.cpp:1512`).
   - Under D48 a family attribute nests index terms, and under D19 a
     generated `else if` ladder nests one match per branch: both inputs
     the list's recursions scale with (*derivation*).

4. **"The tools' 64 GiB stack goes with the programs'."** *Holds*, with
   an order: the tools' reservation is the workaround of PIN
   mlir-recursion (`PINS.md:585-605`), so it shrinks in the change that
   lands the last of the patches above, with the pool's workers on the
   same reserved stacks (lane 13 DP-39: today they run on LLVM's default,
   8 MiB on Darwin, *read* there). Hard cutover: no small stack with the
   big one kept "until".

### D34: tail recursion modulo context as a promise

*Holds with four corrections*; the exact rule is §2.5.
- Today the context is found after counting, on `idr.cell.init` (*read*:
  `IR/Tail.h:45-64`; `Trmc.cpp:28-31`; `Pipeline.cpp:131`), and a pass
  that inserts a `dup` or a drop on the context's path makes `contextAt`
  fail silently (`IR/Tail.cpp:134-195`: any other use returns none).
  D34's "read off the program as the frontend wrote it" needs the
  decision on `idr.con` before counting, carried on the call (§2.1's
  third kind), with TRMC executing it after counting. *Integration
  mismatch*.
- "Self call" is syntactic only where the frontend emits Idris's case
  blocks inside their parent: today they are separate functions,
  contified later (*read*: `Contify.cpp:15-21` as 10 §4.6 C-6 cites), so
  a self call inside a `case` of the right-hand side is a call from the
  case block to its parent, a mutual call. D34's "across a rejoin" needs
  case blocks in place (10 NQ-4; 0003 B1 under D44). *Integration
  mismatch*, seam L16.
- A context through a stack cell is refused silently (*read*:
  `IR/Tail.cpp:168`); the stack inference must honour the property
  instead. *Integration mismatch* (L07).
- The rule's boundary on effects: an op the transformation must move
  before the call (a constructor's other field computed after the call)
  must be movable across it under D21 (*read*: `mayRunAt`,
  `IR/Effects.cpp:161-184`, asked at `IR/Tail.cpp:273-274`). A call whose
  context needs a crashing or looping op moved is outside the promise, and
  says so in the rule, not in a silent `nullopt`. *Structural
  incompleteness* of the stated rule.

### C4: accumulators widened

*Holds with corrections*; the exact conditions are §2.6.
- *Associativity and an identity suffice*; commutativity is not needed,
  when the accumulator is combined on the side the call was: for
  f(n) = g(n) ⊕ f(n−1) the clone computes acc ⊕ g(n), for
  f(n) = f(n−1) ⊕ g(n) it computes g(n) ⊕ acc (*derivation*: both orders
  reproduce the original bracketing up to associativity). The class may
  therefore include an exactly associative non-commutative runtime
  operation, string concatenation among them.
- `Int` and every fixed-width integer's `+` and `*` are exact: the
  frontend lowers them to `arith.addi`/`arith.muli` with no overflow
  flags, wrapping modulo 2^w (*read*:
  `compiler/src/IdrisMLIR/Frontend/Translate/Primitives.idr:84`;
  `compiler/src/IdrisMLIR/Dialect/Arith.idr:26-30`), a ring.
- `&&` and `||` are lazy in their second argument in Idris (*recalled*:
  `(&&) : Bool -> Lazy Bool -> Bool`): with the self call on the right the
  call is already a tail call and needs no accumulator; with it on the
  left the call's result is matched, and the accumulated loop is exact
  only when the other operand is pure and total, and it runs to the base
  case unless the function is `total`, since the original always
  evaluates the recursion first (*derivation*).
- Today: only `idr.big.add` (*read*: `AccumulatorPlan.cpp:129`), all
  self calls of the function must be sites or none is rewritten
  (`:212-228`), and the order condition is "the ops between the call and
  the addition are effect-free and speculatable" (`:138-141`). Plus a
  special case C4 does not name: the countdown recognized by its op
  sequence (`AccumulatorPlan.cpp:165-200`; 10 H-5), which becomes the
  closed form of an accumulated loop (§2.6).

### C5: the stack's sizes

- **"The stack: D32's computed bound and a margin for the runtime's and
  the C library's frames, rounded to pages; tens to hundreds of KiB
  expected."** *Holds with a correction*: the runtime is computed, not
  margined (D32 item 4); the host's thread overhead and floor are added
  at start; on arm64 Linux the floor alone is 128 KiB (*recalled*), so
  "tens of KiB" holds only where the host allows it.
- **"The runtime's own units take `-fstack-clash-protection`, since GMP's
  temporaries use `alloca`."** *Refuted as reasoned*: GMP is a separate
  static library the bootstrap builds with its default temporary policy
  (*read*: `tools/bootstrap.sh:1060-1066`, no `--enable-alloca`;
  `third_party/gmp/configure.ac:104-114`, default `reentrant`), under which
  `TMP_ALLOC` takes up to 0x7f00 bytes per call from the stack
  (`third_party/gmp/gmp-impl.h:373-391`); the runtime's compile flags do
  not reach GMP. Corrected (§4 I-10): GMP built with
  `--enable-alloca=malloc-reentrant` (`gmp-impl.h:393-403`: every
  temporary through the memory functions the runtime installs), so GMP has
  no `alloca` and its frames are fixed; probes on the runtime, GMP and the
  tools alike, on every target.
- **"The guard: one page, or the largest frame rounded up if larger,
  checked when the program is built."** *Holds* (D32 item 6).
- **"The signal stack: the target's `SIGSTKSZ` for programs (today 1
  MiB)."** *Holds with a correction*: on glibc 2.34 and later the size a
  signal frame needs depends on the processor's saved state, and the
  library reports it at run time (*recalled*: `sysconf(_SC_SIGSTKSZ)`);
  the platform layer asks it there and uses the constant where the
  platform has only the constant (macOS). Today 1 MiB, below the guard
  (*read*: `Runner.cpp:33, 71-72`), which 18 R-STK-2 corrects with a
  guard under it.
- The heap and page-map rows are L11's.
- **"Nothing is committed before it is used"**, applied to the stack:
  the thread's stack is a writable mapping today (*read*:
  `Posix/Memory.cpp:65-85`); under strict overcommit a writable private
  mapping is charged whole (*recalled*). Charging the small static bound
  at start against committing page by page on fault is §6 Q1.

## 2. Boundaries

### 2.1 Tail position: one fact on the call

- **`idr::TailKind`**, an enum generated from the specification (D16): 
  `nontail`, `tail`, `modulo_context` (§2.5). An inherent property of
  `idr.call`, printed as a keyword (`idr.call tail @g(...)`), `nontail`
  unprinted. Generated builders take it with no default value.
- **Invariants**, checked by `idr.func`'s region verifier in one top-down
  walk of the body (iterative), and by `idr.call::verifySymbolUses`:
  - `tail`: the ops after the call to its block's terminator are only
    ops with no run-time form that carry its results (today's
    `Idr_ResultCarriesOperand` casts: `borrow`, `share`, `lin.enter`,
    `lin.use`, *read*: `IdrOwnershipOps.td:98, 118, 403, 416`); the
    terminator forwards exactly those values; and the terminator is
    `idr.return`, or yields to a region op whose results are in tail
    position by the same rule (a match's yield, a join's exit), or jumps
    to a join region in tail position (D25's `idr.jump`). No operand has a
    lifetime that ends with this call (D40's `frame`, or a lifetime bound
    inside the function). The callee's result types equal the caller's
    modulo grades with no run-time form.
  - `modulo_context`: §2.5's rule; the callee is the caller (symbol
    identity by `StringAttr`, not text).
  - `nontail`: nothing (a call whose shape happens to allow a tail call
    may stay `nontail`; a canonicalization may promote it).
- **Constructors.** The frontend writes `tail` on each call it emits in
  return position and `modulo_context` on each self call D34's rule
  admits (seam L16; the fact is the frontend's, D10's "a fact an earlier
  stage knew"). Passes that make calls write the kind they create:
  frames (every call of a run or resume is `tail`, §2.3), TRMC (the clone
  call `tail`), accumulation (the clone call `tail`),
  defunctionalization (an application's kind becomes its dispatch's; a
  dispatch function's case calls `tail`), specialization (copies keep
  kinds). The inliner composes (`lib/IR/Func/Inliner.cpp`,
  `processInlinedCallBlocks`): an inlined call keeps `tail` only when the
  site was `tail`; an inlined `modulo_context` call becomes `nontail`
  unless the site is a self call of the same function. Join-point
  formation and idr-tail-loops consume the fact (the call becomes a jump
  or a back edge).
- **Readers.** Borrow inference (§2.2), placement (no op after a `tail`
  call), the stack inference (operand lifetimes), lifetimes (no extent
  covers a `tail` call), frames (which calls end a run), TRMC (executes
  `modulo_context`), the lowering. None recomputes it.
- **Lowering** (seam G DP-38, L13): `idr.call` reaches the LLVM
  conversion as itself (our op implements the conversion to LLVM), never
  as `func.call`. Every internal function (private, every use a direct
  call: every program function but `@main` and the entry body) is
  `tailcc`; every call of one carries `tailcc`; a result type that does not
  fit `tailcc`'s return registers, asked once per type of the one target
  machine (lane 13's recipe), makes the function take a `noalias` pointer
  first and return nothing; a non-tail call of it passes a slot of its
  frame, a tail call its caller's pointer (`PassThroughMemory.cpp`, kept).
  `tail` becomes `llvm.call … tail_call_kind = musttail`.
- **Materialization** (the one step left of idr-tail-calls): after
  `convert-to-llvm`, for each `musttail` call, split its block after it
  and end it with `llvm.return` of its results (stored through the
  pointer for a through-memory function, `PassThroughMemory.cpp:61-72`).
  Sound because the verified property says every path from the call
  returns those values unchanged; LLVM's verifier is the last check.
  Erases the blocks only that path reached (`eraseUnreachableBlocks`,
  as `TailCalls.cpp:107`).
- **Deletes**: `lib/Conversion/TailPosition.cpp` and `.h` (the second
  definition); `lib/Conversion/TailCallPlan.cpp` and `.h` (conventions
  become a property of the function's kind and type; the cycle condition;
  `numFrameBound`, `frameBound()`, `bound`); `lib/Conversion/Frame.cpp`
  and `.h` (the points-to walk and `leaked`); in `TailCalls.cpp` the plan
  and the statistics walk; `IR/Tail.cpp`'s per-query `endsTail`,
  `inTailPosition`, `inTailPositionModuloContext` (their one walk moves
  into the function verifier; `contextAt` survives as the verifier's and
  TRMC's reading of §2.5); `forTails`, `reachesTailCall`; the deciders at
  `Borrows.cpp:236-237`, `Stack.cpp:229-235`, `Recursion.cpp:33-35`,
  `Lifetimes.cpp:59-66` (`loopsInFrame` reads the kind); `Recursion.cpp`
  and its header (§1 D32 item 8); the `numFrameBound` statistic in
  `Passes.td:887`.
- **Essential distinctions kept**: a tail call against a call that
  returns; a self tail call (a loop), a local tail continuation (a join
  point) and any other tail call (`musttail`): three lowerings of one
  fact; a call's tail position against tail position modulo a context
  (two promises, D30 and D34); a result in registers against one through
  memory (the target's answer).

### 2.2 What every other pass owes a tail call (seams)

| owner | obligation | today |
| --- | --- | --- |
| L07/L08 borrows | a parameter is owned when any `tail` call passes it a value the caller owns (Lean's rule, §5.10 B2, made unconditional); a borrowed argument at a tail call is the caller's own view, whose lifetime outlives the caller | only within a cycle (`Borrows.cpp:236-241`) |
| L07 placement | no drop, dup or token free after a `tail` call; values dead at it drop before it | not checked |
| L07 stack inference | no operand of a `tail` call is a frame value; no value live across a call to a member of the caller's component (framed, §2.3) is a frame value | cycle tail calls only (`Stack.cpp:229-241`); the 64-byte recursive budget |
| L05 lifetimes | no `idr.lifetime` region contains a `tail` call (its end would follow the call); a frame kind's field outlives the native frame | — |
| L09 join points | the general loop is a recursive join point whose exit forwards a non-self call's results unchanged, not a flag in a payload | `Loop.cpp:7-14` |
| L08 exclusivity | a frame field is an edge from the pushed operand to the popped result of the same kind | frames are data cells |
| L01/L02 effects | push and pop are pure on a linear value; `frames.enter`/`frames.exit` read and write upstream's `frame` resource; chunk growth `Allocate` on `heap`, reporting only (recommendation) | — |
| L04 families | the frames family's third layout (§2.3) | — |
| L11 runtime | guard reached: the internal-error ending; the runner's size parameter; the stack bound object | crash "stack exhausted" (`Entry.cpp:79-82`) |
| L12 arrays | a generating op on a call cycle has a sequential form frames can split (§2.3) | — |
| L13 lowering, pipeline | DP-38's call op to LLVM; frames' position (§2.3) | `FuncToFunc.cpp:54` |
| L14 program graph | the components (cycles) frames and the bound read, one maintained graph | `CallCycles` rebuilt three times (10 §2.4) |
| L16 frontend | writes `TailKind`; case blocks and `ifThenElse`'s branches in place so D34's rule is syntactic | — |
| idr-returned-arguments | functions joined by tail calls drop the same results, or none (§4 I-2) | not checked |

### 2.3 Frames: typed, linear, uncounted, contiguous (D31, D32)

- **The type.** Per component, one D48 family indexed by the awaited
  result: `#idr.family<"frames.<c>" [awaits : fin R] { @done_j where
  awaits = j (answer : !idr.dest<R_j>) ; @k_i where awaits = t_i,
  m… : … (held_i …, below : self[o_i]) }>` for R distinct result rows
  R_0…R_{R−1} (a row: one or several result types, so a multi-result
  member is no gap), frame kinds k_i awaiting t_i and continuing in o_i,
  each kind binding its own index variables m (D48's per-constructor
  binders), so a frame of a recursion over an indexed family is one kind,
  not one per index. Its layout is a third one beside inline and cell:
  **the frame stack**, linear by type (no `dup`, `share` or `borrow`
  accepts it), uncounted (no header, no count word), `below` implicit in
  the position. A held value is any value with a static size (memref
  descriptors, vectors, tokens: no `isFieldType` gap); never an
  `!idr.cont` (it cannot escape).
- **Ops**: push is `idr.con` of a kind (a linear result takes a fresh
  identity, C3); pop is `idr.match` on the linear handle, which consumes
  it and binds the held values at their own grades and `below`; D48's
  refinement removes every kind whose equation is false, so the resume of
  R_j matches only kinds awaiting j: the `ub.unreachable` cases cannot be
  written. `idr.frames.enter` (reads the thread's top, pushes `done_j`
  with a destination) and `idr.frames.exit` (the last consumer of the
  handle, in `done_j`'s case, writes the top back).
- **Functions.** Per member f: `f.run(args…, s : frames[j_f])`, its body
  on the stack; per result row: `resume_j(v…, s : frames[j])`, a pop
  whose case for k_i runs k_i's continuation; per escaped join point
  (below) a continuation function. All return nothing: the answer goes
  through `done_j`'s destination, so every run and resume has the same
  (empty) return type, which `musttail` demands, and the answer sum,
  `fromAnswer` and `asAnswer` do not exist (§4 I-6). The member itself
  becomes the wrapper: a slot, `frames.enter`, a non-tail call of `f.run`,
  the slot read. All calls inside runs, resumes and continuation
  functions are `tail`.
- **The construction (CPS of each component, D32).** For each function of
  a component with a non-tail call of a member (any member, not only
  closure labels):
  1. every region op on the path from such a call to the function body
     whose results are used afterwards gets its continuation as a join
     point (D19's join-point form; L09's encoding);
  2. a join point that a frame's continuation must reach from another
     function (it "escapes", D31) becomes a continuation function of the
     component, tail-called with its live-ins and the stack, by the run on
     paths with no frame and by resumes on paths with one: no code is
     copied per site;
  3. each non-tail call of a member, now with a block-local continuation,
     is a frame kind: push the kind holding the continuation's live-ins
     (one backward liveness walk per block: O(block), not today's
     O(rest²) `madeInRest`, `FramesPlan.cpp:31-35`), then tail-call the
     callee's run; its continuation becomes the kind's case in its
     result's resume; a later non-tail call in that continuation is the
     next frame, found in the same left-to-right walk;
  4. a loop or a generating op on such a path (if frames runs where they
     exist) is first written as a recursive join point (a generator by its
     sequential expansion, L12), which step 2 lifts.
  Termination: one walk per function, each op moved once (*derivation*).
- **Position in the pipeline**: after counting, demand and TRMC, before
  idr-tail-loops (§4 I-7). There a reuse token live across a framed call
  is a held value; exclusivity's answer for a held value travels with its
  grade; the stack inference has already kept every value live across a
  call on the cycle off the native frame (§2.2).
- **Run time.** One frame stack per thread (per shard under 0007), in
  chunks of one size C, aligned to C, so a chunk's end is computed from
  the top pointer and the handle is one register. C is the smallest power
  of two at least snmalloc's chunk granule and the program's largest frame
  kind (the granule is the pinned allocator's constant; the largest frame
  is computed when built: no round constant of ours). Push: compare,
  stores, bump; the slow path `idris_rt_frames_grow` links the next chunk
  (the spare if any) through a header word. Pop: load the tag, switch,
  loads, bump, one compare against the chunk's base; the slow path
  `idris_rt_frames_shrink` moves to the previous chunk and keeps the
  emptied one as the spare, releasing an older spare. Memory exhaustion
  in the slow path is D23's out-of-memory ending, counted by D36's limit
  like any memory snmalloc commits. The thread's top lives in a
  thread-local slot read by `frames.enter` and written by `frames.exit`
  only.
- **Deletes**: `FramesPlan.cpp`, `Frames.cpp`, `FramesTypes.cpp` as they
  stand (rewritten whole); in `Transforms/Tail.h` `Members`,
  `memberCalled`, `Labels`, `closureLabels`, `Frame`, `restOf`,
  `madeInRest`, `isConstant`, `caseCallee`, `FramesPlan` (its nullable
  answer), `FramesMade` (its `sum`), `stackTypeOf`, `answerTypeOf`,
  `fromAnswer`; the `ub.unreachable` cases (`Frames.cpp:237-240`,
  `FramesTypes.cpp:84-94`); the `heldAs` re-entries (`Frames.cpp:244`,
  `FramesTypes.cpp:91`); the effects-mismatch branch (`FramesPlan.cpp:157-160`);
  the content names `<f>.answer` and the per-type resume hash; the
  labels walk over every type of the program (`FramesPlan.cpp:123-140`).

### 2.4 The native stack bound, step by step (D32)

Run by the driver on the final LLVM module (the program's functions and
the runtime's bitcode linked in, after LLVM's optimization pipeline) and
on the bins' code generation:

1. **The graph.** Nodes: the module's defined functions. Edges: each
   `call` to a defined function, marked `musttail` or not; each call to a
   declaration (C library, GMP, compiler-rt) recorded as an external leaf
   by symbol. An indirect call other than the runner's two fixed ones
   (`runTask` calling the task, `runProgram` calling the body,
   `Runner.cpp:53-57`, `Entry.cpp:29-32`) is an internal error. A
   dynamically sized `alloca` anywhere is an internal error (none in the
   runtime's sources, *measured*: `grep -rn "alloca" runtime`, no code hit;
   ours are constant and in entry blocks, `Conversion/Cells.cpp:95`,
   `Memrefs.cpp:53`, `PassThroughMemory.cpp:82`).
2. **The acyclic check.** Strongly connected components over all edges
   (LLVM's `scc_iterator`); any edge that is not `musttail` and lies inside
   a component is an internal error naming the call: frames missed a
   non-tail call on a cycle. This turns D32's "reaching the guard is an
   internal error" from a run-time event into a build-time one for every
   cyclic depth. (`musttail` cycles are frames' runs and resumes and the
   program's mutual tail recursions.)
3. **The weights.** Code generation runs with `"warn-stack-size"="0"` on
   every function; each bin's diagnostic handler keeps each
   `DiagnosticInfoStackSize` (function, size) and prints nothing; a
   function with no diagnostic has size 0. The weight of f is
   `size(f) + |getOffsetOfLocalArea()| + incoming(f) + outgoing(f)`,
   where `incoming` is f's own stack-argument area and `outgoing` the
   largest argument list among f's calls, each argument rounded to the
   stack slot, added only when f has no reserved call frame; the target's
   frame lowering answers each, not a table of ours (§1 D32 item 3).
4. **The external margin.** Per external symbol, a stack bound recorded in
   the target's entry with its measurement (the C library's entry points
   the runtime calls, GMP's with the policy of I-10, compiler-rt's
   builtins and the `mem*` functions code generation may call), measured
   once per target by painting a stack and running each library's deepest
   operations at the largest sizes the test machine holds, and re-measured
   when a pin moves: the one measured number of the bound, labelled so.
5. **The longest path.** In reverse topological order of the
   components: depth(C) = max over f in C of max( w(f) + max over non-tail
   edges f→g out of C of depth(g), max over `musttail` edges f→g out of C
   of depth(g), w(f) + max over f's external leaves of their margin ). A
   `musttail` edge replaces the caller's frame, so it contributes the
   callee's depth, not a sum. Linear in edges.
6. **The bound.** depth(entry body) plus the runner's fixed chain
   (`startThread`, `runTask`, `runProgram`: runtime functions, weighted by
   step 3) plus the thread start's own C library frames (margin), rounded
   up to pages. The guard is the larger of one page and the largest
   weight, rounded to pages.
7. **To the runner.** The driver compiles one more object holding the
   constant `idris_rt_program_stack` (the bound and the guard), after the
   bins, with the target's machine; `idris_rt_start` reads it and calls
   `idris_rt_run_on_stack(fn, arg, bytes, guard, exhausted)`, which adds
   the host's thread overhead (`sysconf(_SC_THREAD_STACK_MIN)` where the
   C library computes it, `PTHREAD_STACK_MIN` elsewhere: a fact of the
   machine read at start) and lays out `[guard | signal stack | guard |
   stack]` (18 T-STK1), the signal stack sized by the host (§1 C5).
8. **Probes.** `"probe-stack"="inline-asm"` and `stack-probe-size` = the
   target entry's page on every function of the module (program and
   runtime bitcode), and `-fstack-clash-protection` for GMP and the tools
   (18 T-STK1; §5.11 K6).
9. **The tools** (D33): their bound is not static until the recursions of
   §1 D33 are iterative; it is a measured constant in the tools' build
   with its measurement, the main thread and every pool worker on the
   same reserved, guarded stack.

Deletes: `Runner.cpp:39-44`'s `stackSize` and its comment; the 1 MiB
`guardSize` constant (`:35-37`) and the claim "none is" it rests on; the
fixed 1 MiB `alternateSize` (`:27-33`); in `Support/Stack.h` the shared
size; PIN mlir-recursion in the change that lands D33's last patch.

### 2.5 D34's rule, exact

A call c in function f is `modulo_context` when, in the frontend's IR
(before counting, case blocks in place):
1. c calls f itself, and has one result r;
2. r's only use, through ops with no run-time form, is one field of one
   constructor application k (`idr.con`) made for it;
3. k's result, through such ops, either reaches the terminator of a block
   that ends in tail position (the function's return, or the yield of a
   match whose results are in tail position), or is the only use of one
   field of another constructor application made for it (several deep),
   or is yielded by a region of a match all of whose running regions
   yield a context at the same position (across a rejoin; one call per
   path), or is read back as the part it is (`idr.unpack` or a field read
   of a constructor that is no cell), which is how an IO action inside
   the actions that run it reaches the result;
4. nothing else reads, matches, copies, drops, passes or stores any value
   on that path;
5. every op of c's block between c and the terminator that the
   transformation moves before c may move across c under the effect rules
   (D21: no crash, divergence, exit or IO moved past c's own);
6. the constructors on the path are fresh: counting makes each a heap cell
   (never a stack cell), or, on an exclusive scrutinee, recycles a token
   into it (D24, C1).

Counting honours it (no `dup`, drop or stack cell on the path); TRMC,
after counting, executes it (holes, destinations, the clone); the
verifier re-checks 2-4 and 6 on the call after every pass, so a pass that
breaks it is an internal error. Mutual recursion modulo a context is not
promised (D34 names a self call); under D32 such a call costs a frame on
the typed stack, never native stack.

### 2.6 C4's exactness conditions

A self call c of f is an accumulator site when:
1. its one result r is used once, by one operation ⊕ that the runtime
   defines as exactly associative with an identity e: `Integer` `+` (e
   0) and `*` (e 1); `+` and `*` of `Int` and every fixed-width integer
   type (modular); bitwise and (e all ones), or and xor (e 0); string
   concatenation (e the empty string); `&&` and `||` under item 4;
2. ⊕'s result is the value the tail returns, or again an operand of the
   same ⊕ whose result is (chains by associativity);
3. the other operand does not depend on any self call, and either is
   computed before c in eager order, or is pure, total and speculatable
   (it may then move before c);
4. for `&&`/`||`: the call on the right needs nothing (it is a tail call
   already); on the left, the other operand is pure and total, and the
   loop runs to the base case unless f is `total`;
5. every self call of f is a site or a tail call (a function with any
   other self call, `f l ⊕ f r` among them, is left to frames);
6. the clone combines on the call's side: acc ⊕ g for g ⊕ f(…), g ⊕ acc
   for f(…) ⊕ g; seeded with e by f;
7. never a floating-point operation and never a user's `Semigroup` or
   `Monoid` (*decision*: C4).

The countdown special case goes: an accumulated loop that adds a constant
k on each of n iterations has the closed form acc + n·k, a rewrite of the
loop form after idr-tail-loops, the same for words and `Integer`.

### 2.7 Every way a tail call could still grow the stack, and its fix

| # | way | fix |
| --- | --- | --- |
| 1 | a pass inserts an op after a `tail` call (a drop for a borrowed parameter, a token free, a lifetime's end, a stack cell's release) | borrow forcing and placement (§2.2); the function verifier: internal error |
| 2 | idr-returned-arguments drops a tail callee's result and not the caller's | tail-joined functions drop alike (§4 I-2) |
| 3 | a tail call's caller and callee return different LLVM types (a drop, narrowing, an answer) | `verifySymbolUses`; frames return nothing; I-2 |
| 4 | the result does not fit the return registers, so LLVM demotes it to `sret` and cannot tail-call | through-memory pointer per function type (kept) |
| 5 | a tail call reaches its caller's frame (a stack cell, an `alloca`) | the operand lifetime rule; the lowering's own slots go only to runtime calls and non-tail calls (`Memrefs.cpp:47-57`, `PassThroughMemory.cpp:74-88`) |
| 6 | calling conventions differ | every internal function `tailcc`; only the entry body and `@main` are C, and they make no tail call of the program |
| 7 | an ABI attribute LLVM forbids under `tailcc` (`byval` on AArch64, `inreg`, `inalloca`, …) | the lowering writes argument attributes from a closed generated set without them |
| 8 | a variadic function | none exists (`idr.func` has no variadic form) |
| 9 | AArch64's sibling call from a callee-pops function corrupts the stack pointer | `upstream/30` carried, its test kept, reach widened (§1 D30 item 7) |
| 10 | a runtime function calls program code | the specification's ABI table admits no function-pointer parameter but the runner's, a `consteval` check (§4 I-1) |
| 11 | a non-tail call on a cycle | frames (§2.3); the build-time acyclic check (§2.4 step 2) |
| 12 | the general loop's flag hides a tail call | the recursive join point (L09) |
| 13 | a call inside a lifetime region | no lifetime extent covers a `tail` call (L05) |
| 14 | inlining at a non-tail site | composition demotes; the site's own frame was already there, so no growth beyond it (*derivation*) |
| 15 | LLVM's inliner inlines a `musttail` callee at a non-`musttail` site | LLVM demotes the inlined `musttail` itself (*recalled*); the same composition |
| 16 | an external library recurses on input size | GMP without `alloca` (I-10); its depth bound measured in the margin (§2.4 step 4) |
| 17 | lazy binding runs the resolver on the program's stack | immediate binding on Linux (§1 D32 item 4) |
| 18 | a foreign call's frames (0020) | open for 0020 (D32) |

## 3. QTT

**Where quantities enter this area and what happens to them.**
- *Quantity 0* (erased): never a call argument, a frame field or a
  destination (the frontend emits no value for it, AGENTS.md). Erased
  indices (D48) appear in the types of held values and of the stack:
  each frame kind binds its own index variables, as a family constructor
  does, and a push instantiates them by substitution at compile time
  (`idr.con` of the kind at the call's indices); no index is stored. Today
  frames lose nothing here only because data types carry no indices yet.
- *Quantity 1*: a linear argument passed to a `tail` call is moved, so no
  drop can follow (Lean's rule, §5.10 B2); D30 makes the borrow rule's
  forcing unconditional (§2.2). A linear continuation `k : !idr.lin<K>`
  applied in tail position is a join point (D19) or a `tail` call of a
  dispatch, never a frame unless its application crosses a framed call
  (match-and-counting §9). The frame stack handle is linear by its type:
  push and pop consume it and produce the next; a second pop is a second
  consumer of a consumed value, which the linearity verifier
  (`IR/Verify/Linearity.cpp`, one walk per function, used exactly once on
  every path) rejects: **a second resume cannot be written**. Pop binds
  each held value at the product of the handle's quantity and the
  field's, 1 × q = q, so a linear value comes back linear; today the
  handle is an unrestricted box and the product is ω, then `heldAs`
  forges q back (§1 D31 item 4).
- *Quantity ω*: owned references move into a frame and out of it with no
  count change (the frame owns them while it lives); a borrowed view may be
  held only when its owner outlives the run (static, counted elsewhere, or
  a lifetime parameter of the caller), or is held by a frame below it,
  which LIFO pops later (*derivation*; typing the last case needs the
  frames' lifetimes ordered, open).
- *Exclusivity* (`!idr.excl`): a field's grade travels through the frame,
  so a value exclusive before a framed call is exclusive after it, and a
  reuse token held in the frame rebuilds in place across the call: D24's
  promise survives a non-tail rebuild across a cycle only because frames
  runs after counting (§4 I-7).
- *Destinations* (`!idr.dest`): written once, by `idr.dest.write`'s
  declared rule (*read*: `IdrOps.td:372-375`); TRMC's hole and `done_j`'s
  answer are both destinations, so the answer of a run cannot be written
  at the wrong type or twice.

**Facts a quantity proves that the design still paid for, and the fix.**
- Frames as counted cells: each push allocates and counts, each pop takes
  apart, though each frame is used once by construction (D10): uncounted
  linear frames (§2.3).
- The forged quantity at the pop (`heldAs`): the linear handle.
- `Frame.cpp`'s points-to walk at compile time re-derives what lifetimes
  in types say: the operand lifetime rule on the call.
- `TailPosition.cpp` re-derives tail position on the CFG on every
  compile: the property.
- The `ub.unreachable` resume cases and the answer sum's impossible
  cases: an unchecked claim the types can make (§2.3).

**Representations that make a misuse unwritable.**
- `!idr.frames` (the family, layout frame stack): no `dup`, no second
  pop, no frame of the wrong awaited type.
- `TailKind` with no builder default: a pass cannot make a call without
  saying what it is.
- The tail call's operand lifetimes: a frame value cannot be passed to a
  call that ends the frame.
- `done_j`'s destination: the answer has its type in the kind.
- `!idr.cont` (L09): a join token cannot be a frame field; a frame is what
  an escaping continuation becomes, never a token stored.

## 4. Improvements

**I-1. Tail position as an obligation on the call; conventions from the
function's own kind; the plan deleted.** *Coordinator* (D30, G DP-38).
- *Evidence*: §1 D30 items 3, 6, 7; `TailCallPlan.cpp:69-167`;
  `TailPosition.cpp:283-330`; `Frame.cpp:28-61`.
- *Counterexample*: the two definitions disagree on a call followed by a
  cast with no run-time form. On `idr`, `inTailPosition` needs the op
  right after the call to be the terminator (*read*: `IR/Tail.cpp:31-35`),
  so in
  ```mlir
  %r = idr.call @g(%cell) : (...) -> !idr.lin<!T>
  %v = idr.lin.use %r : ...
  idr.return %v
  ```
  the call is not in tail position for the stack inference, which may
  then put `%cell` in the frame (`Stack.cpp:233` asks only that
  definition); after lowering the cast is gone, `TailPosition.cpp` finds
  the call in tail position, `Frame.cpp` finds the slot passed, and the
  call stays a call, counted in `numFrameBound` and nothing else
  (*read*: `TailCallPlan.cpp:110-113`). With `g` on the caller's cycle the
  recursion grows a native frame per round. (*Conjecture*: whether today's
  frontend writes such a cast before a return; the disagreement itself is
  read.)
- *Root cause*: tail position is computed twice, once per level, and the
  frame question is asked of LLVM pointers instead of read off lifetimes.
- *Correction*: §2.1, with the specification's ABI table refusing a
  function-pointer parameter in any runtime entry but the runner's (a
  `consteval` check), which keeps "no cycle through C" a build-time fact.
- *Deletes*: §2.1's list.
- *Discriminated by*: the function verifier (a `tail` call followed by a
  drop is rejected); a program test: a mutual recursion of 10^8 rounds
  runs under the computed stack bound (§2.4) and exits 0.

**I-2. idr-returned-arguments keeps tail calls.** *Coordinator* (a defect).
- *Evidence*: `ReturnedArguments.cpp:59-82` replaces a dropped result by
  the call's argument with no regard to the call's position;
  `Verifier.cpp:4400-4401` needs equal return types.
- *Counterexample*:
  ```idris
  mutual
    g : Nat -> Nat -> Nat
    g a Z     = a
    g a (S n) = case f a n of _ => a    -- non-tail: f's result is matched
    f : Nat -> Nat -> Nat
    f a n = g (a + 1) n                 -- a tail call
  ```
  g gives back its first argument on every path; f gives back `a + 1`,
  which is no argument of f. The drop turns f into `g(a+1, n); return
  a+1`: the tail call is gone. Today the cycle then grows by a native
  frame per round, counted nowhere (the call is no candidate); under the
  design the build-time check of §2.4 step 2 finds a non-tail edge inside
  the component and the valid program gets an internal error.
- *Root cause*: the drop is decided per function, but a tail call ties
  its caller's results to its callee's (the same return type).
- *Correction*: functions joined by `tail` calls form classes (one
  union-find over the tail edges); a result position drops in every
  member of a class or in none.
- *Deletes*: nothing new; it is a rule of 10 D3's redesign.
- *Discriminated by*: the program above with n = 10^7 runs under the
  computed bound; before the fix it ends in an internal error.

**I-3. Borrow forcing at every tail call.** *Coordinator* (seam L07/L08).
- *Evidence*: `Borrows.cpp:236-241`.
- *Counterexample*: `k n = sum (replicate n 1)` where `sum` only reads its
  list: the parameter is inferred borrowed, k owns the fresh list and
  drops it after `sum` returns; k's tail call becomes a call (D30
  violated off any cycle).
- *Root cause*: the rule was scoped to "constant stack on a cycle", not to
  tail position.
- *Correction*: §2.2's first row; the callee drops its own argument (the
  same work, moved).
- *Discriminated by*: the function verifier on the IR after counting.

**I-4. The tail call's operand lifetimes replace the frame analysis.**
*Coordinator* (seam L05, L07).
- *Evidence*: `Stack.cpp:229-241`; `Frame.cpp`; D40.
- *Counterexample*: `q n = sum [n, n]`, `sum` borrowing: the two cons cells
  do not escape `sum`, so the stack inference may put them in q's frame;
  forcing `musttail` without the rule, `sum` would read q's torn-down
  frame (LangRef `:14105-14111`), a miscompile; today the call silently
  stays a call.
- *Correction*: §2.1's lifetime invariant; the stack inference reads the
  kind of every call.
- *Deletes*: `Frame.cpp`, `Frame.h`, the cycle test in `Stack.cpp`.
- *Discriminated by*: the verifier rejects a `frame`-lifetime operand of
  a `tail` call; the program above runs.

**I-5. Frames as a D48 family with a linear frame-stack layout.**
*Coordinator* (D31, D48; seam L04 for the layout).
- *Evidence*: §1 D31 items 2, 4; `Frames.cpp:229-244`;
  `FramesTypes.cpp:84-94`.
- *Counterexample*: a frames bug that resumes one frame twice (a pop
  duplicated by a rewrite) passes today's verifier, since the stack is an
  unrestricted box and the popped linear handle `h` of `withFile h …` is
  forged linear again by `heldAs`: `h` is closed twice at run time.
- *Root cause*: the stack is data like any other, so its single use is
  not in its type.
- *Correction*: §2.3's type and ops.
- *Deletes*: §2.3's list; R·(F+1) + M·R impossible regions become none.
- *Discriminated by*: a verifier test of two pops of one handle; the
  bindGrammar-shaped fixture (S1) counts its regions before and after.

**I-6. The answer through the base frame's destination.** *Coordinator*.
- *Evidence*: `FramesTypes.cpp:46-97`, `Frames.cpp:279-288, 340`; lane 10 D2
  kept the answer sum because "which member started a run is not in any
  type".
- *Counterexample*: a component with R = 12 result types (bindGrammar's,
  §8 of match-and-counting) gives each member a 12-case match with 11
  `ub.unreachable`; a wrong tag from any bug is undefined behaviour, not
  an error.
- *Root cause*: every run returns the answer, so the answer must be one
  type for all.
- *Correction*: runs and resumes return nothing; `done_j` holds an
  `!idr.dest<R_j>` into the wrapper's slot, written once.
- *Deletes*: the answer sum, `answerTypeOf`, `asAnswer`, `fromAnswer`,
  the answer's name.
- *Discriminated by*: no `ub.unreachable` in frames' output; a test whose
  members give three result types runs.

**I-7. Frames after counting and TRMC.** *Coordinator* (D31's "reuse
tokens carried in it"; seam L13 for the order).
- *Evidence*: `Pipeline.cpp:122-132`; D24.
- *Counterexample*: an in-place `LList` rebuilt across a call of another
  member of its cycle (`f (x :: xs) = let r = g xs in y :: r`, g calling
  f): with frames first, the take is in the run and the construction in a
  resume, two functions, and no token crosses functions, so the cell is
  freed and a new one allocated: D24's promise broken ("a pass that would
  break the promise is a bug").
- *Root cause*: a token can live across a call only as a value, which
  frames can hold only if it exists when frames runs.
- *Correction*: frames after demand and TRMC, before idr-tail-loops; the
  stack inference keeps values live across calls on the cycle off the
  native frame (§2.2).
- *Discriminated by*: `tests/uniqueness-shared-rebuild`-style test across
  a cycle: the rebuild allocates nothing (the runtime's checked
  allocation count, L19).

**I-8. D32's CPS of every component.** *Coordinator* (D32).
- *Evidence*: §1 D31 item 8, D32 item 1.
- *Counterexample*: `size (Node l r) = size l + size r` on a degenerate
  tree of height 10^6: two non-tail self calls in one block, so
  `callsAgain` refuses a frame (`FramesPlan.cpp:87-99`), and the recursion
  is over data, so it is no closure run (`:64`): under a small native
  stack it reaches the guard.
- *Correction*: §2.3's construction.
- *Discriminated by*: the program runs at height 10^7 under the computed
  bound; the build-time check (§2.4 step 2) finds no non-tail edge in a
  component. Cost measured as D32 asks: the tree benchmark's time against
  native recursion (`bench/`), recorded with build and input.

**I-9. The stack bound as §2.4 states it.** *Coordinator* (D32, C5).
- *Evidence*: §1 D32 items 3-5.
- *Counterexample*: reading `.stack_sizes` works on the three Linux
  targets and reads nothing on macOS (`MCObjectFileInfo.cpp:1273-1277`):
  a per-target gap. Reading `getStackSize()` alone under-counts by the
  return address on every x86-64 call (`X86FrameLowering.cpp:76-77`).
- *Correction*: §2.4.
- *Deletes*: §2.4's list.
- *Discriminated by*: a program whose acyclic depth is known (a chain of
  k calls each with a known large local array) runs with its bound and
  the next page of its stack unmapped: it exits 0; one with a frames miss
  injected is an internal error at build.

**I-10. GMP without `alloca`.** *Coordinator* (C5's GMP row).
- *Evidence*: `bootstrap.sh:1060-1066`; `gmp-impl.h:373-403`;
  `configure.ac:104-114`.
- *Counterexample*: `product [1..100000] : Integer` multiplies operands in
  GMP's divide-and-conquer range, each level taking up to 32,512 bytes of
  stack by `TMP_ALLOC` (*recalled*: the recursion), so GMP's stack use
  grows with the operands and no fixed margin is sound.
- *Correction*: `--enable-alloca=malloc-reentrant` in `args_gmp`; GMP and
  the runtime with `-fstack-clash-protection`.
- *Deletes*: C5's stated reason; the alloca term of the margin.
- *Discriminated by*: `nm` of GMP's archive shows no `alloca` call
  (*measurement to take*: `llvm-objdump -d libgmp.a | grep -c
  "__chkstk\|sub.*sp, sp, x"` against the default build); the bench's
  bignum rows measure the heap temporaries' cost.

**I-11. TailKind's third case for D34.** *Coordinator* (D34, D30's
carrier).
- *Evidence*: §1 D34.
- *Counterexample*: counting inserts a `dup` of the holed cell (for a
  borrowed reader of the result): `contextAt` returns none
  (`IR/Tail.cpp:134-143`) and `copy`'s recursion keeps its frames,
  silently; the promise depended on counting's choice.
- *Correction*: §2.5; the frontend writes the kind; the verifier holds
  counting to it.
- *Deletes*: `inTailPositionModuloContext`'s recomputation; TRMC's second
  `contextAt` on the clone (10 Tr-3).
- *Discriminated by*: `copy` of a list of 10^8 cells runs with no frame
  pushed (the frames statistic of the run is zero: a test reading the
  ending's record, not a pass name).

**I-12. D33 corrected, and our recursions to worklists.** *Coordinator*.
- *Evidence*: §1 D33.
- *Counterexample*: an attribute nested 10,000 deep, which compile-time
  evaluation makes from a list of 10,000 elements (upstream/10's README),
  overflows any small tools stack in the parser; a generated `else if`
  ladder of 10,000 branches recurses 10,000 deep in `walk`.
- *Correction*: one upstream patch per recursion family of §1 D33 item 3
  (`walk`; the printer; the parser; attributes' parse, print, alias walk,
  walker and replacer; the bytecode writer; clone; drop and destruction;
  region DCE; dead-code initialization; call graph construction; slices),
  each with its upstream test, PINS.md entry and plan; this lane's
  recursions (§1 D33 item 1) as worklists, most deleted by I-1 and I-5.
  The measurement to take first: the deepest stack of `idris-mlir` on the
  stage-1 module and on the S1 fixtures, by painting the reserved stack
  before the run and finding the high-water mark after (no build here).
- *Discriminated by*: `tests/upstream-recursive-attribute-parser` and a
  10,000-deep ladder fixture pass under the tools' measured stack.

**I-13. C4 as §2.6 states it.** *Coordinator*.
- *Evidence*: §1 C4.
- *Counterexample for the order condition*: `f (S n) = f n + g n` where
  `g 3` and `g 7` crash with different causes: the original evaluates the
  recursion first and crashes at `g 3`; a loop that adds top down crashes
  at `g 7` first; the crash site (D38) differs. The rule admits the site
  only when `g` is total.
- *Deletes*: the countdown recognizer (`AccumulatorPlan.cpp:165-210`,
  `Accumulate.cpp`'s countdown action), `Site`'s optional (10 H-6).
- *Discriminated by*: a test per operation of §2.6 item 1 whose
  accumulated and plain forms print the same output, and the crash-order
  test above.

## 5. Work units

Drafts; none dispatched. Paths are real; `compiler/spec/` is C7's home
of the specification.

- **W1. TailKind on the call.** *Writes*: the call's record in the
  specification under `compiler/spec/` (L03's layout), the generated
  `.td` it emits, `lib/IR/Func/Call.cpp`, `lib/IR/Func/Func.cpp` (region
  verifier), `lib/IR/Func/Inliner.cpp`, `lib/IR/Tail.cpp`,
  `include/idr/IR/Tail.h`. *Outcome*: §2.1's property, verifier,
  composition. *Deletes*: the per-query climb. *Must not*: give the
  builder a default; keep a second derivation. *Acceptance*: a module
  with a `tail` call followed by a drop fails verification; every
  existing program test passes.
- **W2. The frontend writes it.** *Writes*:
  `compiler/src/IdrisMLIR/Frontend/Translate/*.idr` where calls are
  emitted, the call builder (`compiler/src/IdrisMLIR/Dialect/Idr.idr`
  until D50/D51 generate it). *Outcome*: `tail` in return position,
  `modulo_context` per §2.5. *Must not*: derive it by a pass. *Acceptance*:
  both hosts build; the IR of a mutual recursion shows `tail` on its
  calls.
- **W3. Readers switch.** *Writes*: `lib/Analysis/Ownership/Borrows.cpp`,
  `lib/IR/Lifetimes.cpp`, `lib/Transforms/Stack/Stack.cpp`,
  `lib/Analysis/Recursion.cpp` (deleted with its header), the passes
  that build calls (`lib/Transforms/Defunctionalize/{Patterns,PatternsCalls,Forces}.cpp`,
  `lib/Transforms/Specialize/Redirect.cpp`, `lib/IR/OpsClosures.cpp`).
  *Outcome*: §2.2's rows for borrows and stack. *Acceptance*: I-3's and
  I-4's programs.
- **W4. The lowering and the materialization.** *Writes*:
  `lib/Conversion/TailCalls.cpp`, `PassThroughMemory.cpp`,
  `ReturnRegisters.cpp`; deletes `TailCallPlan.cpp`, `TailPosition.cpp`,
  `Frame.cpp` and their headers, the statistic in `Passes.td`'s generated
  source. *Depends*: DP-38's call op through the lowering (L13).
  *Outcome*: §2.1's lowering. *Must not*: decide tail position.
  *Acceptance*: every tail call of the program tests is `musttail` in the
  LLVM module (a property check), the four targets build and pass.
- **W5. Returned keeps tail calls.** *Writes*:
  `lib/Transforms/Tail/Returned.cpp`, `ReturnedArguments.cpp` (with 10
  D3's redesign). *Acceptance*: I-2's program.
- **W6. Frames rebuilt.** *Writes*: `lib/Transforms/Tail/{FramesPlan,Frames,FramesTypes}.cpp`,
  `include/idr/Transforms/Tail.h` (frames part), the frames family's
  layout in the specification (with L04), the lowering of the frame
  stack (`lib/Conversion/`, a new unit), the runtime's frame stack
  (`runtime/Frames/`, new: `idris_rt_frames_grow`, `_shrink`, the
  thread-local top). *Outcome*: §2.3. *Deletes*: §2.3's list. *Must
  not*: count frames; copy a continuation per site. *Acceptance*: I-5,
  I-6, I-8's programs; the frames fixtures of S1.
- **W7. The stack bound and the runner.** *Writes*:
  `lib/Driver/Artifacts.cpp` and a new `lib/Driver/StackBound.cpp`, the
  target entries in `CMakeLists.txt` (margins, measured),
  `runtime/Start/{Runner,Entry}.cpp`, `Start.h`, `runtime/idris_rt.h`,
  `runtime/Platform/Posix/Stacks.cpp`, `include/idr/Support/Stack.h`.
  *Outcome*: §2.4. *Deletes*: the 64 GiB constant and its kin.
  *Acceptance*: I-9's two programs on the four targets; a program starts
  under `ulimit -v` at its bound plus heap.
- **W8. GMP's policy.** *Writes*: `tools/bootstrap.sh` (`args_gmp`),
  `PINS.md`. *Acceptance*: I-10's measurement; the bignum tests pass.
- **W9. Upstream recursions.** *Writes*: one `upstream/<id>-…/` per
  family of I-12 with its patch, report, test and plan; `PINS.md`;
  `tests/upstream-<id>`. *Acceptance*: each test; then the tools' stack
  shrinks in the last one's change (W7's tools half).
- **W10. Accumulation widened.** *Writes*:
  `lib/Transforms/Tail/{AccumulatorPlan,Accumulate}.cpp`, the closed-form
  rewrite beside `TailLoops.cpp`. *Acceptance*: I-13's tests.
- **W11. TRMC executes the kind.** *Writes*: `lib/Transforms/Tail/Trmc.cpp`,
  `lib/IR/Tail.cpp` (`contextAt` as the rule's reading). *Acceptance*:
  I-11's program.

## 6. Owner questions

**Q1. The thread's stack under D35.** D35 says a program "commits no
memory before it uses it"; C5 applies it to the stack ("reserved
`PROT_NONE`, made writable as used"). Under strict overcommit a writable
stack mapping is charged whole at creation (*recalled*).
- *A, charge the static bound at start*: the stack is mapped writable at
  its computed size (tens to hundreds of KiB, the program's own worst
  case by construction). Buys: no fault handler state beyond the guard,
  no signal on first touch, one mapping. Costs: that many bytes charged
  before the deepest call happens; D35's letter bent for the stack.
- *B, commit page by page*: the stack reserved `PROT_NONE` but its top,
  the fault handler making the next pages writable (18 T-STK3). Buys:
  D35's letter. Costs: a signal round trip per page first touched, a
  second fault kind in the handler (reserved but uncommitted against the
  guard), for a region D32 already made small.
- *Recommendation*: A. A strict host starts the program either way; the
  static bound is what the program may use, computed, not guessed.

Handoff, as the dispatch asks: file
`audits/p0/verify/L10-tail-frames-stack.md`; HEAD `e96bb991` at start and
finish.
