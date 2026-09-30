# Differential testing: the prototype

The scratch prototype behind `differential-testing.md` section 9, kept here
because the scratch directory does not survive. It is Python and sh for
speed of writing; section 3.3 of the main file says why the real generator
belongs in Idris, in `tests/`.

## How to run it

```sh
# the compiler under test: a clean build of one commit in $here/tree
# (tree.commit names it; only .toolchain is a symlink to the repository's)
# one program: generate, build 5 ways, compare, one verdict line
./run4.sh SEED [vect]
# a batch, three at a time (jobs4.txt: "SEED MODE" per line)
xargs -P 3 -L 1 ./run4.sh < jobs4.txt > batch4.log
# judge the raw verdicts against the allowlist
python3 classify.py runs4
# reduce a failure (PREDICATE exits 0 while the candidate is interesting;
# FIXED is the number of leading statements of main to keep)
FIXED=0 python3 reduce.py IN.idr OUT.idr './pred.sh "null operand" "--directive no-eval"'
# keep the contract text of a build that fails (for idris-mlir-opt experiments)
./keep.sh IN.idr DIR [--directive no-eval]
# a candidate fix: the contract text through a patched idris-mlir-cc, linked, run, against Chez
CC_FIX=fix/idris-mlir-cc-w ./fixcheck.sh IN.idr eval|noeval [-p base]
```

