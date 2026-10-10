# Snapshot addendum: Agda user manual, performance and unfolding control

Addendum to `docs/agda/SNAPSHOT.md` (same revision `83f3fcce37fc5bd11cd7da10bccbe0f59d860037`,
same `LICENSE`, both from the dependent-equality cluster's staging); merge it there.
Written by the elaborators cluster of the 2026-10-09 pass.

- **Fetched:** 2026-10-09, from
  `https://raw.githubusercontent.com/agda/agda/83f3fcce37fc5bd11cd7da10bccbe0f59d860037/<path>`
  (HEAD re-resolved with `git ls-remote`, unchanged). `LICENSE` was fetched again and is
  byte-identical to the staged copy; not stored twice.
- **Licence:** MIT-style (Agda `LICENSE`).
- **Threads:** elaborators (Fast dependent type checking and elaboration).

**What is here and why.**
- `doc/user-manual/tools/performance.rst`: the whole "Performance debugging" page; it says of
  itself "This is a stub", lists `--profile=definitions|modules|internal`, `+RTS -s`, and
  points to `agda-bench`. It contains no measurements.
- `doc/user-manual/language/lossy-unification.lagda.rst`: `--lossy-unification` and
  `INJECTIVE_FOR_INFERENCE` (try `es₀ = es₁` before unfolding `f es₀ = f es₁`; sound, not
  complete; the constant-function counterexample).
- `doc/user-manual/language/opaque-definitions.lagda.rst`: `opaque` blocks and `unfolding`
  clauses, after Gratzer et al.'s controlling-unfolding theory, as an elaborator-level
  mechanism for readability and performance.

**Not taken:** `tools/command-line-options.rst` (72 KB), the type checker sources. Nothing
was built or run.

## File manifest

The files this addendum adds: 3 files, 14,460 bytes in all.

```
SHA-256                                                               bytes  path
4dc65def846a3edb2b658f1aee0cf994482e8237fa6b4b12023b420ef01fd45c       4371  doc/user-manual/language/lossy-unification.lagda.rst
47a9cc13d746e65c0287884c1ee822229cff86981f302a4852181765a79cd5aa       7794  doc/user-manual/language/opaque-definitions.lagda.rst
4c80d29662fcc2ef128fc706b55a28330ceee7d874d85eaa32cdaedb8ed39346       2295  doc/user-manual/tools/performance.rst
```
