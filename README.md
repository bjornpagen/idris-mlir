<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# idris-mlir

*Sub-zero cost abstractions: what you prove, you don't pay for.*

A whole-program compiler from Idris 2 to native code through MLIR. It reads
the program Idris 2 has checked, keeps what the types proved
(multiplicities, erasure, indices, totality), and compiles it through an
MLIR dialect whose types carry those facts to every pass. A fact the types
prove is never tested when the program runs, and an abstraction that
carries one compiles to code a hand-written version, lacking the fact,
cannot match.

## Status (2026-10-24)

`main` is partway through the MLIR-native cutover
([proposals/0000-mlir-native.md](proposals/0000-mlir-native.md)), which
rewrites the dialect, its passes and the runtime. Read this section before
anything below: the rest of this file describes the code as written, not
code that has run.

- **The Idris side** (the frontend, the type checker, the dialect's
  specification) builds with the pinned stock Idris 2, and the frontend
  runs over the test programs, writing their modules.
- **The C++ side** (the dialect, the passes, the runtime) has not been
  built at the current LLVM pin since the cutover began; changes to it are
  checked only against an older toolchain. So no program compiled by the
  current tree has run, and no module the frontend writes has been through
  the passes.
- **Self-hosting:** the frontend writes the modules of three of its own
  programs (knowngen, syntax-samples, specgen); the test runner stops at
  one refusal. The frontend compiling itself has not finished within a
  two-hour CPU limit, almost all of it in the growth check below; that is
  being optimized now.
- **Linux:** no Linux target has built anything yet.
- **Benchmarks:** no numbers are published until they are measured again
  on the current tree.

## What the types buy

A cost an abstraction usually carries is removed by the fact its type
states, and the fact is kept in the IR so that no pass can lose it:

| The type says | So the compiled code |
|---|---|
| quantity 0 (erased) | has no value for it: no parameter, field or argument |
| quantity 1 (`!idr.graded<once, …>`) | consumes it exactly once; the verifier checks this after every pass |
| a value is held `unique` | updates it in place with no count read and no test |
| an index fixes the shape (`Vect n`, `Fin n`) | has no bounds check and no tag where the index decides the constructor |
| a function is `total` | carries no divergence effect, so LLVM is told it makes progress |
| a function's effect row has no crash and no divergence | may delete or move the call when its result is unused |
| a closure's possible targets are known | calls them directly: closures are compiled away (defunctionalization) |

A value's grade is `!idr.graded<uses, hold, T>`: `uses` is `once` or
`many`, and, for a type that holds references, `hold` says who frees it
(`static`, `counted` or `scoped`) and what is known of its sharing
(nothing, `unique self` or `unique deep`). A data type is the inductive
family Idris checked, applied to its indices (`!idr.data<#Vect[n]>`): a
match refines the index, and a case whose equation is false does not
exist. A lifetime is an SSA value, opened by `idr.lifetime`, so MLIR's
scoping and dominance check that nothing outlives it.

## What a program means

- **A strict subset of Idris 2, never a contradiction.** The compiler may
  refuse a program upstream accepts. A program it accepts means what
  upstream's language says, and every flag, pragma and default (`partial`,
  `covering`, `total`, `%default`, `--total`) means what it means upstream.
- **Eager evaluation.** Arguments are evaluated before the call, so an
  unused computation still runs, and its crash or endless loop still
  happens. Only the derived effect row licenses deleting a call.
- **Refusal, never a silent miscompile.** A program the compiler cannot
  compile is refused with an `unsupported` error naming the rule and the
  site. Acceptance is a property of the program, decided by total analyses,
  never by how far an optimizer got.
- **Monomorphic by construction.** Every construct whose runtime choices
  (types, instances, implementations, shapes) form a set the whole program
  fixes is compiled to the code a monomorphic program would be, through
  specialization, closed sums and defunctionalization. A megamorphic
  construct, such as a recursion that builds its type deeper at each call,
  is refused; nothing is compiled to a uniform boxed form. The growth check
  decides this before translation.
