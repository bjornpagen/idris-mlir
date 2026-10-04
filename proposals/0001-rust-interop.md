# Proposal 0001: Rust as the one foreign world

Status: proposed, 2026-10-04, at 6fda6d8. Nothing here changes the
compiler. Once the user decides on it, it becomes a
`findings/decision-*.md` note and a staged plan (§14).

The brief: give programs the Rust ecosystem as their way out to the rest
of the world (databases, HTTP, crypto, parsers, cloud APIs), and reach C
only through Rust (`libc`, the `-sys` crates and the safe wrappers already
written over them). Embed one pinned rustc, link statically and accept the
monster we are building, as Zig accepts LLVM. Rust is a library layer. It
never hosts the runtime: no tokio, and no Rust scheduler. Every runtime
concern stays in Idris and in `runtime/`.

Claims are marked as in `findings/`. **read**: the path given, at
6fda6d8. **recalled**: from memory of upstream Rust and its tools, not in
`sources/`; treat it as approximate and check it at R0. **decision**:
what this proposal decides, for the user to accept or change.
**conjecture**: an estimate.

## 1. Lead

The compiler already has the three things a Rust interface needs, and it
built them for its own reasons:

- **Reference counting with exact frees.** Every runtime value is a
  counted cell, freed when its last reference dies (`runtime/idris_rt.h`,
  `rt.rc:freeing`). A Rust value with a destructor is one more kind of
  cell whose release runs that destructor. Drop order is then
  deterministic, which is what a Rust programmer expects. A tracing
  collector cannot give it.
- **Ownership as grades in the types.** Grades are view (borrow), owned
  and exclusive (`!idr.excl`, proved by `idr.ownership:exclusive` on
  MLIR's solver and checked after every pass; IdrOps.td:126-150,
  1326-1460). Rust's `&T`, `T` and the uniqueness `&mut T` relies on are
  these three grades. The README's central promise (in-place update with
  no runtime test, or a rejection with a named reason) is the same proof
  obligation a `&mut` argument puts on the caller.
- **A runtime linked as bitcode into every program.** `linkRuntime`
  (Driver/LinkRuntime.cppm) joins the prepared runtime's bitcode to the
  program's module before O3, `LinkOnlyNeeded`. Rust code compiled to
  bitcode by a rustc on the same LLVM joins the same way, so a call into
  Rust inlines across the language boundary, in both directions.

What the compiler lacks is equally specific: a value kind for foreign
objects (the runtime has five kinds and no finalizer), a call op whose
callee is not a runtime primitive, a toolchain step for rustc, and a way
for library code that is neither the Prelude, base nor `libs/` to be
trusted (`Registry/Libraries.idr`: anything else is `Untrusted`, loaded
but never reached).

The design in one paragraph. A project names the crates it uses in
`rust.toml`. A generator, `idris-mlir-bind`, reads each crate's public API
from rustdoc's JSON and writes two things from one description: an Idris
package of bindings, and a Rust crate of shims. The bindings are plain
Idris over `%foreign` definitions, each with two specs: `rust:` for this
compiler and `C:` for the stock Chez backend. Chez loads the shims as a
shared library, so the oracle runs the same program. This compiler gives
the `rust:` convention one meaning through the registry: a call of a
runtime-ABI shim, compiled by the pinned rustc to bitcode and joined to
the program before O3. Rust values live in counted foreign cells.
Ownership maps onto the existing grades:

- `&T` is a view;
- `T` by value is a consumed owned reference;
- `&mut T` is a quantity-1 thread of a mutable handle, in the style of
  `Linear.Array`;
- a value frozen into `Shared` gets a read-only API, and a borrow taken
  from it holds a counted reference to it, so the count is the borrow
  checker.

What the type system cannot see is checked at runtime with a crash that
names it (aliased arguments, a re-entrant callback, an abandoned mutable
borrow), as an index out of bounds crashes today. The compiler deletes
each check it proves redundant.

## 2. The rules this design keeps

Each is from AGENTS.md or a decision in `findings/`, and each constrains
the design:

1. **The Idris 2 language does not change**, and third_party/Idris2 stays
   unmodified (decision-linear-libraries.md). Idris has no pragma for
   importing a crate, so crates are declared outside Idris source
   (`rust.toml`), and bindings are an ordinary package.
2. **User code has no pragmas and no escape hatches**
   (`Frontend.Profile.checkPragmas`, `checkReachable`): no `%foreign`, no
   `%runElab`, no `believe_me`. Bindings must therefore be *trusted
   library* code, and user code calls them as ordinary functions.
   Elaborator reflection in user code is unavailable, which rules out
   generating bindings at elaboration time.
