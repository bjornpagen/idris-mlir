<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Proposal 0020: Rust as the one foreign world

**Status:** parked; nothing is built. The tree has no `foreign/rust/`,
`libs/mlir-rust/`, `IDRIS_RT_KIND_FOREIGN`, `!idr.foreign` or
`idr.rust.call` (*read*, 2026-10-18). Every stage is **AFTER-SELF**:
`make self` compiles the frontend, which reaches no foreign world, so
self-hosting neither needs this nor waits for it. It is taken up when its
first consumer starts: 0007's P3 (asynchronous Rust on the reactor),
0013's T8 (solvers as Rust crates) or bumbledb's storage (LMDB through
heed, `../bumbledb/proposals/0003-idris-port.md`). Proposed 2026-10-04
(6fda6d8), parked 2026-10-12, reconciled 2026-10-14, audited 2026-10-15.
Revised 2026-10-18 at the owner's direction (§0). The revision's own
choices are *proposed* until the owner confirms them (§19).

The brief: programs reach the rest of the world (databases, HTTP, crypto,
parsers, cloud APIs) through the Rust ecosystem, and C only through Rust
(`libc`, `-sys` crates and the safe crates over them). One pinned rustc,
static linking only. Rust is a library layer and never a host: no tokio,
no Rust scheduler; every runtime concern stays in Idris and `runtime/`.

Claims are marked *read* (the path given, in the 2026-10-18 tree),
*recalled* (upstream Rust and its tools, not in `sources/`; checked at
R0), *decision* (settled earlier, or ruled by the owner), *proposed* (this
revision, for the owner) or *conjecture*. *Read* claims about Idris's
syntax were checked against the stock Idris in `.toolchain/`.

## 0. What the 2026-10-18 revision changes

The owner's rulings (*decision*): one strict way to do each thing,
representation first; ASCII identifiers only; Rust's `static` and `const`
items well supported; nothing annotated on the Idris side, since a binding
generator exists to generate the bindings; name collisions settled here.

The earlier text asked a package's author for three hand-written tables,
and all three are gone:

- **`[select]`** listed which Rust items to bind. Now every public item of
  a crate the manifest names is bound, with every type it reaches (§6).
- **`[pure]`** was a promise that a Rust function only computes its
  result (no files, network, clock or hidden state), so its Idris type
  could leave out `IO`. Rust's types do not say this, so nothing could
  check the promise, and a wrong one lets the optimizer drop, repeat or
  merge a call that writes a file. Now every Rust call is an `IO` action,
  and the only pure bindings are the values Rust itself fixes: constants
  and immutable statics (§8.7, §9).
- **`[instances]`** named a generic Rust type at chosen type arguments
  (`WordCounts = HashMap<String, i64>`). Now a generic type is bound at
  the instances the crates' own signatures use, and a generic function at
  every type of the surface that rustc confirms meets its bounds (§8.6).

What follows from removing them (*proposed*):

- **One handle.** `Shared`, `freeze`, `thaw` and the quantity-1 threading
  of `Rust t` are gone. An `IO` result is unrestricted in Idris, so the
  threading could not hold for an effectful call, and AGENTS.md makes
  linearity a matter of speed, never of correctness. Each Rust object
  carries a borrow state, as Rust's own `RefCell` does: a call that would
  break Rust's borrowing rules stops the program with a message naming
  it, and the compiler deletes the check where the grades prove the
  object unshared (§10.2).
- **Data and objects.** A Rust struct or enum whose contents are all
  public, and that promises no hidden ones, is plain Idris data, copied
  across. Everything else is an object behind a handle (§8).
- **Traits are interfaces**, generated from the impls rustdoc lists. The
  fixed table onto `Show`, `Eq` and `Ord` is gone, since those are pure
  (§8.5).
- **No Rust containers of Idris values** (`RVec`, `RDeque`, `RMap`,
  `IdrisValue`, `RustKey`). Idris values live in Idris containers, and
  the only Idris values Rust holds are callbacks (§8.8).
- **One record** of what was bound and what was left out:
  `rust.surface`. `report.txt` is gone (§12).

## 1. Lead

The compiler already has what a Rust interface needs:

- **Exact frees.** Every runtime value is a counted cell freed when its
  last reference dies, from a worklist threaded through the dying cells,
  in constant stack (*read*: `runtime/Rc/Freeing.cpp`, `Dying`,
  `releaseOwned`). A Rust object with a destructor is one more kind of
  cell whose release runs it, once, right after its last use.
- **Ownership in the types.** A grade `!idr.q<quantity, permission,
  value>` with permissions plain, borrow, own and excl (*read*:
  `IdrTypes.td` `Idr_QType`, `IdrBase.td` `Idr_Permission`); exclusivity
  solved once on MLIR's solver (`include/idr/Analysis/Ownership.h`);
  grades verified after every pass. A grade that proves a reference the
  only one deletes a run-time check (§10.2).
- **A runtime joined as bitcode.** `linkRuntime` joins the runtime's
  bitcode to the program's module with `LinkOnlyNeeded` before O3
  (*read*: `include/idr/Driver/Runtime.h`, `lib/Driver/LinkRuntime.cpp`).
  Bitcode from a rustc whose LLVM is not newer than ours joins by the
  same link, so calls inline across the boundary both ways.

What it lacks: a value kind for foreign objects (the runtime's five are
box, thunk, string, bignum and array, `IDRIS_RT_KIND_*` in
`runtime/idris_rt.h`), a call op whose callee is a per-binding shim, a
rustc step in the bootstrap, and trust for generated library code (an
installed package outside the table is `Untrusted`:
`Registry/Libraries.idr`, `moduleOrigin`).

The design. A package names its crates in `rust.toml`, in Cargo's own
dependency syntax, and writes nothing else about Rust. A generator,
`idris-mlir-bind`, reads every crate's public API from rustdoc's JSON into
one description per program, the surface, and prints from it an Idris
package of bindings and a Rust crate of shims. Every public item of a
named crate is bound, and every type its signatures reach. An item that
cannot be bound is left out with a reason, listed beside the bound ones in
`rust.surface`. A binding is an `IO` action whose Idris type is its whole
signature. The compiler lowers it to a call of a runtime-ABI shim,
compiled by the pinned rustc to bitcode and joined by the runtime's own
link (§11.3). A Rust value is either data, copied into a plain Idris
value, or an object, held by a counted handle whose last release runs its
destructor. Each object carries a borrow state, so what Rust's borrow
checker proves at compile time is checked at run time where the types
cannot see it, with a message naming the call, and the check is deleted
where the compiler proves it.

