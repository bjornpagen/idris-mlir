<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# P0 design: what equality saturation buys this compiler

Status: written 2026-10-21 for D57 and D85 (`proposals/0000-mlir-native.md:973-986,
1232-1245`), answering the owner: "remind me, why do we need this again?
what kind of unholy optimizations could this make for us. i really want to
flesh this out", and earlier "we want to wring as much perf as possible and
nasty, ridiculous unintuitive optimizations ... once we have the
representation, the search could be trivial". The headline case is the
owner's (via the coordinator, 2026-10-21): parser combinators, linear ones
over a quantity-1 byte buffer most of all, "it stress tests like every part
of our compiler". This file catalogues the payoffs, grounds them in the
programs of this tree, measures what can be measured on this machine, and
ranks them. It reverses nothing. Engine speed is `speed.md`'s, the engine's
build `one-engine.md`'s, the sparse form `sparse-mlir.md`'s and
`sparse-library.md`'s, the open questions `unknowns.md`'s (its U1 and
U25-U28 are cited, not redone); `workloads.md` had not appeared.

Grounds: *read* (path:line), *measured* (a command I ran, its build, input
and machine), *measured (agent)* (a run by one of this task's subagents,
scripts and raw output in `/tmp/eg-payoffs/{census,theorems,passes}/`),
*read (agent)* (a primary source a subagent read, its location theirs),
*recalled*, *conjecture*, *decision* (a ruling Dn). Ours at HEAD e96bb991
with the working tree. Machine: Apple M2 Max (virtual), 8 cores, 32 GB,
macOS, shared (load average 9-12 during the runs). Host tools: Apple clang
21.0.0; stock Idris 0.8.0-1c630e67c on the Chez in `.toolchain/`; the fork
as the host built it (`build/idris2-host/idris2-0.8.0/idris-compiler-0.8.0`).
The runtime was compiled from `runtime/` at HEAD by the host clang with the
flags of `runtime/CMakeLists.txt` (`-O3`, snmalloc header-only, the
darwin target entry's page size and address bits) into
`/tmp/eg-payoffs/rt/libidris_rt.a` (`rt/build.sh`); every C++ experiment
links it, allocates through `idris_rt_cell`, counts through
`idris_rt_inc`/`idris_rt_dec`, and ends with `idris_rt_live_cells`
unchanged (no leaks). Nothing of the LLVM project was built; nothing in the
repository was built or run. Times are the minimum of three runs of five
timed repetitions.

## 0. In plain words

- **Why we need it.** Not for one optimization. The measured wins on the
  killer case come from three sources, in this order: *specialization* of
  code over facts the program fixes (closure labels, static grammars,
  constant lists), *representation* (an offset instead of a list of
  characters, a view instead of a copied token, a linear buffer instead of
  a shared input), and the *cleanup that makes specialization pay*:
  known-constructor folds, case-of-case, sinking a value into the one path
  that uses it, dead code of total calls, dispatch on First sets. The
  e-graph is the one mechanism for the third, with no pass order to fight
  (the class of bug in c179ab2d, 1b2e31da, 3a96c407 becomes
  unrepresentable) and with a cost to choose where two forms are each best
  somewhere. It is an amplifier of the facts this compiler holds, not the
  source of the speed by itself.
- **The headline, measured.** The fork's lexer and parser, lowered by hand
  to C++ against `runtime/` and run on the frontend's own 78 source files
  (1.45 MB, 222,369 tokens): as written, 442.9 ms to lex and 104.6 ms to
  parse; hand-written, 18.9 and 6.6 ms (23.4× and 15.9×). Specialization
  plus the e-graph's directional rules, with nothing marked research,
  reach 122.0 + 9.6 ms (5.2× of hand-written overall, 1.45× on the parser);
  the lexer's remaining 6.4× is representation, which a library written
  over `Linear.String.Iterator` and views chooses for itself, and an
  optimizer reaches only by research. §1.
- **The nastiest payoffs that are real.** (1) The combinator tower
  specialized and folded: 4.5× and 6.4× fewer cells on the parser. (2)
  Failure payloads (error lists) never built on the paths that drop them:
  a further 2.4×. (3) A static deep embedding (the lexer's `Recognise`)
  partially evaluated away: 3.0×, 12.7 M of 20.5 M cells gone, once the
  grammar is a compile-time value, which nothing computes today. (4)
  First-set dispatch: 1.2-1.45×. (5) A fold law from base's proofs turns
  `concat` on lists from quadratic to linear: 45× at 100 pieces, 395× at
  1,000 (base's `Foldable List` makes every `concat` and `concatMap`
  over a list a left fold of `<+>`, `Prelude/Types.idr:669`).
- **What is weak.** String reassociation (E5) is cold in every program
  here. Theorem rules (E6) almost never match source text, and
  map fusion's allocation win is already reuse's (a measured 1.13×
  residual). Share-or-keep-apart (E7) has essentially no occurrence in
  real code; its value is the guard the unique class already gives. §7.
- **What facts are missing for the killer case.** A grammar value known at
  compile time (static evaluation of a constant, proposal 0010, not
  built); proved combinator laws (the fork's `Grammar` breaks the functor
  and monad identities on the nose, *measured*); a theorem that `scan`
  returns a prefix of its input; a string view type with a lifetime; a
  First-set analysis; tail recursion modulo a case on the recursive
  result. §1.7.

## 1. The headline: parser combinators

### 1.1 What runs, and where the time goes

The frontend runs the fork's lexer and parser on every source it reads
(`compiler/src/IdrisMLIR/Frontend/Driver.idr:47` imports `Idris.ModTree`).
They are:
- **The lexer**, a deep embedding: `Recognise` is a data type of
  recognisers (`compiler/idris/src/Libraries/Text/Lexer/Core.idr:17-26`)
  interpreted by `scan` over `List Char` (`:107-132`), accumulating the
  token's characters in a `SnocList` and returning `Maybe (SnocList Char,
  List Char)` per step. `some l = l <+> many l` with `many` behind `Inf`
  (`Lexer.idr:117-126`), so each character `many` consumes forces a thunk
  that builds two new grammar nodes. The tokenizer tries the 23
  alternatives of `rawTokens` in order for every token
  (`Parser/Lexer/Source.idr:308-346`; `Tokenizer.idr:101-127`), packs the
  token by `fastPack (token <>> [])`, counts newlines by `filter` then
  `length` (`Tokenizer.idr:91-99`), makes every whitespace character its
  own `Space` token (`space = pred isSpace`, `Lexer.idr:265-266`), tests
  every identifier with `elem` over 41 keywords (`Source.idr:349`), tests
  an operator character with `elem` over an `unpack`ed literal
  (`Core/Name.idr:87-88`; `unpack` is an Idris loop, not a runtime op,
  `Registry/Primitives.idr:493-511`), and then makes four list passes:
  `filter isNotSpace`, `map spotComment`, `partitionEithers`, `map (++
  end)` (`Source.idr:373-391`) (*read*).
- **The parser**, a shallow embedding since 360db182: a grammar is a boxed
  function `Input -> ParseResult` (`Parser/Core.idr:63-65`), because the
  deep embedding "hid the type of the first grammar's result ... which
  this compiler cannot represent" (360db182's message, *read*). `>>=` runs
  the first grammar, applies the continuation and then `mergeWith`s the
  bounds into the result (`:71-73, 87-93`), so the continuation is never a
  tail call; `<|>` keeps its input for the second branch and appends both
  branches' errors when both fail (`:180-204`); `terminal` rebuilds the
  `Input` record per token (`:276-284`); `many` rebuilds its grammar per
  iteration (`Parser.idr:77-88`).

*Measured* (stock Idris on Chez, `/tmp/eg-payoffs/lexcount/{LexCount,ParseTime}.idr`,
input the 78 files of `compiler/src`, 1,454,140 characters): the real lexer
gives 226,597 non-space tokens (Ident 105,639; Symbol 90,206; Keyword
7,927; DocComment 5,879; Comment 2,343; StringBegin and StringEnd 2,672
each; StringLit 2,644; IntegerLit 2,204; DotIdent 2,137; DotSepIdent
2,054; the rest under 100 each); 319,596 characters (22%) are whitespace.
Lexing takes 1.04-1.47 s and lexing plus parsing 4.98-5.74 s, all 78 files
parsed: the parser is about three quarters of source processing on that
host. Chez is not our compiler; the ratio, not the time, is the finding.

### 1.2 The lexer, lowered by hand at nine levels

`/tmp/eg-payoffs/lexer/lex.cpp` models the lexer above: the 23
alternatives in `rawTokens`' order with their recognisers (block comments
without nesting, `cgDirective` and multiline strings simplified), the
group and string compositions as `Tokenizer.idr`'s nested `tokenise` with
its scan of the closing lexer before every token, and the four list
passes. Its token counts are within 1.1% of the real lexer's on every kind
(Ident 104,861 against 105,639; Symbol 89,498 against 90,206; DocComment
5,843 against 5,879), and every level produces the same counts. Build:
`clang++ -std=c++20 -O2 -mcpu=apple-m1`, linked with the runtime above.

| level | what changed | what it needs | ms/run | cells | strings | × previous | × h |
| --- | --- | --- | --- | --- | --- | --- | --- |
| v0 | as written | | 442.9 | 20,528,573 | 461,494 | | 23.4 |
| v1 | `scan` specialized on the static grammar: no tree walk, no `Just`/pair per step, no `Inf` unfolding; `isOpChar` a table | the grammar as a compile-time value (missing); specialization by label; known-constructor folds across the specialized recursion; a closed total call hoisted; `elem` over a constant list unrolled | 145.7 | 7,851,547 | 461,494 | 3.04 | 7.7 |
| v1d | v1, alternatives filtered by the first byte | a First-set analysis of the static grammar | 122.0 | 7,851,547 | 461,494 | 1.19 | 6.4 |
| v2 | v1, the input an offset into the string, no `List Char` | a representation change (research), or a library over `Linear.String.Iterator` | 129.9 | 6,397,400 | 461,494 | 1.12 (on v1) | 6.9 |
| v3 | the token a substring: no `SnocList`, reverse or pack; no text for `const Space` | a theorem that `scan` returns a prefix (missing), or a library returning offsets; dead code of a total call | 90.7 | 3,431,335 | 222,369 | 1.43 | 4.8 |
| v4 | v3 with first-byte dispatch | First sets | 65.3 | 3,431,335 | 222,369 | 1.39 | 3.5 |
| v5 | the four passes fused into the loop: no `Space` token built, comments and tokens through destinations; `Bounds` inline | producer-consumer fusion of a recursive loop (research), or a library that filters as it goes; layout (D48, D58) | 32.2 | 674,397 | 222,369 | 2.03 | 1.70 |
| v6 | the token's text a view | a string view scoped by a lifetime (missing) | 26.3 | 674,397 | 0 | 1.22 | 1.39 |
| h | hand-written: a switch on the first byte, tokens as structs in an array | | 18.9 | 0 | 0 | 1.39 | 1 |

All *measured*. v0's 20.5 M cells are 462 MB for 1.45 MB of source, with
9.7 M increments and 9.6 M decrements. In v0 a `Just` and a pair die the
moment the caller takes them apart, so reuse (C1) would recycle some of
them; the model pays snmalloc's free-list path for them instead, which is
about what reuse costs (*conjecture*).

### 1.3 The parser, lowered by hand at five levels

`/tmp/eg-payoffs/lexer/parse.cpp` runs the fork's combinators, as written
and specialized, on the real token stream (the lexer's tokens with spaces
and comments out, as `Source.lexTo` gives them). The grammar is small:
declarations starting at column 0, each a sequence of items (identifiers,
literals, symbols, bracketed groups of items), with the fork's `many`,
`<|>`, `>>=`, `>>`, `map`, `nextIs`, `terminal`, `eof` and its commit,
error and bounds semantics. All five levels parse all 78 files to the same
211,130 AST nodes.

| level | what changed | what it needs | ms/run | cells | combinator steps | × previous | × h |
| --- | --- | --- | --- | --- | --- | --- | --- |
| p0 | as written: grammars are cells (defunctionalized closures) run by a switch; `Input`, `Res`, `Failure`, `WithBounds` cells; `many` rebuilt per iteration; errors built and appended on every failed alternative; a bounds cell per bind | | 104.6 | 7,889,012 | 2,620,822 | | 15.9 |
| p1 | one function per nonterminal; results and `Input` by value; bounds merged in registers; errors still eager | specialization by closure label; inlining; case-of-case and known-constructor folds on `Res`/`Failure` (E8, E9); records unboxed; `many` as a loop needs tail recursion modulo a case (research; the recursive form costs frames, not cells) | 23.3 | 1,227,341 | 1,160,453 | 4.49 | 3.5 |
| p2 | errors built only on the path that returns them | sinking a total construction past the alternatives that drop it, and dead code (E2) | 9.55 | 408,884 | 1,160,453 | 2.44 | 1.45 |
| p3 | the token list an array and an index | a representation change (research) | 9.99 | 408,884 | 1,160,453 | 0.96 | 1.52 |
| h | hand-written recursive descent: a switch on the token's kind | First sets on tokens | 6.57 | 408,884 | 235,667 | 1.45 (on p2) | 1 |

All *measured*. The 408,884 cells of p2, p3 and h are the AST, the output.
p0 makes 7.6 M increments. The model charges native calls; under D32
"every recursion on a call cycle keeps its depth on D31's typed frame
stacks" (`proposals/0000-mlir-native.md:583-605`, *read*), and p0's
combinator calls are on the cycle through the closure dispatch, so in
compiled code each of p0's 2.6 M steps would also pay a frame's push and
dispatch: p0's gap is a lower bound (*conjecture*). The real Idris grammar
is much larger (275 grammar-typed definitions, 218 `<|>`, 37 `commit` in
the fork's parser files, *measured (agent)*, `census/c9_grammar.txt`), so
its share of failed alternatives, and with it of p1→p2 and p3→h, is likely
larger than this model's (*conjecture*).

Lexing and parsing together: 547.5 ms as written, 25.5 ms hand-written
(21.5×); 131.6 ms with what needs no research (v1d + p2, 5.2×); about
36 ms (v6 + p2, 1.4×) where the library chooses the representation
(*measured* for the hand-lowered levels; that a library written over
offsets and views compiles to v6 is *conjecture*).

### 1.4 Each fact, traced

- **Defunctionalization and the combinator tower.** After
  defunctionalization every grammar is a label of the closed sum of
  `Input -> ParseResult` closures, and `runGrammar` a dispatch over it
  (AGENTS.md; `unknowns.md` U25 settles that the e-graph runs after this,
  on first-order code). Specialization by label (L18) turns `runGrammar g
  inp` with `g` a known label into a direct call; inlining exposes
  `case (case runGrammar act inp of ...) of ...`, which is case-of-case
  (E9) on every bind; the known-constructor fold then removes `Res` and
  `Failure` (E8). That is p0→p1: directional rewrites, not saturation. The
  fork's choice of a shallow embedding (360db182) is what makes this
  first-order specialization rather than an interpreter to partially
  evaluate: the lexer, still a deep embedding, needs the harder step (v1).
- **Binds on frame stacks (D31, D32).** `bindGrammar`'s continuation is
  followed by `mergeWith` (`Core.idr:93`), so it is a non-tail call; on
  the cycle through the dispatch it pushes a frame. Depth is the nesting
  of binds times the input's nesting, plus one level per item of each
  `many` (`some p = pure (!p ::: !(many p))`, `Parser.idr:82`). D31 bounds
  the native stack, not the frames. What would make every bind a tail
  call is the monoid law of the bounds: `mergeBounds` is a monoid action
  (irrelevant is the identity; two relevant bounds merge by `union`, which
  is associative, `Bounded.idr:33-38, 93-99`, *read*), so the pending
  merge can be carried down as an accumulator, the shape `idr-accumulate`
  makes for `+` only (`Transforms/Tail/Accumulate.cpp:5-11`, *read*).
  Proving it needs `min` and `max` on `Int` pairs to be lattice
  operations, which base does not prove for the primitive order (a
  declared law); the law-driven accumulator is research (N5).
- **Backtracking `<|>` against in-place reuse (E7's cousin).** `<|>` holds
  `inp0` for its second branch (`Core.idr:186-194`), so `Input` is never
  exclusive inside the first, and every `{ tokens := xs } inp` in
  `terminal` builds a new cell instead of updating one. This is sharing by
  backtracking, not by a hash-cons merge; extraction cannot fix it. The
  representation fixes it: once `Input` is unboxed (p1) there is nothing to
  copy but a pointer or an index, and in the linear form (§1.6) the input
  is a position, a word.
- **Recursive grammars and tail calls (D30, D34).** A grammar's recursion
  (`expr` through a group back to `expr`) is genuine nesting and keeps its
  frames. `many` and `sepBy` are where a hand-written parser loops: the
  self call's result is examined (`Failure` passes through, `Res` is
  wrapped in `x ::: xs`), a context D34's constructor contexts do not
  cover. Tail recursion modulo a case whose other arm returns the callee's
  result unchanged is the missing promise; p1 assumes it.
- **Lifetimes for token views (D63).** A token's text as a view into the
  source is v5→v6 (1.22×, 222,369 strings gone). A view must not outlive
  the source: with D63 the view is allocated into the source's lifetime
  and MLIR's dominance checks it. Identifiers escape into the AST, which
  outlives the lexing; they need a copy (or interning) at the boundary,
  and punctuation and keywords, which the parser consumes, need none
  (*conjecture* on the split; *read* D63, `proposals/0000-mlir-native.md:1043-1067`).
  The runtime's string has no view form (`runtime/idris_rt.h:140-150`):
  the type is missing.
- **The `consumes` index.** `Grammar state tok consumes ty` states, at
  quantity 0, the fact Krishnaswami and Yallop's type system computes as
  ¬Null (§1.8): a consuming grammar is not nullable, so First-set dispatch
  needs no nullability test and `many p`'s loop always advances. In
  upstream's deep embedding the constructors' indices prove it (`SeqEat :
  Grammar state tok True a -> ... -> Grammar state tok True b`,
  `third_party/Idris2/src/Libraries/Text/Parser/Core.idr:22-51`); in the
  fork's shallow embedding `MkGrammar` wraps any function at any index
  (`compiler/idris/src/Libraries/Text/Parser/Core.idr:63-65`), and the
  invariant holds by the module's encapsulation, not by a type (*read*).
  D48 carries the index into MLIR, but here it would be trusted, not
  proved.
- **Totality and rows (D13).** The deletions above are of constructions
  (errors, a token's text, `Just`, pairs), which are total and pure (C3),
  so they need no row condition. `Libraries/Text` and `Parser/Lexer` are
  `%default total` (`Source.idr:22`) with `assert_total` at the recursion
  points (25 uses, *measured (agent)*); `Idris/Parser.idr` is `%default
  covering` (`:24`), where a call may not be deleted or reordered.
  `unknowns.md` U1 measured that `total` does not exclude a crash
  (division by zero in total code), so what licenses deleting a call is
  the derived row having neither `crash` nor `divergence`.

### 1.5 The laws: which are true

*Measured* (`/tmp/eg-payoffs/laws/Laws.idr`, `Laws2.idr`, stock Idris on
Chez, the fork's `Libraries.Text.Parser`, two tokens with real bounds):

| law | as stated | result |
| --- | --- | --- |
| functor identity `map id p = p` | on `bounds peek` | false: `MkBounds 3 7 3 8` against `MkBounds (-1) (-1) (-1) (-1)` |
| left identity `pure x >> p = p` | on `bounds (pure () >> peek)` | false, the same way |
| right identity `p >>= pure = p` | on `bounds (peek >>= pure)` | false, the same way |
| `fail <|> p = p` | on success / on failure | equal on success; on failure 2 errors against 1 |
| `p <|> fail = p` | on failure | 2 errors against 1 |

The cause is a flag: `WithBounds` holds `isIrrelevant : Bool` beside a
`bounds` that is junk when the flag is set, and `mergeBounds` and `map`
normalize junk to `-1` while `peek` keeps the token's real bounds
(`Bounded.idr:48-53, 85-99`; `Core.idr:163-175, 256-266`, *read*). With a
sum (`Irrelevant val | Relevant val bounds`) the identities would hold,
except that `bounds peek` would no longer expose a peeked token's
position. So laws here are only what the library proves, as `unknowns.md`
U26 concluded for PEG choice; none is proved today, and the ones a reader
would assume are false. The alternation laws hold modulo error lists, so
they are usable only where the errors are dead (inside a `<|>` whose last
branch succeeds), which is exactly what p2 exploits without any law.

### 1.6 A linear parser over a quantity-1 buffer with views

The tree already has the input half: `Linear.String.Iterator` is a byte
offset into a string's UTF-8, made only by `withString` and `uncons`, so
"a loop over `uncons` keeps the iterator and the step's result off the
heap" (`libs/mlir-linear/Linear/String/Iterator.idr:3-27, 63-91`, *read*).
A parser over it, or over a quantity-1 byte buffer, has:
- *Input*: a position, a word; the buffer threaded linearly. `<|>` saves
  a position, not an input record, so the copy of §1.4 does not exist.
  Failure must hand the buffer back for the second branch, which
  `unknowns.md` U28 found is also what makes un-factoring linear-safe.
- *Tokens*: views (offset, length) in the buffer's lifetime; the lexer
  does not build `List Char`, `SnocList` or packed strings (v2, v3, v6 by
  construction). Whether a read of the buffer floats in the e-graph
  depends on the library's type: a handle to immutable bytes has no
  resource, a mutable buffer's reads are ordered (`unknowns.md` U28; an
  owner question there).
- *Counting*: the buffer is quantity 1 and exclusive by type, so no count
  operation and no uniqueness test touches it (D10, D24); views are two
  words, a type that bounds what it reaches, so D26 lets a frame hold
  them past their last use.
- *What is left for the optimizer*: v0→v1 and p0→p2 (specialization,
  known-case, case-of-case, sinking, dead code) and First-set dispatch.
  The research rows of §1.2 and §1.3 become library choices.
So the representation-first answer to the killer case is that the linear
library removes the problems an optimizer could only research, and the
e-graph's job on it is the directional cleanup measured above.

### 1.7 How close, what is research, what is missing

- **How close** (*measured* in the model): without research, 1.45× of
  hand-written on the parser and 6.4× on the lexer; with the library's
  representation, about 1.4× overall. Parsley's best staged parser is
  1.08-1.25× a hand-written one and its naive recursive form 1.69-3.29×
  (Willis's thesis, Fig. 6.4, *read (agent)*), the same band.
- **Research** (each marked in the tables): the input and token-list
  representation changes (v1→v2, v6→h, p2→p3), producer-consumer fusion of
  the post-passes (v4→v5), the law-driven accumulator for bounds (N5),
  tail recursion modulo a case for `many`.
- **Missing facts**: (1) the grammar as a compile-time value: `rawTokens`
  is a constant built by closed calls (`choice $ exact <$> symbols`),
  which "run at run time" until static normalization (0010) exists
  (AGENTS.md); without it v0→v1 does not happen. (2) Proved combinator
  laws (§1.5), and the representation that would make them true. (3)
  `scan`'s prefix theorem. (4) A string view type with a lifetime. (5) A
  First-set (and Null, FLast) analysis over specialized grammar code,
  with U27's dispatch node. (6) The promise of tail recursion modulo a
  case.

### 1.8 Prior art, and what transfers

All *read (agent)* (notes with pages in `/tmp/eg-payoffs/prior-art/notes-parsley-flap-tap.md`):
- **Parsley** (Willis, Wu, Pickering, ICFP 2020; Willis's thesis 2024): a
  deep embedding optimized bottom-up by applicative, alternative and
  selective laws in their improving direction until a normal form (§3.1),
  sharing and recursion found by pointer identity (§3.2), compiled to a
  typed stack machine whose interpreter is staged away (§4-5); 4-24×
  faster than parsec and megaparsec, 1.55-2.18× faster than happy on
  JavaScript (Fig. 5); 1.08-1.25× a hand-written loop (thesis Fig. 6.4).
  What transfers: its laws are directional rules over a deep embedding,
  and the thesis defunctionalizes library functions so laws can match them
  (§6.1.1), which our defunctionalization does for every closure. What
  does not: its laws are proved for its semantics, not ours (§1.5).
- **flap** (Yallop, Xie, Krishnaswami, PLDI 2023): normalizes a typed
  grammar into a deterministic Greibach form, replaces each token by its
  lexer's regex and specializes the lexer per nonterminal, so no token is
  ever built; MetaOCaml generates code with no indirect call and no
  allocation outside user actions; 2-6× ocamlyacc's throughput, 1.7-7.4×
  from fusion alone, about 1.4 GB/s on JSON. What transfers: the fused form
  is v5 and beyond with no token list at all; it needs a static deep
  grammar and determinism, which the fork's shallow parser does not give
  (the lexer would).
- **Typed algebraic parsing** (Krishnaswami, Yallop, PLDI 2019): types
  {Null, First, FLast}; sequence needs FLast₁ ∩ First₂ = ∅ and ¬Null₁,
  alternation disjoint First sets; linear time, no backtracking; staged
  7.9-94× faster than unstaged. What transfers: the analysis behind v1d,
  v4 and h, and the `consumes` index as its Null component (§1.4).
- **Parsing with derivatives** (Might et al. 2011; Adams et al. 2016):
  compaction rules applied once per node at construction, never to a
  fixpoint, keep the bound and gave about 90× and then 951×. The same
  discipline as Cranelift's rules at node creation. ReGiS (abstract only)
  found Kleene-algebra axioms in an e-graph do not saturate.
- **No paper applies equality saturation to parsers** (two searches,
  *read (agent)*); `unknowns.md` U27 measured why: commutation of
  alternatives is exponential in egglog, and associativity alone cannot
  bring same-byte alternatives together.

## 2. The catalogue

Each class: the real occurrences (counts are syntactic, a proxy: inlining
and specialization create more after the frontend), the win in a stated
measure, the demonstration, the mechanism (a *directional rule*, an
*analysis*, *saturation* with extraction choosing, *specialization*, or
*representation*, which is not the e-graph's), and the fact only this
compiler holds. Census counts are *measured (agent)*, `/tmp/eg-payoffs/census/run_classes.sh`;
corpora: bench (30 files), libs (7), the frontend (78), the fork's parser
files (28), the rest of the fork (176).

| class | real occurrences | win | demonstration | mechanism | research | the fact |
| --- | --- | --- | --- | --- | --- | --- |
| E1 fights between rewrites | c179ab2d, 1b2e31da (six hours in one sink call), 3a96c407 (75 M pattern attempts in 31 minutes); guards against fights at `Canon/Sink.cpp:34-36`, `CaseOfCase.cpp:12-15`, `OpsClosures.cpp:34-39`, `Canon.h:25-35` | the class of bug unrepresentable; about 1,744 lines deleted (§5) | none needed; the commits are the record | saturation | no | none special |
| E2 sink to the path that uses it | every failed alternative of a parser (218 `<|>` in the parser files); the lexer's dead text of `const Space` | 2.44× on the parser (p1→p2), 3× fewer cells | §1.3 | elaboration's placement and dead code | no | construction is pure (C3) and total |
| E3 guards an index proves | bench 2 (`spectral-norm-linear/Main.idr:33`, `k-nucleotide/Main.idr:157`); the frontend's 83 `index` calls need none (`Vect.index` has no guard) | one compare per access in an inner loop | not measured | analysis seeded by `Fin n` | no | D58, D59 |
| E4 integer algebra | `Integer` only in `pidigits`; `Nat`: 876 signature lines, 311 `S`, 72 `minus` in the frontend; 15 `div`/`mod` pairs on the same operands | a tag test and overflow branch per op, not an allocation: a small `Integer` is an odd word (`runtime/idris_rt.h:158-169`) | not measured | rules with `Exact` conditions; intervals | no | D41's `wraps` |
| E5 reassociation of strings | output lines built with `++`: bench 18, frontend 2, fork 12; `pidigits` builds a line of at most 10 digits | two string allocations per printed line | not measured; cold by inspection | saturation | no | C4's exact associativity |
| E6 theorems as rules | 211 usable rewrites in base; left sides in source: `map f (filter p xs)` 6 + 6, `fold (map ..)` 9 + 3, `concat (map ..)` 3, `lengthMap`, `reverse . reverse`, `(xs ++ ys) ++ zs`: 0 (§3) | per match n cells and n calls; map fusion only 1.13× under reuse | `demos/fold.cpp` | directional rules with row conditions | yes (harvest) | proofs in checked TT |
| E7 share or keep apart | equal constructions on one line: frontend 30, rest of fork 31 (1 of 4 sampled on one path); old record used after update: 22 of 435; none in the linear benchmarks | a copy per in-place rebuild defeated; frequency about 0 (§4) | §4 | extraction with counting in the cost | the exact form | D24, D70 |
| E8 specialization keys in classes | the combinator tower (p0→p1); `Just`/`Right` passed to a call: frontend 63, fork 124 (heuristic) | with E9, 4.49× on the parser, 6.4× fewer cells | §1.3 | analysis feeding the specializer | no | closed closure sums |
| E9 case-of-case | 0 syntactic; one per bind after inlining (286 `do` in the parser files, 664 in the frontend) | part of p0→p1 | §1.3 | skeleton rule, copy or join by cost | global choice | D19 join points |
| E10 array algebra | 1 bench site, `sum (tabulate ..)` (`spectral-norm-linear/Main.idr:33`) | 1.69× on that loop at n = 5,500 (51.0 against 30.1 ms per product) | `demos/tab.cpp` | region rules over generating ops | yes | D42, D43 |
| E11 heap reads across a crash | none found | unknown | none | partial-order skeleton | yes | D21, D27 |
| N1 static deep embeddings evaluated away | the lexer (`Recognise`, `Tokenizer`), run on every source character; `TokenMap`s elsewhere in the fork | 3.04× on the lexer, 12.7 M of 20.5 M cells | §1.2 | specialization plus known-case, given the constant | needs 0010 | the grammar is a closed term |
| N2 First-set dispatch | the lexer's 23 alternatives; every `<|>` chain over tokens | 1.19-1.39× lexer, 1.45× parser | §1.2, §1.3 | analysis and a dispatch node (U27) | partly | the `consumes` index (trusted) |
| N3 fold laws from proofs | `concat` and `concatMap` on lists: frontend 18 + 18 lines, fork 75 + 49; all left-nested (`Prelude/Types.idr:669`) | quadratic to linear: 45× at 100 pieces, 395× at 1,000 | `demos/fold.cpp` | directional rule from `appendAssociative`, `appendNilRightNeutral` | no | proofs in base |
| N4 counts bounded by the address space | every `Nat` produced by `length` of an in-memory structure | the small/large test and overflow branch of each `Nat` op on it | not measured | interval seeded by the target entry | no | `IDRIS_MLIR_USER_ADDRESS_BITS` (47 or 39, `CMakeLists.txt:205,222,241,273`) |
| N5 accumulators from monoid laws | every bind of a combinator parser (bounds); `++ [x]` in loops (frontend 42, fork 27) | frames to none for sequential binds; quadratic to linear for snoc loops | not measured | rule plus the tail passes | yes | proved monoid laws |
| N6 representation changes | `List Char` input, `List` of tokens, token `SnocList` + pack | v1→v2 1.12×, v2→v3 1.43×, v6→h 1.39× | §1.2 | not an e-graph rewrite | yes, or the library's | quantity 1, lifetimes |
| N7 closed calls and constant lists | `isOpChar` unpacks a 20-character literal per call (`Core/Name.idr:87-88`); keywords by `elem` over 41 strings (`Source.idr:349`) | 20 cells and a walk per call; 41 compares per identifier | part of v0→v1 | hoisting to static data; unrolling | no | totality of `unpack` |

Notes on the rows that need them:
- **E4 and N4.** A list cell is at least 16 bytes and a target's user
  addresses have at most 47 bits (39 on arm64 Linux with 4 KiB pages), so
  `length xs` of any structure in memory is below 2^43, far inside the
  small range of `±2^62` (`runtime/idris_rt.h:158-169`), and so is any
  count bounded by it plus a constant. The interval analysis seeded from
  the target entry, the one place a target is decided, folds the
  small/large test and the overflow branch on such values. The fact is
  this compiler's (frame-limited counting, the target entry); its
  frequency in the frontend is *conjecture*, and the win per operation is
  a few instructions, not an allocation.
- **E6 and reuse.** *Measured* (`demos/fold.cpp`, n = 10^6): `map g (map
  f xs)` with the unique intermediate reused costs 13.9 ms and 1.0 M
  cells, without reuse 23.8 ms and 2.0 M, fused 12.3 ms and 1.0 M. Perceus
  reuse already takes map fusion's allocation; the theorem buys the 1.13×
  of one traversal and the uniqueness tests (which D10 removes anyway
  where exclusivity is proved).
- **E10 and upstream.** D42 maps `tabulate` and `foldLast` to tensor and
  linalg semantics; upstream's producer-consumer fusion of an elementwise
  generator into a reduction may already do this loop once it is linalg
  (*conjecture*), which would make E10's rule upstream's.
- **N3, legality.** `concat` (`foldMap id`) calls no user function, so
  right-nesting it is always legal. `concatMap f` must keep the order of
  `f`'s calls: the target `f x ++ concatMap f xs` evaluates `f x` first
  under left-to-right eager evaluation, whereas `foldr` would call `f` on
  the last element first and needs `f`'s row free of `crash`,
  `divergence` and IO (*read* D13; the order under `foldr` is my
  derivation). How many pieces the frontend's calls see is unmeasured; the
  cliff is the measured 395×. On strings the same left fold copies the
  accumulated prefix each time; upstream's `%transform` replaces `concat`
  on `List String` by `fastConcat` (`Prelude/Types.idr:728`), a rule of
  its code generator, not of checked TT; whether our frontend's registry
  hook for `fastConcat` (`Registry/Entry.idr:275-280`) is ever reached
  from a `concat` call I did not check.

## 3. Theorem harvest

*Measured (agent)* (`/tmp/eg-payoffs/theorems/scripts/harvest.py` over
`third_party/Idris2/libs/{prelude,base}`; outputs `harvest3.tsv`,
`classified.tsv`, `shape-counts.tsv`):
- 275 declarations whose type is an equation; 211 usable as rewrite rules,
  all in base, none in prelude: Nat 48, Fin 38, Bool 26, data structures
  89, proof-internal 10. No functor or monad law is proved anywhere. The
  Nat, Fin and Bool ones restate arithmetic the folders already do.
- Every module involved is `%default total`, and none of `length`, `map`,
  `++`, `reverse`, `filter`, `foldl`, `replicate` or `drop` uses
  `assert_total`; legality turns on the user's functions, not the
  library's (Fin's `+` and `*` use `assert_smaller`, `Fin.idr:272,275`).
- Improvements in one direction, with what they need: `appendAssociative`
  (`Data/List.idr:1042`, right-nesting copies `l` once), `lengthMap`
  (`:1078`, deletes n cells and n calls; `f`'s row clean), `mapFusion`
  (`:1117`; reorders calls; 1.13× under reuse), `foldlAppend` (`:1089`),
  `revOnto` (`:1047`), `reverseInvolutive`, `lengthReplicate`,
  `lengthTRIsLength` (`:992`; right to left gives the accumulator, which
  `idr-accumulate` already makes for `+`).
- Their left sides in source: almost none (§2, E6). The valuable use is
  not matching user text but deriving rules: the fold law of N3 follows
  from `appendAssociative` and `appendNilRightNeutral`.
- Easy theorems base lacks: `length (filter p xs) = count p xs` (the
  lexer's `countNLs` is one), `length xs == 0 = isNil xs`, fold-map
  fusion (the commonest real shape), `map` over `filter` as one
  `mapMaybe`, `length (unpack s) = length s`.
- Laws over primitives, declared rather than proved: string `++`
  associativity and unit, `pack (unpack s) = s`, building a string straight
  from a `SnocList` (`fastPack (sx <>> [])`, at `Lexer/Core.idr:184` and
  `Tokenizer.idr:98`).
- Instantiation: a theorem about a function with bodies is matched at
  application sites after specialization, stated pointwise since Idris has
  no function extensionality (`unknowns.md` U26).

## 4. Counting-aware extraction (E7)

- **How often merging would defeat an in-place rebuild.** Rarely, by every
  count: two equal non-nullary constructions on one line occur 30 times in
  the frontend and 31 in the rest of the fork, and of four sampled
  duplicates in one function only one was on one path (the rest in sibling
  arms, which elaboration never merges); an old record named again after
  its update, 22 of 435 updates; in the linear benchmarks, no two equal
  constructions of an in-place value (*measured (agent)*, `census/e7.txt`;
  *read*: `spectral-norm-linear/Main.idr:47` fills `u` and `v` with
  different constants). The nearest real case, `<|>`'s shared input, is
  sharing by backtracking, which extraction cannot undo (§1.4).
- **What extraction with counting would win.** On this code, nearly
  nothing measurable. Its value is the guard: no optimization may turn two
  exclusive values into one shared one, or the in-place promise (D24,
  D70) becomes a copy or a refusal. That guard is representation already
  (`egraph.md` §2.4: every value whose identity a promise reads is
  `Allocate` on `identity`, never hash-consed). The approximate cost of
  `egraph.md` §5 (a `dup` and a `drop` per extra use of a counted class) is
  worth having for sinking and rematerialization decisions; the exact form
  (extract k candidates, run counting on each) is research with no
  measured payoff here, and last in the queue.

## 5. What the e-graph replaces

*Measured (agent)* (`/tmp/eg-payoffs/passes/verdicts.tsv`, every verdict
with its path:line; commands in that directory):
- **Replaced, about 1,744 lines** (4% of the 44,117 lines of C++ in
  `foreign/idr/lib`): `Canon/Sink.cpp` (246), `Canon/CaseOfCase.cpp` (187),
  `Canon/Feeds.cpp` (198, the fold probe at `:75-93`), `Canon/Merge.cpp`
  (119), `Canon/Force.cpp` (146), `Canon/PutList.cpp` (72),
  `Canon/Callees.cpp` (25, a workaround for the driver's worklist), parts
  of `MatchPatterns.cpp`, `MoveOut.cpp`, `Output.cpp` and `Eta.cpp`,
  `FieldOp::canonicalize` (`OpsConReads.cpp:101-150`), three patterns in
  `OpsClosures.cpp` and `OpsTabulate.cpp`, the 10
  `getCanonicalizationPatterns` hooks, the canonicalize and CSE pair inside
  idr-optimize (`Optimize.cpp:64-67`), and `Transforms/Identity` (95, a
  rule "call = argument", an addition to `egraph.md` §6).
- **The runs it replaces**: canonicalize and CSE at `Pipeline.cpp:93-94`
  and `:116-117` on `idr` functions, and one pair per round per node in
  idr-optimize, a count that depends on the program; the pairs at
  `:167-168`, `:181-182` on lowered code stay.
- **Kept, about 8,500 lines**: the 69 folds (an op's meaning, which the
  e-graph calls), SCCP (optimistic), the inliner, the specializer,
  deduplication (a greatest fixpoint), the tail passes (promises: D30,
  D34), the effect derivation. Unrelated, about 10,260: counting and
  after, lowering, test passes.
- **What moves rather than vanishes**: one-use tests, linearity checks and
  tag tests become rule conditions in the specification; ownership
  preferences (`YieldFields` writing k-nucleotide's table in place,
  cd40ab41) become cost; `MoveOut.cpp:56-103` reads effects its own way,
  a second classifier AGENTS.md already forbids, which the one
  classification removes either way.

## 6. Ranked by win × frequency

Win is measured where a number is given, frequency is the census's.
"Research" means not promised until measured on our IR.

| rank | payoff | win | frequency | state |
| --- | --- | --- | --- | --- |
| 1 | E8 + E9: specialized towers folded (closures, `Res`/`Failure`, records) | 4.49× time, 6.4× cells (parser) | every combinator and monadic program; 275 grammar definitions | directional rules after specialization |
| 2 | E2: failure payloads and dead values sunk away | 2.44× time, 3× cells (parser) | every `<|>`, every `Either`/`Maybe` error path | directional, after inlining |
| 3 | N1: static deep embeddings evaluated away | 3.04× time, 2.6× cells (lexer) | every source character the frontend reads | blocked on 0010 |
| 4 | N3: fold law from base's proofs | 45× to 395× on the call | 160 `concat`/`concatMap` lines in frontend and fork; size per call unmeasured | directional rule, ready |
| 5 | N2: First-set dispatch | 1.19-1.45× | every lexer and parser alternation | analysis; dispatch node (U27) |
| 6 | E1: one mechanism, no fights | robustness; 1,744 lines | the pipeline itself | saturation's core |
| 7 | E10: array generators fused | 1.69× on one loop | 1 bench site | research; maybe upstream's |
| 8 | N4 and E4: counts and naturals narrowed | a few instructions per op | frequent in the frontend (conjecture) | analysis |
| 9 | N5: monoid accumulators | frames for binds; snoc loops quadratic to linear | every bind; 69 `++ [x]` | research |
| 10 | E3: index guards | one compare per access | 2 bench sites | analysis |
| 11 | E6 as matching: theorem left sides in source | n cells, n calls per match | almost none | research |
| 12 | E5: string reassociation | two allocations per printed line | cold | saturation |
| 13 | E7 exact | nearly nothing here | about 0 | research |
| 14 | E11 | unknown | none found | research |

## 7. The five strongest payoffs, and the weakest claims of `egraph.md` §9

**The five strongest.**
1. *The combinator tower, specialized and folded* (E8, E9, record
   unboxing): 4.49× and 6.4× fewer cells on a real token stream; the
   e-graph's known-case and case-of-case are what make specialization
   remove `Res`, `Failure` and `Input` instead of copying them.
2. *Failure payloads never built where they die* (E2): a further 2.44×;
   needs only purity of construction (C3) and the alternatives inlined
   into one function.
3. *A static grammar partially evaluated* (N1): 3.04× and 12.7 M cells on
   the lexer; the largest single step, blocked on the grammar being a
   compile-time value.
4. *Quadratic to linear by a proved fold law* (N3): 45-395×, from two of
   base's theorems, legal with no condition for `concat`.
5. *First-set dispatch* (N2): 1.19-1.45×, and by `unknowns.md` U27 also
   what keeps alternation from exploding inside the e-graph.

**The weakest claims of §9.**
- **E5** (`egraph.md:958-965`): string reassociation finds no hot site in
  any program here; the reassociation that matters is the list fold law
  (N3), which is a theorem, not C4's declared associativity of strings.
- **E6** (`:966-974`): "deletes n cells and n calls" is true per match, but
  the left sides almost never occur in source, map fusion's allocation win
  is already reuse's (1.13× left), and "legal only when every label of `f`
  is `total`" is the wrong condition, since total code can crash
  (`unknowns.md` U1): the condition is the derived row.
- **E7** (`:975-979`): "with counting in the cost, extraction keeps them
  apart there" describes a situation the census barely finds; the
  protective half is §2.4's representation, the exact half research
  without a measured payoff.
- **E4** (`:952-957`): framed as algebra on `Integer`, but `Integer` is in
  one benchmark and wrapping `Int` everywhere else; the real form is
  narrowing naturals and counts, worth instructions, not allocations,
  because small integers are unboxed words.
- **E10 and E11** (`:991-1004`): one site and none; E10's rule may be
  upstream's linalg fusion once D42 lowers the generators.
- And one claim §9 does not make but this file must: the largest wins on
  the killer case are not equality saturation proper. Saturation (many
  forms, extraction by cost) is needed for E1, E7, E9's global choice and
  reassociation; the measured factors come from directional rewrites
  after specialization and from representation. D85's full form is
  justified by E1 and by the choices that have two good directions, and
  its yield on parsers depends on the library's representation, as
  `unknowns.md` U28 found for the buffer's reads.

## 8. Reproduction

Scripts in `/tmp/eg-payoffs/` (outside the repository):
- `rt/build.sh`: the runtime from `runtime/` with the host clang
  (`libidris_rt.a`); `lexer/stubs.cpp` stands in for the entry and the
  processor test, which no experiment reaches.
- `lexer/lex.cpp`: `./lex <v0|v1|v1d|v2|v3|v4|v5|v6|h> lexcount/frontend-files.txt 6 [x]`
  (with `x`, token counts per kind).
- `lexer/parse.cpp`: `./parse <p0|p1|p2|p3|h> lexcount/frontend-files.txt 6`.
- Build: `clang++ -std=c++20 -O2 -mcpu=apple-m1 -fno-exceptions -fno-rtti
  -Iruntime -Ibuild/typecheck/foreign/idr/include/idr/IR <file> lexer/stubs.cpp
  rt/libidris_rt.a .toolchain/sysroot/usr/lib/libgmp.a`.
- `lexer/runs.txt`: the three runs behind §1.2 and §1.3.
- `demos/fold.cpp` (N3, E6 under reuse), `demos/tab.cpp` (E10).
- `lexcount/LexCount.idr`, `ParseTime.idr`, `laws/Laws.idr`, `Laws2.idr`:
  stock Idris on Chez with `IDRIS2_PACKAGE_PATH=build/idris2-host/idris2-0.8.0`,
  `-p idris-compiler -p contrib`, the Chez of `.toolchain/chez/bin` on the
  path.
- `census/`, `theorems/`, `passes/`, `prior-art/`: the subagents' scripts,
  raw output and notes.
