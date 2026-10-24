
## 2026-10-24: the stock Idris swapped in

INT-27 built Idris 89ba32eb5 with the 16 carried patches (96, 104 to 118)
into `.toolchain/idris2.new` by the bootstrap's own recipe under a sandbox
(PREFIX the final path, DESTDIR staging), verified it (all 16 patch
reproducers pass, 12 on the old; the checker, spec, specgen, frontend and
knowngen build against it; `make check` runs, 21 of 28), and the
coordinator swapped it in after INT-26: `.toolchain/idris2.old` is the old
tree, `idris2.new` a symlink to the new one for scripts that named it.
Every export's next make rebuilds host-libs, checker and spec against the
new provenance. Roll back: `mv idris2 idris2.new; mv idris2.old idris2`.
