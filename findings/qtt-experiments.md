# QTT stream: experiments

Scratch: `scratchpad/research/qtt/{e1,e2}`. Built with the tree's compiler
(`tools/compile.sh -p base --directive dump-core --directive dump-mlir`), with
the environment of `scratchpad/research/facts-ledger/env.sh`. A program needs
`import Prelude` explicitly, or the profile sees no Prelude ("Unknown operator
'+'"). Both programs print what Chez prints.

## e1: case-block grades, a linear let, an as-pattern, an erased order proof

```idris
data L = N | C Int L

dropHead : (1 xs : L) -> L
dropHead xs = case xs of
                N => N
                C _ t => t

pick : (1 w : L) -> Bool -> L
pick w b = case b of
             True => w
             False => dropHead w

twice : (1 xs : L) -> L
twice xs = let 1 ys = dropHead xs in ys

asPat : L -> (L, L)
asPat all@(C _ t) = (all, t)
asPat N = (N, N)

data LTE' : Nat -> Nat -> Type where
  LZ : LTE' Z n
  LS : LTE' m n -> LTE' (S m) (S n)

sub : (m, n : Nat) -> (0 _ : LTE' n m) -> Nat
sub m Z LZ = m
sub (S m) (S n) (LS p) = sub m n p
```

Output `5 2 3 4` (the same as Chez).

What the Core dump shows:

- **Case blocks get Idris's inferred grades.**
  `Main.case block 843 in pick (w Prelude.Basics.Bool) (1 Main.L)`: the
  environment variable `w` captured by the case block is a quantity-1
  parameter. `Main.case block 826 in dropHead (1 Main.L)`: the scrutinee was
  checked at 1 (Case.idr:384-407 falls back to `linear`). Both come from
  LinearCheck's `getArgUsage`/`updateUsage` (LinearCheck.idr:440, 593), which
  rewrites the case block's type. The frontend reads it like any other type.
- **A linear let reaches Core**: `Main.twice (1 Main.L) : Main.L = let 1 = Main.dropHead(#0) #0`.
  Emit writes it as `idr.lin.enter` followed at once by `idr.lin.use`
  (main.mlir `@Main.twice`).
- **An as-pattern is the scrutinee itself**: `asPat` compiles to
  `C/2 => MkPair(#2, #1)`, where `#2` is the scrutinee. No cell is rebuilt.
- **The erased proof licenses an unchecked predecessor.**
  `Main.sub (w Integer) (w Integer) (0 Erased)`. The compile-time tree's
  matches on the proof become matches whose zero case is `unreachable`, so
  the emitted MLIR is

  ```mlir
  func.func private @Main.sub(%0: !idr.big, %1: !idr.big, %2: !idr.erased) -> !idr.big {
    %8 = idr.match_lit %1 : !idr.big -> (!idr.big) {
      case #idr.big<"0"> { idr.yield %0 }
      default {
        %3 = idr.big.pred %1
        %4 = idr.big.pred %0        // m is never tested: LTE' n m and n > 0 prove m > 0
        ...
        %6 = idr.constant #idr.erased : !idr.erased
        %7 = func.call @Main.sub(%4, %5, %6)
  ```

  Idris used the proof `n ≤ m` to make `m`'s zero case impossible, and the IR
  relies on it (`big.pred %0` has no test). The fact itself, `%1 ≤ %0`, is
  gone: the proof parameter is the anonymous `!idr.erased`, and the recursive
  call passes a fresh `#idr.erased` constant. With Nat as a word, this is the
  fact that licenses `arith.subi %m, %n overflow<nuw>` and a trip count.

## e2: a match on an erased value decided by a relevant one

```idris
data SBool : Bool -> Type where
  SFalse : SBool False
  STrue  : SBool True

sNot : (0 x : Bool) -> SBool x -> Bool
sNot False SFalse = True
sNot True  STrue  = False

pick : Int -> (b : Bool ** SBool b)
```

Output `False`. Idris's case tree matches on the relevant `SBool`, not on the
erased `x` (`Main.sNot (0 Erased) (w Main.SBool[[__]]) = case #1 of SFalse/0 => ...`),
so the frontend's "match on an erased value with more than one alternative"
rejection (Cases.idr:95) is not reached here.

A data fact the dump shows and nothing uses: in `(b ** SBool b)` the relevant
field `b` is determined by the tag of the relevant field `s` (SBool is a
singleton family), so the pair stores one bit twice. The same holds for any
`(x ** P x)` where `P` is detaggable by its index (`safeErase`,
Context.idr:308-310).
