# U18 — The registry: base's surface recognized, pointers as handles, exclusions by name

Mandatory findings: F-base-1 F-base-3 F-base-4 F-base-5 F-base-6

## Permitted outcome

1. **Base's primitives.** The registry maps each Idris primitive of C9.2
   and C9.3 to its `Op p`. It keeps every existing entry, with the same
   names and shapes, mapped to the new `Prim` (C8.4). Mandatory.
2. **Pointers as handles.**
   - `PrimIO.Ptr` is a `WordType` like `AnyPtr`, and
     `Frontend/Translate/Types.idr`'s handler accepts `Ptr t`.
   - The pointer operations become handle operations (C9.1).
   - Their `RawPointer` exclusions go.

   Mandatory, under O1's default.
3. **The hooks carry generated primitives** (C8.3, review R10).
   `Hook.IOCall` carries an `IdrPrim`, and `Hook.ArrayLoop` an
   `IdrRegionPrim` (`Registry/Entry.idr`). `Frontend/Translate/Hooks.idr`
   (`ioCallOf`, `arrayLoopOf`) follows. Mandatory.
4. **`OSClock` and `exitWith`** (C9.1, C9.4, review R11).
   `System.Clock.OSClock` gets a `WordType` entry; the clock primitives
   are recognized by their `scheme:` spec; `System.exitWith` is
   recognized by name. Mandatory.
5. **Exclusions by name.**
   - `System.Signal` is ruled out as `Signal`;
   - `System.Concurrency` as `Threads`;
   - `system`, `popen`, `pclose` and `popen2` with its accessors as
     `Process` (C9.5).

   Mandatory.

## Owner / exclusive writes

- `CS/Registry` (`Entry.idr`, `Libraries.idr`, `Name.idr`,
  `Primitives.idr`, `Recognized.idr`)
- `CS/Registry.idr`
- `CS/Frontend/Translate/Types.idr`
- `CS/Frontend/Translate/Hooks.idr`

**Excluded:**

- `CS/Rule.idr`, where the coordinator adds `Cycle`, `Uniqueness`,
  `Signal` and `Process`.
- `CS/Types.idr` (U17 defines `Prim` and `Op`).
- `CS/Term.idr` and `CS/Frontend/Translate/Terms.idr` (U07 builds
  `Term.Effect` from your hooks).
- `third_party/Idris2`, which is read-only.

## Read first

- `contracts.md` C9 (all), C8.3, C8.4, C1.6 and C13.
- `review.md` R10 and R11.
- `CS/Registry/Entry.idr` (`Hook`) and `CS/Frontend/Translate/Hooks.idr`.
- `findings.md` F-base-1 and F-base-3 to F-base-6.
- `CS/Registry/*`, all of it, especially:
  - `Primitives.idr:90-298` (the `filePrimitive` entries, `filePtr`,
    the `WordType` entry for `AnyPtr`);
  - `Recognized.idr:115-155` (`ruledOut`).
- `CS/Frontend/Translate/Types.idr` (`coreType` and the `WordType`
  handler).
- Base's `System.idr`, `System/File/*.idr`, `System/Directory.idr`,
  `System/Clock.idr`, `System/Errno.idr`, `System/Term.idr`,
  `System/Signal.idr`, `System/Concurrency.idr` and `System/FFI.idr`.

## Fixed decisions

- **Recognized by spec.** Each C9.2 primitive is recognized by its
  `%foreign` spec, as `filePrimitive` entries are today. Its shape is
  its Idris type, and its hook maps it to `Op <Name>`: the generated
  constructor named in C8.2, `FileOpen` for `idr.io.file_open`.
- **The handle hooks** (C9.1):
  - `prim__nullAnyPtr` and `prim__nullPtr` give `Op HandleIsNull`;
  - `prim__getString` gives `Op HandleString`;
  - `prim__free` (`System.FFI`) gives `Op HandleFree`;
  - `prim__forgetPtr` and `prim__castPtr` give the identity hook on
    their last argument;
  - `prim__getNullAnyPtr` gives the literal handle `-1`, as
    `Handle (LInt UInt64 18446744073709551615)`.
