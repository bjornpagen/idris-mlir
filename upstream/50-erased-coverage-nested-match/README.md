<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [Idris2] An erased function with a nested constructor match is reported not covering

At the pin (third_party/Idris2 at 1c630e67, the toolchain's
`idris2` 0.8.0-1c630e67c), the coverage checker rejects an erased (`0`)
function whose clauses match a constructor nested inside another. The same
function without the `0` is accepted.

## Reproduce

`idris2 --check X.idr` on:

```idris
module X
import Data.List.Quantifiers
import Data.List.Elem
%default total

data W = A | F Integer | B

data IsF : W -> Type where
  ItIsF : IsF (F w)

data Pr : W -> Type where
  M1 : Pr (F w)
  M2 : Pr B

0 fp : All IsF ws -> All Pr ws
fp [] = []
fp (ItIsF :: fs) = M1 :: fp fs

fp2 : All IsF ws -> All Pr ws
fp2 [] = []
fp2 (ItIsF :: fs) = M1 :: fp2 fs

0 fp3 : {ws : List W} -> All IsF ws -> All Pr ws
fp3 [] = []
fp3 (ItIsF :: fs) = M1 :: fp3 fs
```

It reports `fp is not covering` and `fp3 is not covering`, each with
missing cases `fp _` and `fp _` (`fp3 _` and `fp3 _`). `fp2`, which
differs from `fp` only in its quantity, is accepted. Measured on arm64
macOS, 2026-10-16.

## Expected

All three are covering: `ItIsF` is the only constructor of `IsF w`, so
`(ItIsF :: fs)` and `[]` cover `All IsF ws` whatever `ws` is, and the
quantity of the function does not change which values its patterns cover.

## Found by

The drafter of the checker packet's lanes P1 and P4
(`proposals/0003-self-host/checker`), writing erased proofs over
`All` and the graph's certificates. Their sketches are now written without
any function that meets it, so nothing in the tree reaches it.

## Cause

Not investigated. The one difference between `fp` and `fp2` is the
quantity, so the erased case tree, or the coverage check of a function
elaborated at quantity 0, is where to look. It is also unchecked whether
the fork's elaborator (compiler/idris), which shares this code at the pin,
has the bug.

## Why there is no patch

Recorded now and fixed later: Bjorn deferred the fix on 2026-10-16. No
code in the tree meets it. A lane that does escalates, and never writes
around it.

## Upstreaming plan

Status: recorded; not reduced further; no fix. Nothing goes to
idris-lang/Idris2 from here (**Idris**, upstream/README.md).

When it is fixed, all of these land in one change:
- the fix, in the place that reaches the bug:
  - if the stock Idris that builds stage 0 needs it, an `idris.patch`
    that the bootstrap's `idris` step applies;
  - if the fork has it too, the fork's own code, with its
    `pull-request.diff` against the pin;
- a `tests/upstream/erased-coverage-nested-match/` check;
- a PINS.md entry.

Whether to report it upstream is Bjorn's call alone, in his own words.
