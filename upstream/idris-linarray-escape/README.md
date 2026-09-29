# [idris2 contrib] `Data.Linear.Array.newArray` lets the linear array escape its scope

In the pinned Idris 2 (the gitlink in `third_party/Idris2`),
`Data.Linear.Array` promises arrays that are updated in place because each is
used linearly. But `newArray`'s continuation can return the array itself,
so the array becomes an ordinary, shareable value, and writes through one
copy show through the others.

## Reproduce

`Main.idr` (in this directory) builds with the stock Chez backend:

```sh
idris2 -p contrib --cg chez -o prog Main.idr && build/exec/prog
```

It prints `Just 20` and then `Just 7`. The first line is the array `a1`,
written with 10, read back after the "consumed" `a` was written again with
20. The second is a value written through one call of a closure that hands
out the array, read through another call.

## Expected

The program should not type-check. A linear array must not outlive the
continuation that receives it. After `write`, the old handle is gone, so no
second write can reach it.

## Where it goes wrong

`libs/contrib/Data/Linear/Array.idr:18`:

```idris
newArray : (size : Int) -> (1 _ : (1 _ : arr t) -> a) -> a
```

The result type `a` is unconstrained, so `a` may be `arr t` itself
(`newArray n (\arr => arr)`), or a function that captures it
(`\arr => \u => arr`). The implementation (`:45`) builds the array with
`unsafePerformIO`, so nothing else stops the aliasing.

## Proposed fix

Linear Haskell's rule for linear creation (Bernardy et al., POPL 2018):
the continuation returns an unrestricted result, so no linear value can
flow out through it.

```idris
newArray : (size : Int) -> (1 _ : (1 _ : arr t) -> Ur a) -> Ur a
```

Here `Ur` is `!*` from `Data.Linear` in libs/linear. With this signature,
Idris rejects both escapes above: that was checked with the pinned
compiler on a local copy of the module. `toIArray` and `copyArray` need the
same treatment.
