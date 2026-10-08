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
3. **Exclusions by name.**
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

**Excluded:**

- `CS/Rule.idr`, where the coordinator adds `Cycle`, `Uniqueness`,
  `Signal` and `Process`.
- `CS/Types.idr` (U17 defines `Prim` and `Op`).
- `third_party/Idris2`, which is read-only.

## Read first

- `contracts.md` C9 (all), C8.3, C8.4, C1.6 and C13.
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
- **The exclusions** are `ruledOut` entries naming each module's
  `prim__` definitions and the public functions a program calls, with
  the rule C9.5 gives. A program that reaches one gets
  `unsupported (signal)`, `unsupported (threads)` or
  `unsupported (process)` at the use.
- **`RawPointer`** stays for `prim__malloc` and anything else raw.
  The `ruledOut` entries for `prim__getString`, `prim__nullPtr`,
  `prim__forgetPtr`, `prim__nullAnyPtr`, `prim__getNullAnyPtr` and
  `System.getEnv` go.

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

## Delete

- The six `ruledOut ... RawPointer` entries listed above.
- Each `IOCall` or `Prim` mapping that U17's `Op p` replaces. Rewrite
  it; never keep both.

## NOT TO DO

- Do not recognize a base wrapper function by name, replacing its body.
  Under O1, base's own code runs unchanged.
- Do not add entries for `contrib`, `network` or `linear` modules.
- Do not edit `Rule.idr`.
- Do not change any existing entry's Idris name or shape.

## Acceptance

- `T/registry` passes. U23 adds entries for the new primitives.
- A program calling `getEnv "HOME"` compiles. One calling
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
