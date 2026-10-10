import argparse
import util

def lean4_appends(n):
    l1 = list(range(n))
    l2 = list(range(n, 2*n))
    l3 = l1 + l2
    return """
class Append {α : Type} (xs₁ xs₂ : List α) (out : outParam $ List α) : Type := (u : Unit := ())
instance AppendBase {α : Type} (xs₂ : List α) : Append [] xs₂ xs₂ := {}
instance AppendStep {α : Type} (x : α) (xs₁ xs₂ out : List α) [Append xs₁ xs₂ out] : Append (x::xs₁) xs₂ (x::out) := {}
new_frontend
set_option maxRecDepth 100000
#synth Append %s %s %s
""" % (str(l1), str(l2), str(l3))

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--experiment', action='store', dest='experiment', type=str, default="append")
    parser.add_argument('--timeout', action='store', dest='timeout', type=int, default=20)
    parser.add_argument('--max_time', action='store', dest='max_time', type=int, default=30)
    parser.add_argument('--n_runs', action='store', dest='n_runs', type=int, default=1)
    parser.add_argument('--n_low', action='store', dest='n_low', type=int, default=0)
    parser.add_argument('--n_step', action='store', dest='n_step', type=int, default=50)
    parser.add_argument('--n_high', action='store', dest='n_high', type=int, default=2000)
    parser.add_argument('--n_skip', action='store', dest='n_skip', type=int, default=1)
    parser.add_argument('--lean4', action='store', dest='lean4', type=int, default=1)
    parser.add_argument('--lean4nosc', action='store', dest='lean4nosc', type=int, default=1)
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

    if opts.lean4:     results["Lean4"]                        = run("Lean4", lean4_appends)
    if opts.lean4nosc: results["Lean4 (without shortcircuit)"] = run("Lean4 (without shortcircuit)", lean4_appends)

    util.log_results(experiment=opts.experiment, ns=ns, results=results)
