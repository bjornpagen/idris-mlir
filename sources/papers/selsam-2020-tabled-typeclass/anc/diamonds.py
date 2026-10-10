import argparse
import util

def lean4_diamonds(n):
    return """
class B (α : Type) (n : Nat) : Type := (u:Unit:=())
class L (α : Type) (n : Nat) : Type := (u:Unit:=())
class R (α : Type) (n : Nat) : Type := (u:Unit:=())
class T (α : Type) (n : Nat) : Type := (u:Unit:=())
instance LtB (α : Type) (n : Nat) [L α n] : B α n := {}
instance RtB (α : Type) (n : Nat) [R α n] : B α n := {}
instance TtL (α : Type) (n : Nat) [T α n] : L α n := {}
instance TtR (α : Type) (n : Nat) [T α n] : R α n := {}
instance BtP (α : Type) (n : Nat) [B α n] : T α n.succ := {}

new_frontend
axiom α : Type
#synth T α %s
""" % ("Nat.zero" + ".succ" * n)

def lean3_diamonds(n):
    return """
set_option class.instance_max_depth 1000
class B (α : Type) (n : nat) : Type := (u:unit:=())
class L (α : Type) (n : nat) : Type := (u:unit:=())
class R (α : Type) (n : nat) : Type := (u:unit:=())
class T (α : Type) (n : nat) : Type := (u:unit:=())
instance LtB (α : Type) (n : nat) [L α n] : B α n := {}
instance RtB (α : Type) (n : nat) [R α n] : B α n := {}
instance TtL (α : Type) (n : nat) [T α n] : L α n := {}
instance TtR (α : Type) (n : nat) [T α n] : R α n := {}
instance BtP (α : Type) (n : nat) [B α n] : T α n.succ := {}
def synthTopFn (α : Type) (n : nat) [T α n] : unit := ()
def synthTop (α : Type) : unit := synthTopFn α %s
""" % ("nat.zero" + ".succ" * n)

def coq_diamonds(n):
    return """
Module Diamonds.

Class B (X : Type) (n : nat) : Set := {}.
Class L (X : Type) (n : nat) : Set := {}.
Class R (X : Type) (n : nat) : Set := {}.
Class T (X : Type) (n : nat) : Set := {}.

Instance LtB (X : Type) (n : nat) (_ : L X n) : B X n := {}.
Instance RtB (X : Type) (n : nat) (_ : R X n) : B X n := {}.
Instance TtL (X : Type) (n : nat) (_ : T X n) : L X n := {}.
Instance TtR (X : Type) (n : nat) (_ : T X n) : R X n := {}.
Instance BtT (X : Type) (n : nat) (_ : B X n) : T X (1+n) := {}.

Example failing_tower (X : Type) : T X %d := _.
End Diamonds.
""" % n

## This version seems to cause Agda to loop.
## https://agda.readthedocs.io/en/v2.6.0.1/language/instance-arguments.html
## warns that instance resolution with overlapping instances is buggy
## and apparently loops when it would not be expected to do so.
## Thus we use the "unrolled" version below instead.
def agda_diamonds_dep(n):
    def mk_mat(n):
        if n == 0: return "mzero"
        else: return "(msucc %s)" % mk_mat(n-1)

    return """
module run%d where

data Mat : Set where
  mzero : Mat
  msucc : Mat -> Mat

record B {x} (X : Set x) (n : Mat) : Set x where field b1 : X
record L {x} (X : Set x) (n : Mat) : Set x where field l1 : X
record R {x} (X : Set x) (n : Mat) : Set x where field r1 : X
record T {x} (X : Set x) (n : Mat) : Set x where field t1 : X

open B {{...}} public
open L {{...}} public
open R {{...}} public
open T {{...}} public

instance
  BtL : ∀ {x} {n : Mat} {X : Set x} {{_ : B X n}} -> L X n
  l1 {{BtL}} = b1

instance
  BtR : ∀ {x} {n : Mat} {X : Set x} {{_ : B X n}} -> R X n
  r1 {{BtR}} = b1

instance
  LtT : ∀ {x} {n : Mat} {X : Set x} {{_ : L X n}} -> T X n
  t1 {{LtT}} = l1

instance
  RtT : ∀ {x} {n : Mat} {X : Set x} {{_ : R X n}} -> T X n
  t1 {{RtT}} = r1

instance
  TtB : ∀ {x} {n : Mat} {X : Set x} {{_ : T X n}} -> B X (msucc n)
  b1 {{TtB}} = t1

f = t1 "foo" %s
""" % (n, mk_mat(n))