Builds per program: Chez (the reference and the type checker), idris-mlir
with evaluation, with `--directive no-eval`, the quantity-weakened variant
(every `(1 _ : T)` rewritten to `T`, section 8.2 of the main file; skipped
when the program has no linear binder), and O0 (the contract text through
the pipeline's steps after `idr-simplify` only, with idris-mlir-opt, then
mlir-translate and clang against the runtime archive). Every idris-mlir
build runs with `IDRIS_RT_LIVE=1` and must report 0 live cells. A run that
dies of SIGSEGV is rerun under `ulimit -s unlimited` so the classifier can
tell stack exhaustion from a crash. Raw verdicts: `OK`, `REJECT-IDRIS` (the
generator's fault), `REJECT-OURS` (`unsupported (…)`), `CRASH-COMPILE`,
`DIFF-CHEZ`, `DIFF-NOEVAL`, `DIFF-WEAK`, `DIFF-O0`, `O0-FAILS`, `LIVE`,
`RUNFAIL`. The first failing build decides the verdict, so a program that
crashes the eval build is not also run through the others.

`classify.py` turns them into AGREE, GEN (discarded), REJECT(reason),
KNOWN(id), QUIRK(id), LIMIT(id), O0GAP and BUG(signature), with the
allowlist `known.tsv` as data: every known divergence is one line with its
reason, never a special case in code.

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

## run4.sh

```sh
#!/bin/sh
# run4.sh SEED [vect]: one generated program, five builds, one verdict line.
# run1.sh plus: build outputs are deleted on exit (disk), Chez gets 60 s, and
# the compiler is a clean build of one commit in $here/tree (no tree lock needed).
# Verdicts: OK, REJECT-IDRIS (the generator's fault), REJECT-OURS <reason>,
# CRASH-COMPILE, DIFF-CHEZ, DIFF-NOEVAL, LIVE, RUNFAIL.
here=/tmp/claude-0/-home-user-idris-mlir/9e6c7b10-225a-5a6c-bf9d-31a304a4cdcc/scratchpad/research/differential
repo=$here/tree
export IDRIS2_PREFIX=$repo/.toolchain/idris2 PATH=$repo/.toolchain/idris2/bin:$PATH IDRIS_MLIR_ROOT=$repo
seed=$1
mode=${2:-plain}
d=$here/runs4/$seed-$mode
cleanup() { rm -rf "$d"/*/build "$d"/o0prog "$d"/o0.ll "$d"/o0.mlir; }
trap cleanup EXIT
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
  if [ $m = weak ] && cmp -s "$d/weak/Main.idr" "$d/Main.idr"; then
    # Nothing to weaken: the variant is the eval build.
    rm -rf "$d/weak"; cp -a "$d/eval" "$d/weak"; echo same > "$d/weak.log"; continue
  fi
  dir=
  [ $m = noeval ] && dir="--directive no-eval"
  timeout 600 $repo/tools/compile.sh --io $pk $dir "$d/$m/Main.idr" prog > "$d/$m.log" 2>&1
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
timeout 60 "$d/chez/build/exec/prog" < "$d/stdin" > "$d/chez.out" 2> "$d/chez.err"; cs=$?
for m in eval noeval weak; do
  IDRIS_RT_LIVE=1 timeout 60 "$d/$m/build/exec/prog" < "$d/stdin" > "$d/$m.out" 2> "$d/$m.err"; echo $? > "$d/$m.status"
done
# A SIGSEGV is rerun with no stack limit: the classifier's stack-exhausted test.
for m in eval noeval weak; do
  if [ "$(cat "$d/$m.status")" -eq 139 ]; then
    (ulimit -s unlimited; IDRIS_RT_LIVE=1 timeout 60 "$d/$m/build/exec/prog" < "$d/stdin" > "$d/$m.unl.out" 2> "$d/$m.unl.err"; echo $? > "$d/$m.unl.status")
  fi
done
echo $cs > "$d/chez.status"
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
  IDRIS_RT_LIVE=1 timeout 60 "$d/o0prog" < "$d/stdin" > "$d/o0.out" 2> "$d/o0.err"; os=$?
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

## classify.py

```python
#!/usr/bin/env python3
"""classify.py RUNS_DIR: the runner's raw verdicts, judged against known.tsv.

Classes: AGREE, GEN (Idris rejected the generator's program: discarded),
REJECT(reason), KNOWN(id), QUIRK(id), LIMIT(id), BUG(raw verdict).
Chez is the reference only where no allowlist entry says its behaviour is an
implementation detail or a resource limit."""
import collections, glob, os, re, sys

here = os.path.dirname(os.path.abspath(__file__))
allow = []
for line in open(os.path.join(here, "known.tsv")):
    if line.startswith("#") or not line.strip():
        continue
    i, cls, where, rx, reason = line.rstrip("\n").split("\t")
    allow.append((i, cls, where, re.compile(rx), reason))


def rd(p):
    try:
        return open(p, errors="replace").read()
    except OSError:
        return None


def classify(d):
    v = (rd(os.path.join(d, "verdict")) or "").split()
    if len(v) < 3:
        return "INCOMPLETE", ""
    raw, rest = v[2], " ".join(v[3:])
    if raw == "OK":
        return "AGREE", ""
    if raw == "REJECT-IDRIS":
        return "GEN", rest
    if raw == "REJECT-OURS":
        return "REJECT", rest
    if raw == "O0-FAILS":
        # O0 is this prototype's own pipeline (no idr-simplify): a gap there
        # is a finding about optionality, not a miscompilation.
        return "O0GAP", rest
    logs = "".join(rd(p) or "" for p in glob.glob(os.path.join(d, "*.log")))
    src = rd(os.path.join(d, "Main.idr")) or ""
    for i, cls, where, rx, reason in allow:
        text = {"log": logs, "source": src}.get(where)
        if text is None:
            text = rd(os.path.join(d, where)) or ""
        if where == "eval.status":
            continue  # tested below, with its confirmation
        if rx.search(text):
            return f"{cls.upper()}({i})", rest
    # stack exhausted: a SIGSEGV that an unlimited stack turns into Chez's answer
    chez = rd(os.path.join(d, "chez.out"))
    segv = [m for m in ("eval", "noeval", "weak")
            if (rd(os.path.join(d, f"{m}.status")) or "").strip() == "139"]
    if segv and all(rd(os.path.join(d, f"{m}.unl.out")) == chez and
                    (rd(os.path.join(d, f"{m}.unl.status")) or "").strip() ==
                    (rd(os.path.join(d, "chez.status")) or "0").strip()
                    for m in segv):
        return "LIMIT(stack-exhausted)", rest
    # A crash's signature: the first diagnostic of the failing build, with
    # locations and SSA names dropped, so one bug is one row.
    m = re.search(r"(?m)^(?:\S+\.idr:\d+:\d+|<unknown>:0): error: (?:loc\([^\n]*?\): )?([^\n]*)", logs)
    sig = re.sub(r"%\w+", "%", m.group(1))[:90] if m else ""
    return f"BUG({raw})", (sig or rest)


def main():
    runs = sys.argv[1]
    counts = collections.Counter()
    rows = []
    for d in sorted(glob.glob(os.path.join(runs, "*")),
                    key=lambda p: (os.path.basename(p).split("-")[1],
                                   int(os.path.basename(p).split("-")[0]))):
        c, why = classify(d)
        counts[c.split("(")[0] if c.startswith("REJECT") else c] += 1
        rows.append((os.path.basename(d), c, why))
    for r in rows:
        if r[1] != "AGREE":
            print("\t".join(r))
    print("---")
    for c, n in counts.most_common():
        print(f"{n:4d} {c}")
    print(f"{sum(counts.values()):4d} total")


main()
```

## known.tsv

```
# The oracle's allowlist: every known divergence, as data, with its reason.
# id	class	matches	regex	reason
# class: known  = our bug, already filed; the verdict is KNOWN(id), not BUG.
#        quirk  = Chez's behaviour is an implementation detail, not Idris's meaning;
#                 the verdict is QUIRK(id) and the line is not compared.
#        limit  = a resource limit, not a meaning; the verdict is LIMIT(id).
# matches: log = any build log; eval.err etc. = that stream; chez.status = Chez's exit.
linear-catchall	known	log	uses a linear value that is already used on the same path	a case on a linear binder whose default region names the scrutinee (uniqueness-pipeline.md 6.5 D5); being fixed
put-char-high	quirk	source	putChar[^\n]*chr[^\n]*(12[89]|1[3-9][0-9]|2[0-5][0-9])	Idris's Char is a code point; Chez writes one byte (latin-1), we write UTF-8; the Prelude leaves the encoding to the backend
chez-timeout	limit	chez.status	^124$	the reference did not finish within 60 s, so there is no reference answer
stack-exhausted	limit	eval.status	^139$	SIGSEGV from an 8 MiB C stack under non-tail recursion that Chez's growable stack absorbs; confirmed per case by rerunning under `ulimit -s unlimited`
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
import os
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
    for i in range(len(stmts) - 1, int(os.environ.get("FIXED", "6")) - 1, -1):
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
        for rep in ["0", "[]", "n1", "Lf", "a", "b", "x"]:
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

## pred.sh, keep.sh

```sh
#!/bin/sh
# pred.sh 'REGEX' 'FLAGS' FILE: interesting when the scratch build's log of FILE matches REGEX.
D=/tmp/claude-0/-home-user-idris-mlir/9e6c7b10-225a-5a6c-bf9d-31a304a4cdcc/scratchpad/research/differential
export IDRIS2_PREFIX=$D/tree/.toolchain/idris2 PATH=$D/tree/.toolchain/idris2/bin:$PATH IDRIS_MLIR_ROOT=$D/tree
w=$(mktemp -d $D/recheck/p.XXXX); cp "$3" $w/Main.idr; cd $w
timeout 300 $D/tree/tools/compile.sh --io $2 Main.idr prog > log 2>&1
grep -qE "$1" log; s=$?
cd /; rm -rf $w; exit $s
```

```sh
#!/bin/sh
# keep.sh FILE DIR [compile flags]: compile with the scratch build and keep build/exec/prog.mlir
# although the build fails (unlink made a no-op under strace).
D=/tmp/claude-0/-home-user-idris-mlir/9e6c7b10-225a-5a6c-bf9d-31a304a4cdcc/scratchpad/research/differential
export IDRIS2_PREFIX=$D/tree/.toolchain/idris2 PATH=$D/tree/.toolchain/idris2/bin:$PATH IDRIS_MLIR_ROOT=$D/tree
f=$1; w=$2; shift 2
rm -rf $w; mkdir -p $w; cp "$f" $w/Main.idr; cd $w
timeout 600 strace -f -o /dev/null -e trace=unlink,unlinkat -e inject=unlink,unlinkat:retval=0 $D/tree/tools/compile.sh --io "$@" Main.idr prog > log 2>&1
tail -3 log
```

## fixcheck.sh, and the candidate fixes it tested

`fix/idris-mlir-cc` and `fix/idris-mlir-cc-w` are the scratch build's
idris-mlir-cc relinked with one or two recompiled objects (`llvm-ar r` into
a copy of `libidr_dialect.a`, then ninja's own link command with the copy),
so the scratch build itself is never changed.

```sh
#!/bin/sh
# fixcheck.sh FILE MODE(eval|noeval) [-p base]: the program's contract text through the
# patched idris-mlir-cc (symbol-dce before idr-prune), linked and run, against Chez.
D=/tmp/claude-0/-home-user-idris-mlir/9e6c7b10-225a-5a6c-bf9d-31a304a4cdcc/scratchpad/research/differential
export IDRIS2_PREFIX=$D/tree/.toolchain/idris2 PATH=$D/tree/.toolchain/idris2/bin:$PATH IDRIS_MLIR_ROOT=$D/tree
f=$1; mode=$2; shift 2
w=$(mktemp -d $D/recheck/f.XXXX)
fl=; ne=; [ "$mode" = noeval ] && { fl="--directive no-eval"; ne=--no-eval; }
$D/keep.sh "$f" $w/k $fl "$@" > /dev/null
cp "$f" $w/Main.idr; cd $w
timeout 300 idris2 --no-banner --no-color --no-prelude "$@" --cg chez -o cprog Main.idr > chez.log 2>&1
echo 123 > in; timeout 60 build/exec/cprog < in > c.out 2>&1; cs=$?
if ! timeout 600 ${CC_FIX:-$D/fix/idris-mlir-cc} k/build/exec/prog.mlir -o p.o $ne > cc.log 2>&1; then echo "FIXED CC FAILS: $(grep -m1 error cc.log | cut -c1-120)"; cd /; rm -rf $w; exit 1; fi
$D/tree/.toolchain/llvm-musl/bin/clang --target=x86_64-unknown-linux-musl -fuse-ld=lld -static-pie p.o -o p -lgmp > ld.log 2>&1 || { echo "LINK FAILS $(head -2 ld.log)"; cd /; rm -rf $w; exit 1; }
IDRIS_RT_LIVE=1 timeout 60 ./p < in > o.out 2> o.err; os=$?
if cmp -s c.out o.out && [ $cs = $os ]; then echo "FIXED AGREES ($(wc -l < o.out) lines) $(tail -1 o.err)"; else echo "FIXED DIFFERS chez $cs ours $os"; fi
cd /; rm -rf $w
```

```diff
--- tree/foreign/idr/lib/Passes/Simplify.cc	2026-09-30 01:58:49.885033222 +0000
+++ fix/Simplify.cc	2026-09-30 03:33:37.187041942 +0000
@@ -215,9 +215,9 @@
       "idr-canonicalize",
       "cse",
       "idr-eval",
-      "idr-prune",
       "symbol-dce",
-      "remove-dead-values",
+      "idr-prune",
+      "remove-dead-values{canonicalize=false}",
       "symbol-dce",
   };
 }
--- tree/foreign/idr/lib/Passes/Prune.cc	2026-09-30 00:44:45.000000000 +0000
+++ fix/Prune.cc	2026-09-30 03:32:17.547550848 +0000
@@ -105,8 +105,14 @@
 
 struct Prune : idr::impl::IdrPruneBase<Prune> {
   void runOnOperation() override {
-    unsigned guarded = guardUnreadParameters(getOperation());
-    numPoisoned += guarded;
+    // Emptying code removes calls, and passing poison removes uses, and
+    // either can leave more to do: repeat until nothing changes, the state
+    // remove-dead-values will see.
+    unsigned emptied = 0, guarded = 0;
+    for (bool again = true; again;) {
+    unsigned guardedNow = guardUnreadParameters(getOperation());
+    numPoisoned += guardedNow;
+    guarded += guardedNow;
     DataFlowSolver solver(DataFlowConfig().setInterprocedural(true));
     loadBaselineAnalyses(solver);
     if (failed(solver.initializeAndRun(getOperation())))
@@ -130,7 +136,10 @@
     for (Block *block : unreachable)
       empty(*block);
     numEmptied += unreachable.size();
-    if (unreachable.empty() && !guarded)
+    emptied += unreachable.size();
+    again = !unreachable.empty() || guardedNow != 0;
+    }
+    if (emptied == 0 && !guarded)
       markAllAnalysesPreserved();
   }
 };
```