**Rust is part of the runtime** (*decision*): one static image, one
allocator (the runtime's), one crash path (a panic is a crash), one O3
over Idris, runtime and Rust, one partition into codegen bins, no loader;
no dynamic Rust library, `dlopen` or plugin, in programs or in tests.
Every decision below takes the smaller mechanism.

## 2. The rules this design keeps

From AGENTS.md:

- The Idris language and `third_party/Idris2` do not change, so crates
  are declared outside Idris and bindings are a package.
- User code has no pragma and no escape hatch (`Frontend/Profile.idr`,
  `checkPragmas`, `checkReachable`), so bindings are trusted library code,
  and none is made by elaborator reflection.
- A binding's one meaning is its shim's; there is no oracle.
- Facts Idris proved live in types, so a call's modes are grades (§11.2).
- The heap stays acyclic (`lib/IR/Verify/Knots.cpp`), so a stored
  callback is an edge for the cycle check (§8.8).
- No option or mode, so a check that stays is one behaviour (§10.2).
- Two targets, decided in the target entry.
- No primitive is implemented in Idris, and no Rust call runs at compile
  time (§14).
- Reject with a named reason.

Three more are this design's:

- **One description** (*decision*): the surface. The bindings and the
  shims are printed from it, and the compiler reads nothing but the
  bindings' Idris declarations and their origin.
- **No C** (*decision*, 2026-10-09; AGENTS.md): nothing reads a C header,
  binds a C function or lets a program declare or call a C symbol. A C
  library is a Rust `-sys` crate and, preferably, the safe crate over it,
  bound as Rust; C exists only inside such crates, compiled by their own
  build (§11.3). The shims' `extern "C"` is the runtime's word-passing
  convention between our compiled code and our generated Rust, not a way
  to C.
- **Nothing written by hand about a Rust item** (*decision*, the owner,
  2026-10-18): the manifest names crates and their Cargo features. Every
  fact a binding states comes from rustdoc's JSON or from rustc, so none
  can be wrong in a way nothing checks.

## 3. Scope

**In:** synchronous Rust APIs: free functions, associated functions,
inherent and trait methods, constructors, destructors, constants and
statics; generic items at the instances §8.6 derives; trait objects;
Idris closures as callbacks (§8.8); C libraries as Rust crates only.

**Out, by decision:**

- C directly, in any form.
- A **tokio island**: async Rust on a Rust runtime, a second scheduler
  and I/O the runtime cannot see.
- Rust calling into Idris from another thread. Counts are plain
  arithmetic; under 0007's shards a foreign thread may wake a shard and
  never touch a count, a cell or a world (0007 §3.3).
- Dynamic linking of Rust in any form.
- `unsafe` functions and `static mut`, whose contracts a binding cannot
  uphold (§11.5).

**Later:** async Rust polled from 0007's task frames, its P3 (§15);
protocol overlays (§13).

## 4. The pieces

- **`rust.toml`**, beside a package's `.ipkg`, whose format has no field
  for it (§5).
- **`idris-mlir-bind`**, a Rust program in `foreign/rust/bind/`, built by
  the pinned cargo, reading rustdoc's JSON through `rustdoc-types` at the
  version the rustc pin fixes (*decision*: a C++ reader would re-implement
  that crate; PINS.md records the deviation from upstream's layout at R1).
- **The surface**: every bound item with its Idris name, its Idris type
  and the mode of each parameter and result, and every item left out with
  its reason. Its outputs are printed from it alone, so they cannot
  disagree.
- **`libs/mlir-rust`**, in-house plain Idris over base: the module `Rust`,
  with the handle type `Rust` (§8.3) and the callback support (§8.8).
  Every binding package depends on it.
- **The support crate**, `idris-rt`, which every shim crate depends on:
  the runtime's C interface, which bindgen (on the pinned clang) generates
  from `runtime/idris_rt.h` and the ODS-generated `idris_rt_ops.h`, so the
  headers stay the one copy; and the Rust half of the runtime's side: the
  foreign cell and its borrow state, `IdrisFn`, the panic hook and the
  global allocator.
- **The shim crate**: one shim per bound item and instance, over the
  named crates and `idris-rt`.

The `idr` pipeline has nothing of its own for Rust: defunctionalization,
the optimizer, `idr-rc` and the lowering see `idr.rust.call` as one more
op, and the runtime link, the partition and code generation see Rust's
bitcode as one more part of the runtime.

## 5. The manifest

```toml
# rust.toml, beside the package's .ipkg
[dependencies]
regex    = "1.11"
rusqlite = { version = "0.32", features = ["bundled"] }
geometry = { path = "rust/geometry" }   # a crate of this package's own
```

That is the whole format (*proposed*): one table, `[dependencies]`, in
Cargo's syntax. Each entry is a version requirement on crates.io or a
`path` inside the package, with `features` and `default-features` as
Cargo reads them. Any other table or key (`git`, `package`, `optional`, a
target table, a registry) fails the generator, naming it: no key is
accepted and ignored.

- **One crate graph per program** (*decision*). A library ships its
  `rust.toml`, never bindings. A program's build unions the manifests of
  every package it depends on, and Cargo resolves one graph, unifying
  features as it always does. A crate that two packages require at
  versions no single version meets fails the generator, naming both
  packages. Every Rust type has one Idris type, and the link holds one
  shim archive and one `std`.
- **A library's Rust bindings compile per program** (*decision*): its
  Idris code imports the program's binding package, generated under the
  program's `build/rust/`, so it is not compiled or installed apart from
  a program.
- Cargo resolves once, at generation, into `rust.lock`, which the
  application commits. `cargo vendor` fills `build/rust/vendor/`, and
  every later build is offline.
- `std` is named like any crate (*decision*, the owner, 2026-10-18):
  `std = "1"`, as `core` and `alloc` are, each requirement met by the
  pinned toolchain's version rather than by crates.io, and each compiled
  from the bootstrap's sysroot (§11.3).
- No table marks a blocking call: 0007's P3 decides how one leaves the
  shard, without a manifest field (§15).
- The binding modules are `Rust.<Crate>` and the generator's internal
  ones `RustShim.*` (§7). Both roots are the generator's, and a project
  module under either fails the build, naming it.

## 6. What is bound

(*proposed*) Nothing is selected by hand:

1. **A named crate is bound whole**: every public item (functions, types,
   traits, constants, statics, re-exports), with each type's and trait's
   associated items and impls.
2. **A reached type is bound with its own items.** A type that a bound
   signature mentions (as a parameter, a result, a field, a variant, a
   constant's type or an associated type), from any crate of the graph,
   is bound with its inherent associated items and its trait impls, and
   so is each trait those impls implement. What they mention is reached
   in turn. A blanket impl (`impl<T: Display> ToString for T`) is not
   bound: the trait it is written over already gives what it gives.
3. **`std` is a crate like any other.** Named, it is bound whole; not
   named, its types still come when a bound signature reaches them
   (`Duration`, `io::Error`, `PathBuf`), as any crate's do. What a crate
   does to the process (prints, reads, exits) the runtime keeps in order
   for every crate alike, `std` included (§10.5).
4. **Generic types** are bound at instances (§8.6).
5. **An item is left out** when it cannot be bound, with one reason of a
   closed set (§11.5). An item that needs a left-out item is left out
   too, its line naming the root.

The vocabulary is fixed: an item is *bound*, *reached* or *left out
(reason)*. `rust.surface` lists every item considered, whichever it is,
and the build prints one line when items were left out:
`12 items left out; see rust.surface`.

Cost (*conjecture*, measured at R1): a crate's whole API makes a larger
binding package and shim crate than a selection did. The shim crate is
compiled once per surface, and the runtime link keeps only the shims a
program reaches. If R1 measures the shim build too slow, building only
the reached shims after the frontend is the lever.

## 7. Names

(*proposed*; the owner left collisions to this revision.) Every Idris
name is a function of the Rust path: readable, and inside the one
mangling's alphabet (`include/idr/Conversion/Mangle.h`: a code point in
`[A-Za-z0-9_.]` is itself), so a shim's symbol is its binding's qualified
name as printed, and the generator holds no copy of the mangling (§12).

- **ASCII only** (*decision*, the owner): an item with a non-ASCII
  identifier anywhere on its path is left out (`ascii`). A named crate
  whose name is not ASCII fails the generator.
- **Modules.** Crate `regex` and module `regex::bytes` are the Idris
  modules `Rust.Regex` and `Rust.Regex.Bytes`: each segment gets an
  upper-case first letter, since an Idris namespace segment starts with
  one (*read*: `Parser/Lexer/Common.idr`, `namespaceIdent`).
- **Types and traits.** Each is a namespace of its module, holding
  everything that belongs to it: `regex::Regex` is the namespace
  `Rust.Regex.Regex`, which holds the type `Regex`, its constructors, its
  associated items, and a nested namespace per trait it implements. A
  record's fields are Idris's own projections, which Idris nests apart,
  so a field and a method may share a name. A type whose name starts
  lower-case gets an upper-case first letter.
- **Values** keep their Rust spelling: functions, methods, variants,
  constants, statics and fields (`Regex.is_match`, `Value.Null`).
- **Reserved words.** A name Idris reserves (its keywords, and `Type`,
  `Lazy`, `Inf`, `Delay` and `Force`, which its parser reads specially;
  *read*: `Parser/Lexer/Source.idr`, `keywords`, and `Idris/Parser.idr`),
  or one that already ends in `_`, gets one more `_`. So
  `Connection::open` is `Connection.open_`, `Default::default` is
  `default_`, a type `Type` is `Type_`, and a Rust `type_` is `type__`:
  no two Rust names meet. The reserved list is the fork's, printed by the
  toolchain (`idris-mlir --print-reserved-names`, from a list the fork's
  lexer exports beside `keywords`), never a copy in the generator.
- **What the generator adds.** A struct's constructor is `Mk<Type>`
  (`MkPoint`), since Idris keeps a constructor apart from its type
  (*read*: Idris reports a type and its constructor spelled alike as one
  name defined twice). A trait object's type is `<Trait>.Dyn` (§8.5).
  Every internal declaration is under the root `RustShim`, kind first,
  then the Rust path it serves: the shims that take compound values apart
  and build them (§8.4), and the interface and instances of a generic
  item (§8.6). No Rust name reaches that root.
- **The binding package spells every name in full**, so a Rust type named
  `String`, `List` or `IO` never meets the Prelude's.
- **One name per item.** An item re-exported under several paths is
  named by its shortest public path in the crate that defines it (fewest
  segments, then the first in path order); an item its defining crate
  does not make public, by its shortest public path in the graph.
- **A re-export is a public import.** A Rust module that re-exports
  another module's items imports that module's Idris module publicly, so
  `import Rust.Std.Time` brings `Duration`, whose name is
  `Rust.Core.Time.Duration`. Idris re-exports modules, not names, so a
  re-export of one item brings its module's other names into scope too;
  every name stays one item's.
- **A name Idris cannot declare.** A Rust name that starts with `_` is
  left out (`name`): Idris declares no name so spelled (*read*), and by
  Rust's convention such an item is not for callers.

| Rust | Idris |
|---|---|
| `regex::Regex` | the type `Rust.Regex.Regex.Regex`, written `Regex` |
| `regex::Regex::is_match` | `Rust.Regex.Regex.is_match` |
| `regex::bytes::Regex` | the type `Rust.Regex.Bytes.Regex.Regex` |
| `rusqlite::Connection::open` | `Rust.Rusqlite.Connection.open_` |
| `<regex::Regex as Clone>::clone` | the `Clone` interface's `clone` (§8.5) |
| `serde_json::Value::Null` | `Rust.Serde_json.Value.Null` |
| `geometry::Point { x, y }` | `Rust.Geometry.Point.MkPoint`, fields `x`, `y` |

**The collisions that remain, and the rule.** Upper-casing a first letter
can make two names one. A module `error` and a type `Error` of one module
share a namespace, so a free function of the module and a method of the
type spelled alike meet; a type `foo` meets a type `Foo`. Beyond that, a
`Mk<Type>` or a `Dyn` can meet an associated item so spelled, two traits
of one name implemented by one type can bring two methods of one name,
and two versions of one crate in the graph give one module two crates.
Each such item is left out with the reason `name`, its line naming every
origin. No collision is resolved by a choice: a choice would rename an
item when another is added.

## 8. How Rust types become Idris types

### 8.1 Plain values

One fixed table, the generator's only list of types (*decision*, with
three rows *proposed*: `!`, arrays and sequences):

| Rust | Idris | in | out |
|---|---|---|---|
| `i8`…`i64`, `u8`…`u64`, `isize`, `usize` | `Int8`…`Int64`, `Bits8`…`Bits64`; `isize`, `usize` as 64-bit (both targets are LP64, which `idris_rt.h` asserts) | the word | the word |
| `i128`, `u128` | `Integer` | the runtime's big conversions | the same |
| `bool`, `char`, `f64` | `Bool`, `Char`, `Double` | the word (both chars are Unicode scalar values) | the word |
| `f32` | `Double` | rounded to nearest | widened |
| `()` | `()` | nothing | nothing |
| `!` | `Void` | — | the call does not return |
| `&str`, `String`, `Box<str>`, `Cow<str>` | `String` | lent as `&str`, no copy: an Idris string is well-formed UTF-8 (`idris_rt_str_from_bytes` replaces ill-formed input); copied where Rust takes ownership | copied (`idris_rt_str_from_utf8`) |
| `&[u8]`, `&mut [u8]`, `Vec<u8>`, `Box<[u8]>` | `Buffer` | lent, no copy; copied where Rust takes ownership | copied |
| `[T; N]` | `Vect N T` | copied | copied |
| `&[T]`, `Vec<T>`, `Box<[T]>` | `List T` | copied | copied |
| `Option<T>`, `Result<T, E>`, tuples | `Maybe T`, `Either E T`, tuples | as their parts | as their parts |
| `Box<T>` | `T` | as `T` | as `T` |

A type this table maps has no bindings of its own: Idris's functions over
`String`, `List` and `Maybe` are its API, and Rust's string methods would
be a second string API.

### 8.2 Data

(*proposed*) A struct whose every field is public and which is not
`#[non_exhaustive]`, and an enum which is not `#[non_exhaustive]` and none
of whose variants is, are **data** when every field's type binds: their
whole contents are the API, and rustdoc states these facts (*recalled*: a
struct's `has_stripped_fields` and the attribute list). Data becomes an
Idris record (named fields), a one-constructor type (a tuple struct) or a
sum (an enum), in its own namespace:

```idris
-- pub struct Point { pub x: i64, pub y: i64 }
-- (shown with short names; the package spells every name in full)
namespace Point
  public export
  record Point where
    constructor MkPoint
    x : Int64
    y : Int64

-- pub enum Value { Null, Bool(bool), Number(Number), String(String),
--                  Array(Vec<Value>), Object(Map<String, Value>) }
namespace Value
  public export
  data Value = Null | Bool Bool | Number (Rust Number) | String String
             | Array (List Value) | Object (Rust (Map String Value))
```

- **Data crosses by copy.** An object inside data (`serde_json::Number`
  above, whose fields are private) is a handle: in an owned result it is
  moved into a cell of its own, in a borrowed result it is a borrow
  handle (§8.4), and in a by-value argument its handle is moved in.
- **A borrowed argument of data that holds an object is left out**
  (`lifetime`): building the Rust value would move an object out of the
  cell Idris holds it in for the length of the call, which Rust forbids
  once an object may be pinned.
- A generic data type (`Range<Idx>`) is one parameterized Idris type at
  all its instances (§8.6); recursive data is recursive Idris data.
- A data type's methods and trait impls are bound as any type's are.
- A copy costs time in the value's size (*conjecture*: the accessor calls
  inline after the runtime link, so it is a copy and no more).

### 8.3 Objects

(*proposed*) Everything else is an **object**: a struct with a private
field, a field whose type does not bind, or `#[non_exhaustive]`; such an
enum; a union; a trait object; an `impl Trait` result (as its trait
object, §8.5); and every reached type the table does not map. An
object's fields are never bound, only its items. An object lives in a
counted foreign cell (§11.1), and Idris holds every object through one
type:

```idris
||| A Rust object of type t, held by a counted reference. Its last release
||| runs its destructor, once, right after its last use, in program order.
Rust : Type -> Type      -- a primitive of libs/mlir-rust; no constructor
```

`t` is the Idris type standing for the Rust one: `Rust Regex`,
`Rust (HashMap String Int64)`. An object is a reference with an identity,
as an `IORef` is: two Idris values may name one object, and a change made
through one is seen through the other. Who may change it, and when, is
kept by its borrow state (§10.2).

### 8.4 Parameters and results

(*proposed*) One mode per parameter and result, decided once in the
surface; the Idris type, the shim's signature and prologue and the
surface's columns are its views:

| Rust | Idris | at a call |
|---|---|---|
| `x: T`, `self`, plain or data | the value | copied in |
| `x: T`, `self`, an object | `(1 _ : Rust t)` | moved out of its cell, which needs the only reference (§10.2) |
| `&T`, `&self` | the value, or `Rust t` | data copied in; an object borrowed shared for the call |
| `&mut T`, `&mut self`, plain or data | the value, and its new value comes back in the result | copied in and back |
| `&mut T`, `&mut self`, an object; `&mut [u8]` | `Rust t`; `Buffer` | borrowed exclusive for the call, changed in place |

- **Results.** An owned object is a new cell; plain and data values are
  copied out.
- **A borrowed result** (`&T`, `&mut T`, or a type holding a parameter's
  lifetime, such as `Iter<'a, T>`) is a **borrow handle**: a cell holding
  a counted reference to the object it borrows from, which keeps that
  object borrowed (shared or exclusive, as the result is) until the
  handle is released. Release happens after the handle's last use, so a
  borrow ends where Rust's own non-lexical borrows would. A borrowed
  result of a plain or data type is copied at once.
- **What a result may borrow from:** one parameter, an object or a
  string (an Idris string never changes). A result that borrows from two
  parameters, or from a `Buffer`, which Idris may change, is left out
  (`lifetime`). So is an argument that must be `'static` and is not a
  callback (`&'static str`).
- **How compound values cross** (*decision*). A shim cannot know a
  program's layouts, which are decided per program before the lowering
  (`lib/IR/Layout/`), so no Idris data moves through a shim. A compound
  result is a result handle that the binding's Idris takes apart through
  accessor shims before it dies; a compound argument is built as a Rust
  value by builder shims. Those shims are internal (`RustShim`, §7), and
  a binding that uses them has a body that calls them. After the runtime
  link, the accessors inline, and the handle's allocation and free are a
  pair LLVM sees whole (§11.4), which O3 may delete (*conjecture*,
  recorded at R1). That changes speed, never meaning.

### 8.5 Traits

(*proposed*) A Rust trait is an Idris interface, and each impl rustdoc
lists is an implementation of it. Self and each type parameter of the
trait are parameters of the interface, and each associated type is a
parameter that Self determines. Each associated constant is a member.
Each method whose signature binds is a method, typed by §8.4 with Self's
kind left open: a `&mut self` method gives Self back, and an object gives
back its own handle.

```idris
-- core::iter::Iterator, as bound
namespace Iterator
  public export
  interface Iterator self item | self where
    next : self -> IO (Maybe item, self)
```

- **Supertraits** are the interface's constraints:
  `trait Error: Debug + Display` is
  `(Debug self, Display self) => Error self`.
- **One signature rule, no table of traits.** A method whose parameters
  are `&self` and a `&mut fmt::Formatter`, and whose result is
  `fmt::Result` (`Display::fmt`, `Debug::fmt`), is bound as
  `self -> IO String`, formatted by that trait's own method.
- **Facts only from impls.** An implementation is generated only for an
  impl rustdoc lists at that type, never from a type's fields. For a
  generic impl at an instance (`impl<K: Clone, V: Clone> Clone for
  HashMap<K, V>` at `HashMap<String, Regex>`), rustc decides through the
  probe (§8.6): the generator never solves a trait bound itself.
- **`Drop` is never bound**: the cell's release is the destructor. Marker
  and auto traits (`Copy`, `Send`, `Sync`, `Unpin`) have no methods; the
  generator reads `Send` and `Sync` where §10.4 needs them.
- **Trait objects.** `dyn Trait` is an object whose Idris type the
  trait's namespace gives (`Rust (Iterator.Dyn Bits32)` for
  `dyn Iterator<Item = u32>`), with an implementation of the trait's
  interface. An `impl Trait` result is bound as that trait object, the
  shim boxing it: one representation for a value known only by its trait,
  and no name made up for a type Rust does not name. An `impl Trait`
  result of a trait that is not dyn compatible is left out (`dyn`).
