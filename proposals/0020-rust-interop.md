<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Proposal 0020: Rust as the one foreign world

**Status:** parked and decided; nothing is built. The tree has no
`foreign/rust/`, `libs/mlir-rust/`, `IDRIS_RT_KIND_FOREIGN`,
`!idr.foreign` or `idr.rust.call` (*read*, 2026-10-15). Every stage is
**AFTER-SELF**: `make self` compiles the frontend, which reaches no
foreign world, so self-hosting neither needs this nor waits for it. It is
taken up when its first consumer starts: 0007's P3 (asynchronous Rust on
the reactor), 0013's T8 (solvers as Rust crates, 0013 §2.5) or bumbledb's
storage (LMDB through heed, `../bumbledb/proposals/0003-idris-port.md`).
Two questions are the owner's (§16). Proposed 2026-10-04 (6fda6d8),
parked 2026-10-12, reconciled 2026-10-14 with the pipeline cutover and
the representation wave (their last texts at 484d6403). The 2026-10-15
audit re-read every path against the live tree and took the decisions
marked *audit*, each deleting a mechanism the tree does not need.

The brief: programs reach the rest of the world (databases, HTTP, crypto,
parsers, cloud APIs) through the Rust ecosystem, and C only through Rust
(`libc`, `-sys` crates and the safe crates over them). One pinned rustc,
static linking only. Rust is a library layer and never a host: no tokio,
no Rust scheduler; every runtime concern stays in Idris and `runtime/`.

Claims are marked *read* (the path given, in the 2026-10-15 tree),
*recalled* (upstream Rust and its tools, not in `sources/`; checked at
R0), *decision* or *conjecture*.

## 1. Lead

The compiler already has what a Rust interface needs:

- **Exact frees.** Every runtime value is a counted cell freed when its
  last reference dies, from a worklist threaded through the dying cells,
  in constant stack (*read*: `runtime/Rc/Freeing.cpp`, `Dying`,
  `releaseOwned`). A Rust value with a destructor is one more kind of
  cell whose release runs it, in program order, which is the drop order a
  Rust programmer expects.
- **Ownership in the types.** A grade `!idr.q<quantity, permission,
  value>` with permissions plain, borrow, own and excl (*read*:
  `IdrTypes.td` `Idr_QType`, `IdrBase.td` `Idr_Permission`); exclusivity
  solved once on MLIR's solver (`include/idr/Analysis/Ownership.h`);
  grades verified after every pass. `&T`, `T` and `&mut T` are a borrow,
  an owned value and an exclusive one.
- **A runtime joined as bitcode.** `linkRuntime` joins the runtime's
  bitcode to the program's module with `LinkOnlyNeeded` before O3
  (*read*: `include/idr/Driver/Runtime.h`, `lib/Driver/LinkRuntime.cpp`).
  Bitcode from a rustc whose LLVM is not newer than ours joins by the
  same link, so calls inline across the boundary both ways.

What it lacks: a value kind for foreign objects (the runtime's five are
box, thunk, string, bignum and array, `IDRIS_RT_KIND_*` in
`runtime/idris_rt.h`, and a finalizer is the `Finalizer` rule), a call op
whose callee is a per-binding shim, a rustc step in the bootstrap, and
trust for generated library code (an installed package outside the table
is `Untrusted`: `Registry/Libraries.idr`, `moduleOrigin`).

