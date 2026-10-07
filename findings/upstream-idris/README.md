# Upstream Idris 2 tests

`tests/upstream-idris/run GROUP` runs one group under
`third_party/Idris2/tests` against this compiler. `--list` prints the
groups that are programs over the prelude and base. A program's output is
compared with the stock Chez backend. A check or a REPL session is
compared with the stock compiler's transcript. `threads=N` is how many
tests run at once.

`results` is one line per test, tab-separated: `pass`, `fail` or `skip`,
the test, and for a failure the first error or the output mismatch.
Threads, collector finalizers, raw pointers, `unsafePerformIO` in the
test's own source, network, and the packages this compiler does not
implement are skipped, with that reason.

The groups `--list` names, run here: 538 passed, 84 failed, 20 skipped.