- **Memory is counted, never collected.** References are counted in the
  style of Lean 4 and Koka: borrowed where a function only reads, reused
  where a value dies, on the stack where it never leaves its frame. A
  reference cycle, which counting could never free, is refused
  (`idr-knots`). Every program is frame-limited: at each allocation, each
  cell is either still reachable or held by an active call, which holds at
  most a bound the compiler computes from types.
- **Proper tail calls.** A call in tail position never grows the stack,
  whether or not it is on a cycle, and a self call that returns inside a
  cell built for it is a loop with a destination (tail recursion modulo
  context). Recursion that is not a tail call keeps its depth on typed
  frame stacks, so the native stack holds only the acyclic call depth,
  sized when the program is built.
- **Every ending has its own status,** from one table: 0 returned, `n` for
  `exit n`, 1 crashed, 111 out of memory, 126 cannot run on this machine,
  and `SIGABRT` for an internal error. A message goes to standard error as
  `<program>: fatal: <cause>`.

`%foreign`, a C ABI, threads and finalizers are outside the language, and
are refused by name. The one foreign world planned is Rust
([proposals/0020-rust-interop.md](proposals/0020-rust-interop.md)).

## How it is built

Idris does types; MLIR does programs.

- **The frontend** (`compiler/src`, in Idris) reads checked Idris TT and
  its definitions through our type checker (`compiler/checker`, Idris's
  checker copied into this tree with its attribution). It checks what the
  compiler accepts, monomorphises, decides representations, and writes the
  `idr` dialect as MLIR bytecode.
- **The dialect's specification** (`compiler/spec`, in Idris) is the one
  source of the `idr` dialect: its ops, types, attributes, effects, rules
  and tables, with their invariants proved by Idris's types. Every `.td`
  file of ours is generated from it and committed, with a manifest of
  fingerprints that `make check` regenerates and compares. So are the
  frontend's op builders and the runtime's tables.
- **The passes** (`foreign/idr`, in C++) are an in-tree MLIR dialect in
  upstream's layout, on MLIR's own pass manager, with function passes run
  in parallel. Simplification is a narrow e-graph whose rules come from the
  specification; no greedy rewriting driver or canonicalization runs on
  our ops. Control flow is regions (a match is a region per case, a local
  continuation is a join point) until upstream's `convert-scf-to-cf` at the
  lowering.

The pipeline, from the frontend's module to LLVM (the specification's
`Pipeline.idr` is the order):

```text
defunctionalize    every closure a constructor, every force a call
knots              reference cycles refused
in-place           the library's in-place promises decided
deduplicate, contify
optimize           each function once, after its callees: specialize,
                   inline, simplify with the e-graph
inline, contify    on the final call graph
columns            a tensor of records becomes its columns
structure-loops    pure word ops to linalg
unique-results, bufferize
accumulate, rc-cells, specialize
lifetimes          every lifetime decided before counting
rc-borrows, rc-place, rc-exclusive, rc-reuse, rc-expand
trmc, frames, tail-loops
narrow             big integers proved small become words
ordered-loops, lower
                   then upstream's vector, linalg, affine, scf-to-cf and
                   to-LLVM conversions; musttail at the end
LLVM               optimized, linked statically with the runtime
```

`runtime/` (C++) is the one meaning of every primitive the runtime
implements (strings, big integers, IO, buffers), and folds at compile time
call the same code.

## Two hosts

Our Idris (the frontend, the checker, the specification, the test runner)
compiles under stock Idris 2 on Chez Scheme, which is how the toolchain
bootstraps, and under idris-mlir itself, which is self-hosting. Both hosts
compile it, so all of it is written in the strict subset. The libraries
in `libs/` are plain Idris that both hosts run; idris-mlir may replace a
definition's body with its own op, and the body stays the meaning.

## What compiles

Idris 2 programs over the stock Prelude and base, with `main : IO ()`:
interfaces resolved at compile time; `Integer`, `Nat`, `Double`, strings,
lists and `Data.Vect`; base's `IOArray` and `Buffer`; files, directories,
the standard streams, the environment, arguments, `System.Clock` and
`exitWith`.