The design. A package names its crates in `rust.toml`. A generator,
`idris-mlir-bind`, reads each crate's public API from rustdoc's JSON into
one description per program, the surface, and prints from it an Idris
package of bindings and a Rust crate of shims. A binding is a bodiless
`%extern`, as `libs/mlir-array/Array/Core.idr` declares its generating
set; its origin makes it a Rust call and its type is its whole signature
(§8.1, §9.2). The compiler lowers it to a call of a runtime-ABI shim,
compiled by the pinned rustc to bitcode and joined by the runtime's own
link (§9.3). Rust values live in counted foreign cells: `&T` is a view,
`T` by value a consumed reference, `&mut T` a quantity-1 thread of a
mutable handle (as `LArray`'s `read` and `write`), and a value frozen
into `Shared` has a read-only API whose borrows hold a counted reference
to it, so the count is the borrow checker. What the types cannot see
(aliased arguments, a re-entrant callback, an abandoned `&mut` borrow)
crashes with a message naming it, as an index out of bounds does, and the
compiler deletes each check it proves redundant.

**Rust is part of the runtime** (*decision*): one static image, one
allocator (the runtime's), one crash path (a panic is a crash), one O3
over Idris, runtime and Rust, one partition into codegen bins, no loader;
no dynamic Rust library, `dlopen` or plugin, in programs or in tests.
Every decision below takes the smaller mechanism.

## 2. The rules this design keeps

From AGENTS.md: the Idris language and `third_party/Idris2` do not
change, so crates are declared outside Idris and bindings are a package;
user code has no pragma and no escape hatch (`Frontend/Profile.idr`,
`checkPragmas`, `checkReachable`), so bindings are trusted library code
and none is made by elaborator reflection; a binding's one meaning is its
shim's; no oracle; facts Idris proved live in types, so a call's modes
are grades (§9.2); the heap stays acyclic (`lib/IR/Verify/Knots.cpp`), so
a mutable Rust container of Idris values is a mutable-cell edge; no
option or mode, so a residual check is one behaviour (§8.3); two targets,
decided in the target entry; no primitive implemented in Idris, and no
Rust call at compile time (§11); reject with a named reason. Two more
are this design's:

- **One description** (*decision*): the surface. The bindings and the
  shims are printed from it, and the compiler reads nothing but the
  bindings' Idris declarations and their origin.
- **No C** (*decision*, 2026-10-09; AGENTS.md): nothing reads a C header,
  binds a C function or lets a program declare or call a C symbol. A C
  library is a Rust `-sys` crate and, preferably, the safe crate over it,
  bound as Rust; C exists only inside such crates, compiled by their own
  build (§9.3). The shims' `extern "C"` is the runtime's word-passing
  convention between our compiled code and our generated Rust, not a way
  to C.

## 3. Scope

**In:** synchronous Rust APIs (free functions, inherent methods, §7.5's
trait methods, constructors, destructors); C libraries as Rust crates
only; generic APIs at instances the manifest names or at Idris element
types (§7.6); Idris closures as callbacks called before the Rust call
returns (§7.7).

**Out, by decision:** C directly, in any form; a **tokio island** (async
Rust on a Rust runtime: a second scheduler and I/O the runtime cannot
see); Rust calling into Idris from another thread (counts are plain
arithmetic; under 0007's shards a foreign thread may wake a shard and
never touch a count, a cell or a world, 0007 §3.3); Rust types as Idris
values without a handle, beyond §7.2's; dynamic linking of Rust in any
form.

**Later:** async Rust polled from 0007's task frames, its P3 (§12);
protocol overlays (§10).

## 4. The pieces

- **`rust.toml`**, beside a package's `.ipkg`, whose format has no field
  for it (§5).
- **`idris-mlir-bind`**, a Rust program in `foreign/rust/bind/`, built by
  the pinned cargo, reading rustdoc's JSON through `rustdoc-types` at the
  version the rustc pin fixes (*decision*: a C++ reader would re-implement
  that crate; PINS.md records the deviation from upstream's layout at R1).
- **The surface**: every bound item with its Idris type and the mode of
  each parameter and result. Its outputs are printed from it alone, so
  they cannot disagree.
- **`libs/mlir-rust`** (`Rust.Core`), in-house plain Idris over base: the
  handles `Rust` and `Shared`, `freeze`, the result-handle helpers, and the
  `IdrisValue` containers. Every binding package depends on it.
- **The shim crate**, over the bound crates and `idris-rt`, a crate of the
  runtime's C interface that bindgen (on the pinned clang) generates from
  `runtime/idris_rt.h` and the ODS-generated `idris_rt_ops.h`, so the
  headers stay the one copy.

The `idr` pipeline has nothing of its own for Rust: defunctionalization,
the optimizer, `idr-rc` and the lowering see `idr.rust.call` as one more
op, and the runtime link, the partition and code generation see Rust's
bitcode as one more part of the runtime.

## 5. The manifest

```toml
# rust.toml, beside the package's .ipkg
[crates]
regex    = "1.11"
rusqlite = { version = "0.32", features = ["bundled"] }

[pure]        # every item is IO unless declared pure, per crate or item
regex    = true

[instances]   # generic types at concrete instances, under an Idris name
WordCounts = "std::collections::HashMap<String, i64>"

[select]      # nothing is bound unless named here; "all" is allowed
regex    = ["regex::Regex::*"]
rusqlite = ["rusqlite::Connection::*", "rusqlite::Statement::*"]
```

- **One crate graph per program** (*decision*). A library ships its
  `rust.toml`, never bindings. A program's build unions the manifests of
  every package it depends on and resolves one graph, so every Rust type
  has one Idris type and the link holds one shim archive and one `std`.
  Requirements no single version meets fail the generator, naming both
  packages; Cargo's semver-incompatible duplicates stay distinct types.
  A library's bindings are generated at the program's build, under its
  `build/rust/`.
- Cargo resolves once, at generation, into `rust.lock`, which the
  application commits; `cargo vendor` fills `build/rust/vendor/`, and
  every later build is offline.
- What is bound is what `[select]` names plus what slicing pulls in (§6);
  a selected item that cannot be mapped is in the report with its reason.
- `[pure]` is a claim (*decision*): purity cannot be read from a Rust
  signature and a wrong claim is unsound, so IO is the default.
- `[blocking]` (*decision*), per crate or item, comes with 0007's P3,
  which offloads each item it names to a runtime-owned thread (0007
  §10.4). Before P3 every call runs on the calling thread, in world order.
- Binding modules are `Rust.<Crate>` (`Rust.Regex`), so none collides
  with an Idris module (*decision*).

## 6. The generator

- **Input:** `rustdoc --output-format json` of every crate of the graph,
  once per target entry (`x86_64-unknown-linux-musl`,
  `aarch64-apple-darwin`), since `#[cfg]` makes an API a per-target fact:
  items, signatures with lifetimes and generics, trait impls with the
  synthesized `Send` and `Sync`. Per item it reads the receiver's and
  parameters' modes, which result borrows from which parameter, whether
  each type maps (§7), §7.5's traits, and whether a type needs drop
  (`std::mem::needs_drop`, evaluated in the shim crate). A rustc bump
  that changes the format fails at the generator's build.
- **Selection and slicing:** from `[select]`'s items, every type their
  signatures mention is bound, transitively and from whichever crate
  defines it, as an opaque handle with its §7.5 traits and only its
  selected methods (`reqwest::Client::get` brings `RequestBuilder`,
  `http::Method` and `url::Url` as handles).
- **Both targets, one surface** (*decision*): only items with one
  signature on every target entry; the rest are reported with the targets
  named. No per-target binding package: it would be a per-target case
  outside the target entry.
- **Output:** `build/rust/idris/` (the binding package, compiled per
  project), `build/rust/shims/`, `build/rust/libidrs-<digest8>.a` (every
  member with its bitcode), `build/rust/report.txt` (each selected item not bound and
  why), `build/rust/surface.digest` (§8.1), and `rust.surface`, a readable
  listing in path order (Rust path, Idris type, modes) that the
  application commits beside `rust.lock`; the build regenerates it and
  fails on a difference, as a lock file does.
- **Determinism:** path order, content-derived names, no timestamps;
  `tests/determinism` covers the generator.
- **Shim symbols** (*audit*): a shim's symbol is its binding's qualified
  Idris name, which the frontend prints from the declaration and the
  generator writes as the shim's `export_name` from the surface record
  that also writes the declaration. Rust identifiers keep it inside the
  one mangling's alphabet (`include/idr/Conversion/Mangle.h`), so it
  reaches the linker as printed, `namesApart` keeps it apart from the
  program's names, and it joins a namespace group by 0008 §3.4's rule.
  This replaces symbols spelled from Rust paths, which the compiler
  cannot know (§2, one description). The archive is named by the surface
  digest (`libidrs-<digest8>.a`) that the trust check reads (§8.1), so a
  package and an archive of different surfaces are never paired.
- **Mangling** (*decision*): the shim crate's whole graph, `std` included,
  builds with `-Csymbol-mangling-version=v0`, whose names have no dot
  (*recalled*), so Rust's own functions join the runtime's namespace group
  by 0008 §3.4's rule and the partitioner needs no rule of its own. R0
  checks that no function of the archive has a dot in its name.

## 7. The surface: how Rust types become Idris types

### 7.1 Handles

A Rust value of a non-copied type lives behind one of two handles, after
`libs/mlir-array`'s `LArray` and `Array` (*decision*):

```idris
||| A Rust value of type t, mutable, threaded at quantity 1: every &mut
||| method takes it and gives it back, so the one object changes in place.
export data Rust : (t : Type) -> Type where MkRust : Foreign t -> Rust t

||| A Rust value frozen: its &self methods only, shared freely.
export data Shared : (t : Type) -> Type where MkShared : Foreign t -> Shared t

export freeze : (1 _ : Rust t) -> Shared t
freeze (MkRust p) = MkShared p
```

- A type with no `&mut self` method is born `Shared` (`regex::Regex`).
- `Shared t` to `Rust t` is only a clone, `thaw`, for `t: Clone`. There is
  no in-place thaw (*decision*): a `Clone` may have effects the crate
  observes, so skipping one would be a different program.
- A handle is a counted foreign cell (§9.1) whose last release runs the
  destructor, once, right after the last use, in program order.

### 7.2 Scalars, strings and bytes, without a handle

| Rust | Idris | at a call |
|---|---|---|
| `i8`…`i64`, `u8`…`u64`, `isize`, `usize` | `Int8`…`Int64`, `Bits8`…`Bits64` (`isize`, `usize` as 64-bit: both targets are LP64, which `idris_rt.h` asserts) | the word |
| `bool`, `char`, `f64` | `Bool`, `Char`, `Double` | the word (both chars are Unicode scalar values) |
| `f32` | `Double` | widened out, rounded to nearest in |
| `&str` | `String` | lent, no copy: an Idris string is well-formed UTF-8 (`idris_rt_str_from_bytes` replaces ill-formed input), so `from_utf8_unchecked` is sound |
| `String` (result) | `String` | copied (`idris_rt_str_from_utf8`) |
| `&[u8]`, `&mut [u8]` | `Buffer` | lent, no copy: its bytes and length |
| `Vec<u8>` (result) | `Buffer` | copied |
| `()` | `()` | nothing |

`i128` and `u128` map to `Integer` through the runtime's big conversions
(R3). A raw pointer in a signature is not bound (reason `pointer`): its
safe wrapper is.

### 7.3 Ownership modes

| Rust | Idris parameter | at a call |
|---|---|---|
| `x: T`, `self` | `(1 _ : Rust t)` | consumed: an exclusive cell is moved out and freed; a shared one is cloned when `t: Clone`, else the call crashes (§8.3) |
| `&T`, `&self` | `Shared t`, or `(1 _ : Rust t)` given back in a `Res` | a view, no count changes |
| `&mut T`, `&mut self` | `(1 _ : Rust t)`, given back | a view whose aliasing is checked (§8.3) |

A `&self` method of a mutable type is generated on both handles, as
`libs/mlir-array` has `read` on an `LArray` and `(!!)` on an `Array`.
Borrowed results: a copyable result is copied (`&i64` is `Int64`); a
handle result is a borrow handle that holds a counted reference to its
parent and exists only on `Shared`, which has no `&mut` API, so the count
is the witness and no flag is needed; a `&mut` borrow (`iter_mut`,
`entry`) consumes the `Rust t` and gives it back at `release`. Quantity 1
does not stop a caller who bound the value at ω from using it meanwhile
(AGENTS.md: a linear binder is not unique ownership), so the shim marks
it mutably borrowed until `release` (§8.3).

### 7.4 Compound values

`Option<T>` is `Maybe T`, `Result<T, E>` is `Either E T` (an `E` is a
`Shared` handle with `Show` from its `Display`), tuples are pairs. A
struct is a handle with an accessor per public field of a mappable type;
an enum is a handle with a generated view, a plain Idris sum over
mappable payloads.

How they cross (*decision*): a shim cannot know a program's layouts,
which are decided per program before the lowering (`lib/IR/Layout/`), so
no Idris data moves through a shim. A compound result is a result handle
that the binding's Idris takes apart through accessor shims before it
dies; a compound argument is built as a Rust value by a builder shim. One
path: after the runtime link the accessors inline and the handle's
allocation and free are a pair LLVM sees whole (§9.4), which O3 may
delete (*conjecture*, recorded at R2); that changes speed, never meaning.

### 7.5 Traits

| Rust impl | Idris |
|---|---|
| `Display` | `Show` |
| `Debug` | `debug : Shared t -> String` |
| `PartialEq`, `Eq`, `PartialOrd`, `Ord` | `Eq`, `Ord` on `Shared t` |
| `Clone` | `thaw : Shared t -> Rust t`; `clone` on `Rust t`, given back |
| `Default` | `def : Rust t` |
| `Iterator<Item = X>` | `next : (1 _ : Rust it) -> Res (Maybe X) (const (Rust it))`; `toList` |
| `Hash` | used by `IdrisValue` keys only (§7.6) |

Each generated instance is monomorphic over one handle type, so it
compiles as any interface resolved at compile time.

### 7.6 Generics

A generic item is monomorphized in the shim crate, so it is bound only at
concrete types (*decision*): at Rust types named in `[instances]`
(`HashMap<String, i64>` as `WordCountsT`), or at Idris element types,
where `Rust.Core` gives `Vec<IdrisValue>`, `VecDeque<IdrisValue>` and
`BTreeMap<K, IdrisValue>` as `RVec a`, `RDeque a` and `RMap k a`, `a`
erased.

- `IdrisValue` is a word holding a counted reference; its `Clone` is
  `idris_rt_inc` and its `Drop` is `idris_rt_release_deferred` (§9.1). It
  is `!Send` and `!Sync`, so rustc keeps Idris values on their thread, and
  the generator leaves out an API whose bounds would need it to cross
  (reason `send`).
- Keys are §7.2's types by construction (*decision*): `RMap k a` is made
  and used only under an interface `RustKey k` whose implementations
  `Rust.Core` gives for §7.2's types alone, so an Idris key type is a type
  error where it is written. A key over Idris values would need its
  `Hash` or `Ord` from the compilation the shim crate feeds.
- A mutable container of `IdrisValue` is a mutable-cell edge for the
  cycle check: an `RVec Node` whose `Node` reaches the same `RVec` is
  `unsupported (cycle)`.
- `Rust.Core`'s Rust half (`IdrisValue`, `IdrisFn`, §12's I/O traits) is
  a crate in `libs/mlir-rust` that every program's graph includes and the
  generator binds as any crate, so every Rust call is a `Library Rust`
  declaration (§8.1); how `RVec a`'s erased element meets `IdrisValue` is
  settled at R3.

### 7.7 Callbacks

A parameter `impl Fn(A) -> B`, `impl FnMut`, `&dyn Fn` or `F: Fn(A) -> B`
takes an Idris function `A -> B` (`A -> IO B` for an effectful item).

- **Shim side:** a wrapper `IdrisFn<A, B>` per signature holds the
  closure as one counted word and the address of its dispatch function,
  and implements `Fn` by calling it.
- **Compiler side** (*decision*): `idr.rust.call` declares the flow
  interface in its ODS (`IdrFlow.td`), with each closure operand flowing
  into a callback key of its own, so the label solve sees every label that
  reaches Rust. Defunctionalization makes the key a sum and gives it one
  private dispatch function, a case of direct calls named from the key;
  the op carries the sum boxed (how it gets its box is decided by fit,
  `lib/IR/Layout/Fit.cpp`, when R3 starts) and a symbol use of the
  dispatch function, whose address the lowering passes to the shim. That
  use keeps the function and its parameters whole: `remove-dead-values`
  leaves alone the parameters of a function named other than as a callee
  (*read*: PINS.md `remove-dead-values-address-taken`). Its one outside
  caller passes only §7.2 to §7.4 values, never a closure or a suspension,
  which the op's verifier checks, so no label enters from outside and the
  closed world holds; nothing is exported.
- **Constraints:** a callback is called only before the Rust call returns;
  one an API stores (`'static`) is bound only on a `Shared` handle, whose
  cell then holds the closure. The closure's sum is one more field type
  for the cycle check. Re-entrancy is checked (§8.3).

## 8. Soundness

### 8.1 Trust

- **The home** (*decision*): a new `Home`, `Bindings`, the binding
  package the generator wrote under the project's `build/rust/idris/`,
  and a new `Lib`, `Rust`: `moduleOrigin Bindings _ = Library Rust`, a row
  trusted and admitted that reports at the caller (`Registry/Libraries.idr`,
  `reportAtCaller`), since no person wrote the source. Not `Generated`,
  which `Origin` already names for code in no module. The package is
  trusted only while its sources hash to `surface.digest`; a hand edit
  makes it `Untrusted`, loaded and never reached.
- **Bindings admitted by origin** (*audit*): `checkReachable` admits a
  bodiless `%extern` that the registry gives a meaning (`meansExtern`,
  `Registry/Entry.idr`) or whose origin is `Library Rust`, and no
  `%foreign` beyond base's own. There is no registry entry per binding:
  the registry is compiled into the frontend (`Frontend/Resolve.idr`,
  `hooksOf`, a function of the name alone), so per-program entries would
  need a loader the tree does not have, and each would restate what the
  declaration and its origin already say.
- **One surface per program, by construction** (*audit*): libraries ship
  only manifests and the program's build writes the one package where
  `Bindings` points, so a second surface cannot reach a program, and the
  driver needs no refusal for one.
- **`Rust.Core`** is `InHouse`, a row beside `mlir-linear` and
  `mlir-array` in `moduleOrigin`. Its `Foreign : Type -> Type` is a
  primitive type with a registry entry (one hook field, as `wordType`
  is): a counted foreign cell holding a Rust value of type `t`, valid
  only from `Library Rust` and `InHouse` origins, so user code holds Rust
  values only through `Rust` and `Shared`. Its release is the cell kind's
  own; there is no finalizer.

### 8.2 What the types guarantee

A Rust value lives while any Idris value refers to its cell, and a borrow
handle refers to its parent's, so no shim sees a dangling reference. No
mutation happens under a shared borrow: borrow handles exist only on
`Shared`. A by-value parameter is quantity 1, and its move reads the
operand's grade: an exclusive cell moves with no test, as `idr.take`
moves a box (`IdrOwnershipOps.td`), and one that may be shared is tested.

### 8.3 What is checked at run time, and named

Three things escape the types (*decision*); each crashes with a message
naming it. The two that read only grades are emitted by `idr.rust.call`'s
lowering, as `idr.take`'s lowering reads its operand, only where the
grade does not decide them; the flag is the shim's, since it reads the
Rust value's state. Only the lowering still sees the grade that removes a
test.

1. **Aliased arguments:** a call with a `&mut` parameter and another
   reference of the same Rust type compares the two cells
   (`rust: Vec::append was given the same Vec twice`).
2. **Re-entrancy and abandoned `&mut` borrows:** each payload is
   `Slot<T> { state: Cell<u32>, value: T }`; the flag is set during a call
   that takes Idris callbacks and while a `&mut` borrow handle lives, and
   an access that finds it set crashes (`rust: the Vec is mutably
   borrowed`). A call without callbacks runs no Idris code and leaves the
   flag alone.
3. **Moving out of a shared, non-`Clone` value:** `idris_rt_is_unique`
   at the move (`rust: the Vec is shared and cannot be moved`).

The compiler removes what it proves: no uniqueness test on an `excl`
operand, no alias test between two distinct exclusive operands, and a
flag write with no reader folds away after inlining. One behaviour, no
mode (*decision*): a check that stays is a runtime check, never a
rejection, and `idr-expect`'s `tests-nothing=@f`
(`lib/Transforms/Expect/TestsNothing.cpp`) reads an `idr.rust.call`'s
by-value and `&mut` operands as it reads takes.

### 8.4 Panics

The shim crate builds with `panic = "abort"`; its panic hook calls
`idris_rt_crash` with `rust panic: <message>`, which flushes output and
exits with `IDRIS_RT_CRASHED` as every crash does. No unwinding crosses
into Idris: on Linux the entry links no unwinder
(`IDRIS_MLIR_NO_UNWINDER`), and on macOS, where libSystem is the
unwinder, nothing unwinds.

### 8.5 Threads

A program is single-threaded (`idris_rt.h`: counts are plain
arithmetic). Rust may start threads of its own (rayon, a pool's reaper),
and they may allocate and free, but nothing of Idris reaches them:
`IdrisValue` and `IdrisFn` are `!Send`, and a handle is an Idris value.
0007's shards keep the rule (0007 §3.3), and a blocking call is offloaded
with its arguments moved into Rust's ownership (0007 §10.4).

## 9. The compiler

### 9.1 A foreign cell

- **Runtime:** a sixth kind, `IDRIS_RT_KIND_FOREIGN`, with no object
  slots: what the Rust value refers to, it owns through its drop glue.
  The cell is `#[repr(C)]` header, drop entry and `Slot<T>`, laid out by
  rustc and made only by the shim, through the runtime's cell allocation
  (`idris_rt_cell`, with an aligned variant for a payload that needs one).
  Freeing gains the foreign kind: the drop entry, at a fixed place, runs
  before the memory is freed (`runtime/Rc/Freeing.cpp`).
- **One layout** (*audit*): the compiler only holds the cell's word and
  never builds, copies or places one, so it needs no size, no layout
  table and no boxed variant. This deletes the earlier boxed v1 layout,
  the inline R2 layout with its layout table, and the boxed exception for
  over-aligned types.
- **Drop glue that releases Idris values** pushes onto the current dying
  list through a new entry, `idris_rt_release_deferred`, which releases at
  once outside a release, so freeing keeps constant stack however Rust
  and Idris cells interleave.
- **Never persistent, never in a frame.** No foreign call runs at compile
  time, so no static datum holds one; a top-level value holding a Rust
  value is a static memo cell whose forced value is counted and released
  at exit by `idris_rt_caf_release`. `idr.con`'s `stack` property builds
  Idris data in a frame (`IdrOps.td`), and the shim makes every foreign
  cell, so none is a stack cell.
- **Dialect:** a type `!idr.foreign<"T">`, named by the Idris qualified
  name of the binding's external type (the compiler never sees a Rust
  path, §2), counted at every grade by implementing the value-facts
  type interface (`isCounted`; `Idr_CountedType` reads it,
  `IdrOwnershipOps.td`). It is no data type and has no constructors.
- **Frontend:** `Ty` (`compiler/src/IdrisMLIR/Types.idr`) gains
  `ForeignT`, with the external type's identity; `coreType`
  (`Frontend/Translate/Types.idr`) maps `Foreign t` to it through
  `Foreign`'s hook.

### 9.2 The call

`idr.rust.call "symbol"(%args...)` (*decision* unless marked):

- **Callee:** the shim's symbol (§6), an inherent string property. A shim
  is part of the runtime and never an `idr.func`, every one of which has a
  body (`lib/IR/Func/Func.cpp`); the lowering declares it as it declares
  runtime functions. It is not an `Idr_Runtime<symbol>` op (`IdrBase.td`),
  whose symbol is one per op class with a prototype idris-mlir-tblgen
  writes; a Rust call's symbol is one per binding.
- **Signature:** an inherent `function_type`, the declaration's Idris type
  lowered, with the modes as grades: `&T` a borrow, a by-value `T` owned
  at quantity one, `&mut T` a borrow at quantity one given back in the
  result. No permission is added: the quantity says the handle comes back,
  and aliasing is read from `excl` grades. The verifier checks operands
  and results against it, as `idr.call` is checked against its callee;
  `idr-rc` and the ownership verifier read its grades as a callee's.
- **Purity from the type** (*audit*): a pure binding is a bodiless
  `%extern` of a pure type, as `Array/Core.idr`'s pure operations are, so
  its call takes no world and needs no `unsafePerformIO` wrapper; an
  effectful one takes and gives the world in its signature. The op
  declares its effects through `MemoryEffectOpInterface` on the IO, crash
  and divergence resources, as `idr.call` does (`lib/IR/Effects.cpp`):
  IO exactly when its signature carries the world, crash and divergence
  always (a crate may panic or loop). It is not `Idr_ObservableIO`: a
  memo label that reaches a pure binding memoizes, by the manifest's
  claim.
- **Flow:** it implements the flow interface for its closure operands
  (§7.7), and is the only op here that carries one.
- **Lowering:** an `llvm.call` of the symbol, each operand as its runtime
  word, after the alias and move tests its grades leave (§8.3). The
  convention is the runtime's C ABI: words in, borrowed unless the grade
  says consumed, an owned result (`runtime/idris_rt.h`). No Rust calling
  convention is computed anywhere.

### 9.3 Linking

**The runtime's own link** (*decision*). The shim archive is one more
input of `readRuntime` and `linkRuntime` (`include/idr/Driver/Runtime.h`),
read after the runtime's, with no step of Rust's own:

- each member is checked and prepared as the runtime's are
  (`lib/Driver/ReadRuntime.cpp`): the program's triple; bitcode in every
  member, so a crate's assembly object is refused, naming it; no static
  constructor (`LinkOnlyNeeded` links appending globals into every
  program); no appending global (`unsupported (runtime)`); `used` markers
  dropped;
- `namesApart` keeps the program's names apart from it, and it joins with
  `LinkOnlyNeeded` before `retarget` and internalization, so a binding's
  call and the Rust under it are optimized as one function;
- a per-program archive is never prepared, so it takes the runtime's
  archive case: each body the program reaches becomes a definition
  compiled with the program. That holds at both of 0008's steps with no
  third case (0008 §3.5), and Rust's functions fall in the runtime's group
  by their dotless names (§6). A step of Rust's own would be a third case
  and a second representation of a part of the runtime.

`std`'s `lang_start` never runs: the entry is `idris_rt_start`, and what
`std` sets up there (*recalled*: arguments on some Linux targets, the
stack guard, `SIGPIPE`) is the runtime's job; no binding exposes
`std::env` or `std::process`, and R0 records what `std` does without it.

**One archive per program:** one surface, one shim crate, one `std`, one
`#[global_allocator]`, one panic runtime. Two archives from two graphs
would bring two `std`s whose symbols collide or two allocators on one
heap.

- **Contents and flags:** the shim crate, its dependencies and `std`,
  each member with its bitcode, built with the entry's bitcode flags
  (as `IDRIS_MLIR_RUNTIME_BITCODE_FLAGS` gives the runtime fat LTO objects
  on ELF and embedded bitcode on Mach-O: `-Clinker-plugin-lto` or
  `-Cembed-bitcode=yes`, *recalled*, settled at R0), `panic = "abort"` and
  v0 mangling. `std` comes from a sysroot the bootstrap builds once per
  target entry with `-Zbuild-std` (§14).
- **Target entry:** two new facts, `IDRIS_MLIR_RUST_TARGET` (the Rust
  triple, with the entry's deployment target) and
  `IDRIS_MLIR_RUST_BITCODE_FLAGS`. On Linux, Rust's self-contained musl
  is not used (`-Clink-self-contained=no`): the program links the pinned
  musl 1.2.6 (`toolchain.lock.json`), whose ABI R0 checks against the
  `libc` crate's (*recalled*: Rust targets musl 1.2.3 or later).
- **C inside `-sys` crates**, the only C in a program: built by the
  crate's `cc` script with `CC` the pinned clang, the target's sysroot and
  the entry's bitcode flags, so it joins too; a `-sys` crate over C++ (a
  solver for 0013's T8) uses the pinned clang++ and the pinned static
  libc++, never the system's. A build script that downloads fails, since
  the build is offline, and is named in the report.

### 9.4 One allocator

The shim crate's `#[global_allocator]` calls the runtime's raw blocks,
`rt::alloc::allocate`, `reallocate` and `release`
(`runtime/Alloc/Alloc.h`), with an aligned allocation added; the runtime
exports none of them as a C entry today, since nothing calls one. Rust
and Idris share one heap and its size classes. The entries carry LLVM's
allocation attributes (`allockind`, `alloc-family`), so LLVM can delete
an allocation and free pair it sees whole after the runtime link.

### 9.5 Diagnostics

(*audit*) The generator's reasons are its own closed set, printed in its
report and its failures: `pointer`, `send`, `lifetime`, `async` and `cfg`
for an item left out, and a failure naming both packages for a manifest
conflict or the crates for a graph that enables tokio's runtime (§12).
None is a case of the dialect's `Rule` enum (`IdrBase.td`), which names
the refusal of a program: an item left out is absent from the surface, so
a program that calls it fails Idris's name resolution, and a failing
manifest stops the build before the compiler runs. This deletes the
earlier `rust` and `rust graph` rules, whose sub-reasons were text.

## 10. Protocol overlays

The handles say who owns a value and whether it may change, not which
state it is in (a statement prepared or mid-iteration, a transaction open
or done). Brady's resource-indexed types add that on top (*decision*), as
ordinary Idris over the generated functions, which needs no trust:
`data Tx : TxState -> Type`, `begin` giving a `Tx Open`, `commit` and
`rollback` consuming one; a `Tx` dropped unfinished rolls back at its
release, as rusqlite's `Drop` does. An overlay lives in the project that
uses it (*decision*): an installed package outside the table is never
reached, and nothing proposes trust for third-party Idris packages. A
library-level `ST` is not adopted (§15).

## 11. Compile-time evaluation

No Rust call runs at compile time. Static normalization runs on the type
checker's interpreter (0010), where code that reaches a world is stuck and
runs at run time (0010 §2). An effectful binding takes the world; a pure
one is a bodiless `%extern` the interpreter has no meaning for, since its
meaning is a shim in the program's archive and never in the compiler's
process, so its call is a neutral term, as any opaque constant is, and
runs at run time.

## 12. Async: 0007's reactor is the executor

Async Rust is 0007 §10's design and its P3, after its P2: the executor is
the shard's reactor, a future is a task frame, and `Rust (FutT a)` is a
foreign cell (§9.1) polled through a shim with the task's waker; P3 needs
R1 and R2 first, and 0007 D12's rule says which crates work. This
proposal's half:

- **I/O traits:** Rust's async I/O traits (`tokio::io::{AsyncRead,
  AsyncWrite}`, `hyper::rt::{Read, Write, Timer, Executor}`, smithy's
  connector and sleep traits; *recalled*) are implemented in `Rust.Core`'s
  shim over the runtime's sockets and timers, with buffers the runtime
  owns until completion.
- **The refusal:** a graph that enables tokio's `rt`, `net` or `time`
  features fails the generator with the reason `async` (§9.5), since those
  crates call tokio's runtime directly (`tokio::spawn`, as reqwest and
  sqlx do; *recalled*).
- **Never** a tokio island (§3). Until P3, a synchronous crate with an
  I/O-free core (rustls's `Connection`, `httparse`) talks to the network
  over sockets the program owns.

## 13. Testing

- A pool `tests/programs/rust/`: each fixture has a `rust.toml`, and its
  `run` generates, compiles, runs and checks committed expected files.
- A fixture per generator reason and per runtime check (§8.3), with
  `expected-crash` holding the message.
- Drop timing: a destructor with a visible effect appears at a fixed
  point of stdout. `IDRIS_RT_LIVE=1` reports zero live cells at the end
  of every fixture, foreign cells included.
- Properties, never op sequences: `tests-nothing=@f` holds of a loop over
  an exclusive handle; on the object, a shim R0's fixture says is inlined
  leaves no relocation naming its symbol, read beside `tests/lib/heap.sh`'s
  `object_imports`; a result handle's cost is a bench record at R2, not a
  gate.
- Determinism: every fixture's executable is byte-identical across thread
  counts (`tests/determinism`), the archive built once per surface.
- The generator's own: determinism, the report, the trust digest (a hand
  edit makes the package untrusted), slicing (an unnamed crate's type
  bound as a handle and nothing else of it), both targets (a
  `#[cfg(target_os = "macos")]` item reported, the rest bound), one graph
  (a library's manifest and the application's give one archive; a
  conflict fails naming both), and `rust.surface` drift failing the build.

## 14. Plan

Every stage is **AFTER-SELF**. It builds on the pipeline as it is; each
stage ends with every suite AGENTS.md names, `tests/determinism`, and the
new pool green on both target entries, and lands as a cutover with
nothing kept beside it.

- **R0, the toolchain** (AFTER-SELF; needs only the bootstrap). A `rust`
  entry in `toolchain.lock.json` and a step in `tools/bootstrap.sh`: an
  official build with its bundled LLVM, whose major
  `tools/verify-pins.sh` checks is not newer than ours (`accept: "24"`),
  since newer LLVM reads older bitcode; rustc does not build against our
  llvm-main commit, and building it so is not planned. Which build is
  §16's question 1. The bootstrap builds `std` once per target entry, with
  the entry's flags, into a Rust sysroot under `.toolchain/`; a program's
  cargo build compiles only its own crates, in `build/rust/`, its only
  cache (*decision*: `std`'s flags are the entry's, and ccache does not
  compile Rust). Exit: a hand-written one-function binding runs on both
  targets, its bitcode reads in the pinned LLVM, its call is inlined
  (§13), no archive function has a dot in its name, no program build
  rebuilds `std`, and the record of §9.3's facts (`std`'s constructors,
  appending globals and assembly members; life without `lang_start`) and
  of §16's question 2 is written.
- **R1, foreign cells and the generator** (AFTER-SELF; after R0): the
  foreign kind and its freeing, `!idr.foreign`, `idr.rust.call`,
  `Bindings` trust and admission by origin; generator v0 (free functions,
  opaque `Shared` types, §7.2, `Option` and `Result` through result
  handles, `[select]` and slicing, rustdoc per entry and the intersection,
  `rust.surface`); one graph per program. Fixtures: `regex`, `sha2`, and a
  library with a manifest used by an application that binds a second
  crate.
- **R2, mutation and ownership** (AFTER-SELF; after R1): `Rust t`,
  `freeze`, `&mut`, moves, `&mut` borrows, the slot flag and §8.3 with its
  fixtures, struct accessors and enum views. Fixtures: `serde_json`,
  `rusqlite` with `bundled` (C under Rust, by the pinned clang), a
  `HashMap` instance.
- **R3, generics and callbacks** (AFTER-SELF; after R2): `IdrisValue`
  containers with `RustKey` and the cycle edge, callbacks through the flow
  interface (the sum's box decided with fit), `i128`. Fixtures: a
  capturing callback, one whose argument the closure ignores, a stored
  `'static` callback on a `Shared` handle, and an Idris key type for
  `RMap` in `tests/reject`.

Size (*conjecture*): generator 4–6k lines of Rust; `Rust.Core` 0.5k of
Idris; frontend 1–1.5k; dialect, lowering, driver and runtime 2–3k;
bootstrap and tests about 1k.

## 15. Alternatives rejected

- **Embedding `rustc_driver` to call the unstable Rust ABI** (`layout_of`,
  `fn_abi_of_instance`): a second LLVM in our process, `rustc_private`
  moving every six weeks, and nothing bought, since every value crosses
  as a word through a shim LTO inlines.
- **Building MLIR from Rust's LLVM fork:** our patches are upstream pull
  requests against llvm main (PINS.md), which a fork's base would not be.
- **Bindings from C headers, as hs-bindgen does:** this design reads no C
  header. Three of its ideas are taken in the form a static two-target
  build needs: shared binding specifications as one graph and one surface
  per program (§5), selection and slicing (§6), and the committed record
  of the API (`rust.surface`); its per-target question is answered for
  the API by the intersection (§6). rust-bindgen and cxx are the closer
  relatives.
- **A library-level `ST`** as the ownership layer: ownership a second
  time beside the grades, Idris 1's weak error messages, and elaborator
  reflection user code cannot have; Brady's idea survives as overlays
  (§10).
- **A C FFI, first or ever:** C headers state no ownership, lifetime or
  thread-safety, so every binding would need annotations nothing checks;
  the `-sys` crates and their safe crates have done that work.
- **A tokio island** (§3, §12); **shims that build Idris data** (layouts
  are per program, §7.4); **a `linkRust` step** (§9.3); **an exported
  apply entry per callback sum** (a public function beside the root);
  **an `idr.func` declaration as callee** (every `idr.func` has a body);
  **a `%foreign` spec per binding** (AGENTS.md admits none beyond base's);
  **a registry entry per binding** (§8.1).

## 16. Questions for the owner

1. **The Rust pin.** AGENTS.md pins every dependency but llvm-project,
   modular and Idris 2 to its latest release, and the earlier text pinned
   a nightly for rustdoc's JSON and `-Zbuild-std`. Default: rustc's latest
   stable release, with those unstable flags enabled by
   `RUSTC_BOOTSTRAP=1` only where the bootstrap builds `std` and where the
   generator runs rustdoc (*recalled*; settled at R0). The alternative is
   a nightly, which the pin policy would then name.
2. **AGENTS.md's target rules and third-party crates.** No inline
   assembly, no cpuid outside the startup check, and OS calls behind the
   runtime's platform layer bind our code and what we vendor (simdutf's
   own detection was replaced by the startup check's, PINS.md
   `simdutf-dispatch`).
   A crate brings its own CPU detection (`std_detect`), assembly (refused
   by the reader, §9.3) and direct OS calls (`std`, a `-sys` crate's C).
   Default: the rules bind the tree, not a program's crates, which are the
   foreign world with `std` as their platform layer; R0 records what the
   fixtures' graphs bring.