def agda_diamonds(n):
    s = """
module run{n} where
""".format(n=n)

    for i in range(n+1):
        s += """
record B{i} {{x}} (X : Set x) : Set x where field b{i} : X
record L{i} {{x}} (X : Set x) : Set x where field l{i} : X
record R{i} {{x}} (X : Set x) : Set x where field r{i} : X
record T{i} {{x}} (X : Set x) : Set x where field t{i} : X

open B{i} {{{{...}}}} public
open L{i} {{{{...}}}} public
open R{i} {{{{...}}}} public
open T{i} {{{{...}}}} public

instance
  BtL{i} : ∀ {{x}} {{X : Set x}} {{{{_ : B{i} X}}}} -> L{i} X
  l{i} {{{{BtL{i}}}}} = b{i}

instance
  BtR{i} : ∀ {{x}} {{X : Set x}} {{{{_ : B{i} X}}}} -> R{i} X
  r{i} {{{{BtR{i}}}}} = b{i}

instance
  LtT{i} : ∀ {{x}} {{X : Set x}} {{{{_ : L{i} X}}}} -> T{i} X
  t{i} {{{{LtT{i}}}}} = l{i}

instance
  RtT{i} : ∀ {{x}} {{X : Set x}} {{{{_ : R{i} X}}}} -> T{i} X
  t{i} {{{{RtT{i}}}}} = r{i}
""".format(i=i)
        if i > 0:
            s += """
instance
  TtB{j} : ∀ {{x}} {{X : Set x}} {{{{_ : T{j} X}}}} -> B{i} X
  b{i} {{{{TtB{j}}}}} = t{j}
""".format(i=i, j=i-1)
    s += """
f = t{n} "foo"
""".format(n=n)
    return s

def scala_diamonds(n):
    s = ""
    for i in range(n+1):
        s += """
case class B{i}(n: Int)
case class L{i}(n: Int)
case class R{i}(n: Int)
case class T{i}(n: Int)

object Diamond{i} {{
implicit def LtB{i}(implicit l{i}: L{i}): B{i} = B{i}(l{i}.n)
implicit def RtB{i}(implicit r{i}: R{i}): B{i} = B{i}(r{i}.n)
implicit def TtL{i}(implicit t{i}: T{i}): L{i} = L{i}(t{i}.n)
implicit def TtR{i}(implicit t{i}: T{i}): R{i} = R{i}(t{i}.n)
""".format(i=i)

        if i > 0:
            s += """
implicit def BtT{j}(implicit b{j}: B{j}): T{i} = T{i}(b{j}.n)
""".format(i=i, j=i-1)
        s += """
}}
import Diamond{i}._
""".format(i=i)
    s += """
object DiamondTest {{
  implicitly[T{n}]
}}
""".format(n=n)
    return s

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--experiment', action='store', dest='experiment', type=str, default="diamonds")
    parser.add_argument('--timeout', action='store', dest='timeout', type=int, default=60)
    parser.add_argument('--max_time', action='store', dest='max_time', type=int, default=100)
    parser.add_argument('--n_runs', action='store', dest='n_runs', type=int, default=1)
    parser.add_argument('--n_low', action='store', dest='n_low', type=int, default=0)
    parser.add_argument('--n_skip', action='store', dest='n_skip', type=int, default=1)
    parser.add_argument('--n_high', action='store', dest='n_high', type=int, default=100)
    parser.add_argument('--n_step', action='store', dest='n_step', type=int, default=1)

    parser.add_argument('--lean3', action='store', dest='lean3', type=int, default=0)
    parser.add_argument('--lean4', action='store', dest='lean4', type=int, default=0)
    parser.add_argument('--coq', action='store', dest='coq', type=int, default=0)
    parser.add_argument('--agda', action='store', dest='agda', type=int, default=0)
    parser.add_argument('--scala', action='store', dest='scala', type=int, default=0)

    opts = parser.parse_args()

    results = {}
    ns      = range(opts.n_low, opts.n_high+1, opts.n_step)

    def run(key, mk_string):
        return util.run(experiment=opts.experiment,
                        ns=ns,
                        prog_info=util.mk_info(key, mk_string),
                        timeout=opts.timeout,
                        max_time=opts.max_time,
                        n_runs=opts.n_runs)

    if opts.lean4: results["Lean4"] = run("Lean4", lean4_diamonds)
    if opts.lean3: results["Lean3"] = run("Lean3", lean3_diamonds)
    if opts.coq:   results["Coq"]   = run("Coq",   coq_diamonds)
    if opts.agda:  results["Agda"]  = run("Agda",  agda_diamonds)
    if opts.scala: results["Scala"] = run("Scala", scala_diamonds)

    util.log_results(experiment=opts.experiment, ns=ns, results=results)