- A trait method with type parameters of its own is left out (`generic`).

Each implementation is at one type, so it compiles as any interface
resolved at compile time.

### 8.6 Generics

A shim is monomorphic: rustc compiles each instance of a generic item
apart, so a generic item is bound only at concrete types (*decision*).
Which types is derived (*proposed*):

- **A generic type at the instances the crates use.** A generic type is
  bound at each instance a bound signature writes
  (`HashMap<String, i64>`), with its items at that instance. An instance
  first met through another instance's items is bound when it is no
  bigger, counting the type names in it, than the biggest instance a
  named crate's own signatures write, so the closure ends:
  `HashMap<String, i64>`'s `iter` brings `Iter<String, i64>`, and
  `Iterator::enumerate` on it, giving `Enumerate<Iter<String, i64>>`, is
  bigger and is left out (`generic`). A generic object is
  `Rust (HashMap k v)`, with `HashMap : Type -> Type -> Type` an Idris type
  standing for Rust's.
- **A generic function at every type that fits.** A function or method
  with type parameters of its own (`Connection::open<P: AsRef<Path>>`,
  `serde_json::from_str<T: DeserializeOwned>`,
  `Row::get<I: RowIndex, T: FromSql>`, an `impl AsRef<[u8]>` argument, a
  `&dyn Trait` argument) is bound at every candidate that rustc confirms
  meets its bounds. A parameter's candidates are the types of the
  surface: §8.1's table in its order, each Idris type once (`&str` before
  `String`, `i64` before `isize`), then every data and object type and
  instance the surface binds.
