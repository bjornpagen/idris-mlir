<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# P0 wave 2, lane frontend-checks: the frontend's refusals, analyses and proofs

Subsystem: `compiler/src/IdrisMLIR/Frontend/Growth.idr`,
`Frontend/Growth/` (Caps, Check, Fields, Graph, Heads, Implementations,
Potential, Sites, Template), `Frontend/Finite.idr`, `Frontend/Profile.idr`,
`compiler/src/IdrisMLIR/Proof/` (Forms, Generations, Growth, Bound,
Requests), `compiler/src/IdrisMLIR/Facts.idr`.

Status: written 2026-10-21 at e96bb991. Read-only: nothing was built or run;
measurements are counts over the source, or quoted from the commit that
recorded them.

## 1. Reading notes

Written while reading, in the order read. Nearly all of the proposal is
about the C++ side; what follows is what bears on the frontend's
refusals, analyses and proofs.

- **§1, §4 (the bar).** Representation first before everything; "a
  budget never rejects a program"; "Hard cutover"; AGENTS.md kept whole.
  §4: "An analysis that a refusal rests on gets termination by
  construction (a finite-height lattice, or widening), no cap at all"
  (stated in §5.3 M9 and S1). This is the line every count in the
  subsystem is judged by; `Frontend/Growth/Caps.idr`'s "caps" turn out to
  be type-derived bounds, not budgets (§3).
- **§2 (brief).** Idris frontend about 31,000 lines; the subsystem here
  is about 9,960 of them (measured, §2 of this document). §2 lists no
  frontend analysis; wave 1 did not read our code.
- **§3 (walls).** Every wall in the table is in the C++ pipeline; none is
  in the frontend's checks. Lesson that carries over: per-value state
  copied along edges (b8301ebe), per-pair interface queries (e96bb991),
  a table rebuilt per declaration (73bba53f). Checked against our Idris
  analyses in §4 of this document (state, rederivation).
- **§5.3 (llvm).** C1: the Attributor's round cap (32) forces the
  pessimistic state, "costs precision, never soundness". C3: LVI caps
  work per value at 500, precision only. C5: clang's cap of 20,000 block
  visits returns an *error* and refuses a CFG larger than the cap before
  solving: "we must never copy it" (M9). M9: "An analysis that a refusal
  rests on gets termination by construction ... no cap at all." S1's
  termination clause: "Finite height or widening at SCC back edges ...
  for every analysis a refusal rests on; an optimization-only analysis
  may stop at a budget ... No error on a budget, ever." **Q-llvm-2** is
  this line put to the owner. S0: "before S1 is given an analysis, wave 2
  asks of it: could the dialect carry this answer ... so that no pass
  solves for it?" Asked here of every frontend analysis (§3). B8:
  `scc_iterator` over `GraphTraits` against a hand-rolled SCC; the Idris
  side has two hand Tarjans (`Growth/Check.idr`, `Translate/Recursion.idr`)
  to weigh the same way (§4 FC-71). E3/M10/Q-llvm-5: one TableGen tool generating the
  Idris mirror: bears on whether refusal categories reach the Idris side
  generated (AGENTS.md: "Every refusal's rule carries its category in
  ODS").
- **§5.4 (modular).** Mojo's elaborator is the nearest relative of the
  frontend's monomorphizer. F11: "no depth cap by default ...
  recursion is found by SCC (`diagnoseAndBreakRecursion`)". F22:
  demand-driven from roots, instance keyed by an interned (definition,
  parameters) pair, "a cycle shows as an exhausted work queue with roots
  unfinished, then a trimmed DFS breaks it or reports it". F23: "Its
  limits mostly degrade, one refuses by count": an opt-in depth cap
  "elaborator expansion is N levels deep - infinite recursion?", a depth
  that "varies based on the traversal order of the callgraph"; F17 lists
  that optional cap among what "our rules forbid". Item 8: "only one limit
  that refuses, an opt-in depth that depends on traversal order. Our
  rules already forbid that one". F15: CheckLifetimes' loops "converge on
  a lattice whose bits only fall ('we know this will terminate'): a
  measure, not a count", while one place "asserts a count"
  (`numIters < 5`). F19: `TriResult<Yes, No, Unknown>` with a payload per
  state, "deliberately no conversion to `TriBool`", and
  `ElaborationState` "in place of a `bool` and a side flag": the C++ form
  of the skill's "Decide, don't test"; bears on every `Bool` and `Maybe`
  in the growth check (§4). F24: Mojo erases origins and traits before
  monomorphizing; "what we must not do" (item 8). **Q-M5** (specializer
  shape) bears on where the frontend's monomorphizer's guarantee is
  consumed.
- **§5.6 (ecosystem).** A2: CIRCT's IMConstProp cuts an op of more than
  128 operands to overdefined: "degrades the answer, never refuses, which
  is the shape AGENTS.md's budget rule asks for". C3: IREE turns DFX's
  spent round budget into a compile error: "exactly what AGENTS.md
  forbids: the solver had already produced a sound answer, and the pass
  threw it away to refuse the program". D2: a fixed-point pipeline with a
  round count that refuses: rejected. Item 3: "An SCC whose members are
  iterated until no summary changes is essential complexity, and it
  terminates because summaries are finite lattices joined monotonically:
  by construction, with no round count." Item 5 (the line **Q-E3**
  confirms): "an analysis a refusal rests on (knots, the in-place
  promise) has no budget, and terminates by its lattice". Note item 5
  names the C++ side's two refusals only; the frontend's growth refusal
  is a third analysis a refusal rests on, and the proposal never names
  it (gap, §3 of this document). Item 6: extract, solve, write back; the
  frontend's growth check is already this shape (extract `Rule`s from TT,
  solve on plain data, refuse or pass): §3. W-E5 asks for every budget,
  round count and cap "and whether any becomes a failure": answered for
  the frontend in §3.
