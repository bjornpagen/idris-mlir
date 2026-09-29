# Second outside review: serious prototype, and where QTT stands

The reviewer's verdict: this is not novice work. It reads like a serious
research prototype, whose design choices are the ones people who have
built compilers make. It is not yet a serious compiler, for different
reasons.

## Why it reads as serious

- **Invariants are machine-checked, not trusted.**
  - After idr-rc, the verifier checks "every reference consumed exactly
    once on every path" after every later pass.
  - Quantities live in types, so no pass can drop them.
- **Tests assert named properties, not output shapes:** counts-nothing,
  no-heap-allocation, reuses-in-place, every-cycle-has-breaker.
- **Everything that could run forever has a budget,** and hitting it is a
  named error: simplify rounds, the clone limit, and the eval
  tick/memory/stack meter.
- **Compile-time evaluation runs the program's own lowered code** in a
  sandboxed child, not a second interpreter that drifts.
- **Known-good orders:** Lean, Koka, MLton and Perceus (MLton's inline rule;
  Lean's reset/reuse → borrow → count), with the README saying what is
  added on top.
- **Hygiene:** statistics and remarks, action tracing, dumps, PINS.md with
  retire conditions, a pinned toolchain and an unmodified Idris.

## Why it is not there yet

- **Scaffolding vs compiler.** About 15k lines of C++, 5k of Idris and 1.3k
  of runtime, carrying the process of a much bigger project: a style
  profile, a mid-flight migration to C++ modules, a quirk registry, lint
  gates.
- **The headline feature doesn't exist.** The reason for the project is
  static in-place reuse. What exists is Lean's runtime-checked reuse:
  `idr.reset` tests count == 1 at runtime, and `ResetReuse.cc`'s header says
  the untested form is planned, not built.
- **Narrow target and coverage.**
  - One triple (x86_64-unknown-linux-musl).
  - The language is at v3, a subset of Prelude programs.
  - Only the classic micro benchmarks exist, no real programs.
- **Bugs that experience catches:**
  - the unchecked header packing (tag in 16 bits, objs in 8);
  - the stale `quantities` attribute that nothing validates.

  See review-external.md.
- **It reads agent-written.**
  - The prose is uniform across 15k lines; AGENTS.md is the real spec.
  - The practical problem: the owner couldn't read their own test. The
    code has to be steerable by a human who catches this class of bug,
    because the agents don't catch them all.

To look unambiguously serious:
- ship the static reuse guarantee, with a rejecting error;
- benchmark against real Idris/Chez, Lean and OCaml on non-toy programs;
- add a fuzzer or differential testing against the upstream Idris backend;
- assert every bit-packing and layout limit.

## Where QTT stands

**Today:** q0 (erasure) is fully done, since `!idr.erased` has no runtime
representation. q1 is carried and preserved: `!idr.lin<T>`, `lin.enter` and
`lin.use` survive every pass, and `quantities-kept` checks that. But it is
barely used. Its only consumers are in idr-rc: `Borrow.cc` keeps q1 params
owned, and counting treats a linear value as a move. That keeps counting
correct; it removes no work.

**Why linearity isn't uniqueness:** q1 is the callee's promise to use the
binder once. It says nothing about the argument, and Idris lets a shared
value fill a q1 binder (the `lin.enter` doc in IdrOps.td says so). So
`f : (1 xs : List Int) -> List Int` cannot rebuild xs in place from its type
alone. Uniqueness needs the caller half: every call site passes something
fresh or unique. That is a whole-program call-graph fact, and nobody has
built it.

**Real Idris code is barely linear.** The Prelude is almost all
unrestricted: map, foldr and list code carry no q1. Linearity shows up in
the IO world and in Control.Linear and the linear array libraries. The big
payoff is mutable buffers (arrays, strings, records updated in a loop).
Small list cells already get most of the benefit from Lean-style
runtime-checked reuse.

## What "the dream" takes, in order

1. **Uniqueness inference.** A call-graph fixpoint like Borrow.cc: a q1
   param is unique if every call site passes a fresh cell, a reused cell or
   another unique value. Put it on the param type.
2. **Untested reset.** For unique scrutinees, `idr.reset` becomes
   unconditional reuse: no runtime check, no branch, no dec.
3. **The rejecting error.** If a value is q1 and matched and rebuilt at the
   same size, but some caller shares it, fail compilation with a named rule.
   The README promises this; Lean and Koka fall back silently.
4. **No reference counting for values unique for their whole lifetime.** No
   inc or dec, possibly no count word, freed at last use.
5. **Linear mutable arrays and strings** in the runtime and the dialect, so
   linear updates become stores. This is where the performance is.
6. **Linear libraries compile** through the supported subset, so 1–5 have
   something to chew on.

Steps 1–2 are cheap, because the machinery exists (quantities in types,
the call-graph fixpoint, the owned-stage verifier). Step 3 is mostly a
diagnostic. Step 5 is the real work: runtime types, ops and verifier rules.
Step 1 comes next: until it exists, the compiler cannot claim to exploit
linearity at all.
