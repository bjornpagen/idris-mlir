import argparse
import subprocess
import timeit
import os
import collections
import sys

def dirof(filename):
    return os.path.dirname(os.path.abspath(filename))

ProgInfo = collections.namedtuple("ProgInfo", ["key", "suffix", "mk_string", "mk_cmd", "mk_env"])

def mk_info(key, mk_string):
    if key == "Lean3":
        return ProgInfo(key="Lean3",
                        suffix=".lean",
                        mk_string=mk_string,
                        mk_cmd=(lambda filename: ["/root/app/lean3/bin/lean", filename]),
                        mk_env=(lambda env: dict(env, LEAN_PATH='/root/app/lean3/library:/root/app/lean3/leanpkg')))

    elif key == "Lean4":
        return ProgInfo(key="Lean4",
                        suffix=".lean",
                        mk_string=mk_string,
                        mk_cmd=(lambda filename: ["/root/app/lean4/bin/lean", filename]),
                        mk_env=(lambda env: dict(env, LEAN_PATH='Init=/root/app/lean4/src/Init')))

    elif key == "Lean4 (without shortcircuit)":
        return ProgInfo(key="Lean4 (without shortcircuit)",
                        suffix=".lean",
                        mk_string=mk_string,
                        mk_cmd=(lambda filename: ["/root/app/lean4nosc/bin/lean", filename]),
                        mk_env=(lambda env: dict(env, LEAN_PATH='Init=/root/app/lean4nosc/src/Init')))

    elif key == "Coq":
        return ProgInfo(key="Coq",
                        suffix=".v",
                        mk_string=mk_string,
                        mk_cmd=(lambda filename: ["/root/.opam/default/.opam-switch/build/coq.8.10.2/bin/coqc", filename]),
                        mk_env=(lambda env: env))

    elif key == "Agda":
        return ProgInfo(key="Agda",
                        suffix=".agda",
                        mk_string=mk_string,
                        mk_cmd=(lambda filename: ["/root/.cabal/bin/agda", "--overlapping-instances", "--include=%s" % dirof(filename), filename]),
                        mk_env=(lambda env: env))
    elif key == "Scala":
        return ProgInfo(key="Scala",
                        suffix=".scala",
                        mk_string=mk_string,
                        mk_cmd=(lambda filename: ["scalac", filename]),
                        mk_env=(lambda env: env))
    else:
        raise Exception("Unexpected key: %s" % key)

def run(experiment, ns, prog_info, timeout, max_time, n_runs):
    results = []
    key, suffix, mk_string, mk_cmd, mk_env = prog_info
    if not os.path.exists("/app/results"):
        os.makedirs("/app/results")

    if not os.path.exists("/app/results/%s" % experiment):
        os.makedirs("/app/results/%s" % experiment)

    outdir = "/app/results/%s/%s" % (experiment, key)
    if not os.path.exists(outdir):
        os.makedirs(outdir)

    offset = None
    for n in ns:
        filename = '%s/run%d%s' % (outdir, n, suffix)
        with open(filename, 'w', encoding='utf-8') as f:
            f.write(mk_string(n))
        cmd = mk_cmd(filename)
        env = mk_env(os.environ)
        result = timeit.timeit(lambda: subprocess.run(cmd, check=False, env=env), number=n_runs) / n_runs
        if offset is None:
            offset = result
        result = result - offset
        if result < max_time:
            results.append(result)
        if result > timeout:
            break
    return results

def log_results(experiment, ns, results):
    with open("%s.csv" % experiment, 'w') as f:
        f.write("ns")
        for n in ns: f.write(", %d" % n)
        f.write("\n")

        for key in results:
            f.write(key)
            for v in results[key]: f.write(", %f" % v)
            f.write("\n")
