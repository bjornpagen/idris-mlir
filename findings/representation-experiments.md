# Representation stream: experiments and loose notes

These are the raw notes behind `representation.md`. Programs are in
`$SCRATCH/research/representation/{fin,nat,vect,rose,tri,tri2,tri3}`, where
`$SCRATCH` is this session's scratchpad. They were compiled with
`tools/compile.sh [-p base] --directive dump-mlir`, under
`flock -s build/.tree.lock`. IR is quoted from
`build/exec/prog.dump/06-idr-tail-loops.mlir`, the last idr form before
`idr-lower`.

## Nat without the Nat hack: a crash the reference does not have

The program:

```idris
tri : Nat -> Nat
tri Z = Z
tri (S k) = S k + tri k

main = do c <- getChar
          let m = cast {to = Int} (ord c) * (cast {to = Int} (ord c) - 40)
          printLn (tri (cast m))
```

**Results.**

| input | m | idris-mlir | Chez (`idris2 --cg chez`) |
| --- | --- | --- | --- |
| `1` | 441 | 97461 | prints 97461 |
| `2` | 500 | exit 139, SIGSEGV | 125250, 0.09 s |
| `z` | 8174 | exit 139, SIGSEGV | 50045010, 0.085 s |

- `gdb` shows 104,736 frames of `Prelude.Types.natToInteger` under
  `main`, with `rsp` at the guard page.
- `show` for Nat goes through `natToInteger`, which here is the
  Prelude's recursion:

  ```
  natToInteger(n) = match_lit n { 0 -> 0; default -> 1 + natToInteger(pred n) }
  ```

  So the depth is the *value* (125250), not the input.

**The same shape elsewhere** in the IR of experiments `fin` and `nat`:
- `Prelude.Types.plus` is
  `match_lit %a {0 -> %b; default -> big.add(plus(pred a, b), 1)}`;
- `integerToNat` recurses on `x - 1`.

All three are `no_inline` non-tail recursions. Upstream turns them into
one `add_Integer`, the identity and a clamp
(`third_party/Idris2/src/Compiler/Opts/Constructor.idr:80-94`).

**Controls.**
- The Int version of `tri`, run alone, prints the right values for
  every input (experiment `tri2`).
- `printLn (the Nat (cast m))` alone works (experiment `tri3`), since
  its values are small.

## Vect 3 Double today

From `tests/e2e/v3/vect/Main.idr`, as the root function after the
simplify loop:
- For each call of `dot`, `mulV` and `norm2`:
  - three `idr.con @Vect::@"::"(%12, x, tail) {idr.stack}` cells for each
    vector;
  - a call of `zipWith`, which allocates a new 3-cell list;
  - a `foldl` loop;
  - an `idr.dec` of the result list.
- `%12 = idr.constant #idr.erased` fills the length field of every
  cons of every vector: one shared erased value.

Closure sums from `foldr`:
- `@fn$0 box closures { lam55 (); lam80(!idr.box<@fn$0>, !idr.data<@fn$1>) }`
- `@fn$1 closures { lam27(f64) }`

`@fn$0` is `List Double`: a chain of continuations, used LIFO.

`Data.Vect.last` takes each cell apart with `idr.take`, then rebuilds
the identical cell with `idr.reuse %tok @"::"(%erased, %x, %tail)` before
the next iteration (the rotated loop from `idr-tail-loops`). The rebuild
writes the same fields back. This is for the ownership stream, not for
representation: a `take` followed by a `reuse` of the same constructor
with the same fields is the identity, and could fold.

## Rose tree

```idris
data Rose = Node Int (List Rose)
```

This gives:
- `idr.data @Main.Rose box { Node (i64, !idr.box<@List[Rose]>) }`
- `idr.data @List[Rose] box { Nil (); :: (!idr.box<@Main.Rose>, !idr.box<@List[Rose]>) }`

Both are boxes because `Graph.cyclic` returns every node of the
component. Per node:
- today: a Rose cell (8 + 8 + 8 = 24 bytes) plus a cons cell (24 bytes);
- with Rose inlined: one cons cell of 8 + 8 + 8 + 8 = 32 bytes.

## Records with sums

`record P where a : Maybe Int; b : Either Int Double` gives an unboxed
sum with:
- the `Maybe` tag and an i64 slot;
- the `Either` tag, an i64 slot and an f64 slot.

The `Either` slots are not shared, because `SumLayout` matches slots by
type equality (`Layout.cc:74-89`).

## Things checked and not pursued

- `Fin` built by pattern and used to index a runtime `Vect 4 Int`:
  specialization folded it all away (the IR shows a `match_lit` on the
  Int input). Runtime `Fin` values stay `!idr.big` (`Maybe (Fin n)` is
  `Just (!idr.big)`).
- `restrict` (Data.Fin) is rejected: `believe_me` is an escape hatch.
  That is correct per the registry.
- A `List Shape` literal with `sum (map area shapes)` was rejected with
  "not a pattern-matching definition" at `main`. I did not chase which
  definition. Someone should, since it is ordinary Prelude code: `sum` on
  a `List Double` of a user sum.
