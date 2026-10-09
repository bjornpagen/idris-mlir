# U05 — Guards lowered once; the total ops' lowering checks nothing

Mandatory findings: F-guard-2

## Permitted outcome

1. **The guards' lowering.** Each of the six guard ops lowers in a new
   partition, `idr.lower:checks` (`IDR/Lower/Checks.cppm`), to the
   comparison today's lowering emits for its op, then
   `runtime.crashIf(..., cause)`. Its result is replaced by its operand.
2. **The total ops' lowering** emits no check.

The crash message text, location and exit status of every partial op
stay byte-identical. Both outcomes are mandatory.

## Owner / exclusive writes

- `IDR/Lower/Checks.cppm` (new)
- `IDR/Lower/Scalars.cppm`
- `IDR/Lower/Strings.cppm`
- `IDR/Lower/Bigs.cppm`
- `IDR/Lower/Arrays.cppm`
- `IDR/Lower/Buffers.cppm`
- `IDR/Lower/Words.cppm`
- `IDR/Lower/RuntimeCalls.cppm`

**Excluded:**

- `IDR/Lower/Patterns.cppm`, `Lower.cppm` and `CMakeLists.txt`, which
  are U13's. U13 registers your partition and calls
  `populateCheckPatterns` per C3.6.
- `IDR/Lower/Runtime.cppm`, U11's: `crash` and `crashIf` keep their
  signatures.
- `IDR/Lower/CrashMessage.cppm`, which stays as it is.

## Read first

- `contracts.md` C3.1, C3.6 and C13.
- `findings.md` F-guard-2.
- `IDR/Lower/RuntimeCalls.cppm`, all of it.
- `IDR/Lower/Scalars.cppm:60-200`.
- `IDR/Lower/Arrays.cppm`, `Buffers.cppm` and `Words.cppm`.
- `IDR/Lower/Runtime.cppm`'s `crash` and `crashIf`.
- `IDR/Lower/CrashMessage.cppm`.

## Fixed decisions

- **The partition.** `export module idr.lower:checks;`, exporting
  `void populateCheckPatterns(RewritePatternSet &, const TypeConverter &, layout::Layouts &, Runtime &)`
  (the signature of the other `populate*` functions).
- **The comparisons**, moved from where they are today:

  | Guard | Crashes when |
  |---|---|
  | `nonzero` (integer) | `divisor == 0` (`Scalars.cppm`) |
  | `nonzero` (big) | the small word `1` (`bigZero`) |
  | `in_bounds` | `index uge length` |
  | `nonempty` | byte length `== 0` (`emptyString`) |
  | `byte` | outside `0..255` (`LowerToByte`) |
  | `finite` | `notFinite` |
  | `range` | today's buffer test (`Buffers.cppm:32`) |

- **The message.** Built by `runtime.crashIf(b, loc, condition, op.getCause())`
  at the guard's own location, which Emit and the creators set to the
  partial op's location. The text is `crashMessage(loc, cause)`, as
  today.
- **The tail of a total op's lowering.** What followed a check in
  today's code (MIN/-1 handling in division, for example) stays: that is
  the total op's meaning, not its precondition.

## Inputs

- The guard ops (C1.1 item 2).
- `Runtime::crashIf` and `Runtime::call` (U11 keeps their signatures).

## Outputs

- `idr.lower:checks` with `populateCheckPatterns`.
- The total ops' patterns without checks.

## Implement

- **`Checks.cppm`.** Write one `IdrPattern` per guard, building the
  comparison from the moved helpers (`emptyString`, `bigZero`,
  `notFinite`, the bounds compare), then `crashIf`, then
  `replaceOp(op, operand)`.
- **`RuntimeCalls.cppm`.** Remove the precondition from each total op's
  pattern, and keep the call.
- **`Scalars.cppm`, `Arrays.cppm`, `Buffers.cppm`, `Words.cppm`.**
  Remove each per-op check driven by the op's crash cause or by
  `in_bounds`.

## Delete

- `crashCondition` and its `requires` list in `RuntimeCalls.cppm`, with
  the `if constexpr` that called it.
- Each `getCrashCause()`-driven `crashIf` in your files.
- Each read of `in_bounds` in `Arrays.cppm`.

## NOT TO DO

- Do not change `crash`, `crashIf` or `CrashMessage`.
- Do not change any message.
- Do not register patterns in `Patterns.cppm` (U13).
- Do not touch `Runtime.cppm`.
- Do not change the meaning of any total op on valid operands.

## Acceptance

- `T/programs/basic/guards-messages-*` print the same crash message, at
  the same line and column, with the same exit status as at the launch
  base for each of the six cases. U23 writes them.
- `grep -n getCrashCause foreign/idr/lib/Lower` finds nothing.
- **Tempting partial:** keeping the per-op checks and also lowering the
  guards. Rejected: that is two checks per access, and the proof that
  removed a guard would not remove the check.

## Escalate if

- A total op's lowering cannot drop its check, because the runtime
  function would then read out of bounds on a path no guard covers.
  Report the op and the path.

## Stop and return

You are done when `Checks.cppm` exists and no total op's lowering
checks. Return the changed paths, the partition name for U13,
`Verification: NotRun (swarm policy)`, and seams.