- **`OSClock`.** `System.Clock.OSClock` (`data OSClock : Type where
  [external]`) gets a `WordType` entry beside `AnyPtr`'s and `Ptr`'s.
  Its values are immediate (C9.4).
- **Clocks by `scheme:` spec.** The clock primitives have only `scheme:`
  and `RefC:` specs (`Clock.idr:119-121`), so they are recognized by the
  `scheme:` one.
- **`exitWith`.** Base's `exitWith` is
  `primIO . believe_me . prim__exit . cast`, and `believe_me` is
  rejected. So `System.exitWith` is recognized by name, as `idr.io.exit`
  followed by `ub.unreachable`. This is the one wrapper recognized by
  name; `exitFailure` and `exitSuccess` reach it through base's code.
- **The hooks.** `Hook.IOCall` carries an `IdrPrim` and
  `Hook.ArrayLoop` an `IdrRegionPrim`, both generated (C8.2). `ioCallOf`
  and `arrayLoopOf` return them.
- **The exclusions** are `ruledOut` entries naming each module's
  `prim__` definitions and the public functions a program calls, with
  the rule C9.5 gives. A program that reaches one gets
  `unsupported (signal)`, `unsupported (threads)` or
  `unsupported (process)` at the use.
- **`RawPointer`** stays only for `System.FFI`'s allocation primitives
  (`prim__malloc` and its kin). `prim__castPtr` and `prim__forgetPtr`
  are identity hooks, never `RawPointer`. The `ruledOut` entries for
  `prim__getString`, `prim__nullPtr`, `prim__forgetPtr`,
  `prim__nullAnyPtr`, `prim__getNullAnyPtr` and `System.getEnv` go.

## Inputs

- U17's mapping table, and `Op p` constructors named by the C8.2 rule.
  Use the rule; do not wait for the table.
- The four new rules (C1.6), used by constructor name.

## Outputs

- Registry entries for C9.2 and C9.3, the exclusions, and the `Ptr`
  type entry.

## Implement

- Per the fixed decisions. Group the new entries by base module, as
  `Primitives.idr` groups today's.
- **`Entry.idr` and `Hooks.idr`.** Change `Hook.IOCall` and
  `Hook.ArrayLoop`'s payloads and their readers in your files.

## Delete

- The six `ruledOut ... RawPointer` entries listed above.
- Each `IOCall` or `Prim` mapping that U17's `Op p` replaces. Rewrite
  it; never keep both.
- The `IOOp` and `ArrayLoop` payloads of `Hook`, and every pattern on
  them in `Hooks.idr`.

## NOT TO DO

- Do not recognize a base wrapper function by name, replacing its body,
  except `System.exitWith` (above). Under O1, base's own code runs
  unchanged.
- Do not add entries for `contrib`, `network` or `linear` modules.
- Do not edit `Rule.idr`.
- Do not change any existing entry's Idris name or shape.

## Acceptance

- `T/registry` passes. U23 adds entries for the new primitives.
- A program calling `getEnv "HOME"` compiles, and so does one calling
  `exitWith (ExitFailure 3)` and one reading `clockTime Monotonic`. One
  calling
  `System.Signal.collectSignal` is rejected with `unsupported (signal)`.
  One calling `System.system "true"` is rejected with
  `unsupported (process)`. U23 writes the fixtures.
- `findings/upstream-idris/results` shows `ReadDir`, `Time` and
  `TermSize` passing when the coordinator reruns
  `tests/upstream-idris/run`.
- **Tempting partial:** recognizing `getEnv` by name and leaving the
  pointer exclusions. Rejected under O1: every wrapper would need its
  own entry, and base's `free` calls would still be rejected.

## Escalate if

- A C9.2 primitive's shape in base does not match the op's operands.
  Report the primitive and both shapes.
- `Ptr t` cannot be a `WordType` without a frontend change outside
  `Frontend/Translate/Types.idr`. Report it.

## Stop and return

You are done when every C9.2 and C9.3 primitive is registered, the
handle hooks and exclusions are in, and the Delete list is empty of
survivors. Return the changed paths,
`Verification: NotRun (swarm policy)`, and seams.