The compiler ships its own packages in `libs/`:
- `mlir-array`: shaped arrays, linear arrays, a growable vector, linear
  byte buffers and a linear parser;
- `mlir-linear`: linear lists, naturals and a string iterator;
- `mlir-relational`: relations as tries over a finite universe, with joins
  and fixpoints;
- `mlir-hash`: XXH3.

```sh
make compile SRC=Main.idr OUT=prog
```

`bench/` holds benchmark programs, each in Idris beside the same program
in C, run against clang `-O2` and against stock Idris on Chez
([bench/README.md](bench/README.md)).

## Building

Four first-class targets, built by one recipe: arm64 macOS, arm64 Linux
at 16 KiB and at 4 KiB pages, and x86_64 Linux. Each links the system's C
library (libSystem, glibc) and nothing else shared. `make bootstrap`
builds every pinned tool into `.toolchain/`: CMake, Ninja, a two-stage
LLVM and MLIR with assertions on, GMP, Chez Scheme and Idris 2, with the
patches in `upstream/` applied. Nothing comes from the host but its C
library, a C++ compiler and a few build tools, and nothing global is
modified. The full LLVM build takes hours; `make typecheck` builds only
TableGen and checks that every unit compiles, in minutes.

On Fedora 44, x86_64 or aarch64:

```sh
sudo dnf install -y git make gcc gcc-c++ python3 m4 curl glibc-devel kernel-headers ccache
```

On arm64 macOS, with the Command Line Tools and MacPorts:

```sh
xcode-select --install
sudo port install coreutils ccache
```

Then:

```sh
git submodule update --init
make doctor            # what the host has, and what is built
make check             # the repository's rules and generated files, no build
make bootstrap         # the pinned toolchain; slow
make typecheck         # every unit compiles, without the full LLVM
make build             # the compiler, dev preset
make test              # compiled and refused programs, scripts
make test-idr          # the idr dialect, with FileCheck and idr-expect
make test-unit         # the C++ unit tests
make test-mlir-tools   # each upstream bug we carry a patch for
make bench             # the benchmarks
make self              # the compiler compiling itself
```

The C++ builds through `CMakePresets.json` (`dev`, `release` with full
LTO, `lint`, `typecheck`); `make build PRESET=<name>` picks one. Each
target compiles programs for the CPU its entry in `CMakeLists.txt` names,
and a program refuses to start on a processor without that CPU's
features. There is no cross-compilation: each target builds on its own
machine, or a VM of it.

## Layout

- `compiler/src/`: the frontend and `Emit`, in Idris.
- `compiler/checker/`: our type checker.
- `compiler/spec/`: the `idr` dialect's specification and its generator.
- `foreign/idr/`: the dialect, its passes and the tools, in MLIR's
  `include/` and `lib/` layout.
- `runtime/`: the runtime every program links.
- `libs/`: the Idris packages this compiler ships.
- `tests/`: the golden tests, one directory each; `harness/` runs them
  (`harness/README.md`).
- `bench/`: the benchmark programs.
- `proposals/`: the designs, numbered in the order the work is done, and
  the decisions taken on them.
- `audits/`: the audits the cutover was planned from.
- `upstream/`: the upstream bugs we carry patches for, each with its
  reproducer and test.
- `PINS.md`: every pin, deviation and workaround.
- `sources/`: papers, upstream docs and source snapshots.
- `tools/`: the bootstrap and the compile chain.
- `AGENTS.md`: the rules every change is held to.

## Where it is going

The order is [proposals/](proposals/README.md)'s: the cutover first, then
self-hosting (`make self`, stage 2 equal to stage 3, on the four targets),
then the rest of the queue, among them a sharded whole-program compiler,
a typed array language in the APL tradition compiled through MLIR's tensor
and linalg stack, and Rust interop.

## License

[0BSD](LICENSE). The Idris 2 dependency keeps its
[upstream license](third_party/Idris2/LICENSE).
