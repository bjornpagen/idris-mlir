<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Lane INT (integration): wire, generate, build, qualify

**Exclusive write:** the hub files in `ownership.json` under `INT`: every
`CMakeLists.txt`, the root `Makefile`, `CMakeLists.txt`,
`CMakePresets.json`, `README.md`, `foreign/README.md`,
`foreign/idr/RuntimeDigest.cmake`, `foreign/idr/include/idr/IR/Generated/`,
`foreign/idr/generated.manifest`.

**Read deeply:** P0 §7 whole and §4; AGENTS.md's last section (checks)
and "A change is done when it is built, run and passes its checks on all
four targets"; in §2 D56, D67, D91, D100, D108; in §3 C15, C16. Every
lane's handoff as it arrives; `review.md`; `L19-tests.md`.

**Contract:** INT starts when the lanes have handed off. It edits only
its hub files; every other failure goes to the coordinator, who
re-dispatches the owning lane with the failure's text. Under D111 it does the Idris half on this machine: it runs the
specification's generator on the stock host, builds the specification,
the frontend, the fork and the libraries on stock Idris, and routes each
error to its lane. Then it stops at the LLVM build. The toolchain's
bootstrap and the C++ build run on the owner's machines for the four
targets. It commits nothing; the coordinator commits.

**End state:** the hub files wired from the handoffs; the generated
outputs and manifest reproduced; `make check`, `make build`, `make test`,
`make test-idr`, `make test-unit`, `make test-mlir-tools` run on the four
targets, each failure routed; the qualification measurements recorded
with their build and input: assertions' price (D91, U8), the output loss
after deleting the cleanup points (D100), the e-graph's time and arenas
(D108), the program suite's peak memory with and without sharing (U24),
the stack bound on stage 1.

**Recipe:** wire, generate, build, route, repeat until every check passes
on every target.

**Delete:** nothing outside the hub files.

**QTT:** the linearity verifier passing after every pass is one of the
checks.

**NOT TO DO:** fix code in a lane's paths; skip a target; report a skipped
test as passed.

**Acceptance:** the cutover built, run and passing on the four targets.

**Stop and return:** when every check passes on every target, or with
the list of failures and their owners.