- **rustc decides, through the probe.** For each candidate the generator
  writes a constant whose value is 1 exactly when the bounds hold: an
  inherent associated constant behind the bounds, which shadows a trait's
  constant of 0, as stable Rust resolves at compile time (*recalled*). It
  reads the values back from rustdoc's JSON, which evaluates numeric
  constants (*recalled*). One reader, and no trait solving of ours.
- **One name per item.** An item's instances are implementations of one
  interface, `RustShim.Generic.<item path>`, and the binding is one
  generic Idris function constrained by it. The program's types choose
  the instance where it is used, and the compiler specializes it as it
  specializes any interface:

  ```idris
  open_ : RustShim.Generic.Rusqlite.Connection.open_ p
       => p -> IO (Either (Rust Error) (Rust Connection))
  ```

- **Left out** (`generic`): an item no candidate fits, a const generic
  parameter, and a type parameter bounded by a closure trait anywhere but
  a callback (§8.8).

Cost (*conjecture*, measured at R2): candidates multiply across a
function's parameters. No cap is set, since a cap would make whether an
item is bound depend on a number.

### 8.7 Constants and statics

Well supported, and a constant is never `IO` (*decision*, the owner);
the forms are *proposed*:

- **Every `const` is a pure Idris value.** Rust fixed it at compile time,
  so the binding computes it once, from a nullary shim, which trusted
  library code may do (AGENTS.md: a trusted library may run an IO action
  for a pure value). After the runtime link the shim's constant folds
  into its uses (*conjecture*, R1). `pub const MAX_SIZE: usize = 4096` is
  `MAX_SIZE : Bits64`.
- **A `const` that holds an object** is that object, made once and
  borrowed shared forever, as an immutable static's is: a constant never
  changes, so an exclusive or by-value use of it stops the program
  (§10.2), and a use that needs a copy of its own calls `clone` where the
  type is `Clone`.
- **A `const` whose type has interior mutability** (`const ZERO:
  AtomicUsize`: a type that is not `Freeze`, which the probe asks rustc,
  §8.6; *recalled*) is left out (`const`): each Rust use of it is a fresh
  value that can change, which one shared pure value cannot be.
- **An immutable `static` of a plain or data type** is a pure value, as
  a constant is: data holds no interior mutability, so its bytes never
  change.
- **An immutable `static` of an object type** is a pure `Rust t` naming
  the static itself. Its identity is fixed, so naming it twice is
  harmless. It is borrowed shared forever, so an exclusive or by-value use
  of it stops the program (§10.2), where Rust refuses one at compile time.
  A static with interior mutability (`AtomicU64`, `Mutex<T>`) is such an
  object, and its methods are `IO`, as every method is.
- **A `static mut`** is left out (`unsafe`).
- **Associated constants** are bound in their type's namespace; a trait's
  are members of its interface.
- **Neither is folded by the compiler**: the value is the shim's, and no
  primitive has an implementation in Idris (§14).

### 8.8 Callbacks

A parameter `impl Fn(A) -> B`, `impl FnMut`, `impl FnOnce`, `&dyn Fn`,
`Box<dyn Fn>` or `F: Fn(A) -> B` takes an Idris function `A -> IO B`
(§9).

- **Shim side:** a wrapper `IdrisFn<A, B>` per signature holds the
  closure as one counted word and the address of its dispatch function,
  and implements `Fn` by calling it.
- **Compiler side** (*decision*): `idr.rust.call` declares the flow
  interface in its ODS (`IdrFlow.td`), with each closure operand flowing
  into a callback key of its own, so the label solve sees every label that
  reaches Rust. Defunctionalization makes the key a sum and gives it one
  private dispatch function, a case of direct calls named from the key.
  The op carries the sum boxed (how it gets its box is decided by fit,
  `lib/IR/Layout/Fit.cpp`, when R3 starts) and a symbol use of the
  dispatch function, whose address the lowering passes to the shim. That
  use keeps the function and its parameters whole: `remove-dead-values`
  leaves alone the parameters of a function named other than as a callee
  (*read*: PINS.md `remove-dead-values-address-taken`). Its one outside
  caller passes only plain, data and handle values, never a closure or a
  suspension, which the op's verifier checks, so no label enters from
  outside and the closed world holds; nothing is exported.
- **An object a callback receives is lent** (*proposed*): its borrow
  handle expires when the callback returns, and a later use of it stops
  the program, naming it (§10.2).
- **Lifetime.** A callback is called only before the Rust call returns,
  unless the API stores it (`'static`). Then the object's cell holds the
  closure, which is an edge of the object's type to the closure's sum for
  the cycle check. A callback that would need `Send` is left out
  (`send`).
- **Re-entrancy** is the borrow state's (§10.2).

## 9. Effects: every call is `IO`

(*decision*, the owner, 2026-10-18.) Every binding of a function or
method is an `IO` action.

Why: Rust's types say who owns a value and who may change it, never
whether a function reads a file, the clock, the network, a global or a
cache. A binding with a pure type would let the optimizer drop, repeat or
merge its call, so purity needs a fact, and the only facts are Rust's:

- **Constants and immutable statics** are values Rust fixed, and they are
  pure bindings (§8.7).
- **Nothing else.** A safe `const fn` can still read a mutable static
  through `unsafe` code when it runs at run time, and LLVM's inferred
  memory effects are an optimizer's result deciding a type (§18).

What this costs: a program calls Rust from `IO` code, as it calls the file
system, and a pure Idris function cannot call into a crate. A pure API
over a crate would be a library of ours in `libs/`, its purity a claim in
trusted code that review checks, never a manifest flag.

In the compiler, every shim call takes and gives the world, so it is
ordered with every other effect, in program order (§11.2).

## 10. Soundness

### 10.1 Trust

- **The home** (*decision*): a new `Home`, `Bindings`, the binding
  package the generator wrote under the project's `build/rust/idris/`,
  and a new `Lib`, `Rust`: `moduleOrigin Bindings _ = Library Rust`, a
  row trusted and admitted that reports at the caller
  (`Registry/Libraries.idr`, `reportAtCaller`), since no person wrote the
  source. Not `Generated`, which `Origin` already names for code in no
  module.