3. **Features are libraries; the registry may make them faster or
   stricter, never different** (Registry.idr). The bindings must have a
   meaning the stock Chez backend runs unchanged, and the registry's
   `rust:` hook is a faster lowering of that same meaning.
4. **Chez is the oracle, not the specification.** Every deliberate
   difference is a named class in `tests/lib/chez-divergences`.
5. **One thing, one representation.** A crate's interface is described
   once. The Idris bindings, the shims and the compiler's lowering are
   derived from it, and the compiler reads nothing but the Idris types of
   the bindings.
6. **Facts Idris proved live in types**, never in discardable attributes
   (`!idr.lin`, `!idr.excl`). Ownership modes at a Rust call are grades on
   the callee's parameter types.
7. **Reject what cannot be compiled, with a named rule; never miscompile.**
8. **The heap stays acyclic** (decision-acyclic-heap.md). A Rust
   container that holds Idris values and can be mutated is a mutable-cell
   edge of the type reachability graph.
9. **Two first-class targets**, x86_64 Linux (musl, static PIE) and arm64
   macOS, decided in one place, the target entry in CMakeLists.txt.
10. **No primitive has an implementation in Idris.** A shim is the one
    meaning of its Rust call at runtime. Compile-time evaluation reaches
    it only through the JIT (§11), never through an Idris re-implementation.

## 3. Scope

**In:**

- synchronous Rust APIs: free functions, inherent methods, trait methods
  of the traits in §7.5, constructors, and the destructor;
- C reached through Rust (`-sys` crates and their C sources, built by the
  pinned clang);
- generic Rust APIs at instances the manifest names, or at Idris element
  types through `IdrisValue` (§7.6);
- Idris closures passed as Rust callbacks that are called before the call
  returns (§7.7).

**Out, by decision:**

- **Async Rust executed by a Rust runtime (a tokio "island").** It would
  give a second scheduler and I/O the runtime cannot see.
- **Rust code that calls into Idris from another thread.** The runtime is
  single-threaded and its counts are plain arithmetic (`idris_rt.h`).
- **Rust types as Idris values without a handle.** The exception is the
  scalars and strings of §7.2, and the `value` types the manifest copies
  across (§7.4).

**Later, staged (§14):**

- async Rust driven by the Idris runtime's own futures, once that runtime
  has them (§12);
- compile-time evaluation of calls the manifest declares pure (§11);
- protocol overlays in Brady's style (§10).

## 4. The pieces

```text
rust.toml ──► idris-mlir-bind ──► rustdoc JSON of each crate (pinned rustdoc)
                    │
                    ▼
              the surface (one description per crate graph)
               ┌────┴──────────────────────────┐
               ▼                               ▼
   build/rust/idris/  Idris package     build/rust/shims/  Rust crate
   Rust.<Crate>.* modules               two entries per item: rust: (runtime ABI)
   %foreign "rust:..." "C:..."          and C: (Chez's C FFI)
               │                               │
               │                    cargo (pinned, offline, vendored)
               │                    ┌──────────┴───────────┐
               ▼                    ▼                      ▼
   idris-mlir frontend    libidrs.a: every member     libidrs.so / .dylib:
   (registry: rust: hook) carries bitcode             the Chez oracle's
               │                    │
               ▼                    ▼
   idr dialect ──► idr-rc ──► idr-lower ──► linkRuntime + linkRust ──► O3 ──► link
```

- **`rust.toml`** is the project's manifest (§5). It sits beside the
  project's `.ipkg`, since Idris's ipkg has no field for it.
- **`idris-mlir-bind`** is the generator (§6). It is a Rust program
  in `foreign/rust/bind/`, built by the pinned cargo, because the
  interface it reads is Rust's and `rustdoc-types` is the reader rustdoc
  publishes (recalled).
- **The surface** is the generator's one intermediate description: per
  crate graph, every bound item with its Idris type, the ownership mode
  of each parameter and result, and the shim symbols. The two outputs are
  printed from it and nothing else, so they cannot disagree.
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

