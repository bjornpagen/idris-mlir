# Proposal 0014: Rust as the one foreign world

**Status:** proposed 2026-10-04 at 6fda6d8; parked 2026-10-12, in the
queue the owner approved on 2026-10-14 (`proposals/README.md`);
reconciled the same day with 0004's pipeline cutover and decided
throughout: there is no open question (§16, §17). Nothing here is
built, and nothing here changes the compiler until it is taken up. It
is parked because nothing before the array work needs a foreign world:
the cutover, self-hosting, 0003's purge and sharding's first stages do
not. Waiting with it: 0006's P3 (asynchronous Rust on the reactor),
0011's T8 (solvers reached as Rust crates, 0011 §2.5) and bumbledb's
storage (LMDB through heed, bumbledb 0003 §3). It is taken up when the
first of them starts, and its staged plan (§14) then becomes work.

The tree it would build on (*measured*, 0002 and 0004 §0): the cutover
0002 designed is committed and builds on arm64 macOS, where `make test`
was 415/415 at 7a27fd34, before the opt-in SCC pipeline, and again at
552d682a with it off by default; both runs took the Simplify rounds,
which 0004's cutover deleted together with that pipeline. x86_64 Linux
is NotRun (0002 §3). `make self` has never finished; it waits on the qualification of
0004's cutover and 0005, coded and integrated (c7aa7b62, 5d5f3312,
bfdcac70) but not yet built (proposals/README.md).

Amended 2026-10-14, for 0004's cutover (each item decided in §17):

- No `idr.func` declaration for a shim: 0004 makes an external
  `idr.func` unexpressible (0004 D7), so `idr.rust.call` names its shim
  by symbol, as the runtime's functions are named and never declared in
  the module, and carries its signature, grades included, as an inherent
  property (§9.2).
- Callbacks export nothing: a closure passed to Rust flows through 0004's
  one flow interface into a callback key, and the shim gets the address
  of the key's private dispatch function, so the closed world stays as
  the verifier states it (§7.7).
- No `linkRust`: the shim archive is read and linked by the runtime's
  own reader and link, and so takes the runtime's two cases and its
  namespace group at both of 0007's steps (§9.3).
- No stack placement of foreign cells: `idr.stack` is an inherent
  property of `idr.con` (0004 §4 stage 11), and the shim makes every
  foreign cell (§7.4, §9.1).
- Rules are cases of the one rule enum 0004 D42 declares in the dialect's
  ODS, not hand-written lines of `Rule.idr` (§9.5).
- Keys of a Rust map of Idris values are unexpressible beyond §7.2's
  types, instead of refused as `runtime closure`, a reason 0004 deletes
  from the C++ side (§7.6).
- The trust home is `Bindings`, since `Generated` already names the
  origin of code in no module (§8.1).
- Async Rust is 0006 §10's; §12 keeps only this proposal's half, and
  the `[blocking]` table 0006 §10.4 assumes comes with its P3 (§5).
- A binding is declared with `%extern`, as `mlir-linear`'s primitives
  are, and its registry entry holds the shim's symbol once; no
  `%foreign` label is written, and no `%foreign` is admitted beyond
  base's own (§1, §8.1, §9.2).
- What earlier texts left as later work is decided: no target-only
  binding packages (§6), no in-place thaw (§7.1), overlays in their
  project (§10), `std` built once per target entry (§14).
- Paths were re-read at ccaba89c (2026-10-14), where no file under
  `foreign/`, `compiler/` or `runtime/` has changed since 3de67510
  (0004 §0).

Amended 2026-10-09:

- A binding is a generated runtime primitive, not a `%foreign "rust:"`
  convention: §1, §2, §4, §8.1 and §9.2.
- The LLVM pin is a trunk commit (PINS.md), and rustc keeps its own
  LLVM: §14 R0 and §15.
- One crate graph and one surface per program, from the union of every
  package's manifest; selection and slicing of what is bound; the surface
  is the intersection of both targets' APIs: §5, §6, §9.3, §13 and §14.
  These come from reading hs-bindgen (§15).
- No C, by decision: rule 12 of §2 (numbered 11 then), §3, §9.3 and §15.
- Rust is part of the runtime, statically linked only, and the open
  questions are decided for the minimum: §1, §5, §7.4, §8.3, §9.5, §14
  and §16.
- No Chez oracle (AGENTS.md): the Chez entries,
  `C:` specs, the shared library and the divergence classes are gone, and
  with them the last C ABI path: §1, §2, §4, §6, §7, §8, §9, §13, §14 and
  §15.

The brief: give programs the Rust ecosystem as their way out to the rest
of the world (databases, HTTP, crypto, parsers, cloud APIs), and reach C
only through Rust (`libc`, the `-sys` crates and the safe wrappers already
written over them). Embed one pinned rustc, link statically and accept the
monster we are building, as Zig accepts LLVM. Rust is a library layer. It
never hosts the runtime: no tokio, and no Rust scheduler. Every runtime
concern stays in Idris and in `runtime/`.

Claims are marked. **read**: the path given, at ccaba89c unless another
commit is named. **recalled**: from memory of upstream Rust and its
tools, not in `sources/`; treat it as approximate and check it at R0.
**decision**: what this proposal decides, for the owner to accept or
change. **conjecture**: an estimate. **measured**: a record.

## 1. Lead

The compiler already has the three things a Rust interface needs, and it
built them for its own reasons:

- **Reference counting with exact frees.** Every runtime value is a
  counted cell, freed when its last reference dies, from a worklist
  threaded through the dying cells, so freeing takes constant stack
  (*read*: `runtime/idris_rt.h:218-224`; `runtime/Rc/Freeing.cpp:92-146`).
  A Rust value with a destructor is one more kind of cell whose release
  runs that destructor. Drop order is then deterministic, which is what
  a Rust programmer expects. A tracing collector cannot give it.
- **Ownership as grades in the types.** A grade is a pair in the type,
  `!idr.q<quantity, permission, value>`: the quantity Idris proved (one
  or many) and what the value owns (plain, borrow, own or excl), with
  `!idr.lin`, `!idr.own` and `!idr.excl` as spellings
  (`foreign/idr/include/idr/IR/IdrTypes.td:116-138`; the permissions,
  `IdrBase.td:83-88`). Exclusivity is solved once on MLIR's solver
  (`include/idr/Analysis/Ownership.h:183-194`), and the verifier checks
  grades after every pass. Rust's `&T`, `T` and the uniqueness `&mut T`
  relies on are a borrow, an owned value and an exclusive one. The
  README's central promise (in-place update with no runtime test, or a
  rejection with a named reason) is the same proof obligation a `&mut`
  argument puts on the caller.
- **A runtime linked as bitcode into every program.** `linkRuntime`
  joins the prepared runtime's bitcode to the program's module before
  O3, with `LinkOnlyNeeded` (*read*: `lib/Driver/LinkRuntime.cpp:130-145`,
  called at `lib/Driver/Run.cpp:181-192`). Rust code compiled to bitcode
  by a rustc whose LLVM is not newer than ours joins the same way, by
  the same link (§9.3), so a call into Rust inlines across the language
  boundary, in both directions.

What the compiler lacks is equally specific: a value kind for foreign
objects (the runtime has five kinds, box, thunk, string, bignum and
array, and no finalizer: `idris_rt.h:95-103`), a call op whose callee is
a shim rather than a runtime function named after its op, a toolchain
step for rustc, and a way for library code that is neither the Prelude,
base, `libs/` nor the fork to be trusted (`Registry/Libraries.idr:87-104`:
any other installed package is `Untrusted`, loaded but never reached,
`Frontend/Profile.idr:240-245`).

The design in one paragraph. A project names the crates it uses in
`rust.toml`. A generator, `idris-mlir-bind`, reads each crate's public API
from rustdoc's JSON and writes two things from one description: an Idris
package of bindings, and a Rust crate of shims. Each binding is a
runtime primitive: an Idris declaration in the generated package, plus a
registry entry the generator writes from the same description, which
recognizes the definition by its name and origin. The declaration is
an `%extern`, as `mlir-linear` declares its runtime primitives
(`libs/mlir-linear/Linear/String/Iterator.idr:27-29`, *read*), and the
registry entry holds the shim's symbol, once (*decision*). This
supersedes a `%foreign` declaration whose spec only labelled the Rust
path: nothing read it, so it was an unread second copy of the entry's
target, and it kept a class of accepted `%foreign` definitions, which
AGENTS.md rules out; Idris needs no spec on a primitive, as `%extern`
shows. This compiler lowers the primitive to a call of a
runtime-ABI shim, compiled by the pinned rustc to bitcode and joined to
the program before O3 by the runtime's own link (§9.3). Rust values live
in counted foreign cells. Ownership maps onto the existing grades:

- `&T` is a view, a borrow;
- `T` by value is a consumed owned reference;
- `&mut T` is a quantity-1 thread of a mutable handle, in the style of
  `LArray`'s `read` and `write` (`libs/mlir-array/Array/Core.idr`);
- a value frozen into `Shared` gets a read-only API, and a borrow taken
  from it holds a counted reference to it, so the count is the borrow
  checker.

What the type system cannot see is checked at runtime with a crash that
names it (aliased arguments, a re-entrant callback, an abandoned mutable
borrow), as an index out of bounds crashes today. The compiler deletes
each check it proves redundant.