- **Always the generator's output** (*proposed*): the driver runs the
  generator before the frontend, and the generator rewrites
  `build/rust/` unless the digest it recorded of its inputs and of its
  outputs both match. So what the frontend reads under `Bindings` is
  always the generator's output: a hand edit is overwritten, never
  trusted, and the earlier untrusted state for an edited package is gone.
- **Bindings admitted by origin** (*decision*): `checkReachable` admits a
  bodiless `%extern` that the registry gives a meaning (`meansExtern`,
  `Registry/Entry.idr`) or whose origin is `Library Rust`, and no
  `%foreign` beyond base's own. There is no registry entry per binding:
  the registry is compiled into the frontend (`Frontend/Resolve.idr`,
  `hooksOf`, a function of the name alone), so per-program entries would
  need a loader the tree does not have, and each would restate what the
  declaration and its origin already say.
- **One surface per program, by construction** (*decision*): libraries
  ship only manifests, and the program's build writes the one package
  where `Bindings` points, so a second surface cannot reach a program.
- **`libs/mlir-rust`** is `InHouse`, a row beside `mlir-linear` and
  `mlir-array` in `moduleOrigin`. Its `Rust : Type -> Type` is a
  primitive type with a registry entry (one hook field, as `wordType`
  is): a counted foreign cell holding a Rust object. It has no
  constructor, so only a shim makes one. Its release is the cell kind's
  own; there is no finalizer.

### 10.2 The run-time borrow checker

(*proposed*) Rust proves its borrowing rules at compile time. Idris cannot
see them, and AGENTS.md keeps linearity out of correctness, so each object
keeps them at run time, as Rust's `RefCell` does:

- **One borrow state per object:** free, shared by n, or exclusive. A
  static's and a constant's is shared forever.
- **A call borrows each object it is given for as long as it runs**:
  shared for `&`, exclusive for `&mut`. A borrow handle keeps its object
  borrowed until it is released (§8.4). So one check covers aliased
  arguments (one object given twice, where the second exclusive borrow
  fails), re-entrancy (a callback touching an object the running call has
  borrowed) and a `&mut` borrow handle still alive.
- **A by-value parameter moves the object out**, which needs the only
  reference to its cell (`idris_rt_is_unique`) and a free state. There
  is no moved-out state, since no reference outlives the move; and no
  clone is made in its place, so a move never turns on whether a type is
  `Clone`.
- **Two byte buffers in one call, one of them `&mut`, are compared**,
  since a `Buffer` has no borrow state.
- **A handle lent to a callback expires** when the callback returns
  (§8.8).
- **A pinned object stays put**: a method taking `Pin<&mut Self>` marks
  its object pinned, and a later move of it stops the program (P3 needs
  this for futures).

Each failure stops the program as an index out of bounds does, through
`idris_rt_crash`, with a message naming the item, the parameter and the
state: `rust: Graph::merge: other is borrowed exclusively by self`,
`rust: RequestBuilder::send: self is shared and cannot be moved`,
`rust: Config::set: CONFIG is a static and cannot be borrowed
exclusively`.

**The compiler removes what it proves.** The lowering of `idr.rust.call`
emits each check around the shim's call, as `idr.take`'s lowering reads
its operand, and the shim checks nothing. A check is emitted only where
the operand's grade leaves it open. An `excl` operand is the only
reference, so no borrow handle holds it and its state is free; an owned
unique operand needs no uniqueness test. With no Idris code between a
borrow and its release, the two writes of the state fold away after
inlining. One behaviour, no mode (*decision*): a check that stays is a
run-time check, never a rejection, and `idr-expect`'s `tests-nothing=@f`
(`lib/Transforms/Expect/TestsNothing.cpp`) reads an `idr.rust.call`'s
by-value and `&mut` operands as it reads takes.

### 10.3 Panics

The shim crate builds with `panic = "abort"`; its panic hook calls
`idris_rt_crash` with `rust panic: <message>`, which flushes output and
exits with `IDRIS_RT_CRASHED` as every crash does. No unwinding crosses
into Idris: on Linux the entry links no unwinder
(`IDRIS_MLIR_NO_UNWINDER`), and on macOS, where libSystem is the
unwinder, nothing unwinds.

### 10.4 Threads

A program is single-threaded (`idris_rt.h`: counts are plain
arithmetic). Rust may start threads of its own (rayon, a pool's reaper),
and they may allocate and free, but nothing of Idris reaches them:
`IdrisFn` is `!Send` and `!Sync`, so rustc keeps Idris callbacks on their
thread, and an item whose bounds would need one to cross is left out
(`send`). A handle is an Idris value. 0007's shards keep the rule (0007
§3.3).

### 10.5 One process

(*proposed*) `std` is the platform layer of Rust code and the runtime is
the platform layer of the program, and there is one process, so the two
must agree on it. Nothing in the bindings sets `std` apart: the ordinary
reasons leave out what would take the process from the runtime
(`std::thread::spawn` and `std::panic::set_hook` need closures that are
`Send`, so `send`; `std::env::set_var` and `std::alloc::alloc` are
`unsafe`). What remains is not a question of which items are bound, since
any crate's own code can print, read or exit; the runtime keeps it in
order for every crate:

- **One output order.** The runtime's output goes through one buffer
  (*read*: `runtime/Io/Output.cpp`) and `std`'s through its own. The
  runtime writes out its buffer before a Rust call starts, and the shim
  flushes `std`'s standard output and error after the call returns, so
  writes from both sides appear in program order (cost *conjecture*,
  measured at R1).
- **One ending.** The runtime writes its pending output and open files'
  buffers only on its own ending paths (*read*: `runtime/Io/Ending.cpp`).
  It runs that ending, once, on every exit of the process, `exit` from C
  included, so `std::process::exit`, which flushes `std`'s own output
  and calls `exit` (*recalled*), ends a program as base's `exit` does.
- **One start.** `std`'s start-up never runs (§11.3), so what `std` reads
  from it the runtime gives it instead: on musl, `std::env::args` is
  filled only there (*recalled*). R0 finds the mechanism and checks that
  `std::env::args` and base's `getArgs` agree on both targets; if `std`
  offers none short of a change to its source, that change is made to the
  pinned source as AGENTS.md says, with its plan to go upstream.
- **Standard input** has two readers when both sides read it, each
  buffering ahead of the other. R1 decides whether `std`'s input reads
  through the runtime's buffer or the two are kept apart by another
  means; until then a fixture shows what happens.

## 11. The compiler

### 11.1 A foreign cell

- **Runtime:** a sixth kind, `IDRIS_RT_KIND_FOREIGN`, with no object
  slots: what the Rust object refers to, it owns through its drop glue.
  The cell is a `#[repr(C)]` header, drop entry, the object's address and
  the address of the borrow state that guards it, then the payload: the
  object itself and its state, for an owned cell; or, for a borrow
  handle, the borrowed value, the counted reference to its owner and the
  borrow it holds. Only the shim makes one, through the runtime's cell
  allocation (`idris_rt_cell`, with an aligned variant for a payload that
  needs one). Freeing gains the foreign kind: the drop entry, at a fixed
  place, runs before the memory is freed (`runtime/Rc/Freeing.cpp`).
- **The layout is checked where rustc lays it out** (*proposed*): the
  support crate asserts, in `const` items, the offsets of the header, the
  drop entry and the state's address against constants bindgen generates
  from `idris_rt.h`. rustc evaluates them on each target entry, so a
  drift fails the build of every shim crate, and no test has to stay
  wired to catch it.
- **One layout** (*decision*): the compiler only holds the cell's word
  and never builds, copies or places one, so it needs no size and no
  layout table.