# Rust types copied into Idris data instead of held behind a handle:
# plain structs and enums whose fields are all copyable across (§7.4).
[values]
"regex::Match" = { fields = ["start", "end"] }
```

- Cargo resolves the crate graph once, at generation, into `rust.lock` (a
  Cargo.lock), which the project commits. `cargo vendor` then puts every
  source under `build/rust/vendor/`, and every later build is offline.
  Generation is the one step that reaches crates.io.
- Nothing is bound that the manifest does not name. The default for a
  crate is every public item whose types §7 can map; an item that cannot
  be mapped is listed in the generator's report with its reason, never
  silently dropped.

## 6. The generator

**Input.** `rustdoc --output-format json` (nightly, `-Z
unstable-options`; recalled) of each named crate, run by the pinned
toolchain. That JSON carries:

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

**Output, per crate graph:**

- `build/rust/idris/rust-<graph>.ipkg` and `Rust/<Crate>/*.idr`: the
  binding package, compiled and installed per project as `libs/` is per
  checkout;
- `build/rust/shims/`: the shim crate, with `Cargo.toml` and one source
  file per bound crate;
- `build/rust/report.txt`: every public item not bound, with its reason;
- `build/rust/surface.digest`: the digest of the surface, which trust
  checks (§8.1).

**Determinism.** Items are emitted in path order, symbols are derived from
paths and the graph's digest, and timestamps are never written.
`tests/determinism` covers the generator as it covers the compiler.

**Symbols.** `idrs_<graph8>_<crate>__<path>__<item>` for the runtime-ABI
entry, and the same with `__chez` for the C entry. `<graph8>` is eight hex
digits of the surface digest, so two projects' shims never collide in one
link.

## 7. The surface: how Rust types become Idris types

### 7.1 Handles

A Rust value of a non-copied type lives behind a handle. Two handle types
exist, after `Linear.Array`'s `Array` and `IArray` (**decision**):

```idris
||| Rust.Core. A Rust value of type t (an [external] phantom naming it),
||| mutable, threaded at quantity 1: every &mut method takes it and gives
||| it back, so the one object is updated in place.
export
data Rust : (t : Type) -> Type where
  MkRust : GCPtr t -> Rust t

||| A Rust value frozen: only its &self methods, shared freely. A borrow
||| taken from it holds it, so it lives as long as the borrow.
export
data Shared : (t : Type) -> Type where
  MkShared : GCPtr t -> Shared t

||| The linear phase ends.
export
freeze : (1 _ : Rust t) -> Shared t
freeze (MkRust p) = MkShared p
```

- **A type with no `&mut self` method is born `Shared`.** `regex::Regex`
  is an example; the generator never offers `Rust Regex`.
- **`Shared t` to `Rust t` exists only as a clone**, for `t: Clone`
  (`thaw : Shared t -> Rust t`, a Rust `clone`). An in-place thaw would
  need "nobody else holds it". The count could answer that on this
  compiler, but not on Chez, whose collector frees on its own schedule,
  so the two backends would differ in which programs crash.
- **`GCPtr` is upstream's own vocabulary**: PrimIO's "pointer with a
  finaliser" (PrimIO.idr:59; read). On Chez it is exactly that:
  `prim__onCollect` registers the Rust drop shim with the collector. On
  this compiler a `GCPtr` of a Rust type is a counted foreign cell (§9.1)
  whose last release runs the drop shim. The meaning is the same (the
  destructor runs once, after the last use). The timing differs, and that
  is the divergence class `rust-drop-timing` (§13).

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
handle, as `Linear.Array` has `read` and `iread`:

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
- **Value types** named in `[values]` are copied into an Idris record or
  data type. They must be plain: every field public and mappable, no
  `Drop` impl, and an enum's variants all mappable. One example is
  `regex::Match`, as `start` and `end`.
- **Every other Rust enum is a handle with a generated view**:

  ```idris
  ||| From serde_json::Value.
  public export
  data ValueView = Null | Bool Bool | Number (Shared NumberT) | String String
                 | Array (Shared (VecT ValueT)) | Object (Shared (MapT ValueT))

  export
  view : Shared ValueT -> ValueView
  ```

**How compound values cross, on both backends (decision).** Chez's C FFI
returns only scalars, strings and pointers, and a shim cannot know how
idr-lower lays out `Maybe Int64` in a given program: layouts are decided
per program (Layout/). So the bindings never move Idris data through a
shim.

- **Results:** a compound result is returned as a *result handle* (a Rust
  value of the `Option`, `Result` or tuple), and the binding's plain Idris
  takes it apart through accessor shims (`tag`, `some`, `ok`, `err`, the
  fields) before the handle dies. On this compiler, all of that inlines
  after `linkRust`: the result cell never escapes its frame, so `idr-stack`
  places it in the frame (§9.1, R2), and LLVM sees through the rest.
- **Arguments:** a compound argument is built as a Rust value first, by a
  builder shim, and passed by value.

This is one path for both backends, with the cost removed by the
optimizer, not by a second lowering.

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

Idris interfaces are resolved at compile time here (README, "What compiles
today"). Each generated instance is a monomorphic implementation over one
handle type, so it compiles like any other.

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
    `idris_rt_inc` and its `Drop` is `idris_rt_dec`.
  - It is `!Send` and `!Sync`: Idris values never leave their thread
    (§3), and rustc enforces that in the shim crate itself. The generator
    rejects an API whose bounds would need it to cross
    (`unsupported (rust send)`) before rustc does.
  - Keys and orderings over Idris values (`Hash`, `Ord` on an
    `IdrisValue`) would need a call back into an Idris interface at
    runtime, which the profile rejects (`unsupported (runtime closure)`).
    Keyed containers take `K` from §7.2 only.
  - A mutable container of `IdrisValue` is a mutable-cell edge for the
    acyclic-heap check (§2.8). An `RVec Node` whose `Node` can reach the
    same `RVec` is `unsupported (cycle)`, named as that check names it.

### 7.7 Callbacks

A parameter of type `impl Fn(A) -> B`, `impl FnMut`, `&dyn Fn` or a
generic `F: Fn(A) -> B` takes an Idris function `A -> B` (or
`A -> IO B` for an effectful item).

- **The shim side.** The shim crate has one wrapper type per callback
  signature, `IdrisFn<A, B>`. It holds the closure's reference and
  implements `Fn` by calling the closure's apply entry.
- **The compiler side.** Closures of known labels are defunctionalized
  into sums (`idr-defunctionalize`). For each sum that reaches a Rust
  callback, the compiler exports its apply function under a symbol the
  `rust:` hook names, with the runtime's ABI (§9.2).
- **On Chez,** a function argument to a C function is a callback the
  backend already builds (Chez.idr's `callback`; read).
- **Constraints:**
  - A callback is called only before the Rust call returns. An API that
    stores one (an event handler kept past the call) needs `'static`, and
    it is bound only on a `Shared` handle whose cell then holds the
    closure.
  - The closure's sum is one more field type for the cycle check.
  - Re-entrancy (the callback reaching the same handle) is checked (§8.3).

## 8. Soundness

### 8.1 Trust

Bindings contain `%foreign` and `unsafePerformIO`, so they must be
trusted code (§2.2). Trust never follows from a name
(Registry/Libraries.idr). It follows from where a module's TTC was built
(`Home`).

**Decision:** a new `Home`, `Generated`, for the binding package that
`idris-mlir-bind` wrote under the project's `build/rust/idris/`, and a new
`Lib`, `Rust`, its origin.

- **What makes it trusted:** the package's sources hash to the digest the
  generator recorded in `build/rust/surface.digest`, and the frontend
  checks that digest. A hand edit makes the package `Untrusted`, so its
  definitions can be loaded but not reached, with the reason named.
- **Its `%foreign` definitions** may use the `rust:` and `C:` conventions,
  and nothing else.
- **`Rust.Core` (`libs/mlir-rust`)** is `InHouse` like `mlir-linear`. It
  joins the table as a row in `moduleOrigin`.
- **`GCPtr` and `prim__onCollect`, for `Rust` and `InHouse` origins
  only.**
  - `PrimIO` admits `GCPtr` (`admittedFromPrimIO`, extended per origin).
  - `Prelude.IO`'s `%extern prim__onCollect` gets a registry entry, with
    the hook `ForeignOwn`.
  - User code still reaches neither: an `%extern` without an entry is
    rejected where it is reached, as today, and the entry is valid only
    from those origins.

### 8.2 What the types guarantee

- **Liveness.** A Rust value lives while any Idris value refers to its
  cell, and a borrow handle refers to its parent's. So no shim ever sees a
  dangling reference. This holds on both backends: by the count here, and
  by the collector on Chez.
- **No mutation under a shared borrow.** Borrow handles exist only on
  `Shared`, which has no `&mut` API.
- **Moves.** A by-value parameter is quantity 1 in the binding. On this
  compiler the move reads the cell's grade: an exclusive cell is moved out
  with no test, as `idr.take` does for boxes, and a cell that may be shared
  is tested at runtime (§8.3).

### 8.3 What is checked at runtime, and named

Three things escape the types. Each is checked in the shim, so Chez and
this compiler crash alike, with the same message (**decision**):

1. **Aliased arguments.** A call with a `&mut` parameter and another
   reference parameter of the same Rust type compares the payload
   pointers: `rust: Vec::append was given the same Vec twice`.
2. **Re-entrancy and abandoned `&mut` borrows.** Each cell's Rust payload
   is `Slot<T> { state: Cell<u32>, value: T }`, a `RefCell`-like flag.
   - The flag is set during a call that takes Idris callbacks, and while
     a `&mut` borrow handle lives.
   - An access that finds it set crashes:
     `rust: the Vec is mutably borrowed`.
   - Calls without callbacks do not touch the flag: the program is
     single-threaded and no Idris code runs inside them, so nothing can
     re-enter.
3. **Moving out of a shared, non-`Clone` value.** On this compiler the
   test is `idris_rt_is_unique`. On Chez nothing counts, so the shim moves
   out and leaves the slot empty, and a later access crashes:
   `rust: the Vec was moved`. A correct program behaves the same on both.
   A program that moves out of a shared value crashes on this compiler at
   the move and on Chez at the next use, which is the divergence class
   `rust-move-shared` (§13).

**The compiler removes what it proves.**

- A move whose operand is `!idr.excl` needs no uniqueness test.
- Aliasing of a call's arguments is decided statically when the operands
  are distinct exclusive values.
- A flag write with no reader in between folds away after inlining.

These are faster lowerings, never different ones. A stricter mode,
`--static-borrows`, would turn each residual check into a rejection,
`unsupported (uniqueness)`, naming the operand. That is the same promise
the README makes for in-place reuse, applied to Rust.

### 8.4 Panics

The shim crate builds with `panic = "abort"` and installs a panic hook at
the first call.

- **On this compiler,** the hook calls `idris_rt_crash` with
  `rust panic: <message>`. That flushes the program's output, writes
  `idris-mlir: rust panic: ...` and exits with `IDRIS_RT_CRASHED`, as
  every crash does.
- **On Chez,** the shared library is built with `panic = "unwind"`. The
  `__chez` entry catches the panic (`catch_unwind`) and returns an error
  code, and the binding crashes through the trusted library's crash path
  with the same message.

A panic is a crash with the panic's message, as an index out of bounds
is.

### 8.5 Threads

The runtime is single-threaded: counts are plain arithmetic, and the
live-cell count is per thread (`idris_rt.h`). Rust code may start threads
of its own (rayon, a connection pool's reaper), and they may allocate,
since the allocator is thread-safe (§9.4). But nothing Idris reaches them:

- `IdrisValue` and `IdrisFn` are `!Send`, so rustc rejects any API that
  would move one to another thread;
- handles are `!Send` on the Idris side, because a handle is an Idris
  value.

A thread-per-core runtime would keep this rule as it is: Idris values
stay on their core.

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
- **Freeing:** `rt.rc:freeing` gains one case. A dying foreign cell's
  drop entry runs before its memory is freed.
- **Drop glue that releases Idris values** (`IdrisValue`'s `Drop`) does not
  call `idris_rt_dec` recursively. It pushes onto the current dying list
  through a new runtime entry, `idris_rt_release_deferred`, so freeing
  still takes constant stack however Rust and Idris objects interleave.
- **Persistent foreign cells never exist.** Compile-time evaluation never
  makes one (§11), so static data never holds one.

**Dialect.** A counted type `!idr.foreign<"path::Type">`, a member of
`Idr_CountedValueType`, at every grade like the others. Layout/ gives it
the cell above, and `idr-stack` may place it in a frame like a box.

**Frontend.** `Ty` gains `ForeignT ForeignId`. `coreType` maps a `GCPtr t`
whose `t` is a binding's `[external]` phantom to it, through a new hook,
`ForeignType`, which the frontend asks for as it asks `isWordType`.

### 9.2 The call

**Registry.** A new kind of key, `Convention String`, matches every spec
of a convention. It is valid only at definitions whose origin is
`Library Rust` or `Library InHouse`. One entry, `Convention "rust"`, has
the hook `RustCall`. `checkReachable` accepts a `ForeignDef` with that
hook, and still rejects every other unregistered `%foreign`.

**The convention is the runtime's own C ABI** (**decision**). A
`rust:<symbol>` shim is called exactly as idr-lower calls an
`idris_rt_*` function (Lower/RuntimeCalls.cppm), and it follows the same
ownership rule: it borrows its arguments and returns an owned result.

- **Arguments:** every value passes as its runtime word, which is a
  scalar, an `idris_rt_str *`, an `idris_rt_array *`, or a foreign cell.
  A by-value parameter consumes its reference.
- **Derivation:** the call's operand and result types are derived from
  the `%foreign` definition's Idris type and nothing else. The binding
  package is the one description, and the compiler does not read the
  surface.

No Rust calling convention is computed anywhere, in particular not
`fn_abi_of_instance`. Every value crossing is a word, and the Rust side of
the shim is ordinary Rust that rustc lowers as it lowers any Rust.

**Op.** `idr.rust.call @symbol(%world, %args...)`:

- **Callee:** a `func.func private` declaration. The parameter types of
  the declaration carry the modes as grades: a view for `&`, an owned
  reference for a by-value parameter, and a view marked for aliasing
  check for `&mut` (a new permission of the grade, not an attribute).
- **Effects:** `Idr_PerformsIO`, threading the world as every `idr.io` op
  does. It is also `Idr_MayCrash`, since a shim may panic.
- **Ownership:** idr-rc sees its operands through the callee's grades, as
  it sees a function call's. The ownership verifier checks them after
  every pass.
- **Lowering:** an `llvm.call` of the symbol, with each operand as its
  word.

The world: pure bindings run their calls under `unsafePerformIO` inside
the trusted package, as `Linear.Array` does. The forged world orders them
with every other effect, and it keeps compile-time evaluation off them
(decision-inhouse-linear.md).

### 9.3 Linking

**Driver.** `linkRust` sits beside `linkRuntime`. It joins the bitcode of
the shim archive's members to the program's module with
`LinkOnlyNeeded`, before O3, so a binding's call and the Rust code under
it optimize as one function.

- **What the archive contains.** It is built as the runtime's archive is
  for the target entry, with every member carrying its bitcode with its
  native code: the shim crate, its dependencies, and `std` itself.
- **Flags.** cargo's `-Zbuild-std`, `-Clinker-plugin-lto`, or
  `-Cembed-bitcode=yes` with fat objects, whichever the entry's object
  format needs (recalled; settled at R0).
- **What stays native.** The archive's native half resolves what LTO
  leaves.

**Target entry.** It gains two facts:

- `IDRIS_MLIR_RUST_TARGET`: `x86_64-unknown-linux-musl` or
  `aarch64-apple-darwin`, with the deployment target the entry already
  has;
- `IDRIS_MLIR_RUST_BITCODE_FLAGS`: the counterpart of
  `IDRIS_MLIR_RUNTIME_BITCODE_FLAGS`.

On Linux, Rust's self-contained musl objects are not used
(`-Clink-self-contained=no`): the program links the pinned musl in
`.toolchain/sysroot`, as everything else does. Rust's `libc` crate must
agree with musl 1.2.6's ABI, which R0 checks (recalled: Rust targets musl
1.2.3 or later).

**C under Rust.** A `-sys` crate's C sources are built by its `cc` build
script with `CC` set to the pinned clang, the target's sysroot, and
`-flto=full` (or the entry's bitcode flags), so its bitcode joins as
well. A build script that downloads anything fails, because the build is
offline. That is the rule, and a crate that needs a network build is
named in the report.

### 9.4 One allocator

The shim crate's `#[global_allocator]` calls the runtime: `idris_rt_alloc`
and `idris_rt_free`, plus new `idris_rt_alloc_aligned` and
`idris_rt_realloc` entries over snmalloc.

- Rust and Idris share one heap and one set of size classes, and any
  block may be freed from any thread (`idris_rt.h`).
- In compile-time evaluation's child, the runtime's allocations go to the
  arena already (`idris_rt_eval_begin`), so Rust's would too (§11).
- The allocator entries carry LLVM's allocation attributes
  (`allockind`, `alloc-family`), so that after `linkRust` LLVM can delete
  an allocation and free pair it sees whole.

### 9.5 Rejections

New rules in `Rule.idr`, each with a reject fixture:

| Rule | Who rejects | When |
|---|---|---|
| `rust` | the generator, through the driver | an item cannot be bound; the phrase names the item and the reason (`rust pointer`, `rust send`, `rust lifetime`, `rust async`) |
| `uniqueness` | idr-rc, under `--static-borrows` | a residual borrow or move check |
| `finalizer` | the frontend | `onCollect` with any finalizer other than a registered drop shim (stricter: the finalizer would run inside the release walk) |

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
- When third-party Idris packages become trustable (today anything outside
  the table is `Untrusted`), an overlay can ship with its crate.

## 11. Compile-time evaluation

In v1, no Rust call runs at compile time. Every binding's call threads a
world, so every function that reaches one performs IO, and `idr-eval`
leaves it alone (Passes.td: "functions that perform no IO"; read).

**Later (R4).** Items the manifest declares `pure` would get a pure op,
`idr.rust.call_pure`, with no world, and `idr-eval` would run them. The
JIT (Eval/Jit.cppm) binds nothing by name: every symbol comes from an
absolute table. So the shim's bitcode and the `std` it reaches would be
compiled into the round's JIT module along with the runtime's. Four
problems are open:

1. **Allocation:** solved already. Rust's allocator is the runtime's, and
   the runtime's is the arena in the child.
2. **Reification:** results must be of Idris types (§7.2 and value types).
   A result that is a foreign cell cannot be reified (`Reifier` has no
   layout for one), so the call stays for runtime, as a result too large
   stays.
3. **libc:** `std` calls libc beyond the JIT's table (`write`,
   `pthread_*`). Either a pure item's call graph reaches none of them,
   which can be checked at the bitcode level, or the call stays.
4. **Budget:** pure Rust code is metered as partial Idris code is, through
   `idris_rt_eval_tick` at loop heads that idr-lower cannot insert into
   Rust code. Under a wall-clock budget instead, the call stays.

## 12. Async, later, with the Idris runtime as the executor

Async Rust is out of v1 because the runtime has no scheduler: a program is
one thread running `main` (`idris_rt_start`). When the runtime grows its
own futures (an Idris-side executor over the platform's completion I/O),
the Rust half is small:

- **Import:** a Rust future imports as `Rust (FutT a)`.
- **Polling:** the executor polls it through a shim. The `Waker`'s
  vtable pushes the Idris task back onto its run queue, and since a
  `Waker` may be woken from any thread, the wake is a post to the owning
  thread.
- **I/O:** Rust's I/O traits (`tokio::io::{AsyncRead, AsyncWrite}`,
  `hyper::rt::{Read, Write, Timer, Executor}`, smithy's connector and
  sleep traits) are implemented over the Idris runtime's sockets and
  timers, with buffers the runtime owns until completion.
- **Crates that work:** those generic over these traits (hyper 1.x, h2,
  `tokio-postgres` over a provided stream, and the AWS SDK with a provided
  connector; recalled).
- **Crates that do not:** those that call into tokio's runtime directly
  (`tokio::spawn`, `tokio::net`, `tokio::time`, as reqwest and sqlx do;
  recalled). The generator rejects any graph that enables tokio's `rt`,
  `net` or `time` features, as `unsupported (rust async)`.
- **Never:** a tokio island on threads of its own.

Until then, a synchronous crate with an I/O-free core is the way to talk
to the network. rustls's `Connection` and `httparse` take bytes in and
give bytes out, and the program owns the sockets.

## 13. Testing

- **A new pool, `tests/programs/rust/`.** Each fixture has a `rust.toml`,
  and its `run` script generates bindings, compiles, runs, and diffs
  against Chez with the shim library on its load path. `tests/lib/chez.sh`
  learns to pass the library.
- **Reject fixtures** for each rule of §9.5, named for the rule.
- **Runtime-check fixtures** (§8.3), with `expected-crash` holding the
  message, which both backends print.
- **New divergence classes** in `tests/lib/chez-divergences`:
  - `rust-drop-timing`: a destructor with a visible effect (a flushed
    file, a closed socket) runs at the last release here, and when the
    collector runs on Chez;
  - `rust-move-shared`: §8.3, case 3;
  - `rust-str-nul`: Chez passes a string to C as NUL-terminated bytes, so
    a string with an interior NUL is cut there on Chez, and whole here.
- **The live-cell count.** `IDRIS_RT_LIVE=1` reports zero live cells at
  the end of every fixture, foreign cells included: every Rust value
  dropped.
- **Properties in `mlir.expect`.** For example: no uniqueness test remains
  in a loop over an exclusive handle, and a call through a result handle
  allocates nothing after inlining. These are stated as `idr-expect`
  properties, never as op sequences.
- **The generator's own tests:** determinism, the report's contents, and
  the trust digest (a hand edit makes the package untrusted).

## 14. Plan

Each stage ends with `make check`, `make test`, `make test-idr`, and the
new pool green on both target entries.

- **R0, the toolchain.**
  - **Pins:** a `rust` entry in `toolchain.lock.json` (the nightly's date,
    its `rustc-nightly-src` tarball and SHA-256, and the LLVM major it is
    built against) and a `rust` step in `tools/bootstrap.sh`.
  - **One LLVM:** the step builds rustc, cargo, rustdoc and `rust-src`
    against the stage-2 LLVM (`llvm-config` of `.toolchain/llvm-musl` or
    `llvm-macos`). `verify-pins` checks that the LLVM majors match.
  - **Bitcode linking:** a hand-written binding of one function
    (`fn add(a: i64, b: i64) -> i64`) with both specs, called through
    `rust:` and joined by `linkRust`; its `mlir.expect` property is that
    the call is inlined.
  - **Exit criterion:** the program runs on both targets and on Chez, and
    the shim's bitcode reads in the pinned LLVM.
- **R1, foreign cells and the generator.**
  - **Runtime and dialect:** `KIND_FOREIGN` and its freeing,
    `!idr.foreign`, `idr.rust.call`, the registry's `Convention` key, and
    `Generated` trust.
  - **Generator v0:** free functions, opaque `Shared` types, §7.2, and
    `Option`/`Result` through result handles.
  - **Fixtures:** `regex` and `sha2`.
- **R2, mutation and ownership.** `Rust t`, `freeze`, `&mut`, by-value
  moves, `&mut` borrows, the slot flag and §8.3 with its fixtures, value
  types and enum views, inline foreign cells, and the `idr-stack`
  placement of result handles.
  - **Fixtures:** `serde_json`, `rusqlite` with `bundled` (C under Rust,
    built by the pinned clang), and a `HashMap` instance.
- **R3, generics and callbacks.** `IdrisValue` containers and the
  cycle-check edge, callbacks through exported apply entries, `i128`, and
  `--static-borrows`.
- **R4, pure calls at compile time** (§11).
- **R5, async on the Idris executor** (§12), when the runtime has one.

**Size (conjecture):**

| Area | Lines |
|---|---|
| Generator | 4–6k (Rust) |
| `Rust.Core` | 0.5k (Idris) |
| Compiler: frontend | 1–1.5k |
| Compiler: dialect, lowering, driver and runtime | 2–3k |
| Bootstrap and tests | about 1k |

The bootstrap's rustc build adds roughly an hour to `make bootstrap`
(conjecture).

## 15. Alternatives considered

- **Embedding `rustc_driver` in idris-mlir-cc and querying `layout_of`
  and `fn_abi_of_instance`, to call the unstable Rust ABI directly.**
  Rejected. The driver links only from Rust built by the same nightly, so
  idris-mlir-cc (C++, static on musl) would host a second LLVM in one
  process. `rustc_private` also changes every six weeks. And it would buy
  nothing: with every value crossing as a word through an `extern "C"`
  shim that LTO inlines, there is no Rust ABI left to compute. rustc
  stays in the toolchain as a tool. It is pinned and built against our
  LLVM, and it decides every Rust layout and calling convention itself.
- **Building MLIR from Rust's LLVM fork instead.** Rejected for now. The
  toolchain's LLVM is upstream `llvmorg-23.1.2`, and PINS.md's MLIR
  workarounds and `upstream/`'s reproducers are pinned to it. rustc
  supports building against an external upstream LLVM of a recent major
  (recalled), so the dependency runs the other way: we pick the nightly
  whose LLVM major is ours. If no such nightly exists at a bump, LTO
  still works as long as rustc's major is not newer than ours, since
  newer LLVM reads older bitcode. `verify-pins` enforces that bound.
- **A library-level `ST`: a context of named resources in an indexed
  monad, with lifetimes as regions.** Rejected as the ownership layer.
  - It would represent ownership a second time, beside the grades the
    compiler already proves and verifies (§2.5).
  - Its error messages were the weak point of Idris 1's `ST`.
  - It would have needed elaborator reflection or a contrib-style
    library, and neither is available to user code here (§2.2,
    decision-inhouse-linear.md).
  - Brady's idea survives where it adds information the grades lack:
    protocol states (§10).
- **A C FFI first (clang, header import, ownership annotations).**
  Rejected by the brief. Rust's signatures already state ownership, and
  C's headers do not. C arrives through Rust's `-sys` crates and their
  safe wrappers.
- **A tokio island.** Rejected (§3, §12).
- **A thaw in place for `Shared` by testing the count.** Rejected for
  divergence: Chez cannot count, so the two backends would crash on
  different programs (§7.1).
- **Shims that build Idris data directly (a `Maybe` in the shim).**
  Rejected: layouts are decided per program, and Chez's FFI returns no
  aggregates. Result handles cost nothing after inlining (§7.4).

## 16. Open questions for the user

1. **Pure by default, or IO by default?** Default IO is safe, and
   `[pure]` opts in. The alternative, pure unless an item touches the
   world, cannot be decided from Rust signatures.
2. **Should `--static-borrows` become the default once R3 lands?** That
   would make Rust's borrow rules a compile-time promise, as the README
   makes in-place reuse one.
3. **`[values]` copying:** opt-in per type, as above, or automatic for
   every plain `Copy` struct?
4. **`Rust.<Crate>` as the namespace of every binding,** or the crate's
   own path (`Regex`, `SerdeJson`)?
5. **The generator in Rust.** It brings a third language into the
   repository's own sources, with its own profile, recorded in PINS.md as
   a deviation from cpp-starter. The alternative, a C++ reader of
   rustdoc's JSON, would re-implement `rustdoc-types` and follow its
   format version by hand.