- **§5.7 (library).** H1: Mitchell's supercompiler terminates by a
  well-quasi-order over bags of source names, "a finite alphabet for a
  given program ... the check is a set comparison and a count": the
  representational form of "this specialization terminates", the same
  question the frontend's growth check answers (does monomorphization of
  the closed program reach finitely many instances). H3: two-level type
  theory makes binding times types: "what a binding-time analysis would
  infer is instead stated, and checked by typing": bears on whether
  "this argument is static" (the growth check's `Static` positions) is
  inferred or carried. L5 (clones as keys): "termination comes from keys
  drawn from a finite alphabet, so a budget only ever limits
  profitability"; "Made unrepresentable: ... a termination argument that
  rests on a count". This is the frontend's acceptance question restated
  for the C++ specializer: the frontend's growth check is the proof that
  the key alphabet is finite (§3 of this document). M7: one-way
  composition reads a frozen answer; a non-monotone question is the
  complement of a monotone one read after the freeze (A2, F6). Wave-2
  questions of §5.7.4: "For each specializer: what its key is, whether
  keys come from a finite alphabet, and whether any budget decides
  termination (L5)": the frontend's monomorphizer is answered in §3.
  "is its fact a lattice per value (PLV) ... or relational?": answered for
  each frontend analysis in §2.
- **§5.9 (mlton).** The section most directly about this subsystem.
  **M10**: "Monomorphization never refuses in SML. MLton's monomorphiser
  is total because SML's polymorphism is rank 1 without polymorphic
  recursion (D1 terminates by the program's scoping). Idris allows what
  SML forbids, and AGENTS.md's `unsupported` refusal of megamorphic
  constructs is exactly the boundary MLton never had to draw; MLton
  offers no lesson on where to draw it, only on how cheap the admitted
  part can be." D1: `Monomorphise` is one pass, no worklist, an instance
  cache per binding keyed by type-argument vector, thunks forced in
  reverse order: "cost is linear in the output; the order is the
  program's own scoping, so termination is by construction". B3/B4:
  analyses as one constraint-generating abstract interpreter, cells as
  union-find with handler lists, "no worklist and no iteration count".
  B5: state sized by types and constructors. G2.7: "Facts written into
  the IR's types ... Nothing is carried between passes except the
  program". C2: "MLton spends a new IR type where the change of
  representation is large ... and a checked invariant where the change
  is an absence": SXML's "no tyvars" is a comment enforced by the checker
  at the boundary. Applied here: the frontend's refusal is the checked
  boundary between "polymorphic TT" and "monomorphic module"; what it
  proves should become representation on the far side (§5). I3: Kovács'
  two-level type theory "bears on how the frontend might promise
  closure-freedom by type". Q-O3 (facts into types) and Q-E2 (where a
  summary lives) bear on whether the frontend's analysis results reach
  the dialect as types (§6).
- **§5.11 (oom).** (A) "A budget may only stop optimization, and only in
  the program's units ... the passes acceptance rests on
  (defunctionalization, the label solve, counting, lowering) cannot be
  budgeted at all: their memory must be bounded by construction." The
  frontend's growth check is a pass acceptance rests on, and the list
  omits it (same gap as §5.6 item 5). C4: GHC's simplifier tick budget is
  "the right measure with the wrong consequence (it rejects)". C7:
  "Determinism is the binding constraint on a compiler's budget ... one
  counted in bytes of RSS or in seconds does not [give the same output]".
  A1: each solver's state sized in the program's units; "a state sized by
  a product of two program quantities is a wall waiting to be met":
  checked for every frontend analysis in §4 (state). A4/**oom-2**:
  budgets "in program units only ... never at bytes or seconds". **oom-1**:
  out of memory outside the language's meaning, a named crash, never a
  value or an effect. Rejected: "a hard RSS limit that ends compilation as
  if the program were at fault (a refusal by resource, which AGENTS.md
  forbids)". Wave-2 item 7: "Every solver and pass whose state is sized by
  a product of two program quantities": the frontend's are in §4.
- **§5.5 (cxx26).** D4(a): "An op's runtime symbol ..., its refusal
  category, its effect row: each is emitted to C++ and to Idris from the
  one record, never typed into a C++ `switch`." D8: `std::expected<T,
  Reason>` "when the failure is data the caller branches on (a refusal's
  category, generated from ODS: AGENTS.md puts every refusal's category
  there)". Checked against the frontend's refusal path in §3.
- **§5.8 (dialect-design).** EF1: "Totality is a trait on the op";
  "Whether non-termination is kept (an effect) or only blocks speculation
  is a semantic question for the owner" (DD-Q2, ods-Q1). The frontend is
  where "this function's loops end" is first known (`Facts.terminating`);
  §3 records what reaches the dialect. DS2.1: a trusted library's forged
  world becomes a region op; `Profile.idr`'s trust classification is the
  frontend's side of who may forge one (AGENTS.md: "A trusted library may
  run an IO action ... User code may not").
- **§5.1, §5.2, §5.10.** Read their summaries, questions and notes. Their
  wave-2 questions (W1-W7, W1-W10, W1-W9) are all C++; none falls in this
  subsystem.
- **0003 (each fact once)**, items that name this subsystem:
  rebuilt terms take `EmptyFC` (`Growth/Sites.idr`,
  `Growth/Template.idr`), `Sites.siteAt` copies `bestFC`'s fallback, and
  "reach refusals (`Profile.userFC`) are placed at the reference, not the
  referring definition"; B3, `Profile.imports` scans the source with
  `words`; "Erased arguments, five readers", one of them
  `Sites.quantitiesOf`; C3, `Sites.conStands` has its own constructor to
  type-constructor map; C5, `Growth/Sites.holed` and `Terms.holed`
  disagree, "a disagreement surfaces as an internal unsoundness"; B5, the
  registry's `validate` returns only `Maybe Refusal`; `lookupDef EmptyFC`
  while the site is known (`Growth/Caps.idr`); "`tot = fromMaybe False`
  where the component was always checked"; `Crash` re-derives trust
  though `Profile.level` classified it; `Profile.refsOf` reads default
  facts for non-user names; "A refusal rule's category false of some of
  its sites": `StaticArgument` is megamorphic, yet a test refuses a choice
  the program bounds "behind a `covering` chooser"; "about 35 more
  position or membership lookups in `Translate/Types.idr` and
  `Growth/Sites.idr`"; "`TS.loops` is a `SortedMap Address Bool`, and
  `Template.Computing` is matched outside where it is built (Caps, Graph,
  Heads, Sites)"; "`Profile.proofOnly` asks `isErased` after its own
  lookup". Each is checked against the code in §4.

## 2. What the subsystem is

### 2.1 Files and sizes (*measured*)

`wc -l` over the listed files: 9,964 lines, 31.6% of `compiler/src`
(31,557 lines, `find compiler/src -name '*.idr' | xargs wc -l`).

| file | lines | what it is |
| --- | ---: | --- |
| `Frontend/Growth.idr` | 336 | the phase: build the graph, `check`, write bounds into `TS`, or refuse each cause as `Polymorphism` |
| `Frontend/Growth/Sites.idr` | 1,477 | what each definition writes at the static positions of what it calls and builds (`Site`, `Argument`, `Reach`), read off signature and case tree with every parameter a marker |
| `Frontend/Growth/Template.idr` | 1,406 | `Template` (11 constructors), its readings of a closed term per `Static` kind, and the measures on it (height, arity, weights, beta, landing) |
| `Frontend/Growth/Graph.idr` | 980 | the definitions' walk, the node walk, the arcs, caps, landings, family evaluation, the one numbering into `Fin` |
| `Frontend/Growth/Check.idr` | 708 | the decision: Tarjan, per-component settle, certificate `Verdict` |
| `Frontend/Growth/Potential.idr` | 687 | certified Bellman-Ford (Lemma 2): a positive cycle or a feasible potential |
| `Frontend/Growth/Heads.idr` | 478 | the dictionary and family flow (least sets per slot), the node split |
| `Frontend/Growth/Implementations.idr` | 233 | an implementation's fields over its parameters (`Method`, `Plain`) |
| `Frontend/Growth/Caps.idr` | 194 | a shape parameter's cap: one more than the deepest match its type makes on it |
| `Frontend/Growth/Fields.idr` | 128 | a data type's fields as sites of the type |
| `Frontend/Finite.idr` | 441 | the translation's worklist, recursing on accessibility; the run-time witness of the growth check (`heightWithin`, `sizedWithin`) |
| `Frontend/Profile.idr` | 483 | pragma and escape-hatch checks on the source; the reachability walk over TT with trust rules |
| `Proof/Requests.idr` | 841 | `Address`, `Listed`, `Token`, `Written`, `Link`, `Bounds`, the erased `Universe`, `within` |
| `Proof/Bound.idr` | 673 | Lemma 1, Theorem 1: erased, over a model `Term m` of templates; nothing runs |
| `Proof/Growth.idr` | 445 | `Decision`, `Weight`, `Label`, `Graph`, the certificates (`Positive`, `StuckArc`, `Feasible`) |
| `Proof/Forms.idr` | 263 | the finite alphabet of a written argument (`Shape`, `Binding`, `Passing`, `Form`) |
| `Proof/Generations.idr` | 173 | the multiset-ordering argument a FIFO worklist recurses on |
| `Facts.idr` | 18 | `record Facts { terminating : Bool }` |

### 2.2 What it computes, in pipeline order (*read*)

`Frontend/Program.idr:209-235` runs, in order: imports
(`Profile.imports`), pragmas (`checkPragmas`), reachability
(`checkReachable`), growth (`checkGrowth`), then translation
(`translateIOProgram`, whose worklist is `Finite.translateFrom`).

1. **Profile** (`Profile.idr:146-183`, `306-483`). Lexes each user module
   with Idris's lexer and refuses every pragma not in `discharged`
   (`:140-141`), every hole and every spelled escape hatch. Walks TT
   breadth-first from main (`level`, `:427-468`), entering each definition
   once into a `Walked` (measure: free places, `Walk.idr:92-192`), and
   refuses: an untrusted module (`:349`), a reach-forbidden rule
   (`outsideLanguage`, `:357`), a deprecated name (`:362`), an escape hatch
   unless a trusted definition reaches a library crash (`:368-379`), an
   unregistered `%extern`/`%foreign` (`:383-392`), a definition a trusted
   module does not admit (`:397`), a name-forbidden rule or `%MkWorld` in
   user code (`:401-408`). Writes `TS.refused` (a `SortedSet Address`),
   `TS.spelled` (`SortedSet (ModuleIdent, String)`).
2. **Growth** (`Growth.idr:324-336`). `Graph.build` (`Graph.idr:920-980`):
   the definitions reachable from main (`definitions`, breadth first on
   `Walked`), each read once at the node with no heads (`Sites.readingOf`);
   the flow of dictionaries and families over unsplit definitions
   (`Heads.flow`, a monotone fixpoint over a finite listing, `:347-377`);
   the readings at every headed node (`Graph.readings`, `:825-836`); the
   node walk from main (`visit`/`under`, depth first, novelty per path,
   `:360-391`); caps (`capsOf`, `:781-789`); landings of family values
   (`landings`, `:686-708`) and evaluation of families given closed values
   (`evaluated`, `:890-913`); arcs (`raw`, `:760-765`); the projection rule
   (`:966-967`); the one numbering into `Fin` (`:971-978`). Then
   `Check.check` (`Check.idr:685-708`): Tarjan's components, callers
   first, each settled as steady (walk back) or by heaviest walks
   (`Potential.heaviestOver`), the potential rechecked (`feasibleIn`)
   with a certified fallback. Admitted: `TS.bounds : SortedMap Position
   Nat` and `TS.sizes : Bounds` are written (`Growth.idr:330-333`) and
   `True` returned. Refused: each `Cause` reported once as rule
   `Polymorphism` (`:305-310`) and `False` returned.
3. **Finite** (`Finite.idr:409-441`). The translation's worklist, a
   generation at a time, each request judged against the instance's
   chain: its static arguments' heights against `TS.bounds`
   (`heightWithin`, `:186-192`), its link against `TS.sizes`
   (`sizedWithin`, `:196-202`, giving the erased `InUniverse`), and new to
   the chain (`elemLink`). It recurses on `Accessible (Follows (Fresh b))`
   (`Proof/Generations`), then in rounds on the room left in the finite
   universe of dictionary fields (`:421-441`).
4. **Facts**: the frontend's one proved function fact, `terminating`,
   built in `Translate/Programs.idr:78-79` (from `TS.loops`, which
   `Translate/Recursion.idr` fills from Idris's size-change graphs) and
   written by Emit as the inherent `UnitAttr:$total` of `idr.func`
   (`Emit/Declarations.idr:56`; `foreign/idr/include/idr/IR/IdrOps.td:161`),
   which C++ reads as the body's divergence (`lib/IR/Func/Func.cpp:190`)
   and in `Tail/Loop.cpp:131`, `Tail/WhileDo.cpp:280`, `Tail/FramesPlan.cpp:161`.

### 2.3 Every fact it holds or derives (*read*)

| fact | representation | where made | who reads it |
| --- | --- | --- | --- |
| a definition reached, trusted or not | `Walked`, `Referrer = User \| Library Placement`, `Loc.origin` | `Profile.level` | Profile only |
| refused definitions | `TS.refused : SortedSet Address` | `Profile.level:450-451` | `Graph.level:198`, `Sites.nodeSites:1422`, translation |
| hatches spelled in source | `TS.spelled : SortedSet (ModuleIdent, String)` | `Profile.checkPragmas:164` | `Profile.level:459` |
| a site | `Site { writer, within : Address; reach : Reach; arguments; fc }` | `Sites.siteAt:293` | Graph, Heads, Growth (messages) |
| a static argument read | `Template` + `Root`, `Argument.term : Maybe ClosedTerm` | `Template.rooted:1395` | Graph (arcs), Heads (flow), Instances (request heights) |
| what a parameter stands for in a walk | `Stand` (6 cases) in `Standing = (Stand, Name, Maybe ClosedTerm)` | `Sites.standFor:1296`, `conStands:1082` | Sites |
| dictionary and family flow | `View = SortedMap Slot (SortedSet Address)`, `Slot = (Fin 2, Address, Address)` | `Heads.flow:376` | `Heads.reaches`, `Heads.roots`, `Graph.familyHeads` |
| a node | `Node { definition : Address; heads : List (Nat, Address) }` | `Heads.reaches:446` | everything keyed by `Position = (Node, Nat)` |
| a cap | `Maybe Nat` per position, `Graph.caps : Vect size (Maybe Nat)` | `Caps.capOf:163` | `Check.floors`, `Proof.Growth.bound` |
| what lands at a family | `Landing = Closed Nat \| Open \| Computed \| Evaluable (List ClosedTerm)` | `Graph.landings:686` | `Template.withClosedFamilies:1110`, `Graph.evaluated` |
| an arc | `Arc n { from, to : Fin n; label : Label }`, `Wrote = FromArgument Site Argument \| FromField` | `Graph.build:977` | Check, Growth (messages) |
| the verdict | `Verdict g = Grows (List1 (Cause g)) \| Bounded pot (Feasible g pot)` | `Check.check` | `Growth.checkGrowth` |
| position bounds | `TS.bounds : SortedMap Position Nat` | `Growth.boundsOf:47` | `Finite.heightWithin`, `Translate/Types.idr:853` |
| sizes per definition | `TS.sizes : Bounds { heightAt : Address -> List Nat; arity; heaviest; breadth }` | `Growth.sizesOf:70` | `Finite.sizedWithin`, `within` |
| a request's identity | `Link Form { definition : Address; arguments : List (Maybe (Written Form)) }` | `Translate/Keys` (lane 15) | `Finite`, `TS.named` |
| a function terminates | `Facts.terminating : Bool`, from `TS.loops : SortedMap Address Bool` | `Programs.idr:78` | Emit, then C++ `getTotal` |

### 2.4 State, threading, and the state models (*read*, *measured* where marked)

All of it runs single-threaded inside `Core` with two `Ref`s (`Ctxt`,
`TState`). There is no parallelism on the Idris side.

Per analysis, the state model (§5.7's PLV question, §5.9's Q-W2):
- **Profile's walk**: one bit per definition (`Walked`), plus
  `Kept.arrivals : SortedMap Address (List Reach)` per trusted definition.
  Linear.
- **Heads' flow**: set-valued per slot (PLV, monotone sets over a finite
  listing), *type-filtered*: only dictionary and family arguments are
  slots (`splitting`, `Heads.idr:204-209`), which is §5.6 Design 2's
  rule already. Solved by naive rounds: each round re-yields every
  equation over a `View` rebuilt from the seen list (`round`, `:350-357`;
  `viewOf`, `:142-143`), each candidate searched for in the seen list
  linearly (`isNew = isElem`, `:127-128`). *Measured* (comment,
  `Heads.idr:107-109`): 1,723 entries over 661 slots on the self compile's
  prototype.
- **Growth graph**: relational (arcs between positions); the answer is a
  potential per position under difference constraints (`Satisfies`).
  Positions are numbered once into `Fin size` (`Graph.idr:971-978`), and
  `Check` keeps its per-position state in a binary trie (`Check.Table`,
  `Check.idr:77-79`), O(log n) per access. *Measured* (3fc4d2e4's
  `bench/profiles/2026-10-17-self-growth.md`): the check fell from 33 s to
  0.6 s when its tables went from `Vect` to trees; the growth phase took
  67.1 s and 77.2 s of the self compile's 1,494 s and 1,575 s; 13,218
  nodes (`Graph.idr:357`, *measured*, comment).
- **Bellman-Ford**: `Potential.Cells` is a linked list (`Potential.idr:117-119`);
  `entry` and `put` walk to the position, so one round is O(arcs x
  positions) and the worst case O(arcs^2 x positions) (*read*,
  arithmetic). It runs only on a component with a losing arc
  (`Check.judge`, `:586-592`), over that component's inner edges.
- **Node walk**: per-path novelty (O(nodes x depth), `Graph.idr:354-359`),
  a `SortedSet Node` of entered nodes.
- **Worklist**: one `Item` per request, its chain a `List Request`;
  freshness by `elemLink`, linear in the chain (`Requests.idr:835-841`).

State sized by a product of two program quantities (§5.11 A1, the
"wall waiting to be met"), *read*:
- `Heads.combinations` (`Heads.idr:416-422`): one callee node per element
  of the product over its dictionary and family parameters of the roots
  the flow allows. The flow is context-insensitive, so the product can
  hold combinations no request makes.
- `Graph.familyHeads` (`Graph.idr:813-816`): every way of heading a
  subset of a definition's families, a product of the flow's type
  constructors per family.
- `Graph.evaluated.choices` (`Graph.idr:871-873`, `903-907`): one argument
  per element of the product of the values landing at each applied
  family.
- `Sites.rebound` (`Sites.idr:1063-1072`) rewrites the whole environment
  for every alternative of a match on a shape (`alternatives`, `:1173-1180`;
  `expand`, `:1221-1232`): per-branch copying, O(alternatives x scope),
  b8301ebe's shape in Idris.

### 2.5 Who reads its results (*read*)

- `TS.refused`: `Graph.level`, `Sites.nodeSites`, the translation.
- `TS.bounds`, `TS.sizes`: `Finite` and `Translate/Types.idr:839-853, 984`
  (data registration).
- `Template.closedHeight`, `rooted`, `templateOf`: `Translate/Instances.idr:65`
  and `Types.idr:852` (a request's and a data instance's heights).
- `Finite.translateFrom`: `Translate/Programs.idr`.
- `Facts`: `Term.idr:534` (`TFn.facts`), `Emit/Declarations.idr:56`.
- Nothing on the C++ side reads anything of the growth check: the bounds
  end with the translation (*read*: no `bound`, `potential` or growth
  attribute in `Emit/`).

### 2.6 Proofs and totality (*measured*)

`grep -rn -E '\bcovering\b|assert_total|assert_smaller|believe_me|postulate|^\s*partial\b'`
over the subsystem, comments excluded: nothing (the two hits are the
strings `"believe_me"` and `"idris_crash"` in refusal messages,
`Profile.idr:376, 378`). 3fc4d2e4's message: "no assert_total, covering,
believe_me or postulate in the proof or the checker". Every recursion is
structural or on an `Accessible`/`SizeAccessible` measure: `Walked`'s free
places (Profile, Graph's definitions walk, Template's unfoldings, Sites'
metavariables), `Room` (node walk), the listing's room (flow), `unseen`
(Tarjan), the rounds left (Bellman-Ford, k + left = the arcs' count), members
(`walkBack`), `Follows (Fresh b)` (worklist), the field universe's room
(rounds). No fuel, no budget, no round cap (`grep -i -E 'fuel|budget|maxIter'`:
nothing).

`Proof/Bound.idr` proves Theorem 1 (every value at a position is within
`bound`) over a *model* (`Term m`: `Head`, `Var`, `Leaf`) and "the
frontend builds no derivation. The worklist checks the conclusion on
every request, so a site read otherwise raises an internal error there"
(`Bound.idr:55-58`). The link between the code's `Template` (11
constructors) and the model's `Term` is the run-time check in
`Finite.heightWithin`/`sizedWithin` and `Translate/Types.idr:853`. That
is the subsystem's one honest gap between proof and program (§8).

## 3. Reconciliation with the proposal

### 3.1 Findings and designs that touch the subsystem

| finding or design | verdict | evidence |
| --- | --- | --- |
| §4, §5.3 M9 and S1, §5.6 item 5, §5.11 (A): an analysis a refusal rests on has no budget and terminates by construction | **holds**, and the frontend already meets it | §2.6: no fuel, no cap, no round count in the subsystem; every recursion on a measure. The two counts that exist are not budgets: Bellman-Ford's rounds, as many as the arcs (`Potential.loop`, `Potential.idr:657-669`), whose exhaustion yields a certified positive cycle (`climb`, `:619-644`), never a refusal for having run out; and `walkBack`'s rounds = members (`Check.idr:492-496`), the length bound of a simple walk |
| §5.6 item 5 and §5.11 (A) list the analyses acceptance rests on: "knots, the in-place promise", "defunctionalization, the label solve, counting, lowering" | **holds in part: a gap** | Neither list names the frontend's growth check, which is the analysis the `Polymorphism` refusal rests on (`Growth.idr:268, 298`; `IdrBase.td:199`, category `Megamorphic`), nor the reachability walk the `Profile` refusals rest on. Both meet the rule (§2.6); the plan's rule (§7) should name them so that no later change gives them a budget |
| §5.3 C5 / M9: clang's cap refuses a CFG larger than it; "we must never copy it" | **holds**; not copied | `Caps.idr` is no cap in that sense: a cap is a bound read off the callee's type (`capFrom`, `:133-134`; proof in the comment `:88-132`), which *admits* programs (a capped position takes no arcs, `Graph.idr:951-955, 968`). The file's name says "cap" for a type-derived bound; the word collides with the proposal's "cap" (a budget) and should not survive the rename (§5) |
| §5.4 F11, F22, F23, item 8: Mojo's elaborator finds recursion by SCC; its one refusing limit is an opt-in depth that depends on traversal order | **holds**; our monomorphizer has no such limit | The frontend decides growth on the whole graph before translating (`Program.idr:224`), and the worklist cannot exceed the bounds without an internal error (`Finite.idr:186-202`). Nothing depends on traversal order: the potential is the least one (`Check.idr:697-701`) |
| §5.9 M10: "Monomorphization never refuses in SML ... AGENTS.md's `unsupported` refusal of megamorphic constructs is exactly the boundary MLton never had to draw" | **holds** | MLton's D1 terminates "by the program's scoping"; ours by a decided graph (`Check`) plus a finite universe (`Proof/Requests.Universe`, `:733-737`) the worklist recurses on. The boundary is drawn as: a cycle of finite arcs whose gains exceed its losses, or an `Unmeasured` arc no growing cycle reaches (`Check.idr:49-56`) |
| §5.7 H1 (Mitchell: termination by a finite alphabet), L5 (clones as keys, "termination comes from keys drawn from a finite alphabet, so a budget only ever limits profitability") | **holds; the frontend is L5 already** | The key is `Link Form` (`Requests.idr:230-233`) over the listed alphabet `Proof.Forms.forms` (`Forms.idr:257-258`) and `addresses` (`Requests.idr:183-184`); the universe within the bounds is finite (`Universe`, erased); the worklist keeps each link once (`elemLink`) and recurses on the room (`Finite.idr:127-138`). The difference from Mitchell: the growth check gives the alphabet's *sizes* a bound before translation, where Mitchell's wqo stops a branch while driving. 3fc4d2e4 replaced exactly a wqo-style rule ("the rule that refused any request growing against an earlier one ... the old relation's AlmostFull goes") by the graph, because the wqo rule refused programs the graph admits |
| §5.7 H3, §5.9 I3 (two-level type theory: binding times stated, checked by typing) | **refuted for P0's scope; recorded** | The frontend infers binding times (`staticsOver`, `Translate/Instances.idr:240-257`, called from `Sites.idr:496, 1416`, `Caps.idr:171`, `Implementations.idr:90, 169`), because Idris 2 source does not state them. Stating them is a language change, not a representation of ours |
| §5.9 B5, G2.4 (state sized by types and constructors), §5.6 Design 2 (state only for values whose type leaves the question open) | **holds** for the flow | `Heads` keeps slots only for dictionary and family arguments (`splitting`, `Heads.idr:204-209`) |
| §5.9 G2.7, Design 3, Q-O3 (a fact a later pass reads is written into a type by the pass that proves it) | **holds in part** | The growth check's answer (bounds, sizes) is a later phase's input, but it is written into mutable state (`TS.bounds`, `TS.sizes`, `Growth.idr:332`) behind a `Bool` (`checkGrowth : ... -> Core Bool`, `:325`), and re-validated at every request (`Finite.heightWithin`), because no proof crosses the boundary (`Finite.idr:181-185`). §5's G1 makes the answer a value passed to the translation |
| §5.6 item 8 / W-E9 (structured walks copy state per branch) | **holds** in Idris | `Sites.rebound` per alternative (§2.4) |
| §5.11 A1 (state sized by a product is the next wall) | **holds in part** | three products (§2.4); none has been a wall (13,218 nodes, 67-77 s at the self compile, *measured* 3fc4d2e4) |
| §5.5 D4(a) (a refusal's category emitted to C++ and Idris from the one record) | **holds in part** | `Idr_RuleCase` carries `category` (`IdrBase.td:173-176`), and `idris-mlir-tblgen` writes `ruleCategory : Rule -> RuleCategory` into `Syntax/Idr.idr:392`, which *nothing on the Idris side reads* (`grep -rn ruleCategory compiler/src`: only its definition). `Profile.outsideLanguage` (`Profile.idr:56-65`) restates a finer category by hand: the five rules forbidden wherever reached (Threads, Finalizer, RawPointer, Signal, Process) against those forbidden only where user code names them, with prose that repeats `IdrBase.td:207-221`'s comments |
| §5.8 EF1 ("Totality is a trait on the op"; DD-Q2) | **holds in part** | The frontend's totality fact is per function, `Facts.terminating` into `idr.func`'s `UnitAttr:$total`; lane 03 owns the op side. `TS.loops : SortedMap Address Bool` and `tot = fromMaybe False (... lookup a after.loops)` (`Programs.idr:78`) collapse "never checked" into "may not terminate", a `Maybe` read as a default where 0003 says the component was always checked |
| §3's lesson from 73bba53f (a table rebuilt per declaration) | **holds** in Idris | `Heads.round` rebuilds the `View` from the whole seen list every round (`Heads.idr:355`) and re-yields every equation (`candidates`, `:293-312`): naive, not semi-naive, iteration |
| §5.3 B8 / M4 (`scc_iterator` against a hand-rolled SCC) | **holds** on the Idris side as a duplication | Two hand Tarjans in the frontend: `Check.components` (`Check.idr:328-371`, over positions, trie state) and `Translate/Recursion.idr:42-60` (over definitions, `SortedMap` state). Idris's base has no graph library both hosts share; one total Tarjan module would serve both (§5) |

### 3.2 0003's items in this subsystem, checked against the code

| 0003 item | status at e96bb991 | where |
| --- | --- | --- |
| rebuilt terms take `EmptyFC` | still true: 29 `EmptyFC` (Sites 16, Caps 4, Template 4, Implementations 3, Graph 1, Profile 1) | `grep -rn -c EmptyFC` |
| `Sites.siteAt` copies `bestFC`'s fallback | still true | `Sites.idr:293-294` |
| reach refusals placed at the referring definition (`Profile.userFC`) | still true | `Profile.idr:318-320`, `349`, `358` |
| B3, `Profile.imports` scans with `words` | still true | `Profile.idr:114-130`, read by `Program.idr:210` |
| erased arguments, `Sites.quantitiesOf` one of five readers | still true | `Sites.idr:481-486` |
| C3, `Sites.conStands` | still true | `Sites.idr:1082-1139` |
| C5, `Growth/Sites.holed` and `Terms.holed` disagree | still two functions | `Sites.idr:239-255`, `Translate/Terms.idr:739` |
| `lookupDef EmptyFC` in `Growth/Caps.idr` | still true | `Caps.idr:183` |
| `tot = fromMaybe False` | still true (lane 15's file, this lane's fact) | `Translate/Programs.idr:78` |
| `TS.loops` a `SortedMap Address Bool` | still true | `Translate/State.idr:385` |
| `Template.Computing` matched outside where it is built | still true: built only by `withClosedFamilies` (`Template.idr:1114-1119`), matched in `Caps.idr:73` (whose comment says "Never met"), `Graph.idr:532`, `Heads.idr:176`, `Sites.idr:320, 370, 415`, and 9 more folds in `Template.idr` | `grep -n Computing` |
| "about 35 position or membership lookups in ... `Growth/Sites.idr`" | still true | `getAt` at `Sites.idr:278, 304, 399, 710, 1118, 1269, 1342, 1357`; `zip`ped parallel lists at `:498, 506-508, 1129-1139, 1332-1335, 1353` |
| `Profile.proofOnly` asks `isErased` after its own lookup | still true | `Profile.idr:225-230`, called per reference at `:415` |

### 3.3 Wave-2 questions of §5 that fall here, answered by ID

- **§5.6 W-E1** (analyses deriving call-graph or SCC facts on their own).
  In this subsystem: `Check.components` (positions of the growth graph,
  not functions), and the flow's and the node walk's own reachability
  from main (`Graph.definitions`, `Graph.nodesFromMain`, `Profile.level`:
  three walks from main over definitions, each on its own `Walked`).
  Outside it but feeding it: `Translate/Recursion.idr` (the call graph's
  components, for `Facts.terminating`). Nothing on the C++ side reuses any
  of them: `Program.idr` hands C++ only the module.
- **§5.6 W-E2** (state against the values whose type leaves the question
  open). The flow: dictionary and family slots only (§2.4). The growth
  graph: static positions only (a runtime parameter is no position,
  `Sites.taking`, `:500-504`). Nothing to cut by type.
- **§5.6 W-E3** (analyses computed more than once). `staticsOver` (one
  function) is called per site, per cap, per implementation, per method
  field (`Sites.idr:496, 1416`, `Caps.idr:171`, `Implementations.idr:90,
  169`), and again by `Instances.classify` for every request: one
  function, two callers (graph and translation) whose agreement the
  run-time bound check witnesses (`Sites.idr:1401-1411`). `Sites.holed`
  and `Terms.holed` compute one fact twice (0003 C5). The three walks from
  main (W-E1). The decision "which parameters are keyed by their shape"
  in `Caps.capOf` is `staticsOver` over markers 0..j, per (definition, j),
  memoized only per pair (`Graph.capsOf`, `:781-789`): O(arity^2) per
  definition.
- **§5.6 W-E4** (facts in discardable attributes). None from this
  subsystem: `total` is an inherent `UnitAttr` (`IdrOps.td:161`).
- **§5.6 W-E5** (every budget, round count and cap; does any fail). None
  refuses (§2.6, §3.1 row 1).
- **§5.6 W-E7 / W-E9** (per-function `DenseMap<Value, ...>`; state
  copied per branch). The Idris analogues: `Position = (Node, Nat)` keys
  every map (`State.idr:162-163`) though Graph numbers positions into
  `Fin` (`Graph.idr:971-978`) and throws the numbering away at the
  boundary (`Growth.boundsOf`, `:47-49`); `Sites.rebound` per branch.
- **§5.7.4** "For each specializer: what its key is, whether keys come
  from a finite alphabet, and whether any budget decides termination
  (L5)". The frontend's monomorphizer: key `Link Form`, finite alphabet
  (`Forms.forms`, `addresses`), sizes bounded by the growth check, no
  budget; termination by `extensionsEnd` and `Generations` (§3.1).
- **§5.7.4** "is its fact a lattice per value (PLV), independent per value,
  or relational?" Flow: PLV (monotone sets per slot). Growth: relational
  arcs, PLV answer (a potential per position). Profile: one bit per
  definition. Worklist: per-request membership in a finite universe.
- **§5.4.4** "Which analyses are summaries over the call graph, in which
  direction, and does each compute its own SCC order?" None here are
  summaries over the *call* graph; `Check` computes its own SCC order over
  positions, callers first (`Check.idr:366-371`).
- **§5.3.4** "`lib/Support/Scc.cpp`: what does it do that `scc_iterator`
  ... does not?" Lane 05's. Recorded for the coordinator: the repository
  has the SCC algorithm in at least three places (`Scc.cpp`, `Check.idr`,
  `Recursion.idr`).

## 4. Issues

Every line *read* unless marked. "Essential" rows are cases the problem
has, kept and recorded so that no later lane flattens them. Paths are
under `compiler/src/IdrisMLIR/` unless they start otherwise; `G/` is
`Frontend/Growth/`. Dispositions point at §5's changes (G1 ...).

### 4.1 The phase and its boundary

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| FC-01 | `Frontend/Growth.idr:324-336`, `Translate/State.idr:441-447, 455-456` | idris, state | `checkGrowth : ... -> Core Bool`: the admission (bounds, sizes) is written into `TS.bounds`/`TS.sizes`, which are empty until then ("Nothing is within it until the growth check writes it"), and a `Bool` is returned; `Program.idr:224-235` branches on it | G1: return the admission as a value |
| FC-02 | `Frontend/Growth.idr:47-49`; `Frontend/Finite.idr:186-192` | rederivation, state | the graph's `Fin` numbering (`Graph.idr:971-978`) is turned back into `SortedMap Position Nat` keyed by `(Node, Nat)`; every request looks its positions up again, a miss being "the growth check is unsound" | G1, G4 |
| FC-03 | `Frontend/Growth.idr:70-75` | idris (essential) | `heightAt a = fromMaybe [] (lookup a table)`: a definition with no static position keys nothing, padded with 0 (`Requests.padded`, `:638-641`) | keep: 0 is the coordinate for "keys nothing" (`argumentSize Nothing = 0`, `Requests.idr:237-239`) |
| FC-04 | `Frontend/Growth.idr:83-87`; `G/Caps.idr:165-169`; `G/Sites.idr:1384-1389`; `G/Graph.idr:925-926` | idris | `Address` is a bare `Vect 8 (Fin 256)` that nothing proves names a definition (or a type constructor), so `definitionAt` and `resolve` misses are internal errors at four sites | G4: key the graph by a resolved identity (`Walk.Placement` with its `GlobalDef`, or an index into the definitions' walk's table) |
| FC-05 | `Frontend/Growth.idr:97-103`; `Translate/Errors.idr:53` | idris | a refusal's owner is `show (fullname def)`, a `String` naming a definition | with lane 15: `reject` takes the `Name`; text only when printed |
| FC-06 | `Frontend/Growth.idr:162-165` | rederivation | `Source = Binds \| Projects`, decided by comparing the arc's node with the site's writer, though `Graph.argument` (`:724-733`) and the projection rule (`:966-967`) know which they draw | G3: `Wrote` records it |
| FC-07 | `Frontend/Growth.idr:176-212, 278-300` | rederivation, idris | `carries`, `parts`, `computationThrough` re-walk an `Unmeasured` arc's template to find the computation that made it stuck; `refuseOpaque` holds two internal errors for "no argument wrote it" (`:282`) and "holds no computation" (`:289`) | G3: `Unmeasured` carries its cause |
| FC-08 | `Frontend/Growth.idr:257-263` | essential | message by `TCon` against any other definition: "a data type grows through its fields, a function through its calls" | keep |
| FC-09 | `Frontend/Growth.idr:268, 298` | essential | both causes refused as `Polymorphism` (`IdrBase.td:199`, `Megamorphic`) | keep; the rule's category is true of both causes |
| FC-10 | `Frontend/Program.idr:190`, `G/Graph.idr:925-927` | rederivation | main resolved twice, the graph's miss an internal error | G1: `checkGrowth` takes main's resolved definition |

### 4.2 Templates (`G/Template.idr`)

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| FC-11 | `G/Template.idr:75-98, 1110-1119` | idris, ladder | `Computing` is built only by `withClosedFamilies` at a node of the graph, yet every reading handles it: `G/Caps.idr:69-73` ("Never met"), `G/Heads.idr:174-176`, `G/Graph.idr:532`, `G/Sites.idr:320, 370, 415`, and 9 folds in `Template.idr` (`:455, 965, 1002, 1021, 1055, 1073, 1149, 1183, 1203, 1236`) | G2: `Template` indexed by its stage |
| FC-12 | 18 hand recursions over the 11 constructors: `Growth.idr:185-195` (`parts`), `G/Caps.idr:62-82` (`deepest`), `G/Template.idr:433-456` (`height`), `:954-972` (`arity`), `:991-1005` (`formalIn`), `:1007-1031` (`beta`), `:1042-1064` (`familiesIn`), `:1066-1082` (`applyingIn`), `:1097-1132` (`withClosedFamilies`), `:1134-1156` (`selfBounded`), `:1172-1212` (`weightsAt`, `stuckAt`), `:1223-1242` (`heaviest`), `:904-924` (`formedTemplate`); `G/Heads.idr:150-180` (`byTemplate`); `G/Graph.idr:502-541` (`carriedAt`); `G/Sites.idr:306-326` (`render`), `:354-390` (`eraseIn`), `:406-425` (`buildsIn`) | ladder | a case over the same tag repeated 18 times (*measured*: `grep -c` of arms matching a `Template` constructor: Template 137, Sites 38, Caps 12, Heads 12, Graph 9, Implementations 2); a new constructor costs 18 arms | G2: one traversal (`children`/`withChildren`, or a base functor and one `cata`, as `Term.idr:345, 427`'s `TermF`/`para` already are) and each measure an algebra |
| FC-13 | `G/Template.idr:77` | idris | `Head (Maybe Address) (List Template)`: a `Maybe` hides two cases (a named head; a binder or primitive former), split again in `Sites.render:311-313`, `eraseIn:362-366`, `buildsIn:410-411` | G2: two constructors |
| FC-14 | `G/Template.idr:83-88` | essential | one `Choice` for five origins (stuck definition, partial application, family argument, projection, structural recursion): one meaning ("one of its leaves at every instance") for every measure | keep |
| FC-15 | `G/Template.idr:1258-1267, 1268-1349` | rederivation | a dictionary is taken apart here (`builtOf`, `projectedPiece`, `rootOf`) and again by the translation (`Translate/Closed.idr`'s projections); the comment says they must agree | with lane 15: one function both call |
| FC-16 | `G/Template.idr:849` | essential (fork boundary) | `bindEach` miss: a case alternative binding a different number of arguments than its constructor, an invariant of Idris's case trees that TT does not carry | keep; lane 17 |
| FC-17 | `G/Template.idr:1134-1156`, read at `:1165`, `G/Graph.idr:560, 899` | idris | `selfBounded : Template -> Bool`, after which callers call `height` | G2: return the closed height (`Maybe Nat`) |
| FC-18 | `G/Template.idr:1395-1400` | idris (low) | `rooted` gives a form and a shape `Unrooted`: a kind that never roots carries a `Root` | G6: the kind's record says whether it roots |

### 4.3 The graph (`G/Graph.idr`)

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| FC-19 | `G/Graph.idr:60-61`, `Frontend/Growth.idr:279-282` | idris | `Wrote = FromArgument Site Argument \| FromField`, not tied to its arc, so a leading arc's label (always `Measured 0 0`, `:744`) is not known to be measured, and `refuseOpaque` holds an internal error for it | G3 |
| FC-20 | `G/Graph.idr:106-112, 181-204`; `Frontend/Profile.idr:284-291, 427-468` | list, rederivation | two copies of `Pending`/`Queued`/`queued` and of the breadth-first level walk over `Walked`, one per module | G8: one walk in `Walk.idr` |
| FC-21 | `G/Graph.idr:129-141` | essential | `kindOf`: "the one switch on the kind, and the problem's" | keep |
| FC-22 | `G/Graph.idr:330, 939-945` | idris | `Stray = Outside \| Unread`: the node walk validates that `readings` covers every node the flow can give (`Unread`) and every head index (`Outside`), with internal errors | G4: `out` computed from the flow and the heads (`familyHeads`) as a total function, not a map lookup |
| FC-23 | `G/Graph.idr:354-359` (*measured*, comment) | state | per-path novelty, O(nodes x depth), 13,218 nodes at the self compile | keep; measure at stage 1 (§8) |
| FC-24 | `G/Graph.idr:559-564` | rederivation (low) | `landingOf` matches the triple (`beta`, `selfBounded`, `term`) per argument, three readings of one template | G2: read once with the template |
| FC-25 | `G/Graph.idr:615-637, 689-708` | state, rederivation | `Carries` keyed `SortedMap Nat (List (Fin n))` by `finToNat`, and `landings` numbers the landing positions a second time (`:690`) before the final numbering (`:973`) | G4: one numbering, per-position state in the trie |
| FC-26 | `G/Graph.idr:645-675` | state (low) | visited set as `Vect n Bool`, O(n) per mark | G4: the trie |
| FC-27 | `G/Graph.idr:792-796, 974-978` | idris | `numbered` looks each arc's ends up in a map; "a miss is a broken invariant ... it stays because a map's lookup gives no evidence of membership" | G4: positions numbered as they are made, arcs drawn between `Fin`s |
| FC-28 | `G/Graph.idr:807-808` | state (low) | `readAt` filters heads by `elem` over the families list | G4 |
| FC-29 | `G/Graph.idr:813-816` | state, budget (none) | `familyHeads`: every way of heading a subset of the families, a product; no bound but the flow's sets | measure (§8); essential if each element is a real instance |
| FC-30 | `G/Graph.idr:849-868` | rederivation | `givenFamilies`, a hand traversal of TT substituting markers, beside `Sites.replacing` (`G/Sites.idr:194-199`), which does the same by `refsToLocals` and `substs` | G12: one substitution |
| FC-31 | `G/Graph.idr:871-873, 903-907` | state | `choices`: one evaluated argument per element of the product of the values landing at each applied family | measure (§8) |
| FC-32 | `G/Graph.idr:933-938` | essential | flow first, readings at every headed node, then the walk | keep |

### 4.4 The flow and the split (`G/Heads.idr`, `G/Implementations.idr`, `G/Fields.idr`)

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| FC-33 | `G/Heads.idr:73-91` | idris | `Slot = (Fin 2, Address, Address)`: the slot's kind as `Fin 2`, its index written as an eight-byte address, "so that a slot is a triple of finite types" whose listing exists | G7: `data Slot = Parameter Address (Fin b) \| Field Address (Fin b)`, listed by `listedEither`/`listedPair`/`listedFin` (`Proof/Requests.idr:76-87, 500-502`) over the breadth `Built.breadth` already holds |
| FC-34 | `G/Heads.idr:93-128, 289-363` | rederivation, state | naive rounds: every round rebuilds the `View` from the seen list (`viewOf`), re-yields every equation (`candidates`), and searches the seen list linearly per candidate (`isNew = isElem`) | G7: semi-naive, equations indexed by the slot they read |
| FC-35 | `G/Heads.idr:246-250` | idris | `placedAt own x = toList (head' (drop x.position own))`: a dispatched argument beyond `own` is dropped with no arc | G7: `own : Vect k Nat` over the method's own arity, the argument's position a `Fin k`; a miss becomes unrepresentable (*conjecture*: today's silent drop could hide growth from the check, caught only by `Finite`'s witness) |
| FC-36 | `G/Heads.idr:404-422` | state | `combinations`: one callee node per element of the product of roots per parameter, from a context-insensitive flow | measure (§8) |
| FC-37 | `G/Heads.idr:407-412` | essential | a dictionary with no root is no choice: "the program's (a lambda's result ...), not the representation's" | keep |
| FC-38 | `G/Implementations.idr:52-56`, read at `G/Heads.idr:226-229`, `G/Graph.idr:494-495` | idris | `fieldAt fs j k = lookup j fs >>= head' . drop k`: a field by position in a list, a miss `Nothing` | G7: `Fields` indexed by its constructor's field count, fields by `Fin` |
| FC-39 | `G/Implementations.idr:96`, `G/Sites.idr:137` | idris | `Erased EmptyFC Impossible` stands for "a run-time value", unambiguous only because the TTC loses Idris's own `Impossible` (0003) | G12: a probe (`Walk`'s family) |
| FC-40 | `G/Implementations.idr:160-166` | idris | a method field whose function `resolve` cannot find is taken as a hand-written field (`Plain (Leaf 1) Unrooted`), so a dispatch through it reaches nothing, beside the essential case of a field that is no eta wrapper | split: no eta wrapper stays `Plain` (essential, a runtime part reads as `Leaf 1` everywhere, `G/Template.idr:613-617`); a name the context does not hold is an internal error (*conjecture*: it cannot happen for a name of a closed term) |
| FC-41 | `G/Fields.idr:76-82` | state (low) | `elem j rs` over the represented positions list per argument | G4 |
| FC-42 | `G/Fields.idr:119-123` | essential (fork boundary) | a type's constructor name the context does not hold: TT carries no proof of a `TCon`'s constructor list | keep; lane 17 |
| FC-43 | `G/Fields.idr:97-98`, `G/Implementations.idr:78, 230`, `G/Sites.idr:547, 824, 827, 982, 1124` | rederivation (*conjecture*) | `implementationType` decided per binder and per argument on freshly normalised types at eight sites | with lane 15: cached per type (`TS.interfaces` holds the interfaces once, `State.idr:413-418`) |

### 4.5 Caps (`G/Caps.idr`)

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| FC-44 | `G/Caps.idr:1-31` (name), `G/Graph.idr:779-789` | budget (none; cannot fail) | a "cap" is a bound read off the callee's type, proved in `:88-132`; it admits programs. The name collides with the proposal's "cap" (a budget) | rename with G2 (`Inspected` or `Depth`); no behaviour change |
| FC-45 | `G/Caps.idr:138-153` | idris | `binder` raises "more parameters than the type has binders"; the type's telescope is re-read per parameter (`parameterAt` walks j binders each time) | G6: a definition's telescope read once (the node's reading already has its kinds) |
| FC-46 | `G/Caps.idr:171` | rederivation | `staticsOver` over markers 0..j per (definition, j): O(arity^2) per definition; `Sites.readingOf` already decided the same kinds at the node with no heads (`G/Sites.idr:1455-1458`) | G6: `Reading` carries its `kinds`; the cap reads them |
| FC-47 | `G/Caps.idr:183` | idris | `lookupDef EmptyFC owner tn` though the site is known (0003) | G12 |

### 4.6 Sites (`G/Sites.idr`)

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| FC-48 | `G/Sites.idr:65-73, 404` | idris | `Argument.term : Maybe ClosedTerm`: `Nothing` for a part of a type already read, `Just` for a written argument; `Graph.landingOf` and `evaluated` branch on it | G12: a sum of the two sources |
| FC-49 | `G/Sites.idr:141-142` | idris | `Standing = (Stand, Name, Maybe ClosedTerm)`, a triple read by position everywhere (`(s, _, _)`) | G12: a record |
| FC-50 | `G/Sites.idr:239-255`; `Translate/Terms.idr:739` | rederivation | two `holed`s (0003 C5: "a disagreement surfaces as an internal unsoundness") | G12, with lane 15 |
| FC-51 | `G/Sites.idr:293-294` | idris | `siteAt` copies `bestFC`'s fallback (0003) | G12 |
| FC-52 | `G/Sites.idr:481-486` | rederivation | `quantitiesOf`, one of five readers of erasure (0003) | G12, with lane 15 |
| FC-53 | `G/Sites.idr:492-508` | idris | `taken`/`decided` match three lists by position (`os`, `kinds`, `rigs`) and drop the rest silently on a length mismatch (`decided _ _ _ _ = []`): the skill's "three lists matched by position" | G12: `staticsOver` returns `Vect n` per binder; one `zipWith3` |
| FC-54 | `G/Sites.idr:561-578` | rederivation (low) | `packing` restates the translation's packing of closed-over values (`Closed.packedType`, `pairNames`) to know which sites it makes | with lane 15: the packing yields its own sites |
| FC-55 | `G/Sites.idr:589-596`; `G/Template.idr:936-948, 1395-1400`; `G/Heads.idr:204-209`; `G/Sites.idr:1296-1302`; `G/Caps.idr:172-194` | ladder | six switches over `Static` (`AType`, `AFamily`, `AForm`, `AShape`, `ADictionary`): reading, root, splitting, standing, builds, cap | G6: one record of operations per kind, dispatched once |
| FC-56 | `G/Sites.idr:762-770` | rederivation | `hooksFor` parses a `%foreign` spec again (`foreignHook`) and drops a failure ("The reach check refuses ..."): the third parse beside `Profile.idr:386-392` and `Translate/Terms.idr:985-988` (0003 B5) | lane 14's registry returns the resolved table; Sites reads it |
| FC-57 | `G/Sites.idr:1028-1030, 1042-1044` | essential (fork boundary) | a metavariable's `Int` index may be negative | keep; lane 17 |
| FC-58 | `G/Sites.idr:1063-1072, 1173-1180, 1221-1232` | state | `rebound` rewrites every stand and type of the environment per alternative of a match on a shape: per-branch copying, O(alternatives x scope) | G12: a stand-in's binding kept once (a substitution map consulted by `termOf`), not pushed into every entry |
| FC-59 | `G/Sites.idr:1082-1139` | rederivation, idris | `conStands` (0003 C3: a third constructor-to-type-constructor reading); `layoutOf` a `List (Maybe Nat)` taken in step with the binders, with a fallback for "a type that shows fewer" (`:1137-1139`) | G12, with lane 15 (`tyConFacts` table) |
| FC-60 | `G/Sites.idr:1332-1335` | idris | `envOf` pads a short standing list with `Runtime` | G12 |
| FC-61 | `G/Sites.idr:1342, 1357, 710, 399, 1118, 1269, 278, 304` | idris | eight `getAt` lookups by position (part of 0003's "about 35") | G12 |
| FC-62 | `G/Sites.idr:1419-1422`, `Frontend/Profile.idr:76-86` | idris | `answersForCalls hs = hs.identityOnLast \|\| isJust hs.generating`, `answersForBody`: booleans over the registry's hook record | lane 14: a hook's kind as a sum |
| FC-63 | `G/Sites.idr:1384-1389` | idris | a family's head not a type constructor is an internal error: heads are bare addresses | G4: a head typed as a type constructor's identity |

### 4.7 The check (`G/Check.idr`, `G/Potential.idr`)

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| FC-64 | `G/Check.idr:77-79` against `G/Potential.idr:117-161` | list, state | two representations of "one value per position" in one check: `Check.Table` (a trie, O(log n), measured 33 s to 0.6 s) and `Potential.Cells` (a list, O(n) per `entry`/`put`); and `Walk.Seen` is a third binary trie (`Walk.idr:92-110`) | G11: one trie type with its lemmas; Potential on it |
| FC-65 | `G/Check.idr:476-477` vs `G/Potential.idr:168-171` | idris (low) | two different `Walk`s | G11: rename |
| FC-66 | `G/Check.idr:479-512, 536-549` | idris | `walkBack` keeps `Table d (Maybe (Walk g))`, and `ring` re-decides whether a walk chains because "the table does not tie an entry to its place"; the `Fails` arm is dead by construction ("no verdict rests on this") | G10: store `Potential.Path g x first` per position; `ring` goes |
| FC-67 | `G/Check.idr:686-708, 638-676` | rederivation, idris | `check` re-validates the potential `settled` built (`feasibleIn`) and, on failure, recomputes it by certified Bellman-Ford over every arc: "a failure here is this module's own bug, which the exhaustive box shows" | G10: `settle` returns `Satisfies` per arc as `Potential.relaxFits` does; `feasibleIn`, `satisfiesIn`, `satisfyAllIn`, `raised` and the fallback go; `tests/growth-check` stays the oracle |
| FC-68 | `Proof/Growth.idr:319-320`; `G/Check.idr:64`; `G/Potential.idr:649-653, 508-516` | idris | `Feasible`'s `All (Satisfies pot) g.arcs` is at quantity many, built at run time (a cons per arc) and kept in `Bounded`, `Fitted.fits` and `Settles`, then discarded (`Growth.idr:330`) | G9: at quantity 0 |
| FC-69 | `G/Potential.idr:657-669` | budget (none; cannot fail) | Bellman-Ford's rounds, as many as the arcs; exhausting them returns a certified positive cycle (`climb`), never a refusal for the count | keep; it is the algorithm's bound with a certificate |
| FC-70 | `G/Check.idr:492-496` | budget (none; cannot fail) | `walkBack`'s rounds = members, the length bound of a simple walk | keep |
| FC-71 | `G/Check.idr:328-371`; `Translate/Recursion.idr:42-60` | list, rederivation | two hand Tarjans in the frontend (positions here, definitions there, with different state) | G8: one total Tarjan module over a graph given as `Fin n -> List (Fin n)` |
| FC-72 | `G/Check.idr:462-466` | idris (low) | `steadily` returns `Maybe` and forgets which edge loses | keep (the losing edge is not reported) |

### 4.8 The worklist (`Frontend/Finite.idr`)

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| FC-73 | `Frontend/Finite.idr:176-202, 385-389`; `Translate/Types.idr:852-853, 984` | rederivation (essential today) | the run-time witness of Theorem 1: each request's heights and size checked against the bounds, a miss "the growth check is unsound". The theorem is over a model (`Proof/Bound.idr:55-58`), so the code holds no derivation | keep as the boundary check while the model is not the code; Q-new-1 (§6) |
| FC-74 | `Frontend/Finite.idr:224-231`; `Proof/Requests.idr:835-841` | rederivation, state | freshness of a request on its chain re-decided by a linear `elemLink` though `Instances.request` records a request only for an instance not yet seen; a hit is an internal error | with lane 15: `request` returns the freshness evidence it already decided; the search goes |
| FC-75 | `Frontend/Finite.idr:433-438` | idris (low) | "a dictionary field learnt twice": an invariant re-checked by `isElem` | keep (cheap) or carry the evidence from `wake` |
| FC-76 | `Frontend/Finite.idr:360-370` | essential | the state restored after a rejected instance (`keepFound after before`) so that every rejection is independent (2a66fbcb) | keep |
| FC-77 | `Frontend/Finite.idr:80-91` | essential (Idris) | erased upper-case aliases (`Bounded`, `Inside`, `Learnable`) because "a lower-case global in a type is bound as an implicit" | keep |

### 4.9 Profile (`Frontend/Profile.idr`)

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| FC-78 | `Frontend/Profile.idr:52-70` | list, ods | `outsideLanguage`/`reason`: a hand list over `Rule` (`_ => Nothing` for every other rule) of the five rules forbidden wherever reached, with prose restating `IdrBase.td:207-221`; the generated `ruleCategory` (`Syntax/Idr.idr:392`) is read by nothing on the Idris side | G5: the scope (reached or named) and the reason are fields of `Idr_RuleCase`, generated |
| FC-79 | `Frontend/Profile.idr:111-130`; `Frontend/Program.idr:209-215` | rederivation | `imports` scans the source with `words` (0003 B3: an `import` in a block comment is imported, one split over lines missed) | lane 17: the TTC keeps each import's FC; the scanner goes |
| FC-80 | `Frontend/Profile.idr:136-141` | list (fork boundary) | `discharged : List String` names pragmas as text, because the fork's lexer gives `Pragma String` | lane 17: a pragma kind from the lexer, or keep at the boundary |
| FC-81 | `Frontend/Profile.idr:163-164, 458-459`; `Translate/State.idr:427-429` | idris | `TS.spelled : SortedSet (ModuleIdent, String)` keyed by the spelling, matched against `nameRoot full`: a printed name used as an identity | G14: key by what the spelling resolves to in the registry (the rule hit and the root `Name`) |
| FC-82 | `Frontend/Profile.idr:189-218` | essential (low) | `mentionsWorld`, `treeMentionsWorld`: a hand traversal for the `%MkWorld` literal, which no reference walk finds (it is a `PrimVal`) | keep |
| FC-83 | `Frontend/Profile.idr:225-230, 414-416, 435` | rederivation | `proofOnly` looks each reference up again (0003), and `level` resolves every reached name again | G14: `refsOf` yields resolved `(Placement, GlobalDef)` once |
| FC-84 | `Frontend/Profile.idr:337-417` | ladder (low) | `visit` is eleven independent rule checks in sequence, each `case ... of Just => reject; Nothing => pure ()`, with `Builtin Crash` matched twice (`:369-371`, `:377-378`) | G14: one list of rule records over a resolved reach; one match on the definition's kind |
| FC-85 | `Frontend/Profile.idr:344, 441` | rederivation (low) | `trusted` computed twice from the same location | G14 |
| FC-86 | `Frontend/Profile.idr:245-260, 368-371` | essential | two notions of trust: where a definition comes from (`origin`) and who reaches it (`Referrer`); "The reach has to come from a trusted definition" | keep; `byLibrary : Referrer -> Bool` folds into G14's match |
| FC-87 | `Frontend/Profile.idr:383-392`; `G/Sites.idr:762-770` | rederivation | registry parses (`meansExtern`, `foreignHookOf`) repeated (0003 B5) | lane 14 |
| FC-88 | `Frontend/Profile.idr:318-320` | idris | reach refusals placed at the referring user definition, not the reference (0003) | G12 (locations) |
| FC-89 | `Frontend/Profile.idr:446-447` | idris (low) | "Primitives have no location" tested as an absent `FC` | G14 |
| FC-90 | `Frontend/Profile.idr:308-316, 470-483` | essential | a second walk reports every user definition behind a rejected trusted definition | keep |

### 4.10 Proofs and facts (`Proof/`, `Facts.idr`)

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| FC-91 | `Proof/Requests.idr:140-144, 366-381` | state, idris | `Address = Vect 8 (Fin 256)`: eight boxed bytes per address at run time; every comparison of a `Node`, `Position` or `Link` walks them (`decideAddress`, `G/Heads.idr:96-99`, `G/Graph.idr:212-224`); the listing that motivates it (`addresses`) is only ever used at quantity 0 | G4: one word (*conjecture*, §8: a `Fin (power 2 64)` or the placement's index with an erased listing) |
| FC-92 | `Proof/Requests.idr:376-381`, read at `Frontend/Growth.idr:165` | idris (low) | `sameAddress` throws a `Decision` away for a `Bool` | G3 deletes its one reader |
| FC-93 | `Proof/Forms.idr:36-80, 99-119, 138-154, 82-92, 121-131, 156-166` | list (essential in the subset) | three enums each written four times (constructors, table, code, `decoded` proof) plus hand `DecEq`/`Eq`/`Ord`: no deriving in the subset both hosts compile | keep; or generate them beside `Rule` if lane 14's generator takes frontend enums |
| FC-94 | `Proof/Forms.idr:181-187` | idris | `IntegerLit (Fin 14) Bool`, `PrimitiveType (Fin 14)`: the fork's primitive types as a code that must agree with `Keys`' numbering | `Numbered PrimType` as for `Shape`; `Form` holds the type |
| FC-95 | `Proof/Bound.idr` (whole, 673 lines) | rederivation (essential today) | Theorem 1 over a model `Term m` (3 constructors) of the code's `Template` (11); referenced by nothing but `compiler/idris-mlir.ipkg` (*measured*, `grep -rln IdrisMLIR.Proof.Bound`) | Q-new-1 (§6) |
| FC-96 | `Facts.idr:11-18`; `Translate/Programs.idr:78-79, 170`; `Translate/State.idr:385` | idris | `Facts { terminating : Bool }`, read from `TS.loops : SortedMap Address Bool` with `fromMaybe False`, collapsing "never checked" into "may not terminate" (0003) | G13 |
| FC-97 | `Proof/Growth.idr:43-45` | essential | the tree's own `Decision` (evidence, or an erased refutation) | keep |
| FC-98 | `Proof/Generations.idr` | none | the multiset argument for a FIFO worklist, total, erased where it should be | keep |

### 4.11 Locations (0003) and what is absent

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| FC-99 | 29 `EmptyFC` (*measured*): `G/Sites.idr` 16, `G/Caps.idr` 4, `G/Template.idr` 4, `G/Implementations.idr` 3, `G/Graph.idr` 1, `Frontend/Profile.idr` 1 | idris | rebuilt terms and internal errors at no location though the location is in hand | G12 |
| FC-100 | the subsystem | none found | no `covering`, `assert_total`, `believe_me`, `postulate`, fuel, budget or round cap (§2.6); no discardable attribute (the one fact emitted, `total`, is inherent); no per-target case (`grep` for triples, page sizes, `x86`, `arm`, `darwin`, `linux`: none); no C++ | — |

## 5. Target design

What stays: the subsystem's architecture is already the proposal's
target shape on the Idris side. The growth check is §5.6's
"extract, solve, write back" (read TT once into `Site`s and `Template`s,
solve on plain data, answer with a certificate), its termination is by
construction everywhere (§2.6), its monomorphizer is §5.7's L5 (keys over
a finite alphabet, a bound before translation, no budget), and its flow
keeps state only for the values whose type leaves the question open
(§5.6 Design 2). Nothing here should move to C++ or to the dialect:
polymorphism, dictionaries and families exist only before
monomorphization, so the growth check's facts are the frontend's alone,
and no C++ pass re-derives them (§2.5). What changes is representation:
answers that cross a boundary as state behind a `Bool`, a type that
admits a constructor its readers cannot meet, eighteen hand folds, three
numberings, and two copies of several walks.

Each change: the representation, what it deletes, and the one line the
skill asks for.

**G1. The admission is a value.** `checkGrowth` returns `Maybe Admitted`
(or `Either (List1 Cause) Admitted`), `Admitted` holding the positions'
numbering, each position's bound in the trie of G4, and the `Bounds`
(sizes); `translateFrom` and data registration (`Translate/Types.idr:839-853,
984`) take it as an argument. `checkGrowth` takes main's resolved
definition from `Program.idr`.
- Deletes: `TS.bounds`, `TS.sizes` and their empty defaults
  (`State.idr:441-447, 455-456`), the `Bool`, the `True <- pure admitted`
  branch's coupling, the second resolution of main (`Graph.idr:925-927`).
- *State made unrepresentable:* a translation run, or a request judged,
  before the growth check admitted the program.

**G2. `Template` by stage, with one traversal.**
`data Template : Stage -> Type` with `Stage = Read | AtNode`; `Computing`
exists only at `AtNode`; `withClosedFamilies : (Nat -> Landing) ->
Template Read -> Template AtNode`. `Head (Maybe Address)` splits into
`Named Address (List t)` and `Former (List t)`. One structural traversal
(`children` and `withChildren`, or a base functor `TemplateF` with one
total `cata`, in the style of `Term.idr`'s `TermF` and `para`
(`Term.idr:345, 427`), which Emit already folds with
(`Emit/Declarations.idr:46, 68`)), and each measure (height, arity, heaviest,
formal, beta, families, applying, self-bounded, weights, stuck, deepest,
byTemplate, carried, render, erase, builds, formed) an algebra.
`selfBounded` returns the closed height. The landing of an argument
(`landingOf`) is read once with its template.
- Deletes: the `Computing` arms outside the graph (`Caps.idr:69-73`,
  `Heads.idr:174-176`, `Sites.idr:320, 370, 415`), most of the 18
  hand recursions' per-tag arms (§4 FC-12), the `Maybe` on heads.
- *State made unrepresentable:* a computing family in a site's, a cap's
  or a request's template; a fold that forgets a constructor. The stage
  index is a parameter the value does not store, so it stays in the
  subset both hosts compile (`SKILL.md`, "Dependent fields").

**G3. A stuck arc carries why, and an arc carries what made it.**
`Weight = Absent | Finite Nat Nat | Stuck Through` and
`Label = Measured Nat Nat | Unmeasured Through`, with
`Through = Recursion Address | Family Nat` (today's
`Growth.Computation`, `Growth.idr:201`); `Template.weightsAt` records
the computation where it writes `Stuck`. An arc is
`MkArc from to (label : Label) (wrote : Wrote label)`, where
`FromField : Wrote (Measured 0 0)` and `FromArgument` records whether the
writer binds or projects the source.
- Deletes: `carries`, `parts`, `computationThrough`, `Source`/`sourceOf`,
  both internal errors of `refuseOpaque` (`Growth.idr:176-212, 279-289`),
  `sameAddress`'s one reader, the parallel `Built.wrote` vector.
- *Branch deleted:* the re-walk of a template to explain an arc it already
  labelled; *state made unrepresentable:* an unmeasured leading arc.

**G4. One numbering, one identity, one per-position store.** Positions
are numbered as the graph makes them (a builder that returns a `Fin` on
first insert), arcs are drawn between `Fin`s, and landings, carries,
caps, visited marks and bounds live in one trie type (today's
`Check.Table`, generalized; G11). A node's definition is a resolved
identity (a `Placement`, which only `placementOf` makes, `Walk.idr:38-58`,
with its `GlobalDef` from `resolve`), and a head is a type constructor's
or an implementation's identity so typed. `out` is computed from the flow
and the heads as a total function. `Address` becomes one word
(*conjecture*, §8), its listing kept at quantity 0 where `Universe`
already is.
- Deletes: `numbered`'s `Maybe` and "lost a position it numbered"
  (`Graph.idr:792-796, 977-978`), the landings' second numbering
  (`:690`), `Carries`' `SortedMap Nat`, `Vect n Bool` visited (`:645-675`),
  `Stray` and its two internal errors (`:330, 939-945`), four
  `definitionAt` internal errors (§4 FC-04, FC-63), `SortedMap Position`
  in `Finite` (with G1).
- *State made unrepresentable:* an arc whose end has no number; a node at
  heads its flow did not give; an address naming no definition.

**G5. A rule's scope lives in ODS.** `Idr_RuleCase` gains the scope
(forbidden wherever reached, or only where user code names it) and the
reason phrase; `idris-mlir-tblgen` writes `ruleScope : Rule -> RuleScope`
beside `ruleCategory`. `Profile.visit` reads it.
- Deletes: `outsideLanguage`, `reason`, `exclusion`'s `Maybe`
  (`Profile.idr:52-70`).
- *One fact, one place:* the five rules' prose today in `IdrBase.td:207-221`
  and again in `Profile.idr:60-64`. Depends on lane 14 (the generator) and
  lane 01/03 (`IdrBase.td`).

**G6. The static kinds dispatch once.** A record of operations per
`Static` (`reading`, `root`, `splits`, `stand`, `builds`, `caps`),
`kindOps : Static -> KindOps`, read at each of today's six switches; a
definition's telescope and kinds read once per node (`Reading` carries
`kinds`, and the cap reads them).
- Deletes: the six `case k of AType ...` (§4 FC-55), `Caps.parameterAt`'s
  re-walk and its internal error, the O(arity^2) `staticsOver` per
  definition in `capOf`.
- *Branch deleted:* a new kind costs one record, not six arms.

**G7. The flow, semi-naive, over typed slots.**
`data Slot = Parameter Address (Fin b) | Field Address (Fin b)`, listed by
the combinators `Proof/Requests` has. Equations are indexed by the slots
they read; a new entry fires only those, and the `View` is the one state,
updated in place of being rebuilt per round; membership by the
`SortedSet Entry` it already builds (`candidates`). `Fields` and a method's
`own` placement are `Vect`s over their counts, read by `Fin`. Termination:
unchanged, the room in the finite listing.
- Deletes: `viewOf` per round, `isNew`'s linear search, `[bytewise]`,
  `sameKind`, the `Fin 2` code, `fieldAt`'s and `placedAt`'s silent
  misses.
- *State made unrepresentable:* a slot of kind 2, an index that is no
  count, a dispatched argument with no place.

**G8. One walk over the context, one Tarjan.** `Walk.idr` gains the one
breadth-first level walk over `Walked` (the visit a parameter), and the
frontend one total Tarjan over `Fin n -> List (Fin n)`, used by
`Check.components` and `Translate/Recursion.idr`.
- Deletes: `Graph.Pending`/`queued`/`level`'s bookkeeping and
  `Profile.Pending`/`queued`/`level`'s (§4 FC-20), one of the two Tarjans
  (§4 FC-71).
- *One analysis, one place.*

**G9. Certificates erased.** `Bounded : (pot : Vect g.size Nat) ->
(0 _ : Feasible g pot) -> Verdict g`, and `Fitted.fits` and `Settles` at
quantity 0.
- Deletes: a run-time cons per arc, built and discarded.
- *Check:* nothing reads the list at run time (`Growth.idr:330` discards
  it; `Check.judge` reads only `fitted.pot`, `Check.idr:592`).

**G10. The check's answer is right by construction.** `settle` carries a
`Satisfies` per arc it settles (as `Potential.relaxFits` does), so
`check` returns `Bounded` without re-validating; `walkBack` stores a
`Potential.Path g x first` per position.
- Deletes: `feasibleIn`, `satisfiesIn`, `satisfyAllIn`, `raised`, the
  certified fallback over every arc (`Check.idr:638-708`), `ring` and its
  dead `Fails` arm (`:502-512, 544-548`).
- *Check moved to a boundary:* the brute-force box (`tests/growth-check`)
  stays the oracle; the run-time recheck goes. Cost: proofs (§8).

**G11. One trie.** Potential's Bellman-Ford runs on the trie (G4), with
`at`/`update` lemmas replacing `entryPut`, `entryPutOther`, `entryMap`,
`indexColumn`; `Walk.Seen` uses the same trie.
- Deletes: `Potential.Cells`, `Table`, `entry`, `put`, `mapTable`,
  `column` and their lemmas (`Potential.idr:117-161`); `Walk.Seen`'s own
  tree; the O(n) per access of Bellman-Ford.
- *One thing, one representation.*

**G12. Sites read once, located.** `staticsOver` returns one `Vect n`
entry per binder (kind and quantity), and `taken` zips it with the
arguments; `Standing` a record; `Argument`'s source a sum (read part or
written term); the run-time placeholder a probe; one `holed` and one
erasure reader (with lane 15); a stand-in's matched constructor kept in a
substitution consulted by `termOf`, not pushed into every entry per
alternative; one TT substitution (`replacing`) for `givenFamilies`; every
rebuilt term at the location of what it rebuilds.
- Deletes: `decided`'s silent truncation, `envOf`'s padding, eight
  `getAt`s, `Graph.givenFamilies`, `Sites.holed` or `Terms.holed`,
  `quantitiesOf`, `rebound`'s per-branch copy, 29 `EmptyFC`s and
  `siteAt`'s fallback.
- *State made unrepresentable:* an argument with no binder; a
  standing read by position.

**G13. Termination is a sum carried from where it is decided.**
`Translate/Recursion.idr` decides the component when the instance is
requested (`:131`); the request carries
`data Termination = Terminates | MayDiverge` (or the generated mirror of
`idr.func`'s `total`), and `Facts` holds it.
- Deletes: `TS.loops : SortedMap Address Bool`, `fromMaybe False`
  (`Programs.idr:78`).
- *State made unrepresentable:* a function emitted with a termination
  verdict never computed. Depends on lane 15 (`Recursion`, `Programs`)
  and lane 03 (whether `total` stays a `UnitAttr` on `idr.func`).

**G14. Profile over resolved reaches.** `refsOf` yields resolved
`(Placement, GlobalDef)`s once; `visit`'s eleven checks become one list
of rule records over a resolved reach and one match on the definition's
kind; `TS.spelled` keyed by what the spelling resolves to; imports from
the TTC (lane 17).
- Deletes: `proofOnly`'s lookup, the second `trusted`, the double
  `Builtin Crash` match, `imports`' text scanner, the string compare at
  `:459`.
- *Check moved to a boundary:* trust and resolution decided once per
  definition.

**Order inside the subsystem, and dependencies.**
1. G3 and G2 (the data: `Label`, `Weight`, `Template`): no dependency.
2. G4 with G1 (numbering, identity, admission as a value): needs lane 15
   for `translateFrom`'s and data registration's signatures.
3. G9, G10, G11 (the check's proofs): independent of the rest, proof work
   only.
4. G6, G7, G8: after G2.
5. G12, G13, G14: with lanes 15 (Translate), 14 (registry, generator),
   17 (TTC imports, pragma kind).
6. G5: with lanes 14 and 01/03 (`Idr_RuleCase` in `IdrBase.td`).

Hard cutover: each change replaces its predecessor in the same change;
no alias of a removed constructor, no second numbering kept "for now".

## 6. Evidence for the owner's questions

No answers: what the code says, by question.

**Q-llvm-2 (budgets in the solver layer) and Q-E3 (the same line from the
ecosystem).**
- The frontend's refusal analyses already follow the line both questions
  propose, and with no budget at all, not even for optimization: the
  growth check and the reachability walk terminate by measures
  (`Walked`'s free places, `Walk.idr:92-192`; the node walk's room,
  `Graph.idr:312-314`; the flow's listing room, `Heads.idr:347-363`;
  Tarjan's unseen count, `Check.idr:221-226`; Bellman-Ford's rounds left,
  `Potential.idr:655-669`), and the translation's worklist recurses on a
  finite universe the growth check bounds (`Finite.idr:127-138, 343-375`).
  No fuel, no cap, no round count (§2.6).
- The two counts in the code are not budgets: Bellman-Ford's rounds, as
  many as the arcs, end in a certified positive cycle (`climb`,
  `Potential.idr:619-644`), and `walkBack`'s rounds are the length bound
  of a simple walk (`Check.idr:487-496`). Neither can reject a program for
  running out.
- History shows the alternative was tried and removed: 3fc4d2e4 replaced
  "the rule that refused any request growing against an earlier one"
  (a well-quasi-order, `Proof/AlmostFull.idr`) with the graph, because the
  wqo refused programs the graph admits; its gate admitted the self
  compile with "no assert_total, covering, believe_me or postulate in the
  proof or the checker".
- The cost of having no budget on an acceptance analysis is visible in
  the record: the growth phase took 1,093 s at its first integration and
  67 s after four representation fixes (three left-folded `++` joins,
  index-lookup sorting, `Vect` tables to tries), each a representation,
  none a limit (*measured*, 3fc4d2e4's
  `bench/profiles/2026-10-17-self-growth.md`).
- The proposal's lists of "analyses a refusal rests on" (§5.6 item 5:
  "knots, the in-place promise"; §5.11 (A): "defunctionalization, the
  label solve, counting, lowering") omit the frontend's growth check and
  reachability walk; if the rule is confirmed, the plan should name them.

**oom-2 (the compiler running out: a crash, not a refusal; budgets in
the program's units).**
- No refusal of the frontend is by resource: `Idr_RuleCategory` has three
  kinds, and "No limit of the compiler's is a kind: a limit is lifted by a
  representation, never refused" (`IdrBase.td:150-161`).
- An admitted program's instance count is finite (`Proof/Requests.Universe`,
  `:733-737`) but bounded only by the universe's size, which is
  astronomically larger than any program needs; nothing bounds the
  translation's actual work but the program. So the frontend can run out
  of memory on an admitted program, and under today's rules that is a
  crash, never a refusal: the evidence that the question is live on the
  Idris side too, not only in the C++ pipeline.
- The frontend has no budget to count in any unit. Its state that grows
  with a product of program quantities (`Heads.combinations`,
  `Graph.familyHeads`, `Graph.evaluated.choices`, §2.4) is
  acceptance-critical (the graph must cover every node the program can
  reach, or the growth check is unsound), so no budget may cut it; only a
  representation can.
- *Measured* at the self compile (3fc4d2e4): peak resident memory of the
  whole frontend run 5.15 GB (idle) and 5.56 GB (under load); no
  per-phase memory record exists.

**oom-1 (out of memory outside the language).**
- Nothing in the frontend's types or facts represents allocation failure:
  the one proved fact emitted is termination (`Facts.idr:18`), which C++
  reads as the `Divergence` effect (`lib/IR/Func/Func.cpp:190`); no rule,
  fact or type names memory.
- The adjacent decision already taken: raw memory is outside the
  language (`RawPointer`, `IdrBase.td:213-216`; refused wherever reached,
  `Profile.idr:62, 357-358`; 355a3f6f: "a reference this compiler keeps
  is a heap value it accounts for").

**Others this subsystem bears on.**
- **Q-O3, Q-E2 (facts into types; where a summary lives).** The growth
  check's answer is read by the next phase only, and today crosses as
  mutable state behind a `Bool` (§4 FC-01); its one fact that reaches the
  dialect, termination, is an inherent `UnitAttr` on `idr.func`
  (`IdrOps.td:161`), read by four C++ passes (§2.2).
- **DD-Q2, ods-Q1 (may a dead call to a non-total function be
  deleted?).** The frontend's `terminating` is per function and about its
  own loops only ("A loop never leaves its component; what it calls
  outside carries its own fact", `Facts.idr:13-17`; ed1503ef), and an
  unchecked component reads as "may not terminate" (`fromMaybe False`,
  `Programs.idr:78`).
- **Q3 (the frontend's mirror cut over in the same change).** G5 needs
  the generator to write a new field of `Idr_RuleCase`; the Idris side
  today ignores the generated `ruleCategory` (§4 FC-78).
- **Q-M5, Q-O4 (specializer shape and order).** The frontend's
  monomorphizer is already demand-driven from the root, one request per
  key, first in first out by generation (`Finite.idr:343-375`), and it
  specializes dictionaries and families (the node split, `Heads.idr:1-37`)
  before defunctionalization ever runs: MLton's order for the part the
  frontend owns.
- **QL4 (byte-identical output for any thread count).** The subsystem is
  single-threaded and its orders are fixed (breadth-first levels, callers
  first components, FIFO generations).

**New questions for the owner.**
- **Q-fc-1. The proof's model and the code.** Theorem 1 is proved over a
  model of templates (`Proof/Bound.idr`, `Term m`, three constructors), and
  "the frontend builds no derivation. The worklist checks the conclusion
  on every request" (`Bound.idr:55-58`): the run-time witness
  (`Finite.heightWithin`, `sizedWithin`, `Translate/Types.idr:853`) is the
  bridge between proof and code. Should the cutover make the code's
  `Template` the model (the frontend builds the derivation and the
  witness goes), or is the witness the accepted bridge, recorded as a
  trust point the way AGENTS.md records `covering`? Today it is neither:
  an internal error that would fire on a frontend bug, never on a user
  program.
- **Q-fc-2. Context-sensitive flow as a representation fix.** If stage 1
  shows the node split's product (`Heads.combinations`,
  `Graph.familyHeads`) is large, the fix that keeps acceptance unchanged
  is a flow split by node (context-sensitive), at the price of a larger
  flow solve. Is that the direction, given that no budget may cut an
  acceptance analysis?

## 7. Deletion list

By change (§5); every symbol *read* at the cited line.

- **G1:** `TS.bounds`, `TS.sizes` and their defaults
  (`Translate/State.idr:441-447, 455-456`); `checkGrowth`'s `Bool`
  (`Growth.idr:325`); the resolution of main in `Graph.build`
  (`Graph.idr:925-927`).
- **G2:** `Template.Computing` outside `Template AtNode`, with
  `Caps.deepest`'s `Computing` arm (`Caps.idr:69-73`),
  `Heads.byTemplate`'s (`Heads.idr:174-176`), `Sites.render`'s,
  `eraseIn`'s, `buildsIn`'s (`Sites.idr:320, 370, 415`); `Head`'s
  `Maybe`; the per-tag recursions of `tallest`/`height`, `widest`/`arity`,
  `holdsFormal`/`formalIn`, `betaAll`/`beta`, `appliedAll`/`appliedIn`/
  `familiesIn`, `applyingAll`/`applyingIn`, `allWithClosed`,
  `allSelfBounded`/`selfBounded`, `weightsAll`/`weightsAt`,
  `stuckAll`/`stuckAt`, `heaviestOf`/`heaviest`, `formedTemplates`,
  `byLeaves`, `carriedAll`, `renderAll`, `eraseAll`, `buildsAll`,
  `partsOf`/`parts`, `deepestIn` (each replaced by an algebra).
- **G3:** `Growth.Source`, `sourceOf`, `subject`'s `Source` argument,
  `carries`, `parts`, `partsOf`, `computationThrough`
  (`Growth.idr:162-212`); the two internal errors of `refuseOpaque`
  (`:282, 289`); `Built.wrote` as a parallel `Vect` (`Graph.idr:73`);
  `Requests.sameAddress` (`:378-381`).
- **G4:** `Graph.numbered` (`:792-796`) and its internal error
  (`:977-978`); `landings`' `number` map (`:690`); `Carries`
  (`:615-637`); `unvisited`, `mark`, `visitLeaves`, `flag`'s use in
  `spread` (`:645-675`); `Stray` and its two internal errors (`:330,
  939-945`); `graphDefinition`'s, `capOf`'s and `nodeValues`'s
  internal errors (`Growth.idr:86`, `Caps.idr:169`, `Sites.idr:1387,
  1389`); `Finite.heightWithin`'s `lookup` (`Finite.idr:189-190`).
- **G5:** `Profile.outsideLanguage`, `reason`, `exclusion`'s `Maybe`
  (`Profile.idr:52-70`).
- **G6:** the six `Static` switches (`Sites.idr:589-596`,
  `Template.idr:936-948, 1395-1400`, `Heads.idr:204-209`,
  `Sites.idr:1296-1302`, `Caps.idr:172-194`); `Caps.binder`,
  `parameterAt` (`Caps.idr:138-153`); the `staticsOver` call in `capOf`
  (`:171`).
- **G7:** `Heads.Slot`'s tuple, `parameterSlot`, `fieldSlot`'s byte
  encoding, `sameBytes`, `sameKind`, `same`, `[bytewise]`, `isNew`,
  `viewOf` per round (`Heads.idr:80-143, 355`); `Implementations.fieldAt`
  (`:55-56`); `Heads.placedAt`'s `head' . drop` (`:246-247`).
- **G8:** `Graph.Pending`, `queued`, `level`'s bookkeeping
  (`Graph.idr:106-112, 181-199`); `Profile.Pending`, `queued`
  (`Profile.idr:284-291`); one of `Check.components` (`:328-371`) and
  `Translate/Recursion.idr`'s `Search`/visit.
- **G9:** nothing deleted but the run-time `All` list; quantities change
  on `Verdict.Bounded`, `Fitted.fits`, `Settled.Settles`.
- **G10:** `Check.feasibleIn`, `satisfiesIn`, `satisfyAllIn`, `raised`,
  the fallback in `check` (`Check.idr:638-708`); `Check.ring` and the
  `Fails` arm of `cycleThrough` (`:502-512, 544-548`).
- **G11:** `Potential.Cells`, `Table`, `entry`, `put`, `mapTable`,
  `column`, `entryPut`, `entryPutOther`, `entryMap`, `indexColumn`
  (`Potential.idr:117-161`); `Walk.Seen`'s own tree (`Walk.idr:92-110`).
- **G12:** `Sites.decided`'s truncation (`:506-508`), `envOf`'s padding
  (`:1335`), `Sites.holed` or `Terms.holed`, `Sites.quantitiesOf`
  (`:481-486`), `rebound`'s per-entry rewrite (`:1063-1072`),
  `Graph.givenFamilies` (`:849-868`), `siteAt`'s fallback (`:294`), 29
  `EmptyFC`s.
- **G13:** `TS.loops` (`Translate/State.idr:385`), `fromMaybe False`
  (`Translate/Programs.idr:78`), `Facts.terminating : Bool`.
- **G14:** `Profile.proofOnly`'s lookup (`:225-230`), `Profile.imports`
  (`:111-130`, with lane 17), `TS.spelled`'s `String` key
  (`Translate/State.idr:427-429`), the second `Builtin Crash` match
  (`Profile.idr:369-371`).

## 8. Risks, unknowns, measurements needed

**Risks.**
- *Proof cost.* G10 and G11 move proofs (Bellman-Ford's lemmas over
  `Cells`, a certificate out of `settle`) onto the trie. The proofs are
  erased, so run time does not change, but Idris's type checking of
  `Potential.idr` and `Check.idr` is the gate; the brute-force box
  (`tests/growth-check`, 542,896 graphs, *read* `expected-stdout`) must
  stay identical.
- *The subset.* G2's `Template : Stage -> Type` indexes by a parameter
  no value stores, which the subset admits ("Index by a parameter the
  value does not store", `SKILL.md`); a `Fix`-style base functor might
  not be, so `children`/`withChildren` is the safer traversal. Both hosts
  must compile it: stock Idris on Chez and idris-mlir.
- *One-word addresses.* G4's `Address` as one word needs a listing at
  quantity 0 over 2^64 values. If its type index is a `Nat` such as
  `power 2 64`, the type checker must not unfold it in unary
  (*conjecture*: Idris 2's evaluator treats `Nat` arithmetic on literals
  as `Integer`; to be tried on both hosts before the change is planned).
  The safe alternative keeps the representation and measures first.
- *Soundness of today's silent drops* (*conjecture*): `Heads.placedAt`
  (§4 FC-35) and `Implementations.methodField`'s unresolved function
  (FC-40) drop arcs without a trace; if either fires, the growth check
  under-approximates and only `Finite`'s run-time witness catches it, as
  an internal error. G7 and the FC-40 split make both unrepresentable.
- *Ordering of G1.* `Translate/Types.idr` reads `TS.bounds` during data
  registration (`:853`); G1 must thread the admission through lane 15's
  code in the same change.

**Unknowns.**
- Whether `Heads.combinations` makes nodes no request makes (the flow is
  context-insensitive). The self compile has 13,218 nodes
  (`Graph.idr:357`, comment) against 69,773 Core functions (3fc4d2e4's
  profile): not yet a wall.
- The cost share of address comparisons in the 67-77 s growth phase.

**Measurements needed** (none can run in this checkout; each on the
self compile and on the stage-1 module):
- per growth sub-phase time: definitions walk, flow, readings, node walk,
  caps, landings, evaluation, arcs, check (the profile has only the
  phase total);
- sizes of the three products: nodes per definition from
  `combinations`, headed readings from `familyHeads`, arguments from
  `choices`;
- flow rounds and candidates per round (`Heads.round`);
- components with a losing arc, their sizes, and Bellman-Ford rounds;
- chain lengths at `elemLink` (`Finite.idr:224`);
- allocations of `Feasible`'s `All` list (G9) and of `rebound`'s
  per-branch copies (`Sites.idr:1063`);
- a per-phase peak-memory record for the frontend (oom-3's question,
  frontend side).

## 9. Sources read

**Read in full:** `.claude/skills/representation-first/SKILL.md`;
`AGENTS.md`; `proposals/0003-facts-once.md`; `audits/p0/README.md`; every
file of the subsystem, line by line: `compiler/src/IdrisMLIR/Frontend/Growth.idr`,
`Frontend/Growth/{Caps,Check,Fields,Graph,Heads,Implementations,Potential,Sites,Template}.idr`,
`Frontend/Finite.idr`, `Frontend/Profile.idr`,
`Proof/{Forms,Generations,Growth,Requests}.idr`, `Facts.idr`;
`Proof/Bound.idr`'s header (`:1-80`), declarations and theorem
statements (`:79-330`, by `grep` of every top-level signature).

**The proposal (`proposals/0000-mlir-native.md`):** §0 to §4 in full
(`:1-339`); §5.3 in full (`:2154-3220`); §5.6 in full (`:4885-5881`);
§5.7 in full (`:5883-6749`); §5.9 in full (`:8052-9038`); §5.11 in full
(`:9857-10771`); §6 to §9 in full (`:10772-11141`); §5.4's F11-F25,
"what it means", designs and questions (`:3222-3281, 3405-3924`); §5.5's
brief, D4, D8 and questions (`:4048-4090, 4580-4600, 4700-4800`); §5.8's
summary, C2-C4, EF1-EF3, DS2-DS3 and questions (`:6800-6830, 7066-7090,
7680-7700, 7790-7962`); §5.1's and §5.2's questions and notes
(`:1097-1162, 1995-2088`); §5.10's brief and questions (`:9064-9084,
9706-9770`). Not read line by line: the findings of §5.1 (A-H), §5.2,
§5.5, §5.8 and §5.10, which concern the C++ side; their questions for
wave 2 were read and none falls here.

**Other code read for context:** `compiler/src/IdrisMLIR/Frontend/Program.idr:185-260`;
`Frontend/Translate/State.idr:72, 146-170, 360-460`;
`Frontend/Translate/Errors.idr:40-105`; `Frontend/Translate/Programs.idr:55-90, 160-175`;
`Frontend/Translate/Recursion.idr:1-60, 105-135` (by `grep`);
`Frontend/Walk.idr:1-192` (signatures); `Emit/Declarations.idr:30-75`;
`Term.idr:345, 427` (by `grep`); `Syntax/Idr.idr:172-205, 242, 273, 303-320, 392`;
`foreign/idr/include/idr/IR/IdrBase.td:150-260`; `IdrOps.td:115-161`
(by `grep`); `lib/IR/Func/Func.cpp:190` and the `getTotal` readers (by
`grep`); `tests/growth-check/run`, `expected-stdout`.

**History:** `git log` of the subsystem's paths (50 commits); messages
of 3fc4d2e4 (the growth graph, with its `--stat`), 997b9d87 (family
evaluation), 998d6cdb (trusted proofs not walked), 1d25638c (waiting
instances), 2a66fbcb (every independent rejection), ed1503ef (the
terminating fact per component), 355a3f6f (threads, finalizers, raw
pointers outside the language); `git show 3fc4d2e4:bench/profiles/2026-10-17-self-growth.md`.

**Commands for the measurements cited** (from the repository root):
- sizes: `wc -l compiler/src/IdrisMLIR/Frontend/Growth.idr compiler/src/IdrisMLIR/Frontend/Growth/*.idr compiler/src/IdrisMLIR/Frontend/Finite.idr compiler/src/IdrisMLIR/Frontend/Profile.idr compiler/src/IdrisMLIR/Proof/*.idr compiler/src/IdrisMLIR/Facts.idr`;
  `find compiler/src -name '*.idr' | xargs wc -l | tail -1`;
- trust points: `grep -rn -E '\bcovering\b|assert_total|assert_smaller|believe_me|postulate|^\s*partial\b' <subsystem>`,
  comments excluded;
- budgets: `grep -rn -i -E '\bfuel\b|budget|maxIter' <subsystem>`;
- internal errors: `grep -rn -E 'internal |unsound ' <subsystem>`;
- `EmptyFC`: `grep -rn -c EmptyFC <subsystem>`;
- template arms: `grep -rn -c -E '^\s+[a-zA-Z]+ .*\((Var|Head|Leaf|Token|Choice|Opaque|Applied|Computing|Formal|Field|Held) ' compiler/src/IdrisMLIR/Frontend/Growth*`;
- `Computing`: `grep -rn -E '\(Computing|Computing ' compiler/src/IdrisMLIR/Frontend`;
- importers: `grep -rln 'IdrisMLIR.Proof.Bound' compiler`;
- `ruleCategory` readers: `grep -rn 'ruleCategory' compiler/src --include='*.idr'`.