- **Drop glue that releases Idris values** (an `IdrisFn`'s closure)
  pushes onto the current dying list through a new entry,
  `idris_rt_release_deferred`, which releases at once outside a release,
  so freeing keeps constant stack however Rust and Idris cells interleave.
- **Never persistent, never in a frame.** No foreign call runs at compile
  time, so no static datum holds one. A top-level value holding a Rust
  object (a static's handle, §8.7) is a static memo cell whose forced
  value is counted and released at exit by `idris_rt_caf_release`.
  `idr.con`'s `stack` property builds Idris data in a frame (`IdrOps.td`),
  and the shim makes every foreign cell, so none is a stack cell.
- **Dialect:** a type `!idr.foreign<"T">`, named by the Idris qualified
  name of the type constructor standing for the Rust type (the compiler
  never sees a Rust path, §2), counted at every grade by implementing the
  value-facts type interface (`isCounted`; `Idr_CountedType` reads it,
  `IdrOwnershipOps.td`). It is no data type and has no constructors.
- **Frontend:** `Ty` (`compiler/src/IdrisMLIR/Types.idr`) gains
  `ForeignT`, with the type constructor's identity; `coreType`
  (`Frontend/Translate/Types.idr`) maps `Rust t` to it through `Rust`'s
  hook.

### 11.2 The call

`idr.rust.call "symbol"(%args...)` (*decision* unless marked):

- **Callee:** the shim's symbol (§12), an inherent string property. A
  shim is part of the runtime and never an `idr.func`, every one of which
  has a body (`lib/IR/Func/Func.cpp`); the lowering declares it as it
  declares runtime functions. It is not an `Idr_Runtime<symbol>` op
  (`IdrBase.td`), whose symbol is one per op class with a prototype
  idris-mlir-tblgen writes; a Rust call's symbol is one per binding.
- **Signature:** an inherent `function_type`, the declaration's Idris
  type lowered, with the modes as grades: a borrowed object a borrow, a
  by-value object owned at quantity one, plain and data values values.
  The verifier checks operands and results against it, as `idr.call` is
  checked against its callee; `idr-rc` and the ownership verifier read
  its grades as a callee's.
- **Effects** (*decision*): every shim call takes and gives the world in
  its signature. The op declares its effects through
  `MemoryEffectOpInterface` on the IO, crash and divergence resources, as
  `idr.call` does (`lib/IR/Effects.cpp`), always: a crate may do I/O,
  panic or loop. A constant's or a static's binding is a pure Idris value
  that trusted code computes from the call (§8.7), so the op itself is
  never pure.
- **Flow:** it implements the flow interface for its closure operands
  (§8.8), and is the only op here that carries one.
- **Lowering:** an `llvm.call` of the symbol, each operand as its runtime
  word, between the borrow checks its grades leave (§10.2). The
  convention is the runtime's C ABI: words in, borrowed unless the grade
  says consumed, an owned result (`runtime/idris_rt.h`). No Rust calling
  convention is computed anywhere.

### 11.3 Linking

**The runtime's own link** (*decision*). The shim archive is one more
input of `readRuntime` and `linkRuntime` (`include/idr/Driver/Runtime.h`),
read after the runtime's, with no step of Rust's own:

- Each member is checked and prepared as the runtime's are
  (`lib/Driver/ReadRuntime.cpp`): the program's triple; bitcode in every
  member, so a crate's assembly object is refused, naming it; no static
  constructor (`LinkOnlyNeeded` links appending globals into every
  program); no appending global (`unsupported (runtime)`); `used` markers
  dropped.
- `namesApart` keeps the program's names apart from it, and it joins with
  `LinkOnlyNeeded` before `retarget` and internalization, so a binding's
  call and the Rust under it are optimized as one function.
- A per-program archive is never prepared, so it takes the runtime's
  archive case: each body the program reaches becomes a definition
  compiled with the program. That holds at both of 0008's steps with no
  third case (0008 §3.5), and Rust's functions fall in the runtime's group
  by their dotless names (§12). A step of Rust's own would be a third
  case and a second representation of a part of the runtime.

`std`'s `lang_start` never runs: the entry is `idris_rt_start`, and what
`std` sets up there (*recalled*: arguments on some Linux targets, the
stack guard, `SIGPIPE`) is the runtime's job, and §10.5 says how `std`
still sees the process the runtime runs. R0 records what `std` does
without `lang_start`.

**One archive per program:** one surface, one shim crate, one `std`, one
`#[global_allocator]`, one panic runtime. Two archives from two graphs
would bring two `std`s whose symbols collide, or two allocators on one
heap.

- **Contents and flags:** the shim crate, its dependencies and `std`,
  each member with its bitcode, built with the entry's bitcode flags (as
  `IDRIS_MLIR_RUNTIME_BITCODE_FLAGS` gives the runtime fat LTO objects on
  ELF and embedded bitcode on Mach-O: `-Clinker-plugin-lto` or
  `-Cembed-bitcode=yes`, *recalled*, settled at R0), `panic = "abort"`
  and v0 mangling. `std` comes from a sysroot the bootstrap builds once
  per target entry with `-Zbuild-std` (§17).
- **Target entry:** two new facts, `IDRIS_MLIR_RUST_TARGET` (the Rust
  triple, with the entry's deployment target) and
  `IDRIS_MLIR_RUST_BITCODE_FLAGS`. On Linux, Rust's self-contained musl
  is not used (`-Clink-self-contained=no`): the program links the pinned
  musl 1.2.6 (`toolchain.lock.json`), whose ABI R0 checks against the
  `libc` crate's (*recalled*: Rust targets musl 1.2.3 or later).
- **C inside `-sys` crates**, the only C in a program: built by the
  crate's `cc` script with `CC` the pinned clang, the target's sysroot and
  the entry's bitcode flags, so it joins too. A `-sys` crate over C++ (a
  solver for 0013's T8) uses the pinned clang++ and the pinned static
  libc++, never the system's. A build script that downloads fails, since
  the build is offline, and is named in the failure.

### 11.4 One allocator

The support crate's `#[global_allocator]` calls the runtime's raw blocks,
`rt::alloc::allocate`, `reallocate` and `release`
(`runtime/Alloc/Alloc.h`), with an aligned allocation added; the runtime
exports none of them as a C entry today, since nothing calls one. Rust
and Idris share one heap and its size classes. The entries carry LLVM's
allocation attributes (`allockind`, `alloc-family`), so LLVM can delete
an allocation and free pair it sees whole after the runtime link.

### 11.5 Diagnostics: the reasons

The generator's reasons are its own closed set (*proposed*: `ascii`,
`name`, `unsafe`, `const`, `generic` and `dyn` are new). Each is a
variant of one Rust enum in the generator, printed by name in
`rust.surface`, so a test reads a fixture's reasons as data:

| Reason | The item is left out because |
|---|---|
| `ascii` | an identifier on its path is not ASCII |
| `name` | its Idris name would start with `_`, or would meet another's (§7) |
| `unsafe` | it is an `unsafe fn`, a `static mut` or an item of an `extern` block |
| `const` | it is a constant whose type has interior mutability |
| `pointer` | its signature holds a raw pointer or a function pointer |
| `lifetime` | a result borrows from two parameters or from a `Buffer`; a borrowed argument is data holding an object; an argument must be `'static` |
| `send` | it would move an Idris value to another thread |
| `async` | it is an `async fn` or returns a future (until 0007's P3) |
| `cfg` | its signature differs between the target entries |
| `generic` | no candidate fits a type parameter; a const generic; an instance bigger than the closure allows; a trait method with type parameters of its own |
| `dyn` | it returns `impl Trait` of a trait that is not dyn compatible |

An item left out because it needs another is listed with that root:
`needs <path> (<reason>)`.

The generator fails, rather than leaving items out, for a manifest error
(an unknown table or key; a crate two packages require at incompatible
versions, naming both; a crate name that is not ASCII) and for a graph
that enables tokio's runtime (§15), naming the crates. None is a case of
the dialect's `Rule` enum (`IdrBase.td`), which names the refusal of a
program: an item left out is absent from the bindings, so a program that
calls it fails Idris's name resolution, and a failing manifest stops the
build before the compiler runs.

## 12. The generator

Its stages (*proposed* where new). Each makes a new value rather than
filling in a field of the last, and each states, beside its definition,
why it comes where it does:

1. **Settings.** One record from the unioned manifests, `rust.lock` and
   the target entry: the features, the target triple, the `cfg`s and the
   compiler flags. It writes the shim workspace's `Cargo.toml` and every
   rustdoc and cargo command line, so the surface and the shims describe
   one build. rustdoc runs inside the shim workspace, so Cargo unifies
   features for it as for the build (*recalled*: documenting one crate
   with `-p` outside that workspace can see other features; R0 checks).
2. **Read.** rustdoc's JSON for every crate of the graph, per target
   entry (`x86_64-unknown-linux-musl`, `aarch64-apple-darwin`), through
   `rustdoc-types` at the version the rustc pin fixes. `std`'s, `core`'s
   and `alloc`'s come from the bootstrap's sysroot (§17, R0). rustdoc's
   JSON is the only reader: no Rust source, `Debug` output, constant
   expression or rustc message is parsed. A format change fails the
   generator's build.
3. **Key.** Every rustdoc `Id`, which is valid only within one JSON file
   (*recalled*), becomes an item key (crate, version, namespace, defining
   path) before anything is indexed; public paths come from walking each
   crate's modules and re-exports. From here on everything is ordered by
   key, never by a hash map's order.
4. **Bind, per target.** Each item becomes a surface record (its Idris
   type, its kind, a mode per parameter and result; type aliases
   expanded) or a reason. Every refusal is made here, so the later stages
   have none.
5. **Zip the targets.** An item whose records are equal on both entries
   is kept; otherwise it is left out (`cfg`), its line naming both targets
   and the first part that differs. There is no per-target binding
   package (*decision*): it would be a per-target case outside the target
   entry.
6. **Reach.** §6's closure from the named crates, §8.6's instances and
   the probe; an item that needs a left-out item is left out, with the
   root.
7. **Name.** §7's names. One registry of every name the package will
   declare, internal ones and shim symbols included, finds the
   collisions that remain; they leave their items out (`name`), and then
   what needs them.
8. **Print.** `rust.surface`, the binding package and the shim crate,
   each a total function of the surface. A shim calls its item by the
   fully qualified path (`<regex::Regex>::is_match(re, s)`,
   `<T as Trait>::method(x)`), never by method syntax, so autoderef, a
   trait in scope or an inherent method of the same name cannot choose
   another function than the one rustdoc described. Everything is
   written into a temporary directory, renamed into `build/rust/` only
   when the whole run succeeds.

- **Outputs:** `build/rust/idris/` (the binding package, compiled per
  project), `build/rust/shims/`, `build/rust/libidrs-<digest8>.a` (every
  member with its bitcode), `build/rust/surface.digest` (§10.1), and
  `rust.surface`, which the application commits beside `rust.lock`. Its
  first line names the two target entries it is the intersection of;
  then one line per item in key order: the Rust path, and either the
  Idris name and type or `left out: <reason>`. The build regenerates it
  and fails on a difference, as a lock file does. No generator version is
  stamped in it.
- **A pure function of its inputs:** the manifests, `rust.lock`, the
  pinned toolchain and the target entries. It reads no environment
  variable, runs no optional tool, never branches on the host and never
  falls back: a missing tool fails it. Path order, content-derived names,
  no timestamps; `tests/determinism` covers it.
- **Shim symbols** (*decision*): a shim's symbol is its binding's
  qualified Idris name, which the frontend prints from the declaration
  and the generator writes as the shim's `export_name` from the surface
  record that also writes the declaration. §7 keeps every name inside the
  one mangling's alphabet, so it reaches the linker as printed;
  `namesApart` keeps it apart from the program's names, and it joins a
  namespace group by 0008 §3.4's rule. The archive is named by the
  surface's digest, so a package and an archive of different surfaces are
  never paired.
- **Mangling** (*decision*): the shim crate's whole graph, `std`
  included, builds with `-Csymbol-mangling-version=v0`, whose names have
  no dot (*recalled*), so Rust's own functions join the runtime's
  namespace group by 0008 §3.4's rule and the partitioner needs no rule
  of its own. R0 checks that no function of the archive has a dot in its
  name.

## 13. Protocol overlays

A handle says what a value is and §10.2 says who may change it, but
neither says which state it is in (a statement prepared or mid-iteration,
a transaction open or done). Brady's resource-indexed types add that on
top (*decision*), as ordinary Idris over the generated functions, which
needs no trust: `data Tx : TxState -> Type` over a `Rust Transaction`,
`begin` giving a `Tx Open`, `commit` and `rollback` taking one; a `Tx`
dropped unfinished rolls back at its release, as rusqlite's `Drop` does.
An overlay lives in the project that uses it (*decision*): an installed
package outside the table is never reached, and nothing proposes trust
for third-party Idris packages. A library-level `ST` is not adopted (§18).

## 14. Compile-time evaluation

No Rust call runs at compile time. Static normalization runs on the type
checker's interpreter (0010), where code that reaches a world is stuck
and runs at run time (0010 §2). Every binding takes the world, and a
constant's pure value is computed from a shim whose meaning is in the
program's archive, never in the compiler's process, so to the type
checker it is a neutral term, as any opaque constant is, and it is
computed at run time. `Vect MAX_SIZE Bits8` does not reduce.

## 15. Async: 0007's reactor is the executor

Async Rust is 0007 §10's design and its P3, after its P2: the executor is
the shard's reactor, a future is a task frame, and `Rust (FutT a)` is a
foreign cell (§11.1) polled through a shim with the task's waker; P3
needs R1 and R2 first, and 0007 D12's rule says which crates work. This
proposal's half:

- **I/O traits:** Rust's async I/O traits (`tokio::io::{AsyncRead,
  AsyncWrite}`, `hyper::rt::{Read, Write, Timer, Executor}`, smithy's
  connector and sleep traits; *recalled*) are implemented in the support
  crate over the runtime's sockets and timers, with buffers the runtime
  owns until completion.
- **The refusal:** a graph that enables tokio's `rt`, `net` or `time`
  features fails the generator, naming the crates (§11.5), since those
  crates call tokio's runtime directly (`tokio::spawn`, as reqwest and
  sqlx do; *recalled*). `reqwest::blocking` runs tokio on a thread of its
  own, a tokio island, and fails the same way.
- **Until P3**, an `async fn` or a future result is left out (`async`),
  and a synchronous crate with an I/O-free core (rustls's `Connection`,
  `httparse`) talks to the network over sockets the program owns.
- **Blocking calls:** every synchronous call runs on the calling thread,
  in world order. P3 decides how a call that blocks leaves the shard,
  with no manifest field marking one (0007 §10.4).
- **Never** a tokio island (§3).

## 16. Testing

Every check states a behaviour or a property, and the machinery that
reads expected files is Idris in the test runner, with shell only as glue.

- **The pool** `tests/programs/rust/`: each fixture has a `rust.toml`
  naming a fixture crate of its own (`path`) or a vendored real crate, an
  Idris program and committed expected files; its `run` generates,
  compiles, runs and checks. Every fixture runs on both target entries,
  and one that cannot run on an entry fails there: none is skipped.
- **The API record:** each fixture commits its `rust.surface`, the API it
  promises. The printed Idris and the shim crate are never expected
  files; they are checked by compiling and running them.
- **A fixture per reason** (§11.5), whose left-out lines a check reads as
  a set of (Rust path, reason): any other reason in the file fails it.
- **A fixture per mode and kind:** plain, data, object, generic instance,
  constant and static, each by value, `&` and `&mut`, as argument and as
  result, over Copy and non-Copy types, an unsized type behind a
  reference, a trait object, a zero-sized type and a `#[non_exhaustive]`
  type. Each compiles its shim crate.
- **Names:** a fixture crate whose items are named by every word of the
  toolchain's reserved list (generated from it), a name starting with
  `_`, a non-ASCII name, a type pair `foo`/`Foo` and a module/type pair
  sharing a member: bound with `_` escapes, or left out (`name`,
  `ascii`).
- **The borrow checker:** a fixture per check of §10.2, with
  `expected-crash` holding its message; and the property that a loop over
  an `excl` handle tests nothing (`tests-nothing=@f`).
- **Both ways across the boundary:** data built in Idris and checked by
  the fixture crate's own function; data the crate makes from a seed,
  read in Idris and compared with the same seed's Idris value; a
  `&mut [u8]` the crate writes, seen by Idris after the call; a constant
  and a static read in Idris, equal to what the crate prints.
- **One process** (§10.5): lines printed by Idris and by a crate,
  alternately, come out in program order; a crate's `std::process::exit`
  keeps the output written before it and the open files' buffers;
  `std::env::args` equals base's `getArgs`; and a fixture reads standard
  input from both sides, its expected files stating what R1 decides.
- **Drop timing:** a destructor with a visible effect appears at a fixed
  point of stdout. `IDRIS_RT_LIVE=1` reports zero live cells at the end
  of every fixture, foreign cells included.
- **Layout:** the support crate's `const` assertions (§11.1) compile on
  both target entries.
- **Linking:** on the object, a shim R0's fixture says is inlined leaves
  no relocation naming its symbol, read beside `tests/lib/heap.sh`'s
  `object_imports`; no archive function has a dot in its name;
  `tests/toolchain/static-linking` covers the Rust fixtures (no Rust
  dylib, no `libgcc_s` or unwinder on Linux, nothing outside `/usr/lib`
  and `/System` on macOS).
- **Failures that must happen:** a `features` entry changed without
  regenerating fails on `rust.surface` drift; a hand edit of
  `build/rust/idris/` is overwritten by the next build; rustdoc and cargo
  given different features never reach a running program; an unknown
  manifest key fails the generator.
- **Both targets from either host:** the generator's fixtures read
  rustdoc's JSON for both entries with `--target`, so on either machine a
  `#[cfg(target_os = "macos")]` item is left out (`cfg`) and the rest is
  bound.
- **One graph:** a library's manifest and the application's give one
  archive; incompatible requirements fail, naming both packages.
- **Determinism:** the generator run twice gives identical outputs, and
  every fixture's executable is byte-identical across thread counts
  (`tests/determinism`), the archive built once per surface.
- **Real crates assert a property of the library**, never only an exit
  status: regex finds the matches its fixture states; sha2's digest of a
  fixed input is the standard's test vector; serde_json prints back the
  document it parsed; rusqlite with `bundled` (C under Rust, by the
  pinned clang) returns the rows it was given. Each failure a real crate
  exposes is reduced to a small fixture crate, which stays.

## 17. Plan

Every stage is **AFTER-SELF**. It builds on the pipeline as it is; each
stage ends with every suite AGENTS.md names, `tests/determinism`, and the
new pool green on both target entries, and lands as a cutover with
nothing kept beside it.

- **R0, the toolchain** (AFTER-SELF; needs only the bootstrap). A `rust`
  entry in `toolchain.lock.json` and a step in `tools/bootstrap.sh`: an
  official build with its bundled LLVM, whose major `tools/verify-pins.sh`
  checks is not newer than ours (`accept: "24"`), since newer LLVM reads
  older bitcode; rustc does not build against our llvm-main commit, and
  building it so is not planned. Which build is §19's question 1. The
  bootstrap builds `std` once per target entry, with the entry's flags,
  into a Rust sysroot under `.toolchain/`, and writes rustdoc's JSON of
  `std`, `core` and `alloc` beside it; a program's cargo build compiles
  only its own crates, in `build/rust/`, its only cache (*decision*:
  `std`'s flags are the entry's, and ccache does not compile Rust). Exit:
  a hand-written one-function binding runs on both targets, its bitcode
  reads in the pinned LLVM, its call is inlined (§16), no archive
  function has a dot in its name, and no program build rebuilds `std`.
  Recorded: §11.3's facts (`std`'s constructors, appending globals and
  assembly members; life without `lang_start`); §19's question 2;
  rustdoc inside the shim workspace sees the build's features; the probe
  (§8.6) reads back through rustdoc's JSON; rustdoc `--target` for the
  other entry works on either host; the layout assertions compile; and
  how `std` gets the program's arguments (§10.5).