**Rust is part of the runtime, not a bridge to it** (**decision**). A
program's Rust is compiled to bitcode by the pinned rustc and joined to
the program before O3 through the runtime's reader and link, as one more
part of the runtime (§9.3). There is one static image: one allocator
(the runtime's), one crash path (a panic is a crash), one optimizer
pass over Idris, runtime and Rust code, one partition of the result into
codegen bins (0004 §5.3), and no loader. Rust is only ever linked statically; there is no
dynamic Rust library, no `dlopen`, and no plugin interface, in programs
or in tests. The design is the
minimum that makes a call into statically linked Rust as cheap and as
checked as a call into the runtime, and every decision below picks the
smaller mechanism.

## 2. The rules this design keeps

Each is from AGENTS.md or a decision the owner took, and each constrains
the design:

1. **The Idris 2 language does not change**, and third_party/Idris2 stays
   unmodified. Idris has no pragma for
   importing a crate, so crates are declared outside Idris source
   (`rust.toml`), and bindings are an ordinary package.
2. **User code has no pragmas and no escape hatches**
   (`checkPragmas` and `checkReachable`,
   `compiler/src/IdrisMLIR/Frontend/Profile.idr:120, 211`): no `%foreign`, no
   `%runElab`, no `believe_me`. Bindings must therefore be *trusted
   library* code, and user code calls them as ordinary functions.
   Elaborator reflection in user code is unavailable, which rules out
   generating bindings at elaboration time.
3. **The binding's meaning is its shim's.** Each binding's generated
   registry entry lowers it to a call of its shim; there is no second
   implementation of a binding, in Idris or anywhere else.
4. **No oracle** (AGENTS.md). The tests' committed
   expected files are the specification; nothing is shaped so that
   Idris's Chez backend can run it.
5. **One thing, one representation.** A crate's interface is described
   once. The Idris bindings, the shims and the compiler's lowering are
   derived from it, and the compiler reads nothing but the Idris types of
   the bindings.
6. **Facts Idris proved live in types**, never in discardable attributes
   (`!idr.lin`, `!idr.excl`). Ownership modes at a Rust call are grades on
   the parameter types of the call's inherent signature (§9.2).
7. **Reject what cannot be compiled, with a named rule; never miscompile.**
   A rule is a case of the one rule enum (0004 D42).
8. **The heap stays acyclic**: a type that could knot it is rejected, as
   `unsupported (cycle)` (`foreign/idr/lib/IR/Verify/Knots.cpp`). A Rust
   container that holds Idris values and can be mutated is a mutable-cell
   edge of the type reachability graph.
9. **No option, toggle or mode** (0004 D2). Every residual check is one
   behaviour, which the compiler removes where it proves it (§8.3), and
   the shims are one build.
10. **Two first-class targets**, x86_64 Linux (musl, static PIE) and arm64
    macOS, decided in one place, the target entry in CMakeLists.txt.
11. **No primitive has an implementation in Idris.** A shim is the one
    meaning of its Rust call at runtime. No Rust call runs at compile
    time (§11).
12. **No C** (**decision**, 2026-10-09). Rust is the one foreign world.
    Nothing here reads a C header, binds a C function, or lets a program
    or a library declare or call a C symbol, and nothing is planned to:
    no C convention, no C FFI, no header import. A program that needs a C
    library uses a Rust `-sys` crate and, preferably, the safe Rust crate
    over it, bound like any other crate. C code exists only inside such
    crates, as their own build compiles it (§9.3). The `extern "C"` of
    the shims is the runtime's word-passing calling convention between
    our own compiled code and our own generated Rust (§9.2), not a way to
    reach C.

## 3. Scope

**In:**

- synchronous Rust APIs: free functions, inherent methods, trait methods
  of the traits in §7.5, constructors, and the destructor;
- C libraries, only as Rust crates: a `-sys` crate and the safe crate
  over it, bound as Rust (rule 12); their C sources are built by the
  crate's own build with the pinned clang;
- generic Rust APIs at instances the manifest names, or at Idris element
  types through `IdrisValue` (§7.6);
- Idris closures passed as Rust callbacks that are called before the call
  returns (§7.7).

**Out, by decision:**

- **C, directly, in any form** (rule 12): C headers, C functions, C
  types, a C convention, and an Idris package of C bindings. A C library
  is reached through a Rust crate or not at all.

- **Async Rust executed by a Rust runtime (a tokio "island").** It would
  give a second scheduler and I/O the runtime cannot see.
- **Rust code that calls into Idris from another thread.** The runtime is
  single-threaded and its counts are plain arithmetic
  (`idris_rt.h:27-38`). Under 0006's shards the rule is the same, stated
  there for every foreign thread: it may wake a shard, never touch a
  count, a cell or a world (0006 §3.3).
- **Rust types as Idris values without a handle.** The exception is the
  scalars and strings of §7.2.
- **Dynamic linking of Rust,** in any form: a Rust `cdylib`, `dlopen`,
  plugins. Rust is linked statically into the program, always (§1).

**Later, staged (§14):**

- async Rust polled from 0006's task frames on its reactor, which is
  0006's P3, after its P2 (§12; 0006 §10);
- protocol overlays in Brady's style (§10).

## 4. The pieces

```text
rust.toml ──► idris-mlir-bind ──► rustdoc JSON of each crate (pinned rustdoc)
                    │
                    ▼
              the surface (one description per program, both targets)
               ┌────┴──────────────────────────┐
               ▼                               ▼
   build/rust/idris/  Idris package     build/rust/shims/  Rust crate
   Rust.<Crate>.* modules               one runtime-ABI entry per item
   + generated registry entries
               │                               │
               │                    cargo (pinned, offline, vendored)
               │                               │
               ▼                               ▼
   idris-mlir frontend               libidrs.a: every member
   (registry: generated)             carries bitcode
               │                               │
               ▼                               ▼
   0004's pipeline ──► idr-lower ──► translate ──► the runtime's link
   (runtime + libidrs.a) ──► O3 ──► bins ──► code generation per bin ──► link
```

The middle row is 0004 §4's pipeline, stages 1 to 16, with nothing of
its own for Rust: defunctionalization, the ready set, `idr-rc` and the
lowering see an `idr.rust.call` as one more op (§9.2), and the runtime
link, the partition and the per-bin code generation see Rust's bitcode
as one more part of the runtime (§9.3).

- **`rust.toml`** is a package's manifest (§5), an application's or a
  library's. It sits beside the package's `.ipkg`, since Idris's ipkg has
  no field for it. A program's build reads the manifests of every package
  it depends on.
- **`idris-mlir-bind`** is the generator (§6). It is a Rust program
  in `foreign/rust/bind/`, built by the pinned cargo, because the
  interface it reads is Rust's and `rustdoc-types` is the reader rustdoc
  publishes (recalled).
- **The surface** is the generator's one intermediate description: per
  program, every bound item with its Idris type, the ownership mode of
  each parameter and result, and the shim symbols. Its outputs (the
  binding package, the registry entries and the shim crate) are printed
  from it and nothing else, so they cannot disagree.
- **`libs/mlir-rust`** is a new in-house package, `Rust.Core`. It is plain
  Idris over base and PrimIO: the handle types (`Rust`, `Shared`),
  `freeze`, the result-handle helpers, and `IdrisValue`. Every binding
  package depends on it.
- **The shim crate** depends on the bound crates and on `idris-rt`, a
  small crate of the runtime's C interface. `idris-rt` is generated from
  `runtime/idris_rt.h` by bindgen on the pinned clang, so the header stays
  the one copy.

## 5. The manifest

```toml
# rust.toml, beside the project's .ipkg
[crates]
regex      = "1.11"
serde_json = "1"
rusqlite   = { version = "0.32", features = ["bundled"] }

# Items are effectful (IO) unless declared pure, per crate or per item.
[pure]
regex      = true
serde_json = true

# Generic Rust types bound at concrete instances, under an Idris name.
[instances]
WordCounts = "std::collections::HashMap<String, i64>"

# What to bind of a crate: path patterns, or "all" for its whole public
# API. Nothing of a crate is bound unless it is selected here. Types the
# selected items mention are bound too (slicing, §6), from whichever
# crate they live in.
[select]
regex      = ["regex::Regex::*"]
serde_json = "all"
rusqlite   = ["rusqlite::Connection::*", "rusqlite::Statement::*"]
```

- **One crate graph per program.** A library package that uses Rust ships
  its `rust.toml`, never generated bindings. A program's build takes the
  union of the manifests of the program and of every package it depends
  on, and resolves one crate graph from it. Every Rust type then has one
  Idris type in the program, and the link holds one shim archive and one
  `std` (§9.3). Two manifests whose requirements on a crate cannot be met
  by one version are rejected, naming both packages; Cargo's own
  duplicate versions of a crate (two semver-incompatible majors in one
  graph) stay distinct Rust types and get distinct Idris types. A
  library's binding modules are generated at the program's build, under
  the program's `build/rust/`, so a library compiles against the surface
  of the program that uses it.
- Cargo resolves the crate graph once, at generation, into `rust.lock` (a
  Cargo.lock), which the application commits. `cargo vendor` then puts
  every source under `build/rust/vendor/`, and every later build is
  offline. Generation is the one step that reaches crates.io.
- **What is bound** is what `[select]` names, plus everything slicing
  pulls in (§6). A crate in `[crates]` that `[select]` does not mention
  contributes only what slicing pulls from it. An item that is selected but cannot be mapped is
  listed in the generator's report with its reason, never silently
  dropped.
- **Blocking items** (*decision*): a `[blocking]` table, per crate or per
  item like `[pure]`, comes with 0006's P3, which offloads each item it
  names to a runtime-owned thread (0006 §10.4). Before P3 there is no
  reactor to offload to, so the table does not exist and every call runs
  on the calling thread, in world order; P3 adds the table and its one
  meaning together.

## 6. The generator

**Input.** `rustdoc --output-format json` (nightly, `-Z
unstable-options`; recalled) of each crate in the graph, run by the
pinned toolchain once per target entry
(`x86_64-unknown-linux-musl`, `aarch64-apple-darwin`): a crate's public
API depends on its `#[cfg]`s, so it is a per-target fact. That JSON
carries:

- public items, signatures with lifetimes and generics, and where-clauses;
- trait impls, including the auto-trait impls rustdoc synthesizes for
  `Send` and `Sync`;
- `const fn`, through the function header's `is_const` (recalled).

Its format version is fixed by the rustc pin, and the generator pins
`rustdoc-types` at the matching version, so a rustc bump that changes the
format fails at the build of the generator, not at runtime.

**What it reads for each item:**

- **receiver and parameters:** by value, `&`, `&mut`, or none;
- **lifetimes:** which result borrows from which parameter (Rust's
  elision rules make this explicit in rustdoc's output);
- **types:** whether each maps by §7;
- **traits:** `Clone`, `Copy`, `Display`, `Debug`, `PartialEq`, `Eq`,
  `PartialOrd`, `Ord`, `Hash`, `Default`, `Iterator`, `Send`;
- **destructor:** whether the type needs drop (`std::mem::needs_drop`,
  evaluated in the shim crate, not guessed).

**Selection and slicing.** The generator starts from the items
`[select]` names, then adds, transitively, every type their signatures
mention (parameters, results, the receiver's type, trait bounds that
§7.5 maps), from whichever crate of the graph defines it, whether or not
the manifest names that crate. A type pulled in this way is bound as an
opaque handle (§7.1) with its §7.5 traits, and its own methods only if
they are selected. So `reqwest::Client::get` brings `RequestBuilder`,
`http::Method` and `url::Url` with it, as handles, without binding all
of `http` and `url`.

**Both targets, one surface.** The surface holds only items that exist,
with the same signature, on every target entry. An item present on one
target only, or with different signatures, is left out and reported with
the reason `rust cfg`, naming the targets. This keeps the program's
meaning the same on both targets. A target-only API is not bound
(*decision*, deciding the earlier "a separate, target-named binding
package, later work"): a binding package per target would be a
per-target case outside the target entry, which AGENTS.md calls a bug.
A program that needs such an API binds a crate that offers one
signature on both targets, as a portable crate does.

**Output, per program:**

- `build/rust/idris/rust-<graph>.ipkg` and `Rust/<Crate>/*.idr`: the
  binding package, compiled and installed per project as `libs/` is per
  checkout;
- `build/rust/shims/`: the shim crate, with `Cargo.toml` and one source
  file per bound crate;
- `build/rust/libidrs.a`: the shim archive cargo builds from it, every
  member carrying its bitcode beside its native code, which the driver
  reads beside the runtime (§9.3);
- `build/rust/report.txt`: every selected item not bound, with its reason;
- `build/rust/surface.digest`: the digest of the surface, which trust
  checks (§8.1);
- `rust.surface`: a readable listing of the surface (each bound item's
  Rust path, Idris type and modes, in path order), which the application
  commits beside `rust.lock`, so that a crate bump or a manifest change
  shows its API change in review. The build regenerates it and fails if
  it differs from the committed one, as a lock file does.

**Determinism.** Items are emitted in path order, symbols are derived from
paths and the graph's digest, and timestamps are never written.
`tests/determinism` covers the generator as it covers the compiler.

**Symbols.** `idrs_<graph8>_<crate>__<path>__<item>` for each item's one
entry. `<graph8>` is eight hex
digits of the surface digest. A program has one surface, so its link has
one set of shim symbols; the digest only keeps a stale archive from
another surface from linking silently. Every name is derived from
content, never from a counter (0004 D18).

**Mangling** (*decision*). The shim crate and its whole graph, `std`
included, build with `-Csymbol-mangling-version=v0`, whose symbols use
only `[_0-9a-zA-Z]` (*recalled*), so every Rust function has a name
without a dot, as the runtime's C identifiers do. 0007 §3.4 puts every
dotless name in one namespace group, the runtime's, so Rust's functions
join that group by the same rule and the partitioner needs none of its
own (0004 §5.3 item 2). Reason: legacy mangling writes `..` inside impl
paths (*recalled*), which would scatter Rust's functions across groups
named by fragments of Rust paths. R0 checks that no function of the
archive has a dot in its name.

## 7. The surface: how Rust types become Idris types

### 7.1 Handles

A Rust value of a non-copied type lives behind a handle. Two handle types
exist, after `libs/mlir-array`'s `LArray` and `Array` (**decision**):

```idris
||| Rust.Core. A Rust value of type t (an [external] phantom naming it),
||| mutable, threaded at quantity 1: every &mut method takes it and gives
||| it back, so the one object is updated in place.
export
data Rust : (t : Type) -> Type where
  MkRust : Foreign t -> Rust t

||| A Rust value frozen: only its &self methods, shared freely. A borrow
||| taken from it holds it, so it lives as long as the borrow.
export
data Shared : (t : Type) -> Type where
  MkShared : Foreign t -> Shared t

||| The linear phase ends.
export
freeze : (1 _ : Rust t) -> Shared t
freeze (MkRust p) = MkShared p
```

- **A type with no `&mut self` method is born `Shared`.** `regex::Regex`
  is an example; the generator never offers `Rust Regex`.
- **`Shared t` to `Rust t` exists only as a clone**, for `t: Clone`
  (`thaw : Shared t -> Rust t`, a Rust `clone`). There is no in-place
  thaw (*decision*, deciding the earlier "later work on a measurement"):
  a Rust `Clone` may have effects the crate observes (an `Rc`'s count),
  so skipping one where the count says nobody else holds the value would
  be a different program, not a faster lowering of the same one (§8.3).
- **A handle is a counted foreign cell** (§9.1), whose last release runs
  the Rust destructor: once, immediately after the last use, in program
  order.

### 7.2 Scalars, strings and bytes, copied or lent without a handle

| Rust | Idris | at a call, on this compiler |
|---|---|---|
| `i8`…`i64`, `u8`…`u64` | `Int8`…`Int64`, `Bits8`…`Bits64` | the word |
| `isize`, `usize` | `Int64`, `Bits64` | the word (both targets are LP64, which `idris_rt.h` asserts) |
| `bool` | `Bool` | the tag |
| `f64` | `Double` | the double |
| `f32` | `Double` | widened on return, rounded to nearest on the way in, as IEEE 754's conversion |
| `char` | `Char` | the scalar (both are Unicode scalar values) |
| `&str` | `String` | **lent, no copy**: `idris_rt_str_bytes` and the byte length. An Idris string is always well-formed UTF-8 (`idris_rt_str_from_bytes` replaces ill-formed input), so the shim's `from_utf8_unchecked` is sound |
| `String` (result) | `String` | copied into a new string (`idris_rt_str_from_utf8`) |
| `&[u8]`, `&mut [u8]` | `Buffer` (base's `Data.Buffer`) | **lent, no copy**: the array's bytes and length |
| `Vec<u8>` (result) | `Buffer` | copied into a new array |
| `()` | `()` | nothing |

`i128` and `u128` map to `Integer` through the runtime's big conversions,
at R3. Raw pointers in a public signature are not bound
(`unsupported (rust pointer)`): a crate that exposes them is unsafe to
call by contract, and its safe wrapper is what gets bound.

### 7.3 Ownership modes

For each parameter and receiver (**decision**):

| Rust | generated Idris parameter | at a call, on this compiler |
|---|---|---|
| `x: T`, `self` (a handle type) | `(1 _ : Rust t)` | consumed: the shim takes the cell's value. An exclusive cell is moved out and freed; a shared one is cloned when `t: Clone`, and otherwise the call crashes with `rust: <T> is shared and cannot be moved` (§8.3) |
| `&T`, `&self` | `Shared t`, or `(1 _ : Rust t)` given back in a `Res` | a view: no count changes |
| `&mut T`, `&mut self` | `(1 _ : Rust t)`, given back | a view whose aliasing is checked (§8.3) |

A `&self` method on a mutable type is generated twice, once on each
handle, as `libs/mlir-array` has `read` on an `LArray` and `(!!)` on an
`Array`:

```idris
||| Rust.Std.WordCounts, generated from HashMap<String, i64>::get.
export
get : (1 _ : Rust WordCountsT) -> String -> Res (Maybe Int64) (const (Rust WordCountsT))

export
iget : Shared WordCountsT -> String -> Maybe Int64

||| From HashMap::insert: &mut self, so the map is given back.
export
insert : (1 _ : Rust WordCountsT) -> String -> Int64 -> Res (Maybe Int64) (const (Rust WordCountsT))
```

**Borrowed results**, where a result's lifetime ties it to a parameter:

- **A copyable result is copied**: `&i64` becomes `Int64`, `&str` becomes
  `String`. This is the default.
- **A handle result is a borrow handle that holds its parent.** For
  example `Shared VecT -> Iter`: the iterator's cell keeps a counted
  reference to the vector's, so the vector outlives it. These methods
  exist **only on `Shared`**. A frozen value has no `&mut` API, so no
  mutation can happen while a shared borrow lives, and no flag is needed:
  the count is the witness.
- **A `&mut` borrow** (`iter_mut`, `get_mut`, `entry`) consumes the
  `Rust t` and returns a handle that gives it back when released:

  ```idris
  export
  iterMut : (1 _ : Rust VecT) -> Rust (IterMutT VecT)

  export
  release : (1 _ : Rust (IterMutT VecT)) -> Rust VecT
  ```

  Quantity 1 does not stop a caller who bound the vector at ω from using
  it while the borrow lives ("A linear binder does not imply unique heap
  ownership", AGENTS.md). So the shim marks the vector mutably borrowed
  until `release`, and any other access through it crashes (§8.3).

### 7.4 Compound values: Option, Result, tuples, enums, structs

- **`Option<T>` → `Maybe T`, `Result<T, E>` → `Either E T`, tuples → pairs,
  for mappable `T` and `E`.** An error type `E` is a `Shared` handle, with
  `Show` from its `Display`.
- **A struct is a handle**, with an accessor shim for each public field
  of a mappable type (`regex::Match` gives `start` and `end`). There is
  no copying of Rust structs into Idris records: after the runtime link
  (§9.3) an accessor inlines to a load, so a copy would buy nothing and
  would be a second path.
- **An enum is a handle with a generated view**:

  ```idris
  ||| From serde_json::Value.
  public export
  data ValueView = Null | Bool Bool | Number (Shared NumberT) | String String
                 | Array (Shared (VecT ValueT)) | Object (Shared (MapT ValueT))

  export
  view : Shared ValueT -> ValueView
  ```

**How compound values cross (decision).** A shim cannot know how
idr-lower lays out `Maybe Int64` in a given program: layouts are decided
per program, whole-program, before the lowering
(`foreign/idr/lib/IR/Layout/`; 0004 §4 stage 12). So the bindings never
move Idris data through a shim.

- **Results:** a compound result is returned as a *result handle* (a Rust
  value of the `Option`, `Result` or tuple), and the binding's plain Idris
  takes it apart through accessor shims (`tag`, `some`, `ok`, `err`, the
  fields) before the handle dies. On this compiler, all of that inlines
  after the runtime link, and the handle's allocation and its free are a
  pair LLVM sees whole, through the allocator's allocation attributes
  (§9.4), so O3 may delete both (*conjecture*, recorded at R2, §13). The
  shim makes every foreign cell, so `idr-stack`, whose placement is a
  property of `idr.con` (0004 §4 stage 11), never places one; this
  supersedes the earlier "`idr-stack` places it in the frame".
- **Arguments:** a compound argument is built as a Rust value first, by a
  builder shim, and passed by value.

This is one path, with the cost removed by the
optimizer, not by a second lowering. Whether O3 removes it changes speed,
never meaning.

### 7.5 Traits

| Rust impl | Idris |
|---|---|
| `Display` | `Show` (through `to_string`) |
| `Debug` | `debug : Shared t -> String` |
| `PartialEq`, `Eq` | `Eq` on `Shared t` |
| `PartialOrd`, `Ord` | `Ord` on `Shared t` |
| `Clone` | `thaw : Shared t -> Rust t`; `clone` on `Rust t`, given back |
| `Default` | `def : Rust t` |
| `Iterator<Item = X>` | `next : (1 _ : Rust it) -> Res (Maybe X) (const (Rust it))`; `toList` |
| `Hash` | used by `IdrisValue` keys (§7.6); no Idris interface |

Idris interfaces are resolved at compile time here (`README.md`, "What
compiles": "interfaces, resolved at compile time"). Each generated
instance is a monomorphic implementation over one handle type, so it
compiles like any other.

### 7.6 Generics

A generic Rust item is monomorphized in the shim crate, so it is bound
only at concrete types. There are two ways to have one (**decision**):

- **Named instances** (`[instances]`), at Rust types:
  `HashMap<String, i64>` becomes `WordCountsT`. The generator writes the
  instance's methods as for any type.
- **`IdrisValue` elements**, for containers of Idris values: `Rust.Core`
  binds `Vec<IdrisValue>`, `VecDeque<IdrisValue>` and
  `BTreeMap<K, IdrisValue>` (for each `K` of §7.2) as `RVec a`,
  `RDeque a` and `RMap k a`, with `a` erased (quantity 0).
  - `IdrisValue` is a word holding a counted reference. Its `Clone` is
    `idris_rt_inc` and its `Drop` is `idris_rt_release_deferred` (§9.1),
    so a drop inside a dying foreign cell joins the runtime's worklist
    instead of recursing.
  - It is `!Send` and `!Sync`: Idris values never leave their thread
    (§3), and rustc enforces that in the shim crate itself. The generator
    rejects an API whose bounds would need it to cross
    (`unsupported (rust send)`) before rustc does.
  - Keyed containers take `K` from §7.2 only, and that is a fact of
    `Rust.Core`'s types, not a refusal (*decision*): `RMap k a` is made
    and used only under an interface `RustKey k`, whose implementations
    `Rust.Core` gives for §7.2's types alone, so an Idris key type has no
    instance and is a type error where it is written. Reason: a key over
    Idris values needs its `Hash` or `Ord` to be an Idris function, known
    only after the frontend's monomorphization, while the shim crate is
    generated from the surface before the program is compiled (§6), so
    the shim would depend on the compilation it feeds. This supersedes
    the earlier refusal as `unsupported (runtime closure)`: the
    implementation is not chosen at run time, so the frontend's
    megamorphic rule does not apply (0004 §2.5), and the C++ side's use of
    that phrase is deleted by 0004 (§6 there).
  - A mutable container of `IdrisValue` is a mutable-cell edge for the
    acyclic-heap check (§2.8). An `RVec Node` whose `Node` can reach the
    same `RVec` is `unsupported (cycle)`, named as that check names it.

### 7.7 Callbacks

A parameter of type `impl Fn(A) -> B`, `impl FnMut`, `&dyn Fn` or a
generic `F: Fn(A) -> B` takes an Idris function `A -> B` (or
`A -> IO B` for an effectful item).

- **The shim side.** The shim crate has one wrapper type per callback
  signature, `IdrisFn<A, B>`. It holds the closure as one counted word
  (an `IdrisValue`, §7.6) and the address of its dispatch function, and
  implements `Fn` by calling that function on the word and the
  arguments.
- **The compiler side** (*decision*, superseding the earlier "the
  compiler exports its apply function under a symbol the binding's
  registry entry names", which would be a public function beside the
  root and break 0004's closed world, D7 there):
  - `idr.rust.call` implements 0004's one flow interface (0004 §2.2,
    D8), declared in its own ODS as every op of ours declares it (0005
    D7): each closure operand has a declared edge into a callback key of
    its own, so the label solve sees every label that reaches Rust, and
    the verifier's rule that a closure-typed operand sits on an op with
    the interface holds (0004 §4 stage 2).
  - Defunctionalization makes the key a sum, as every key (0004 §2.4),
    and for each such key one dispatch function: a case over the key's
    constructors, each arm a direct call, private, named from the key
    (0004 D18), with the runtime's ABI (§9.2). The op then carries the
    sum, boxed (`!idr.box`, so boxing is the value's type, 0004 D29;
    since 0005 D11 every box is fit's, decided once from the type graph,
    so how this sum gets its box is settled with fit when this proposal
    is taken up) so that it crosses as one counted word, and a symbol use of the
    dispatch function, whose address the lowering passes to the shim.
  - The dispatch function is kept by that symbol use, as a label's
    function is kept by the label constructor holding it (0005 D1), and is
    never inlined, since nothing in the module calls it. Its signature is
    the shim's ABI, so the dead-value removal (0004 §4 stage 10) must
    leave it whole: upstream RemoveDeadValues treats a function with a
    non-call symbol use as called from outside (*recalled*), which R3
    checks with a callback whose argument the closure ignores.
  - Its one caller outside the module is Rust, and it passes only
    first-order values: a callback's parameters and result are §7.2 to
    §7.4 types, never closures or suspensions, which the op's verifier
    checks. So no label enters from outside, which is what 0004 §2.4's
    first step is for: once this lands, its "every caller of a non-root
    function is in the module" reads "every caller that can pass a
    closure or a suspension", and the rest of the argument is unchanged.
- **Constraints:**
  - A callback is called only before the Rust call returns. An API that
    stores one (an event handler kept past the call) needs `'static`, and
    it is bound only on a `Shared` handle whose cell then holds the
    closure.
  - The closure's sum is one more field type for the cycle check.
  - Re-entrancy (the callback reaching the same handle) is checked (§8.3).

## 8. Soundness

### 8.1 Trust

Bindings contain `%extern` primitives and `unsafePerformIO`, so they
must be trusted code (§2.2). Trust never follows from a name
(`compiler/src/IdrisMLIR/Registry/Libraries.idr:27-32`). It follows
from where a module's TTC was built (`Home`, `:32`).

**Decision:** a new `Home`, `Bindings`, for the binding package that
`idris-mlir-bind` wrote under the project's `build/rust/idris/`, and a new
`Lib`, `Rust`, its origin: `moduleOrigin Bindings _ = Library Rust`
(`:95-104`). The name is `Bindings`, not the earlier `Generated`, because
`Origin` already has a `Generated`, the origin of code in no module
(`:34-40`), and one name for two things is the drift AGENTS.md forbids.
`Rust`'s row in the table (`:62-72`) is trusted and admitted, and
reports a diagnostic at the user's code that reached it, since no person
wrote the generated source.

- **What makes it trusted:** the package's sources hash to the digest the
  generator recorded in `build/rust/surface.digest`, and the frontend
  checks that digest. A hand edit makes the package `Untrusted`, so its
  definitions can be loaded but not reached, with the reason named
  (`Frontend/Profile.idr:240-245`).
- **Its `%extern` declarations** are reachable only through their
  generated registry entries, which name them by name and origin, as
  the profile admits `mlir-linear`'s (`Frontend/Profile.idr:279-283`).
- **`Rust.Core` (`libs/mlir-rust`)** is `InHouse` like `mlir-linear`. It
  joins the table as a row in `moduleOrigin`, beside
  `moduleOrigin (Installed "mlir-linear") _ = Library InHouse`
  (`Libraries.idr:102`).
- **`Foreign t`, for `Rust` and `InHouse` origins only.** `Rust.Core`
  declares `Foreign : Type -> Type` as a primitive type with a registry
  entry: a reference to a counted foreign cell (§9.1) holding a Rust
  value of type `t`. Its release is the cell kind's own, which runs the
  drop shim; there is no finalizer, and `onCollect` stays refused
  everywhere. User code cannot name `Foreign` (the entry is valid only
  from those origins), so it holds Rust values only through `Rust` and
  `Shared`.

### 8.2 What the types guarantee

- **Liveness.** A Rust value lives while any Idris value refers to its
  cell, and a borrow handle refers to its parent's. So no shim ever sees a
  dangling reference: the count guarantees it.
- **No mutation under a shared borrow.** Borrow handles exist only on
  `Shared`, which has no `&mut` API.
- **Moves.** A by-value parameter is quantity 1 in the binding. On this
  compiler the move reads the operand's grade: an exclusive cell is moved
  out with no test, as `idr.take` does for boxes
  (`include/idr/IR/IdrOwnershipOps.td:137-150`), and a cell that may be
  shared is tested at runtime (§8.3).

### 8.3 What is checked at runtime, and named

Three things escape the types. Each crashes with a message naming it
(**decision**). The two that read only grades, aliasing and moves, are
emitted by `idr.rust.call`'s lowering, which reads its operands' grades
as `idr.take`'s lowering does and writes each test only where the grade
does not decide it; the one that reads the Rust value's state, the slot
flag, is the shim's. This supersedes the earlier "each is checked in the
shim": a test the shim made could only be removed by LLVM after
inlining, where the grade that proves it redundant is gone.

1. **Aliased arguments.** A call with a `&mut` parameter and another
   reference parameter of the same Rust type compares the two operands'
   cells, each of which owns its one `Slot<T>`:
   `rust: Vec::append was given the same Vec twice`.
2. **Re-entrancy and abandoned `&mut` borrows.** Each cell's Rust payload
   is `Slot<T> { state: Cell<u32>, value: T }`, a `RefCell`-like flag.
   - The flag is set during a call that takes Idris callbacks, and while
     a `&mut` borrow handle lives.
   - An access that finds it set crashes:
     `rust: the Vec is mutably borrowed`.
   - Calls without callbacks do not touch the flag: the program is
     single-threaded and no Idris code runs inside them, so nothing can
     re-enter.
3. **Moving out of a shared, non-`Clone` value.** The test is
   `idris_rt_is_unique`: a move out of a cell another reference still
   holds crashes at the move, `rust: the Vec is shared and cannot be
   moved`.

**The compiler removes what it proves.**

- A move whose operand is `!idr.excl` needs no uniqueness test.
- Aliasing of a call's arguments is decided statically when the operands
  are distinct exclusive values: two exclusive values live at one call
  cannot be one cell, since each holds the only reference to what it
  reaches.
- A flag write with no reader in between folds away after inlining.

These are faster lowerings, never different ones. There is one behaviour
and no mode (**decision**; 0004 D2): a check the compiler cannot remove
stays in the program as a runtime check. A flag that turned the
residual checks into rejections would be a second meaning of the same
program. Both are stated in idr-expect's terms: `tests-nothing=@f`
(`foreign/idr/lib/Transforms/Expect/TestsNothing.cpp`) holds of a
function whose takes are of exclusive values, and it reads an
`idr.rust.call`'s by-value and `&mut` operands as it reads takes, so it
holds where neither test is left (§13).

### 8.4 Panics

The shim crate builds with `panic = "abort"` and installs a panic hook at
the first call. The hook calls `idris_rt_crash` with
`rust panic: <message>`. That flushes the program's output, writes
`idris-mlir: rust panic: ...` and exits with `IDRIS_RT_CRASHED`, as every
crash does (`runtime/idris_rt.h:420-431`). No unwinding crosses into
Idris, and none is built: the target entries link no unwinder
(`IDRIS_MLIR_NO_UNWINDER`, `CMakeLists.txt:176`).

A panic is a crash with the panic's message, as an index out of bounds
is.

### 8.5 Threads

The runtime is single-threaded: counts are plain arithmetic, and the
live-cell count is per thread (`idris_rt.h:27-38, 242-246`). Rust code may
start threads of its own (rayon, a connection pool's reaper), and they
may allocate, since the allocator frees a block from any thread
(`idris_rt.h:182-195`; §9.4). But nothing Idris reaches them:

- `IdrisValue` and `IdrisFn` are `!Send`, so rustc rejects any API that
  would move one to another thread;
- handles are `!Send` on the Idris side, because a handle is an Idris
  value.

0006's shards keep this rule as it is: a foreign thread may wake a
shard and free raw blocks remotely, and may never touch a count, a cell
or a world (0006 §3.3); a blocking Rust call is offloaded to a
runtime-owned thread whose arguments move into Rust's ownership (0006
§10.4).

## 9. The compiler

### 9.1 A foreign cell

**Runtime.** A sixth kind, `IDRIS_RT_KIND_FOREIGN`. Its header has no
object slots (objs 0): what the Rust value refers to, it owns through its
own drop glue, `IdrisValue` included.

- **v1 layout:** the header, the drop entry's address, and the Box
  pointer to the `Slot<T>`. That is 24 bytes, one snmalloc class.
- **R2 layout:** the `Slot<T>` inline after the header and drop entry,
  with size and alignment from the shim crate's layout table. A type
  aligned beyond the cell's 8 bytes keeps the Box.
- **Freeing:** `releaseOwned` (`runtime/Rc/Freeing.cpp:100-122`), which
  today tells only arrays from the rest, gains the foreign kind: a dying
  foreign cell's drop entry runs before its memory is freed. Freeing still
  reads only the header's objs, kind and stack bit (`idris_rt.h:40-43`),
  since the drop entry sits at a fixed place in the cell.
- **Drop glue that releases Idris values** (`IdrisValue`'s `Drop`) does not
  call `idris_rt_dec` recursively. It pushes onto the current dying list
  (the `Dying` worklist, `Freeing.cpp:42-90`) through a new runtime
  entry, `idris_rt_release_deferred`, which outside a release releases at
  once, so freeing still takes constant stack however Rust and Idris
  objects interleave.
- **Persistent foreign cells never exist.** No foreign call runs at
  compile time (§11), so static data never holds one. A top-level value
  that holds a Rust value is a static memo cell whose forced value is the
  foreign cell: counted, and released at exit by `idris_rt_caf_release`
  (`idris_rt.h:226-230`), so its destructor runs then (0008 §2's
  first-demand constants; per shard under 0006, 0006 §6).
- **Never in a frame** (*decision*): the shim makes every foreign cell,
  through the runtime's allocator (§9.4), and `idr-stack`'s placement is
  an inherent property of `idr.con` (0004 §4 stage 11), which builds
  Idris data, so no foreign cell is a stack cell. This supersedes the
  earlier "`idr-stack` may place it in a frame like a box".

**Dialect.** A counted type `!idr.foreign<"path::Type">`, a member of
`Idr_CountedValueType` (`include/idr/IR/IdrOwnershipOps.td:35-41`), at
every grade like the others. Its layout is the cell above, decided with
the program's other layouts (`lib/IR/Layout/`). It is no data type and
has no constructors, so 0004's identified data types (D29) do not
concern it; the Rust path is its whole identity, and a path names one
type in the program's one crate graph (§5).

**Frontend.** `Ty` (`compiler/src/IdrisMLIR/Types.idr:109`) gains
`ForeignT ForeignId`. `coreType` (`Frontend/Translate/Types.idr:396`)
maps a `Foreign t` whose `t` is a binding's `[external]` phantom to it,
through a new hook, `ForeignType`, which the frontend asks for as it
asks `wordType`: one more field of the registry's `Hooks` record, one
field per kind of hook (`compiler/src/IdrisMLIR/Registry/Entry.idr`,
0005 D20, which replaced `Frontend/Translate/Hooks.idr`'s `firstOf`
projections).

### 9.2 The call

**Registry.** Each binding is a runtime primitive with its own registry
entry, which `idris-mlir-bind` generates from the surface beside the
shim. The entry names the definition
by its name and its origin (`Library Rust`), as base's foreign functions
are named, with the hook `RustCall` and the shim's
symbol. `checkReachable` admits a generated `%extern` with an entry,
as it admits `mlir-linear`'s, and admits no `%foreign` beyond base's own
foreign functions, which it recognizes by their spec as today
(`Frontend/Profile.idr:284-288`). The generated
entries live in the program's build directory and are loaded with the
generated package; they are valid only at definitions of `Library Rust`
origin, so no user module can claim one.

**The convention is the runtime's own C ABI** (**decision**). A
binding's shim is called exactly as idr-lower calls an
`idris_rt_*` function (`lib/Conversion/RuntimeCalls.cpp`), and it follows
the same ownership rule: it borrows its arguments and returns an owned
result (`runtime/idris_rt.h:248-252`).

- **Arguments:** every value passes as its runtime word, which is a
  scalar, an `idris_rt_str *`, an `idris_rt_array *`, or a foreign cell.
  A by-value parameter consumes its reference.
- **Derivation:** the call's operand and result types are derived from
  the `%extern` declaration's Idris type and nothing else. The binding
  package is the one description, and the compiler does not read the
  surface.

No Rust calling convention is computed anywhere, in particular not
`fn_abi_of_instance`. Every value crossing is a word, and the Rust side of
the shim is ordinary Rust that rustc lowers as it lowers any Rust.

**Op.** `idr.rust.call "symbol"(%world, %args...)` (*decision*, each
point; superseding the earlier callee "a private `idr.func`
declaration", which 0004 makes unexpressible, since the function
verifier demands a body of every `idr.func`, 0004 D7 and §4 stage 2):

- **Callee:** the shim's symbol, an inherent string property. A shim is
  part of the runtime (§1), and the runtime's functions are never
  `idr.func`s: the lowering declares them from the decided set before it
  converts (0004 §4 stage 12), and the shims join that set. The op is
  not `Idr_CallsRuntime`, whose pattern names the runtime function after
  the op (`include/idr/IR/IdrInterfaces.td:31-36`); its lowering is its
  own, below.
- **Signature:** an inherent `function_type`, the binding's Idris type
  lowered, whose parameter types carry the modes as grades
  (`!idr.q<quantity, permission, value>`, `IdrTypes.td:116-138`): `&T`
  a borrow, a by-value `T` owned at quantity one, `&mut T` a borrow at
  quantity one, given back in the result. No new permission is added:
  the quantity says the handle is given back, and whether two operands
  can alias is read from their `excl` grades (§8.3). This supersedes the
  earlier "a new permission of the grade" for `&mut`. The op's verifier
  checks its operands and results against the signature, as
  `idr.call`'s `verifySymbolUses` checks a call against its callee
  (`IdrOps.td:59-66`).
- **Effects:** `Idr_PerformsIO`, threading the world as every `idr.io`
  op does, and `Idr_MayCrash`, since a shim may panic
  (`IdrInterfaces.td:40-83`). Its effects are the full set, io, crash
  and diverge (`IdrAttrs.td:154-175`), since a crate may loop, so the
  one effects summary (0004 §4 stage 9) reads nothing more for it, a
  callback's dispatch function included. It is not `Idr_ObservableIO`:
  an effectful binding is called only from IO with the program's world,
  and a pure one is the manifest's claim that nothing outside observes
  it (§16 item 1), so a memo label that reaches a pure binding memoizes,
  as one that reaches an `IOArray`'s operations does
  (`IdrArrayOps.td:36`; `IdrInterfaces.td:76-82`).
- **Ownership:** idr-rc sees its operands through the signature's
  grades, as it sees a call's through its callee's (`consumesOperand`,
  `IdrOps.td:63-66`). The ownership verifier checks them after every
  pass.
- **Flow:** it implements 0004's flow interface for its closure
  operands (§7.7), and is the only op of this proposal that can carry
  one.
- **Lowering:** an `llvm.call` of the symbol, with each operand as its
  word, preceded by the alias and move tests its grades do not decide
  (§8.3).

The world: pure bindings run their calls under `unsafePerformIO` inside
the trusted package, as `Linear.Array` did before 0003's stage 1
replaced it with `libs/mlir-array`, whose pure operations are bodiless
`%extern`s instead (`Array/Core.idr`; 0005 D5). The forged world orders
them with every other effect.

### 9.3 Linking

**Driver: the runtime's own link** (*decision*, superseding the earlier
`linkRust` step beside `linkRuntime`). Rust is part of the runtime (§1),
so the program's shim archive, `build/rust/libidrs.a` (§6), is one more
input of the runtime's reader and link, read after the runtime's, and
no step is Rust's own:
- `readRuntime` checks and prepares its members as it prepares the
  runtime's (`lib/Driver/ReadRuntime.cpp:126-164`): the member's target
  triple must be the program's; static constructors are refused, since
  `LinkOnlyNeeded` always links appending globals and they would run in
  every program; `used` markers are dropped; an appending global is
  refused as `unsupported (runtime)`. A crate graph whose bitcode needs
  a constructor is refused there, with the member named, and R0 records
  which members of `std` the two targets bring.
- `namesApart` keeps the program's names apart from the runtime's
  (`lib/Driver/LinkRuntime.cpp:74-103`), and so from Rust's.
- `linkRuntime` joins what the program reaches with `LinkOnlyNeeded`
  before `retarget` and internalization (`lib/Driver/Run.cpp:181-192`),
  so Rust's functions are raised to the program's CPU as the runtime's
  are (`include/idr/Driver/Runtime.h:58-65`), everything but `main` is
  internal, and O3 optimizes a binding's call and the Rust code under it
  as one function.

Rust then takes the runtime's two cases unchanged: bodies
`available_externally` when the native half runs on the program's CPU,
resolved at the link in the native half, where every piece of state has
its one definition, and otherwise definitions compiled with the program
(`include/idr/Driver/Runtime.h:67-78`). That holds at 0004's S2, where
the optimized module is cut into bins after one O3 (0004 §4 stages
13-15), and at its second step, where each unit links the same bodies
before its own O3 by the same link and the reached definitions are
defined once in the runtime's namespace group (0007 §3.5). Rust's
definitions fall in that group by their dotless names (§6, Mangling;
0007 §3.4). Reason: a step of Rust's own would be a third case at
0007's second step, which 0007 decides against ("the second step keeps
today's two cases and adds no third"), and a second representation of
"a part of the runtime".

`std`'s runtime start (`lang_start`) never runs: the process entry is
the runtime's (`idris_rt_start`, `runtime/idris_rt.h:433-449`), as any
Rust static library linked into a C program lives without it. What
`std` sets up there (*recalled*: the arguments on some Linux targets,
the stack guard, `SIGPIPE`) is the runtime's job, behind its platform
layer (AGENTS.md); no binding exposes `std::env` or `std::process`, and
R0 records what `std` does without it on both targets.

**One archive per program.** The program's one surface (§5) gives one
shim crate and one archive, with one copy of `std`, one
`#[global_allocator]` (§9.4) and one panic runtime. This is what makes
the static link sound: two archives built from two graphs would each
bring their own `std`, and their symbols would collide or, worse, two
allocators would share one heap. The driver refuses a program whose
packages bring generated bindings from more than one surface, naming
them.

- **What the archive contains.** It is built as the runtime's archive is
  for the target entry, with every member carrying its bitcode with its
  native code: the shim crate, its dependencies, and `std` itself, which
  comes from the Rust sysroot the bootstrap builds once per target entry
  (§14). The runtime's members carry theirs by `-flto=full
  -ffat-lto-objects` in the section `.llvm.lto` (`CMakeLists.txt:168-169`).
- **Flags,** the same for `std` in the bootstrap and for each program's
  crates: `-Clinker-plugin-lto`, or `-Cembed-bitcode=yes` with fat
  objects, whichever the entry's object format needs (*recalled*;
  settled at R0), `panic = "abort"` (§8.4) and
  `-Csymbol-mangling-version=v0` (§6); `std` is built with cargo's
  `-Zbuild-std` once, there.
- **What stays native.** The archive's native half resolves what the
  optimizer leaves, as the runtime's does (above).

**Target entry.** It gains two facts:

- `IDRIS_MLIR_RUST_TARGET`: `x86_64-unknown-linux-musl` or
  `aarch64-apple-darwin`, with the deployment target the entry already
  has;
- `IDRIS_MLIR_RUST_BITCODE_FLAGS`: the counterpart of
  `IDRIS_MLIR_RUNTIME_BITCODE_FLAGS`.

On Linux, Rust's self-contained musl objects are not used
(`-Clink-self-contained=no`): the program links the pinned musl in
`.toolchain/sysroot`, as everything else does. Rust's `libc` crate must
agree with the ABI of musl 1.2.6, the pinned release
(`toolchain.lock.json:24-30`), which R0 checks (recalled: Rust targets
musl 1.2.3 or later).

**C inside `-sys` crates.** This is the only C in a program (rule 12). A
`-sys` crate's C sources are built by its `cc` build script with `CC` set
to the pinned clang, the target's sysroot, and `-flto=full` (or the
entry's bitcode flags), so its bitcode joins as well. The program binds
the Rust crate, never the C below it: the generator binds no item whose
signature exposes a raw C type or pointer (`rust pointer` in §9.5), so a
`-sys` crate's own raw API is not bound, only safe crates over it. A
`-sys` crate over C++ (a SAT or SMT solver for 0011's T8, 0011 §2.5)
is built the same way, with `CXX` the pinned clang++ and the pinned
static libc++, never the system's (AGENTS.md). A build script that
downloads anything fails, because the build is offline. That is the
rule, and a crate that needs a network build is named in the report.

### 9.4 One allocator

The shim crate's `#[global_allocator]` calls the runtime: `idris_rt_alloc`
and `idris_rt_free`, plus new `idris_rt_alloc_aligned` and
`idris_rt_realloc` entries over snmalloc.

- Rust and Idris share one heap and one set of size classes, and any
  block may be freed from any thread (`idris_rt.h:182-195`).
- The allocator entries carry LLVM's allocation attributes
  (`allockind`, `alloc-family`), so that after the runtime link LLVM can
  delete an allocation and free pair it sees whole.

### 9.5 Rejections

New cases of the one rule enum, each with a reject fixture. The enum is
declared once in the dialect's ODS and its Idris `Rule` is generated
from it, which deletes the hand-written `compiler/src/IdrisMLIR/Rule.idr`
(0004 D42); this supersedes the earlier "new rules in `Rule.idr`". A
refusal carries its rule as data, and the phrase is rendered from the
enum in one place:

| Rule | Who rejects | When |
|---|---|---|
| `rust` | the generator, through the driver | an item cannot be bound; the phrase names the item and the reason (`rust pointer`, `rust send`, `rust lifetime`, `rust async`, `rust cfg`) |
| `rust graph` | the generator, through the driver | two packages' manifests require versions of one crate that no single version satisfies, naming both packages; or a program's packages bring bindings from more than one surface |

## 10. Brady-style protocols, on top

The handle types say who owns a Rust value and whether it may change.
They do not say what state it is in: a prepared statement, a statement
mid-iteration, a committed transaction. That is Brady's contribution
(resource-indexed types, as in Idris 1's `Effects` and `ST`), and it is
layered on top (**decision**):

```idris
||| An overlay over the generated rusqlite bindings: plain Idris in the
||| project, no %foreign, no escape hatch.
data TxState = Open | Done

export
data Tx : TxState -> Type where
  MkTx : Rust TransactionT -> Tx Open

export
begin : (1 _ : Rust ConnectionT) -> Res (Tx Open) (const (Rust ConnectionT))

||| The two ways to finish a transaction threaded at quantity 1. Dropped
||| unfinished (bound at ω and forgotten), it rolls back when its cell is
||| released, as rusqlite's Drop does.
export
commit   : (1 _ : Tx Open) -> IO (Either Error ())
export
rollback : (1 _ : Tx Open) -> IO ()
```

- Overlays are ordinary user-level Idris. They call only generated
  functions, so they need no trust, and they compile under the profile as
  written.
- What a library-level `ST` would have added (a context of named
  resources threaded through an indexed monad) is not adopted. §15 says
  why.
- An overlay lives in the project that uses it, as user code
  (*decision*): an installed package outside the library table is
  `Untrusted`, loaded but never reached
  (`Registry/Libraries.idr:93-104`), and nothing proposes trust for
  third-party Idris packages, so an overlay that ships with its crate is
  not planned. This decides the earlier "when third-party Idris packages
  become trustable".

## 11. Compile-time evaluation

No Rust call runs at compile time. The compiler has no compile-time
evaluation feature (`idr-eval` and its JIT left the C++ side, 0008's
status); it normalizes the static part of the program on the type
checker's interpreter (0008), where code that reaches a world, a forged
one included, is stuck and runs at run time (0008 §2). Every binding
reaches one (§9.2), so a binding's call is stuck there and runs at run
time. The stage that would have run calls the manifest declares `pure`
is withdrawn.

## 12. Async: 0006's reactor is the executor

Async Rust is out of v1 because the runtime has no scheduler: a program
is one runner thread running `main` (`idris_rt_start`,
`runtime/idris_rt.h:433-461`). The design of async Rust is 0006 §10's,
and this file does not restate it: the executor is the shard's reactor,
a future is a task frame, a waker is one word, and `Rust (FutT a)` is a
counted foreign cell of §9.1 holding a pinned future, polled through a
shim with the task's waker (0006 §10.1 to §10.3); a blocking Rust call
is offloaded (0006 §10.4). It is 0006's P3, after its P2, and it needs
this proposal's foreign cells and shims (R1, R2) first. Which crates
work is 0006 D12's rule, computed per crate graph.

What stays here is this proposal's half:
- **I/O traits:** Rust's async I/O traits (`tokio::io::{AsyncRead,
  AsyncWrite}`, `hyper::rt::{Read, Write, Timer, Executor}`, smithy's
  connector and sleep traits) are implemented in `Rust.Core`'s shim over
  the runtime's sockets and timers, with buffers the runtime owns until
  completion (*recalled*: the trait sets).
- **The refusal:** the generator rejects any graph that enables tokio's
  `rt`, `net` or `time` features, as `unsupported (rust async)` (§9.5),
  since those crates call into tokio's runtime directly (`tokio::spawn`,
  `tokio::net`, `tokio::time`, as reqwest and sqlx do; *recalled*).
- **Never:** a tokio island on threads of its own (§3).

Until P3, a synchronous crate with an I/O-free core is the way to talk
to the network. rustls's `Connection` and `httparse` take bytes in and
give bytes out, and the program owns the sockets (*recalled*).

## 13. Testing

- **A new pool, `tests/programs/rust/`.** Each fixture has a `rust.toml`,
  and its `run` script generates bindings, compiles, runs, and checks the
  committed expected files, as every e2e fixture does.
- **Reject fixtures** for each rule of §9.5, named for the rule.
- **Runtime-check fixtures** (§8.3), with `expected-crash` holding the
  message.
- **Drop timing:** a destructor with a visible effect (a flushed file, a
  closed socket) runs at the last release, so its effect appears in
  stdout at a fixed point; a fixture pins that order.
- **The live-cell count.** `IDRIS_RT_LIVE=1` reports zero live cells at
  the end of every fixture, foreign cells included: every Rust value
  dropped (`runtime/idris_rt.h:258-266`).
- **Properties, each in a test API's terms, never as op sequences**
  (*decision*, superseding the earlier "a call through a result handle
  allocates nothing after inlining" as an `idr-expect` property, which
  no `idr-expect` property can see, since the Rust code joins after the
  MLIR pipeline):
  - in the module, before lowering: `tests-nothing=@f` holds of a loop
    over an exclusive handle, reading `idr.rust.call`'s by-value and
    `&mut` operands as it reads takes (§8.3);
  - on the object: a binding's shim is inlined where R0's fixture says
    so, read as no relocation in the object naming the shim's symbol,
    beside `tests/lib/heap.sh`'s check of the object's imports
    (`object_imports`, `:57-70`), which then allows no shim symbol;
  - a result handle's cost is recorded at R2 in a bench profile, not
    gated: the handle is the one path whether or not O3 deletes its
    allocation (§7.4), so the record changes speed, never acceptance.
- **Determinism:** every fixture's executable is byte-identical at 1, 2
  and 8 threads (`tests/determinism`; 0004's determinism rule), with the
  shim archive built once per surface.
- **The generator's own tests:** determinism, the report's contents, and
  the trust digest (a hand edit makes the package untrusted).
- **The surface's rules**, each a fixture:
  - slicing: a selected method whose result type is in an unnamed crate
    binds that type as a handle, and nothing else of that crate;
  - both targets: a crate with a `#[cfg(target_os = "macos")]` item
    reports it as `rust cfg` and binds the rest, on both targets;
  - one graph: a library package's manifest plus the application's give
    one surface and one archive; conflicting requirements are a
    `rust graph` reject fixture naming both packages;
  - `rust.surface` drift: a manifest change without regenerating the
    committed listing fails the build with the diff.

## 14. Plan

It is taken up after 0004's cutover, on its pipeline, and builds on
nothing the cutover deletes. Each stage ends with `make check`, `make
build`, `make test`, `make test-idr`, `make test-mlir-tools` (it changes
how we use MLIR), `tests/determinism` at 1, 2 and 8 threads, and the new
pool green on both target entries (AGENTS.md; 0004 §10). Each lands as a
cutover, with nothing kept beside it (0004 D2).

- **R0, the toolchain.**
  - **Pins:** a `rust` entry in `toolchain.lock.json` (the nightly's date,
    its `rustc-nightly-src` tarball and SHA-256, and the LLVM major it is
    built against) and a `rust` step in `tools/bootstrap.sh`.
  - **LLVM:** the LLVM pin is a commit of llvm main (PINS.md:68-73;
    `toolchain.lock.json:3-7`: `llvmorg-24-init-13225-g7208ba24ca28`,
    24.0.0git), which rustc does not build against (it supports external
    LLVM 22 and 23, rust-lang/rust#163572, *recalled*). The step pins an
    official nightly with its bundled LLVM, and `tools/verify-pins.sh`
    checks that rustc's LLVM major is not newer than ours, so that our
    LLVM reads its bitcode (23 against our 24, *recalled* for rustc's).
    Building rustc, cargo, rustdoc and `rust-src` against the stage-2
    LLVM is possible only once a nightly is on our major, and is not
    planned.
  - **Bitcode linking:** a hand-written binding of one function
    (`fn add(a: i64, b: i64) -> i64`) with a hand-written registry
    entry, its archive read and joined by the runtime's link (§9.3); its
    property is that the call is inlined, read on the object as no
    relocation naming the shim's symbol (§13).
  - **The archive's facts:** no function of the archive has a dot in its
    name (v0 mangling, §6); which members of `std` bring a constructor
    or an appending global, which the runtime's reader refuses (§9.3);
    what `std` does without `lang_start` on both targets (§9.3).
  - **Exit criterion:** the program runs on both targets, and the shim's
    bitcode reads in the pinned LLVM.
- **R1, foreign cells and the generator.**
  - **Runtime and dialect:** `KIND_FOREIGN` and its freeing,
    `!idr.foreign`, `idr.rust.call` with its inherent signature (§9.2),
    generated registry entries, and `Bindings` trust (§8.1).
  - **Generator v0:** free functions, opaque `Shared` types, §7.2, and
    `Option`/`Result` through result handles; `[select]` and slicing;
    rustdoc per target entry and the intersection, with `rust cfg` in the
    report; `rust.surface`.
  - **One graph per program:** manifests from dependencies unioned, one
    archive, the conflict rejection.
  - **Fixtures:** `regex` and `sha2`, and a library package with a
    manifest used by an application that binds a second crate.
- **R2, mutation and ownership.** `Rust t`, `freeze`, `&mut`, by-value
  moves, `&mut` borrows, the slot flag and §8.3 with its fixtures (the
  alias and move tests in the lowering, the flag in the shim), struct
  accessors and enum views, and inline foreign cells. The earlier
  "`idr-stack` placement of result handles" is withdrawn (§9.1); the
  result handle's cost is recorded instead (§13).
  - **Fixtures:** `serde_json`, `rusqlite` with `bundled` (C under Rust,
    built by the pinned clang), and a `HashMap` instance.
- **R3, generics and callbacks.** `IdrisValue` containers with `RustKey`
  keys (§7.6) and the cycle-check edge, callbacks through the flow
  interface and private dispatch functions (§7.7), and `i128`.
  - **Fixtures:** a callback that captures a value and one whose
    argument the closure ignores (the dispatch function keeps its
    signature through dead-value removal); a stored `'static` callback on
    a `Shared` handle; an Idris key type for `RMap`, which is a type
    error, in `tests/reject`.
- **R4** is withdrawn: no Rust call runs at compile time (§11); 0008's
  static normalization runs closed calls of total Idris code, and a
  binding's call reaches a world, so it is stuck and runs at run time
  (0008 §2).
- **R5, async on the reactor**, is 0006's P3, not a stage here (§12).

**Size (conjecture):**

| Area | Lines |
|---|---|
| Generator | 4–6k (Rust) |
| `Rust.Core` | 0.5k (Idris) |
| Compiler: frontend | 1–1.5k |
| Compiler: dialect, lowering, driver and runtime | 2–3k |
| Bootstrap and tests | about 1k |

R0 pins an official nightly, so the bootstrap builds no rustc (PINS.md
records the pins). *Decision*, deciding the earlier "goes through a
compiler cache": the bootstrap builds `std` once per target entry, with
the entry's flags (§9.3: bitcode, v0 mangling, `panic = "abort"`), into a
Rust sysroot under `.toolchain/`, as it builds the runtime once per
target; a program's cargo build compiles only the shim crate and the
bound crates against that sysroot, and keeps them in its own target
directory under `build/rust/`, which is the only cache. Reason: `std`'s
flags are the target entry's, not the program's, so building it per
program would repeat one build, and ccache, the cache of every C and C++
compile the bootstrap runs (`tools/bootstrap.sh:240-246`), does not
compile Rust, so a Rust cache would be one more pinned tool for no
measured need. R0 checks that no program's build rebuilds `std`.

## 15. Alternatives considered

- **Embedding `rustc_driver` in idris-mlir and querying `layout_of`
  and `fn_abi_of_instance`, to call the unstable Rust ABI directly.**
  Rejected. The driver links only from Rust built by the same nightly, so
  idris-mlir (C++, statically linked with LLVM) would host a second LLVM in one
  process. `rustc_private` also changes every six weeks. And it would buy
  nothing: with every value crossing as a word through an `extern "C"`
  shim that LTO inlines, there is no Rust ABI left to compute. rustc
  stays in the toolchain as a tool: a pinned nightly with its own LLVM
  (§14 R0), which decides every Rust layout and calling convention
  itself.
- **Building MLIR from Rust's LLVM fork instead.** Rejected. The
  toolchain's LLVM is a commit of llvm main (PINS.md:68-73), and
  PINS.md's MLIR workarounds and `upstream/`'s reproducers are pinned to
  it; a patch we carry is then its upstream pull request, one diff
  (PINS.md:68-70), which a fork's base would not be. rustc ships its own
  release LLVM (23 since July 2026, rust-lang/rust#158734, *recalled*).
  LTO works as long as rustc's major is not newer than ours, since newer
  LLVM reads older bitcode, and `verify-pins` enforces that bound; rustc
  built against our LLVM is possible only when a nightly is on our
  major.
- **Generating bindings from C headers, as hs-bindgen does for Haskell**
  (well-typed/hs-bindgen, read 2026-10-09: its manual on binding
  specifications, portability, and selection and slicing). Not
  applicable: this design reaches C only through Rust, and no C header is
  read. Its portability problem does not arise either. hs-bindgen freezes
  sizes and offsets that libclang reports at generation time into the
  bindings, which its manual says "are not portable in general, and
  cannot be"; here only words cross a call (§9.2), Idris layouts are
  decided per program (§7.4), and the one layout table (R2's inline
  slots) comes from the same rustc build as the shim, for its target.
  Static LTO also removes its wrapper and shared-library concerns
  (§9.3). Three of its ideas are taken, in the form a static, two-target
  build needs:
  - its external binding specifications, which let separately generated
    bindings share a type, become one crate graph and one surface per
    program from the union of every package's manifest (§5), since a
    static link must hold one `std`;
  - its selection predicates and program slicing become `[select]` and
    slicing by the types a selected item mentions (§6);
  - its advice to keep the specification as a record of the public API,
    so that regeneration shows API changes, becomes the committed
    `rust.surface` (§6).

  Its per-target question, answered for layouts there, is answered for
  the API here: rustdoc per target entry, and the intersection (§6).
  rust-bindgen (C to Rust; `-sys` crates use it, and `idris-rt` is
  generated by it) and cxx (a shared bridge description between two
  languages, which is the shape of the surface) are the closer relatives.
- **A library-level `ST`: a context of named resources in an indexed
  monad, with lifetimes as regions.** Rejected as the ownership layer.
  - It would represent ownership a second time, beside the grades the
    compiler already proves and verifies (§2.5).
  - Its error messages were the weak point of Idris 1's `ST`.
  - It would have needed elaborator reflection or a contrib-style
    library, and neither is available to user code here (§2.2; contrib
    is no commitment, AGENTS.md).
  - Brady's idea survives where it adds information the grades lack:
    protocol states (§10).
- **A C FFI, first or ever (clang, header import, ownership
  annotations).** Rejected, permanently (rule 12). Rust's signatures
  already state ownership, lifetimes and thread-safety, and C's headers
  state none of them, so every C binding would need annotations a person
  writes and nothing checks. The Rust ecosystem's `-sys` crates and the
  safe crates over them have done that work, reviewed and tested; using
  them is the whole point of this proposal.
- **A tokio island.** Rejected (§3, §12).
- **Shims that build Idris data directly (a `Maybe` in the shim).**
  Rejected: layouts are decided per program, so a shim cannot know one.
  A result handle costs what O3 leaves of it, recorded at R2 (§7.4).
- **A `linkRust` step beside the runtime's link.** Rejected (§9.3): it
  would be a third case at 0007's second step and a second
  representation of a part of the runtime.
- **An exported apply entry per callback sum.** Rejected (§7.7): a public
  function beside the root breaks 0004's verified closed world.
- **A private `idr.func` declaration as the shim's callee.** Rejected
  (§9.2): 0004 makes a bodiless `idr.func` unexpressible.

## 16. Decisions on the open questions (2026-10-09)

Each picks the smaller mechanism (§1).

1. **IO by default.** Every binding is `IO` unless the manifest's
   `[pure]` declares its crate or item pure. Purity cannot be read from a
   Rust signature, and a wrong `pure` is unsound, so it is an explicit
   claim.
2. **No `--static-borrows`, and no mode.** A residual borrow or move
   check stays a runtime check (§8.3), and the compiler
   removes every check it proves. No rule refuses a residual check: the
   earlier draft's use of the `uniqueness` rule for it is withdrawn, and
   `uniqueness` stays `idr-demand`'s own rule (0004 D42).
3. **No `[values]` copying.** Every Rust struct and enum is a handle;
   fields are read through accessor shims, which inline after the
   runtime link (§7.4, §9.3). One path for every compound value.
4. **`Rust.<Crate>` as the namespace** of every binding module
   (`Rust.Regex`, `Rust.SerdeJson`), so no binding can collide with an
   Idris module and every module that came from Rust says so.
5. **Nothing is bound unless `[select]` names it** (`"all"` is allowed,
   explicitly). Slicing adds what the selected items need. A large crate
   never binds thousands of items no program calls (§5).
6. **The generator is written in Rust**, built by the pinned cargo, and
   reads rustdoc's JSON through `rustdoc-types` at the version the rustc
   pin fixes. Rust is a first-class part of the toolchain anyway; a C++
   reader would re-implement that crate by hand. The deviation from
   the MLIR layout of the C++ side is recorded in PINS.md when R1 adds
   the generator.

## 17. Decisions of the 2026-10-14 reconciliation

Each makes this design consistent with 0004's cutover or decides what an
earlier text left open. There is no open question for the owner.

7. **The shim is named, not declared** (§9.2). `idr.rust.call` carries
   its shim's symbol and its signature, grades included, as inherent
   properties; there is no `idr.func` for a shim. Reason: 0004 D7 makes
   a bodiless `idr.func` unexpressible, and the shims are part of the
   runtime, whose functions the lowering declares (0004 §4 stage 12).
8. **`&mut` is a borrow at quantity one** (§9.2). No permission is added
   to the grade. Reason: the quantity already says the handle is given
   back, and the alias test reads `excl` grades.
9. **Grade tests in the lowering, state tests in the shim** (§8.3). The
   alias and move tests are emitted by the op's lowering where the
   grades do not decide them; the slot flag stays in the shim. Reason:
   only the lowering still sees the grade that removes a test.
10. **Callbacks through the flow interface** (§7.7). A closure passed to
    Rust flows along `idr.rust.call`'s declared edge into a callback
    key, whose private dispatch function's address the shim gets.
    Reason: 0004's closed world stays as the verifier states it, and a
    callback is one more first-order caller.
11. **The op's effects are the full set and not observable** (§9.2).
    Reason: a crate may do anything, so no summary is read for the op;
    an effectful binding is ordered by the program's world, and a pure
    one is the manifest's claim.
12. **One runtime link** (§9.3). The shim archive is read and linked by
    the runtime's reader and link; there is no `linkRust`. Reason: the
    runtime's two cases and its namespace group then hold for Rust at
    both of 0007's steps, with no third case.
13. **v0 mangling** (§6). Reason: every Rust function is a dotless name
    and joins the runtime's namespace group by 0007 §3.4's rule.
14. **No foreign cell in a frame** (§7.4, §9.1). Reason: `idr.stack` is a
    property of `idr.con`, and the shim makes every foreign cell; the
    result handle's cost is LLVM's to remove and is recorded, not gated.
15. **Map keys by type** (§7.6). `RMap k a` needs `RustKey k`, which
    exists for §7.2's types only. Reason: an Idris key's ordering is
    known only after the compilation the shim crate feeds, and an
    unexpressible case needs no refusal.
16. **`Bindings` is the trust home, `Rust` the library** (§8.1), with a
    row that is trusted and admitted and reports at the caller. Reason:
    `Generated` already names an origin.
17. **Rules are cases of the one generated rule enum** (§9.5; 0004 D42).
18. **Overlays live in their project** (§10). Reason: an installed
    package outside the table is never reached, and no proposal makes
    third-party packages trusted.
19. **Async is 0006's** (§12). This file keeps the I/O traits, the tokio
    refusal and, with P3, the `[blocking]` table (§5).
20. **`std` is built once per target entry by the bootstrap** (§14).
    Reason: its flags are the entry's; cargo's target directory is the
    only cache.
21. **A binding is an `%extern`** (§1, §8.1, §9.2), as `mlir-linear`'s
    runtime primitives are, and its registry entry holds the shim's
    symbol once; `checkReachable` admits no `%foreign` beyond base's own.
    Reason: the earlier `%foreign` spec was a label nothing read, an
    unread second copy of the entry's target, and a class of accepted
    `%foreign` definitions AGENTS.md rules out; Idris needs no spec on a
    primitive.
