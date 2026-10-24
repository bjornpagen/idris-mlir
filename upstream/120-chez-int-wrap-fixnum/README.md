<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [Idris] The Chez support wraps every Int and Bits64 result through bignum masks, a fixnum included

At Idris 2 main 89ba32eb (third_party/Idris2's gitlink), and on upstream
main as of 2026-10-24 (*read*), every arithmetic step a program built by
the Chez backend takes on a fixed-width integer ends in a call of the
support's wrap to its width: `bs+`, `bs-`, `bs*`, `bs/` and every cast to
`Int` call `blodwen-toSignedInt`, the unsigned ones `blodwen-toUnsignedInt`
(`support/chez/support.ss:34-40`, `:74-82`; the casts from
`src/Compiler/Scheme/Common.idr:127-137`). The wrap tests the width's
sign bit and masks with `(ash 1 bits)`, a bignum for `Int` (63) and
`Bits64` (64), on every call, though a 64-bit Chez fixnum (61 bits) is
already inside both widths and comes back unchanged. Chez does not inline
the procedure, so an `Int` add costs a call and two bignum operations: on
the stock host an `Int` step is about 15 to 20 times a `Nat` step, whose
`+` and `*` are the host's own (Idris's `natHack`).

`Cost.idr` times ten million steps of each (*measured*, programs built
by the toolchain's stock Idris, 96 and 104 to 118, on Chez 10.4.1; this
repository's 8-core arm64 macOS machine at load average about 40 from
other work; CPU time of the process, two runs):

| step | unpatched | with the patch |
| --- | --- | --- |
| `Nat` add and multiply | 1.5 to 1.8 ns | 1.5 ns |
| `Int` add and multiply | 27.7 to 31.6 ns | 2.0 to 2.2 ns |
| `Int` `.&.` and add | 17.2 to 19.0 ns | 1.7 to 1.8 ns |
| `Bits64` add and multiply | 27.5 to 32.1 ns | 2.5 to 2.7 ns |

Stage 0 runs on the stock host and computes on `Int` throughout (offsets,
counters, the hash's words), so every program it builds pays this.
Through mlir-array, whose reads and loops end in `Int` slots (*measured*,
/tmp/perf/p8/bench, 10^5 elements, the same programs with only the support
swapped): `Array (!!)` 31 -> 13 ns a read, `LArray.write` 65 -> 34 ns,
a growable vector's push, read and write 49 -> 21 ns, `Array.map` 35 ->
12 ns an element, `fromList` 51 -> 20 ns; `SortedMap Int` lookup 140 ->
105 ns.

## Cause

*read* at 89ba32eb, `support/chez/support.ss`:

```scheme
(define (blodwen-toSignedInt x bits)
  (if (logbit? bits x)
      (logor x (ash -1 bits))
      (logand x (sub1 (ash 1 bits)))))

(define (blodwen-toUnsignedInt x bits)
  (logand x (sub1 (ash 1 bits))))
```

`bits` is the width less one for a signed type (63 for `Int` and `Int64`,
7, 15, 31) and the width for an unsigned one (8 to 64). A Chez fixnum is
inside [-2^(w-1), 2^(w-1)), `w` the fixnum's width (`(fixnum-width)`, 61
on a 64-bit host), so for every `bits` of at least `w - 1` a fixnum is a
value of the signed width as it is, and a fixnum that is not negative a
value of the unsigned width as it is: the wrap is the identity on it.
The masks are needed only for a bignum (a product past 2^60, an `Integer`
cast down) and for the narrow widths.

## Patch

`idris.patch`, against 89ba32eb (no other patch of the series touches the
file; it applies alone and after 118 with the series), gives each wrap a
first case: a fixnum, for a width at least the fixnum's own (a fixnum not
negative, for an unsigned one), is returned as it is; everything else is
wrapped as before. The test is two fixnum comparisons and `fixnum?`,
which Chez compiles inline. It changes no result: the identity is the
wrap's own value on those inputs. `Int8` to `Int32` and `Bits8` to
`Bits32` keep the masks on a 64-bit host (their `bits` is below 60), and
on a 32-bit Chez (`w` 30) `Int32` and `Bits32` take the new case too.

## Testing

On the toolchain's stock Idris (96 and 104 to 118), with only its Chez
support replaced by the patched file (`IDRIS2_DATA` naming a copy of the
installed `support/` with the patched `chez/support.ss`; the support is
written into every program the Chez backend builds, so this is what a
bootstrap with the patch installs) (*measured*):

- `Wrap.idr`, every fixed-width type's cast, sum, difference, products,
  negation and quotient at each width's bounds and one past them, at the
  fixnum's bounds (+-2^60, which `Int` and `Bits64` results cross), and
  from bignum inputs (2^64, 2^100 and their negations), prints the same
  324 lines with the patch as without it (`Wrap.out`, the unpatched
  support's output, which the check compares with).
- `Cost.idr`: the table above.
- the 22 array, linarray and ioarray fixtures of tests/ with a Main.idr
  (against mlir-array with the bodies of every function of its generating
  set, which the stock host could not build before), built by both and
  run on Chez: every case prints the same with the patch as without it,
  its committed expected-stdout but for the two crash cases of
  linarray-rows-crash-order, which crash at the specification's operation
  with Chez's own message.

Not yet done: a bootstrap of the stock Idris with the patch, and stage 0
built by it and timed. Swapping the installed stock Idris under running
work is scheduled with the integration that lands this.

`tests/upstream-chez-int-wrap-fixnum` runs `Wrap.idr` on the pinned Idris
and checks every result is the unpatched support's. It cannot see the cost
the patch removes, which no result shows; `tests/upstream-patches` shows
the patch still applies, and `Cost.idr` measures the cost by hand.

## When it goes

When the Idris pin's Chez support returns a fixnum from the wrap
unchanged on its own (upstream main has the code above on 2026-10-24).
Until then the bootstrap applies the patch.

## Upstreaming plan

Nothing is sent: Idris takes no contribution written with generative AI
or a coding agent (upstream/README.md, **Idris**). Whether Bjorn reports
it, in their own words, is their call. The patch is kept as this
submission and goes when the pin moves past an upstream change that makes
it unneeded.
