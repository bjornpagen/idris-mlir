# idris-mlir

An experimental whole-program compiler from unmodified Idris 2 programs over
the stock Prelude and base to native code through MLIR. The goal is high-level code
with guaranteed costs. Where the types promise something (in-place reuse of
linear values, no bounds check), the compiler either
delivers it or rejects the program with a named rule. It is not a Rust
replacement for explicit layout and control, and not merely a faster Idris
backend.

```text
Idris frontend (pinned) → checked TT → Core (Idris: types, monomorphisation, representations)
  → idr dialect (C++) → the simplify loop: inline, specialize, evaluate at compile time
    by running the program's own code in a JIT, to a fixpoint
  → defunctionalize, reference counting, loops → idr-lower → LLVM O3 with the runtime
  → object → linked as the target entry says (static PIE on musl today)
```

Targets: x86_64 Linux (musl, static PIE) today; arm64 macOS is the next
first-class target, and the code is written for both (AGENTS.md). What a
target is lives in one place, its entry in CMakeLists.txt, whose comment
lists every fact an entry gives.

Idris does types; MLIR does programs. Idris checks the program,
monomorphises it and decides each value's representation; everything else
(inlining, specialization, compile-time evaluation, defunctionalization,
reference counting and loops) happens in MLIR. Compile-time
evaluation is runtime evaluation run early: every closed call of pure code
is evaluated by running the program's own lowered code with its own
runtime. As in Idris's own evaluator, totality does not decide what is
evaluated: total code runs to the end, and partial code runs within a
budget, past which the call is left to run at runtime.

## Why not Lean 4

Lean 4 is dependently typed, compiles through precise reference counting
with borrowing and in-place reuse, and ships a production compiler. Our
memory plan ports its passes. What Lean
cannot promise is *when* reuse happens. It tests the count at runtime, so one
extra reference anywhere silently turns an in-place update into a copy.
Koka's fully in-place functions check a function's body statically, but
still decide at runtime whether a call's argument is shared (FP², ICFP 2023).
Idris 2's quantitative type theory states linearity in the types, and this
compiler sees the whole program, so it can prove both halves: the callee
uses the value once, and every caller passes an unshared one. The plan is
to promise the result. A quantity-1 value that is matched and rebuilt at
the same size will be updated in place with no runtime test, or the program
will not compile, with a named reason. The promise will be
carried as ownership types in the `idr` MLIR dialect, and MLIR's verifier
will check it again after every pass instead of trusting the frontend.
Today the counting underneath is in place (below); the static promise is not.
That promise, more than dependent types alone, is why this compiler exists.

## What compiles today

Idris 2 programs over the stock Prelude and base, with `main : IO ()`,
imported explicitly (`--no-prelude` plus `import Prelude`): interfaces
resolved at compile time, `Integer`, `Nat`, `Double`, strings, lists,
`Data.Vect`, base's `IOArray` and `Buffer`, and `System.File` on the
standard streams. Linear arrays and lists come from the compiler's own
`libs/mlir-linear`, plain Idris the stock backend runs unchanged. Values
that remain after the pipeline live in counted cells: `idr-rc` reuses the
cell of a value that dies, borrows what a function only reads, and the
verifier checks after every pass that every reference is consumed exactly
once; cells that never leave their frame are on the stack. A call in tail
position that goes round a cycle of calls is a guaranteed tail call, so a
loop through such calls (a mutual recursion, an IO loop through its binds)
runs in constant stack, as on Chez. With
`IDRIS_RT_LIVE=1` a program reports how many cells are live when it ends:
none. What the compiler cannot compile it rejects with a named rule
(`unsupported (<rule>)`), never miscompiles. The measurements are in
[bench/](bench/README.md).

```sh
idris-mlir --no-prelude --cg mlir -o prog Main.idr
make compile SRC=Main.idr OUT=prog
```

## Setup

Prerequisites: Git, Make, a host C/C++ compiler, python3 and m4 (to build
LLVM and GMP), the Linux UAPI headers and coreutils' `timeout`. Chez Scheme
does not come from the host: `make bootstrap` builds the pinned release,
which Idris 2 and the tests' oracle run on, the same on every host. On
Ubuntu 24.04:

```sh
sudo apt-get install -y git make gcc g++ python3 m4 curl linux-libc-dev
```

The scripts run on macOS's BSD userland too (`tools/host.sh` holds every
difference). There the Command Line Tools give the compiler, the SDK,
Make, Git, python3, m4, curl and perl (whose clock times what `date`
cannot), and Homebrew the rest: coreutils for `gtimeout`, and MLton for
the benchmarks:

```sh
xcode-select --install
brew install coreutils mlton
```

`make bootstrap` builds the pinned CMake, Ninja, a two-stage LLVM/MLIR
(static on musl and libc++, with LTO), musl, GMP, Chez Scheme and Idris 2
into `.toolchain/`; the steps and their environment are at the top of
`tools/bootstrap.sh`. Stage 1 and stage 2 take hours and tens of GB of disk.
Distribution LLVM packages track release branches, not the pinned commit, so
they are not used.

```sh
git submodule update --init
make doctor                  # what the host has, and what is built
make check                   # the repository: pins, commands, source rules; no build
make bootstrap               # slow: the pinned LLVM/MLIR, musl, GMP, Chez, Idris
make build                   # the C++ dev preset and the compiler
make test                    # compiler, profile, e2e (incl. the Chez diff and the dumps' properties), bench
make test-idr                # the idr dialect, with FileCheck
make test-mlir-tools         # the upstream bugs in upstream/ still reproduce
make bench                   # bench/run.sh
```

Everything is installed under `.toolchain/`; `make` alone lists the commands.

## Where a primitive's meaning comes from

The runtime is the one meaning of every primitive; constant folding and
compile-time evaluation call it too. That meaning comes from Idris's own
definition first, then the standard the primitive implements (Unicode,
IEEE 754, POSIX), then a decision of ours written down in
`findings/decision-primitive-semantics.md`. The stock Chez backend is the
test oracle, not the specification: every deliberate difference from it is
a named class in `tests/lib/chez-divergences`.

## Layout

- `compiler/`: the Idris side: frontend, Core, `Emit`.
- `foreign/idr/`: the `idr` dialect, its passes, the JIT and the tools.
- `runtime/`: the runtime every program links, and that folding and
  compile-time evaluation call.
- `libs/`: the Idris packages this compiler ships (`mlir-linear`: linear
  arrays and lists), installed per checkout under `build/idris2`.
- `tests/`: golden tests (`tests/Main.idr`, `tests/README.md`); `bench/`:
  benchmarks against C, Chez, MLton, Koka and Lean 4.
- `findings/`: decisions taken (`decision-*.md`) and research notes with
  staged plans; `findings/one-representation.md` is the cleanup plan for
  everything the compiler still represents twice.
- `tools/`: the toolchain's bootstrap and the compile chain;
  `tools/bisect.sh SOURCE TAG` finds the action of TAG (an evaluation, a
  clone) after which a program behaves differently than with `--no-eval`.
- `upstream/`: upstream bugs we work around, written to be filed.
- `PINS.md`: every pinned workaround and deviation.
- `sources/`: vendored papers, upstream docs and source snapshots.

## License

[0BSD](LICENSE). The Idris 2 dependency keeps its
[upstream license](third_party/Idris2/LICENSE).