- **R1, objects, data and traits** (AFTER-SELF; after R0). Runtime: the
  foreign kind, its freeing, the borrow state, and one process (§10.5:
  the output order, the ending on every exit, standard input). Dialect:
  `!idr.foreign`, `idr.rust.call` and its checks' lowering. Frontend:
  `ForeignT`, `Rust`'s hook, the `Bindings` home, admission by origin and
  the reserved-name list. Driver: the generator step and the archive in
  the runtime link. Generator: every stage of §12 for items with no type
  parameters of their own: §8.1 to §8.5, §8.7, trait objects and
  `rust.surface`. Fixtures: the shape, name and borrow-checker fixtures,
  regex, and a library with a manifest used by an application that names
  a second crate.
- **R2, generics** (AFTER-SELF; after R1): §8.6, the instances with their
  size bound, the candidates and the probe, an interface per item,
  `&dyn Trait` and `impl Trait` arguments. Fixtures: sha2, serde_json
  (`from_str` at `Value` and at a type of the program's own fixture
  crate), and rusqlite with `bundled`.
- **R3, callbacks** (AFTER-SELF; after R2): §8.8, `IdrisFn` and the flow
  interface (the sum's box decided with fit), lent handles that expire,
  stored callbacks and their cycle edge. Fixtures: a capturing callback,
  one whose argument the closure ignores, a re-entrant callback that
  stops the program, a stored callback, and a stored callback that
  captures its own object in `tests/reject`.

Size (*conjecture*): generator 6–9k lines of Rust; support crate 1–1.5k;
`libs/mlir-rust` 0.3k of Idris; frontend 1–1.5k; dialect, lowering,
driver and runtime 2–3k; bootstrap and tests about 1.5k.

## 18. Alternatives rejected

- **`[select]`, a list of the items to bind:** a hand-written fact per
  crate, and a pattern language (anchoring, re-export paths, what "all"
  means), in each of which hs-bindgen shows a class of bug. Whole crates
  and reach replace it (§6).
- **`[pure]`, a promise of purity per crate or item:** nothing checks it,
  and a wrong one is unsound (§9).
- **Purity from `const fn`**, or from LLVM's inferred memory effects: a
  safe `const fn` can read a mutable static through `unsafe` code at run
  time; an optimizer's result would decide a type, and an internal cache
  (regex keeps one, *recalled*) counts as a write anyway.
- **`[instances]`, hand-chosen instances of generic types** (§8.6).
- **Linear handles**: `Rust t` threaded at quantity 1 beside a frozen
  `Shared t`, with `freeze` and `thaw`. An `IO` result is unrestricted,
  so the threading cannot hold for an effectful call, and correctness may
  not rest on linearity; two handle types also doubled every `&self`
  method.
- **Clone on move** (moving a shared object clones it when it is
  `Clone`): a meaning that turns on a count and on a trait; a move needs
  the only reference instead (§10.2).
- **Rust containers of Idris values** (`RVec`, `RDeque`, `RMap`): a
  second representation of what `libs/mlir-array` holds.
- **A fixed table of traits** onto `Show`, `Eq` and `Ord`: those are pure,
  and a Rust impl is not known to be.
- **Naming by choice** when names collide (a suffix by order, a table of
  renames): a name that changes when another item is added. A collision
  leaves its items out instead (§7).
- **Escaping reserved words with `'`** (`open'`): readable, but a prime
  is outside the mangling's alphabet, so the generator would need a
  second copy of the mangling to spell a shim's symbol.
- **Setting `std` apart**, whether as a crate that cannot be named or as
  a list of its items left out as the runtime's: a special case, where the
  ordinary reasons and one process (§10.5) do the work, for every crate.
- **A made-up name for an `impl Trait` result**, from its use site: one
  more generated name, where the trait object is the value's one
  representation (§8.5).
- **Embedding `rustc_driver` to call the unstable Rust ABI** (`layout_of`,
  `fn_abi_of_instance`): a second LLVM in our process, `rustc_private`
  moving every six weeks, and nothing bought, since every value crosses
  as a word through a shim LTO inlines.
- **Building MLIR from Rust's LLVM fork:** our patches are upstream pull
  requests against llvm main (PINS.md), which a fork's base would not be.
- **Bindings from C headers, as hs-bindgen does** (Well-Typed's generator
  for Haskell, read 2026-10-18 at f86ad99): this design reads no C
  header. Taken from it: a verdict per item with the root cause reported,
  stable keys before any index, one settings record for generating and
  compiling (its 1.0 cutover to one rendering of the root directives), one
  mode per parameter with the outputs as its views, refusals only in the
  reader and total printers, trait facts only from listed impls with
  rustc deciding generic ones, fully qualified calls in shims, writing
  nothing unless the run succeeds, and its testing lessons (§16).
  Avoided, from its record: hand-written binding specifications trusted
  unchecked, keys accepted and ignored, silent fallbacks when a tool is
  missing, output that depends on the environment, several readers of
  one input, a range of supported toolchains, skipped tests counted as
  passes, unanchored selection patterns, and text goldens of generated
  code. rust-bindgen and cxx are the closer relatives.
- **A library-level `ST`** as the ownership layer: ownership a second
  time beside the grades, Idris 1's weak error messages, and elaborator
  reflection user code cannot have; Brady's idea survives as overlays
  (§13).
- **A C FFI, first or ever:** C headers state no ownership, lifetime or
  thread-safety, so every binding would need annotations nothing checks;
  the `-sys` crates and their safe crates have done that work.
- **A tokio island** (§3, §15); **shims that build Idris data** (layouts
  are per program, §8.4); **a `linkRust` step** (§11.3); **an exported
  apply entry per callback sum** (a public function beside the root);
  **an `idr.func` declaration as callee** (every `idr.func` has a body);
  **a `%foreign` spec per binding** (AGENTS.md admits none beyond base's);
  **a registry entry per binding** (§10.1).

## 19. Questions for the owner

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
   `simdutf-dispatch`). A crate brings its own CPU detection
   (`std_detect`), assembly (refused by the reader, §11.3) and direct OS
   calls (`std`, a `-sys` crate's C). Default: the rules bind the tree,
   not a program's crates, which are the foreign world with `std` as their
   platform layer; R0 records what the fixtures' graphs bring.
3. **The 2026-10-18 model.** The owner has ruled that every Rust call is
   `IO` (§9) and that `std` is named like any crate (§5). The revision's
   other choices are *proposed*, each taken as its default and each with
   its alternative in §18: one handle with a run-time borrow state, and no
   linear handles (§10.2); data and objects (§8.2, §8.3); whole named
   crates (§6); one process kept by the runtime (§10.5); traits as
   interfaces (§8.5); generic functions over the surface's types, decided
   by rustc (§8.6); and the names (§7). Default: as written.
