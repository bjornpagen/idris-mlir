# Differential testing: the prototype

The scratch prototype behind `differential-testing.md` section 9, kept here
because the scratch directory does not survive. It is Python and sh for
speed of writing; section 3.3 of the main file says why the real generator
belongs in Idris, in `tests/`.

## How to run it

```sh
# one program: generate, build 5 ways, compare, one verdict line
./run1.sh SEED [vect]
# a batch, three at a time
seq 1 100 | xargs -P 3 -I{} ./run1.sh {}
# reduce a failure (PREDICATE exits 0 while the candidate is interesting)
python3 reduce.py runs/SEED-plain/Main.idr reduced.idr ./pred-null.sh
```

Builds per program: Chez (the reference and the type checker), idris-mlir
with evaluation, with `--directive no-eval`, the quantity-weakened variant
(every `(1 _ : T)` rewritten to `T`, section 8.2 of the main file), and O0
(the contract text through the steps after `idr-simplify` only, with
idris-mlir-opt, then mlir-translate and clang against
`build/dev/runtime/libidris_rt.a`). Every idris-mlir build runs with
`IDRIS_RT_LIVE=1` and must report 0 live cells. Verdicts: `OK`,
`REJECT-IDRIS` (the generator's fault), `REJECT-OURS` (`unsupported (…)`),
`CRASH-COMPILE`, `DIFF-CHEZ`, `DIFF-NOEVAL`, `DIFF-WEAK`, `DIFF-O0`,
`O0-FAILS`, `LIVE`, `RUNFAIL`.

Seeds run before the weakened and O0 builds were added (the first ~25) have
only the Chez, eval and no-eval builds.

## What the generator does

- A fixed prelude of helpers (`Color`, `P`, a tree `T`, `LL` with a linear
  tail field, safe division that avoids 0 and -1, a list builder `mk`,
  list and tree folds), then 5 to 10 functions drawn from templates, then a
  `main` that reads three digits from stdin and prints 4 to 9 values.
- Expressions are generated at a type from an environment of typed
  variables and the functions generated so far (a DAG), so every call
  terminates unless the template is the partial `Int` loop.
- Linear templates consume each linear binder once by construction, and
  include what Idris accepts although the argument is shared: a tail used
  twice (`e :: (takeL 6 xs ++ f xs)`), two conses out of one, a subtree
  kept or rebuilt. Every list and tree variable of `main` is read again at
  the end, after linear functions consumed it: the sharing-injection
  relation, built in.
- One program in four lines is closed (evaluated at compile time; left to
  runtime by `--no-eval`).
- `vect` mode adds `Data.Vect` (`-p base`): `fromList` of a runtime list,
  zipped with its own reverse under an erased length. The Prelude's
  `map` on `Vect` of runtime length is rejected ("unsupported (runtime
  closure): an implementation chosen at runtime"), so the templates avoid
  it.

Pitfalls met, each a generator bug Idris caught: the Prelude's `take` and
`drop` are on `Stream`, not `List`; a linear accumulator cannot flow into
the unrestricted field of `(::)`; a linear consumer's result cannot be an
argument of `+` (the argument is unrestricted), so linear consumers are
written tail-recursively with an accumulator; linear constructor fields
need GADT syntax (`LCons : Int -> (1 _ : LL) -> LL`).

## gen.py

```python
#!/usr/bin/env python3
"""Prototype generator of well-typed Idris 2 programs for differential testing.

Type-directed (Palka et al.): every expression is generated at a target type
from an environment of typed variables and a library of already generated
functions (a DAG, so every call terminates, plus structural self recursion
and deliberately partial Int loops).  Linear code is generated from templates
that consume every linear binder exactly once, so it type checks by
construction; the templates include the ones Idris accepts although the
argument is shared (fields of `::` are unrestricted), to test that a linear
binder is not taken for a unique reference.

    gen.py SEED > Main.idr      (stdin: three digits)
"""
import random
import sys

INT_EDGE = ["0", "1", "(-1)", "2", "7", "100", "(-100)", "9223372036854775807",
            "(-9223372036854775808)", "4611686018427387904", "65535", "(-65536)"]


class G:
    def __init__(self, seed):
        self.r = random.Random(seed)
        self.fns = []          # (name, [argtypes], rettype, total)
        self.decls = []
        self.n = 0
        self.uses_vect = False

    def fresh(self, p):
        self.n += 1
        return f"{p}{self.n}"

    def chance(self, p):
        return self.r.random() < p

    def lit(self):
        if self.chance(0.3):
            return self.r.choice(INT_EDGE)
        v = self.r.randint(-50, 50)
        return f"({v})" if v < 0 else str(v)

    # -- expressions --------------------------------------------------------
    def vars_of(self, env, ty):
        return [v for v, t in env if t == ty]

    def int_expr(self, env, d, allow_calls=True):
        vs = self.vars_of(env, "Int")
        if d <= 0:
            if vs and self.chance(0.7):
                return self.r.choice(vs)
            return self.lit()
        k = self.r.randint(0, 13)
        if k <= 1 and vs:
            return self.r.choice(vs)
        if k == 2:
            return self.lit()
        if k in (3, 4):
            op = self.r.choice(["+", "-", "*"])
            return f"({self.int_expr(env, d-1)} {op} {self.int_expr(env, d-1)})"
        if k == 5:
            op = self.r.choice(["div", "mod"])
            return f"({op} {self.int_expr(env, d-1)} (safeD {self.int_expr(env, d-1)}))"
        if k == 6:
            return (f"(if {self.bool_expr(env, d-1)} then {self.int_expr(env, d-1)} "
                    f"else {self.int_expr(env, d-1)})")
        if k == 7 and allow_calls:
            c = self.call(env, d, "Int")
            if c:
                return c
        if k == 8:
            l = self.list_expr(env, d-1)
            f = self.r.choice(["sum", "sumLen", "headOr", "prodSmall"])
            return f"({f} {l})"
        if k == 9:
            v = self.fresh("v")
            return f"(let {v} = {self.int_expr(env, d-1)} in {self.int_expr(env + [(v, 'Int')], d-1)})"
        if k == 10:
            col = self.color_expr(env, d-1)
            return (f"(case {col} of {{ R => {self.int_expr(env, d-1)}; G => {self.int_expr(env, d-1)}; "
                    f"B => {self.int_expr(env, d-1)} }})")
        if k == 11:
            m = self.fresh("m")
            return (f"(case safeDiv {self.int_expr(env, d-1)} {self.int_expr(env, d-1)} of "
                    f"{{ Nothing => {self.int_expr(env, d-1)}; Just {m} => {self.int_expr(env + [(m, 'Int')], d-1)} }})")
        if k == 12:
            a, b = self.fresh("a"), self.fresh("b")
            l = self.list_expr(env, d-1)
            body = self.int_expr([(a, "Int"), (b, "Int")] + env, d-1)
            return f"(foldl (\\{a}, {b} => {body}) {self.int_expr(env, d-1)} {l})"
        if k == 13:
            t = self.tree_expr(env, d-1)
            return f"(tsum {t})"
        return self.int_expr(env, d-1)

    def bool_expr(self, env, d):
        op = self.r.choice(["<", "<=", "==", "/=", ">", ">="])
        b = f"({self.int_expr(env, d)} {op} {self.int_expr(env, d)})"
        if d > 0 and self.chance(0.2):
            b = f"({b} {self.r.choice(['&&', '||'])} {self.bool_expr(env, d-1)})"
        return b

    def color_expr(self, env, d):
        vs = self.vars_of(env, "Color")
        if vs and self.chance(0.5):
            return self.r.choice(vs)
        return f"(toColor {self.int_expr(env, d)})"

    def list_expr(self, env, d):
        vs = self.vars_of(env, "List")
        if d <= 0 or self.chance(0.25):
            if vs and self.chance(0.8):
                return self.r.choice(vs)
            return f"(mk {self.r.randint(0, 12)} {self.int_expr(env, 0)})"
        k = self.r.randint(0, 8)
        if k == 0:
            v = self.fresh("x")
            return f"(map (\\{v} => {self.int_expr(env + [(v, 'Int')], d-1)}) {self.list_expr(env, d-1)})"
        if k == 1:
            v = self.fresh("x")
            return f"(filter (\\{v} => {self.bool_expr(env + [(v, 'Int')], d-1)}) {self.list_expr(env, d-1)})"
        if k == 2:
            return f"({self.list_expr(env, d-1)} ++ {self.list_expr(env, d-1)})"
        if k == 3:
            return f"(reverse {self.list_expr(env, d-1)})"
        if k in (4, 5, 6):
            c = self.call(env, d, "List")
            if c:
                return c
        if k == 7:
            return f"(toL {self.tree_expr(env, d-1)})"
        if k == 8:
            return f"(takeL 12 {self.list_expr(env, d-1)})"
        return self.list_expr(env, d-1)

    def tree_expr(self, env, d):
        vs = self.vars_of(env, "T")
        if d <= 0 or self.chance(0.3):
            if vs and self.chance(0.7):
                return self.r.choice(vs)
            return f"(fromL {self.list_expr(env, 0)})"
        c = self.call(env, d, "T")
        if c:
            return c
        return f"(fromL {self.list_expr(env, d-1)})"

    def expr(self, env, ty, d):
        if ty == "Int":
            return self.int_expr(env, d)
        if ty == "List":
            return self.list_expr(env, d)
        if ty == "T":
            return self.tree_expr(env, d)
        if ty == "Color":
            return self.color_expr(env, d)
        if ty == "P":
            c = self.call(env, d, "P") if self.chance(0.5) else None
            return c or f"(MkP {self.int_expr(env, d)} {self.int_expr(env, d)})"
        if ty == "Nat":
            return f"(smallNat {self.int_expr(env, d)})"
        if ty == "Fn":
            v = self.fresh("x")
            return f"(\\{v} => {self.int_expr(env + [(v, 'Int')], d)})"
        raise ValueError(ty)

    def call(self, env, d, ret):
        cands = [f for f in self.fns if f[2] == ret]
        if not cands:
            return None
        name, args, _, _ = self.r.choice(cands)
        return "(" + name + "".join(" " + self.expr(env, a, d-1) for a in args) + ")"

    # -- function templates -------------------------------------------------
    def add(self, name, args, ret, total, lines):
        self.decls.append("\n".join(lines))
        self.fns.append((name, args, ret, total))

    def f_arith(self):
        n = self.fresh("arith")
        env = [("a", "Int"), ("b", "Int")]
        body = self.int_expr(env, 3)
        self.add(n, ["Int", "Int"], "Int", False,
                 [f"{n} : Int -> Int -> Int", f"{n} a b = {body}"])

    def f_fold(self):
        n = self.fresh("fold")
        tail = self.chance(0.5)
        if tail:
            body = self.int_expr([("x", "Int"), ("acc", "Int")], 2, allow_calls=True)
            self.add(n, ["List", "Int"], "Int", True,
                     [f"{n} : List Int -> Int -> Int", f"{n} [] acc = acc",
                      f"{n} (x :: xs) acc = {n} xs {body}"])
        else:
            body = self.int_expr([("x", "Int"), ("r", "Int")], 2)
            base = self.lit()
            self.add(n, ["List", "Int"], "Int", True,
                     [f"{n} : List Int -> Int -> Int", f"{n} [] k = {base} + k",
                      f"{n} (x :: xs) k = let r = {n} xs k in {body}"])

    def f_lin_list(self):
        """Linear list transformers: Idris accepts them however the argument is shared."""
        n = self.fresh("lin")
        k = self.r.randint(0, 5)
        env = [("x", "Int")]
        e = self.int_expr(env, 2)
        if k == 0:     # same-size rebuild: the reuse candidate
            lines = [f"{n} : (1 _ : List Int) -> List Int", f"{n} [] = []",
                     f"{n} (x :: xs) = {e} :: {n} xs"]
        elif k == 1:   # filter: cells die
            c = self.bool_expr(env, 1)
            lines = [f"{n} : (1 _ : List Int) -> List Int", f"{n} [] = []",
                     f"{n} (x :: xs) = if {c} then x :: {n} xs else {n} xs"]
        elif k == 2:   # reverse onto a linear accumulator: a tail loop
            n2 = n + "Acc"
            lines = [f"{n2} : (1 _ : List Int) -> List Int -> List Int",
                     f"{n2} [] acc = acc", f"{n2} (x :: xs) acc = {n2} xs ({e} :: acc)",
                     "", f"{n} : (1 _ : List Int) -> List Int", f"{n} xs = {n2} xs []"]
        elif k == 3:   # the tail used twice: legal, since the fields of (::) are unrestricted
            lines = [f"{n} : (1 _ : List Int) -> List Int", f"{n} [] = [{self.lit()}]",
                     f"{n} (x :: xs) = {e} :: (takeL 6 xs ++ {n} xs)"]
        elif k == 4:   # a cell grows: two conses out of one
            lines = [f"{n} : (1 _ : List Int) -> List Int", f"{n} [] = []",
                     f"{n} (x :: xs) = x :: {e} :: {n} (dropL 1 xs)"]
        else:          # swap pairs of cells
            e2 = self.int_expr([("x", "Int"), ("y", "Int")], 2)
            lines = [f"{n} : (1 _ : List Int) -> List Int", f"{n} [] = []", f"{n} [x] = [x]",
                     f"{n} (x :: y :: xs) = y :: {e2} :: {n} xs"]
        self.add(n, ["List"], "List", False, lines)

    def f_lin_p(self):
        n = self.fresh("linP")
        env = [("a", "Int"), ("b", "Int")]
        self.add(n, ["P"], "P", False,
                 [f"{n} : (1 _ : P) -> P",
                  f"{n} (MkP a b) = MkP {self.int_expr(env, 2)} {self.int_expr(env, 2)}"])
        m = self.fresh("pInt")
        self.add(m, ["P"], "Int", False,
                 [f"{m} : P -> Int", f"{m} (MkP a b) = {self.int_expr(env, 2)}"])

    def f_lin_tree(self):
        n = self.fresh("linT")
        env = [("x", "Int")]
        e = self.int_expr(env, 2)
        if self.chance(0.5):
            lines = [f"{n} : (1 _ : T) -> T", f"{n} Lf = Lf",
                     f"{n} (Nd l x r) = Nd ({n} l) {e} ({n} r)"]
        else:   # mirror, and a subtree used twice
            lines = [f"{n} : (1 _ : T) -> T", f"{n} Lf = Lf",
                     f"{n} (Nd l x r) = Nd ({n} r) {e} (if x > 0 then l else {n} l)"]
        self.add(n, ["T"], "T", False, lines)

    def f_ll(self):
        """A list whose tail field is linear: every tail is consumed exactly once."""
        n = self.fresh("llmap")
        e = self.int_expr([("x", "Int")], 2)
        self.add(n, ["List"], "List", False,
                 [f"{n}' : (1 _ : LL) -> LL", f"{n}' LNil = LNil",
                  f"{n}' (LCons x t) = LCons {e} ({n}' t)", "",
                  f"{n} : List Int -> List Int", f"{n} xs = llToList [] ({n}' (llFromList xs))"])

    def f_loop(self):
        n = self.fresh("loop")
        e = self.int_expr([("k", "Int"), ("acc", "Int")], 2, allow_calls=False)
        self.add(n, ["Int", "Int"], "Int", False,
                 [f"partial", f"{n} : Int -> Int -> Int",
                  f"{n} k acc = if k <= 0 then acc else {n} (k - 1) {e}"])

    def f_hof(self):
        n = self.fresh("hof")
        e = self.int_expr([("x", "Int"), ("c", "Int")], 2)
        self.add(n, ["Fn", "Int", "List"], "List", False,
                 [f"{n} : (Int -> Int) -> Int -> List Int -> List Int", f"{n} f c [] = []",
                  f"{n} f c (x :: xs) = f ({e}) :: {n} f (c + 1) xs"])

    def f_tree(self):
        n = self.fresh("tins")
        self.add(n, ["List", "Int"], "T", False,
                 [f"{n} : List Int -> Int -> T", f"{n} xs k = foldr ins (Nd Lf k Lf) xs"])

    def f_nat(self):
        n = self.fresh("nat")
        e = self.int_expr([("r", "Int")], 2)
        self.add(n, ["Nat"], "Int", True,
                 [f"{n} : Nat -> Int", f"{n} Z = {self.lit()}", f"{n} (S k) = let r = {n} k in {e}"])

    def f_erased(self):
        n = self.fresh("erased")
        e = self.int_expr([("x", "Int")], 2)
        self.add(n, ["Int"], "Int", False,
                 [f"{n}' : (0 _ : Nat) -> Int -> Int", f"{n}' _ x = {e}", "",
                  f"{n} : Int -> Int", f"{n} x = {n}' (S (S Z)) x"])

    def f_vect(self):
        self.uses_vect = True
        n = self.fresh("vect")
        e = self.int_expr([("x", "Int"), ("y", "Int")], 2)
        self.add(n, ["List"], "Int", False,
                 [f"{n}z : Vect k Int -> Vect k Int -> Vect k Int", f"{n}z [] [] = []",
                  f"{n}z (x :: xs) (y :: ys) = ({e}) :: {n}z xs ys", "",
                  f"{n} : List Int -> Int", f"{n} xs = let v = fromList xs in vsum ({n}z v (vrev v))"])

    def program(self, vect):
        makers = [self.f_arith, self.f_fold, self.f_lin_list, self.f_lin_list, self.f_lin_p,
                  self.f_lin_tree, self.f_ll, self.f_loop, self.f_hof, self.f_tree, self.f_nat,
                  self.f_erased]
        if vect:
            makers.append(self.f_vect)
        for _ in range(self.r.randint(5, 10)):
            self.r.choice(makers)()
        # main
        env = [("n1", "Int"), ("n2", "Int"), ("n3", "Int")]
        body = []
        for i in range(self.r.randint(4, 9)):
            k = self.r.randint(0, 9)
            if k <= 2:
                v = self.fresh("xs")
                body.append(f"  let {v} = {self.list_expr(env, 2)}")
                env.append((v, "List"))
            elif k == 3:
                v = self.fresh("t")
                body.append(f"  let {v} = {self.tree_expr(env, 2)}")
                env.append((v, "T"))
            elif k == 4:
                v = self.fresh("i")
                body.append(f"  let {v} = {self.int_expr(env, 3)}")
                env.append((v, "Int"))
            elif k <= 7:
                body.append(f"  printLn {self.int_expr(env, 3)}")
            else:
                body.append(f"  printLn (takeL 20 {self.list_expr(env, 3)})")
            # a closed line: evaluated at compile time, left to runtime by --no-eval
            if self.chance(0.25):
                body.append(f"  printLn {self.int_expr([], 3)}")
        # every list variable is used again after the others consumed it
        for v, t in env:
            if t == "List":
                body.append(f"  printLn (sum {v}, length {v})")
            if t == "T":
                body.append(f"  printLn (tsum {v})")
        return self.render(body, vect)

    def render(self, body, vect):
        head = ["module Main", "", "import Prelude"]
        if vect:
            head.append("import Data.Vect")
        head += ["", "%default covering", "", PRELUDE]
        main = ["main : IO ()", "main = do",
                "  c1 <- getChar", "  c2 <- getChar", "  c3 <- getChar",
                "  let n1 = the Int (cast (ord c1) - 48)",
                "  let n2 = the Int (cast (ord c2) - 48)",
                "  let n3 = the Int (cast (ord c3) - 48)"] + body
        vhelp = [VECT] if vect else []
        return "\n".join(head + vhelp + ["\n\n".join(self.decls), "", "\n".join(main)]) + "\n"


PRELUDE = r"""
data Color = R | G | B

toColor : Int -> Color
toColor k = case mod k 3 of { 0 => R; 1 => G; _ => B }

data P = MkP Int Int

data T = Lf | Nd T Int T

data LL : Type where
  LNil : LL
  LCons : Int -> (1 _ : LL) -> LL

llFromList : List Int -> LL
llFromList [] = LNil
llFromList (x :: xs) = LCons x (llFromList xs)

llToList : List Int -> (1 _ : LL) -> List Int
llToList acc LNil = reverse acc
llToList acc (LCons x t) = llToList (x :: acc) t

safeD : Int -> Int
safeD d = if d == 0 then 7 else if d == (-1) then 3 else d

safeDiv : Int -> Int -> Maybe Int
safeDiv a b = if b == 0 || b == (-1) then Nothing else Just (div a b)

mk : Nat -> Int -> List Int
mk Z s = []
mk (S k) s = (mod s 97 - 40) :: mk k (s * 31 + 7)

sumLen : List Int -> Int
sumLen xs = sum xs + cast (length xs)

headOr : List Int -> Int
headOr [] = 17
headOr (x :: _) = x

prodSmall : List Int -> Int
prodSmall xs = foldl (\a, b => a * (mod b 5 + 1)) 1 xs

ins : Int -> T -> T
ins x Lf = Nd Lf x Lf
ins x (Nd l y r) = if x < y then Nd (ins x l) y r else Nd l y (ins x r)

fromL : List Int -> T
fromL = foldr ins Lf

toL : T -> List Int
toL Lf = []
toL (Nd l x r) = toL l ++ x :: toL r

tsum : T -> Int
tsum Lf = 1
tsum (Nd l x r) = tsum l * 3 + x - tsum r

takeL : Nat -> List Int -> List Int
takeL Z _ = []
takeL _ [] = []
takeL (S k) (x :: xs) = x :: takeL k xs

dropL : Nat -> List Int -> List Int
dropL Z xs = xs
dropL _ [] = []
dropL (S k) (_ :: xs) = dropL k xs

smallNat : Int -> Nat
smallNat k = cast (mod k 40)
"""

VECT = r"""
vsum : Vect k Int -> Int
vsum [] = 0
vsum (x :: xs) = x + 2 * vsum xs

vrev : Vect k Int -> Vect k Int
vrev xs = reverse xs
"""

if __name__ == "__main__":
    seed = int(sys.argv[1])
    g = G(seed)
    vect = len(sys.argv) > 2 and sys.argv[2] == "vect"
    sys.stdout.write(g.program(vect))
```

## run1.sh

```sh
#!/bin/sh
# run1.sh SEED [vect]: one generated program, three builds, one verdict line.
# Verdicts: OK, REJECT-IDRIS (the generator's fault), REJECT-OURS <reason>,
# CRASH-COMPILE, DIFF-CHEZ, DIFF-NOEVAL, LIVE, RUNFAIL.
here=/tmp/claude-0/-home-user-idris-mlir/9e6c7b10-225a-5a6c-bf9d-31a304a4cdcc/scratchpad/research/differential
repo=/home/user/idris-mlir
export IDRIS2_PREFIX=$repo/.toolchain/idris2 PATH=$repo/.toolchain/idris2/bin:$PATH IDRIS_MLIR_ROOT=$repo
seed=$1
mode=${2:-plain}
d=$here/runs/$seed-$mode
rm -rf "$d"; mkdir -p "$d/eval" "$d/noeval" "$d/chez"
pk=
[ "$mode" = vect ] && pk="-p base"
python3 $here/gen.py "$seed" $mode > "$d/Main.idr"
python3 -c "import random; r=random.Random($seed); print(''.join(str(r.randint(0,9)) for _ in range(3)))" > "$d/stdin"
verdict() { echo "$seed $mode $*" > "$d/verdict"; echo "$seed $mode $*"; exit 0; }
for m in eval noeval chez; do cp "$d/Main.idr" "$d/$m/"; done
# The metamorphic variant: every quantity 1 weakened to unrestricted.
mkdir -p "$d/weak"; sed 's/(1 _ : \([^)]*\))/\1/g' "$d/Main.idr" > "$d/weak/Main.idr"
# Chez first: it is the type checker too.
(cd "$d/chez" && timeout 300 idris2 --no-banner --no-color --no-prelude $pk --cg chez -o prog Main.idr) > "$d/chez.log" 2>&1 ||
  verdict REJECT-IDRIS "$(grep -m1 -E 'Error|error' "$d/chez.log")"
[ -x "$d/chez/build/exec/prog" ] || verdict REJECT-IDRIS "$(grep -m1 -E 'Error|error' "$d/chez.log")"
for m in eval noeval weak; do
  dir=
  [ $m = noeval ] && dir="--directive no-eval"
  flock -s $repo/build/.tree.lock timeout 600 $repo/tools/compile.sh --io $pk $dir "$d/$m/Main.idr" prog > "$d/$m.log" 2>&1
  st=$?
  if [ $st -ne 0 ]; then
    if grep -q 'unsupported (' "$d/$m.log"; then
      verdict REJECT-OURS "$m $(grep -m1 -o 'unsupported ([^)]*)' "$d/$m.log")"
    fi
    verdict CRASH-COMPILE "$m exit $st $(grep -m1 -iE 'error|assert|fault' "$d/$m.log")"
  fi
done
# O0: the contract text lowered with no simplify loop, the reference for pass bugs.
TC=$repo/.toolchain/llvm-musl/bin
if timeout 600 $repo/build/dev/foreign/idr/idris-mlir-opt --mlir-disable-threading "$d/eval/build/exec/prog.mlir" \
     --pass-pipeline='builtin.module(idr-defunctionalize,canonicalize,idr-stack,idr-rc,idr-tail-loops,idr-lower,canonicalize,cse,convert-scf-to-cf,convert-to-llvm,reconcile-unrealized-casts)' \
     -o "$d/o0.mlir" > "$d/o0.log" 2>&1 &&
   timeout 300 $TC/mlir-translate --mlir-to-llvmir "$d/o0.mlir" -o "$d/o0.ll" >> "$d/o0.log" 2>&1 &&
   timeout 600 $TC/clang --target=x86_64-unknown-linux-musl -O1 -fuse-ld=lld -static-pie "$d/o0.ll" \
     $repo/build/dev/runtime/libidris_rt.a -lgmp -o "$d/o0prog" >> "$d/o0.log" 2>&1; then
  o0=yes
else
  o0=no
fi
timeout 20 "$d/chez/build/exec/prog" < "$d/stdin" > "$d/chez.out" 2> "$d/chez.err"; cs=$?
for m in eval noeval weak; do
  IDRIS_RT_LIVE=1 timeout 20 "$d/$m/build/exec/prog" < "$d/stdin" > "$d/$m.out" 2> "$d/$m.err"; echo $? > "$d/$m.status"
done
es=$(cat "$d/eval.status"); ns=$(cat "$d/noeval.status")
if ! cmp -s "$d/eval.out" "$d/chez.out" || [ "$es" -ne "$cs" ]; then
  verdict DIFF-CHEZ "eval exit $es chez exit $cs"
fi
if ! cmp -s "$d/eval.out" "$d/noeval.out" || [ "$es" -ne "$ns" ]; then
  verdict DIFF-NOEVAL "eval exit $es noeval exit $ns"
fi
if ! cmp -s "$d/eval.out" "$d/weak.out" || [ "$es" -ne "$(cat "$d/weak.status")" ]; then
  verdict DIFF-WEAK "eval exit $es weakened exit $(cat "$d/weak.status")"
fi
for m in eval noeval weak; do
  grep -q '^idris-rt: live cells 0$' "$d/$m.err" || verdict LIVE "$m $(head -c 200 "$d/$m.err")"
done
if [ $o0 = yes ]; then
  IDRIS_RT_LIVE=1 timeout 20 "$d/o0prog" < "$d/stdin" > "$d/o0.out" 2> "$d/o0.err"; os=$?
  if ! cmp -s "$d/o0.out" "$d/chez.out" || [ "$os" -ne "$cs" ]; then
    verdict DIFF-O0 "o0 exit $os chez exit $cs"
  fi
  grep -q '^idris-rt: live cells 0$' "$d/o0.err" || verdict LIVE "o0 $(head -c 200 "$d/o0.err")"
else
  verdict O0-FAILS "$(grep -m1 -iE 'error' "$d/o0.log")"
fi
[ "$cs" -eq 0 ] || verdict RUNFAIL "all exit $cs"
verdict OK "$(wc -l < "$d/eval.out") lines"
```

## reduce.py

```python
#!/usr/bin/env python3
"""reduce.py IN OUT PREDICATE: greedy delta debugging over the program's
chunks (top-level declarations, and statements of main's do block), then over
balanced parenthesised subterms, each replaced by a literal of a guessed type
(only kept when the predicate, which type checks first, still holds).
PREDICATE is a shell command run with the candidate's path; exit 0 = still
interesting."""
import re
import subprocess
import sys

src, out, pred = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(src).read()
work = out + ".cand.idr"


def interesting(t):
    open(work, "w").write(t)
    ok = subprocess.run(["sh", "-c", pred + " " + work], stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL).returncode == 0
    if ok:
        open(out, "w").write(t)
    return ok


def chunks(t):
    head, _, main = t.partition("\nmain : IO ()\nmain = do\n")
    decls = re.split(r"\n\n+", head)
    stmts = main.rstrip("\n").split("\n")
    return decls, stmts


def join(decls, stmts):
    return "\n\n".join(decls) + "\nmain : IO ()\nmain = do\n" + "\n".join(stmts) + "\n"


assert interesting(text), "the input is not interesting"
decls, stmts = chunks(text)
# The fixed part: the first 3 statements read stdin, the next 3 bind n1..n3.
changed = True
while changed:
    changed = False
    for i in range(len(stmts) - 1, 5, -1):
        c = stmts[:i] + stmts[i + 1:]
        if interesting(join(decls, c)):
            stmts = c
            changed = True
            print("dropped stmt", i, file=sys.stderr)
    for i in range(len(decls) - 1, 0, -1):
        c = decls[:i] + decls[i + 1:]
        if interesting(join(c, stmts)):
            decls = c
            changed = True
            print("dropped decl", i, file=sys.stderr)
text = join(decls, stmts)


# Subterm simplification: a parenthesised subterm replaced by `0`, `[]` or a
# variable, whichever keeps it interesting (the predicate type checks).
def subterms(t):
    stack, res = [], []
    for i, ch in enumerate(t):
        if ch == "(":
            stack.append(i)
        elif ch == ")" and stack:
            j = stack.pop()
            res.append((j, i + 1))
    res.sort(key=lambda p: p[0] - p[1])  # largest first
    return res


for sweep in range(3):
    i = 0
    before = len(text)
    while True:
        spans = subterms(text)
        if i >= len(spans):
            break
        a, b = spans[i]
        done = False
        for rep in ["0", "[]", "n1", "Lf"]:
            c = text[:a] + rep + text[b:]
            if len(c) < len(text) and interesting(c):
                text = c
                print("replaced", a, b, "by", rep, file=sys.stderr)
                done = True
                break
        if not done:
            i += 1
    if len(text) == before:
        break
open(out, "w").write(text)
```

## pred-null.sh

```sh
#!/bin/sh
# interesting: the program type checks and --no-eval hits the null operand.
repo=/home/user/idris-mlir
export IDRIS2_PREFIX=$repo/.toolchain/idris2 PATH=$repo/.toolchain/idris2/bin:$PATH
d=$(mktemp -d /tmp/claude-0/-home-user-idris-mlir/9e6c7b10-225a-5a6c-bf9d-31a304a4cdcc/scratchpad/research/differential/red.XXXX)
cp "$1" "$d/Main.idr"
cd "$d"
flock -s $repo/build/.tree.lock timeout 300 $repo/tools/compile.sh --io --directive no-eval Main.idr prog > log 2>&1
grep -q 'null operand found' log; s=$?
cd /; rm -rf "$d"; exit $s
```
