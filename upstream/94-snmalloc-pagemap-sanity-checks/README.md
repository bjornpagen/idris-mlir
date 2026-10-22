<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [snmalloc] A bounded pagemap tests every lookup against its range

At snmalloc 0.7.6 (f126f1c, the pin of third_party/snmalloc), a bounded
`FlatPagemap` (`has_bounds = true`, the map a fixed-range configuration
uses) tests every `get_mut`, `get` and `set` against its range and calls
`PAL::error` when the address lies outside it
(`src/snmalloc/ds/pagemap.h`, `get_mut`, `set`, *read*). On the lookup
of a pointer the caller says is in range (`get<false>`, which `dealloc`
and the remote paths use) and on `set`, that test checks the client,
which is what snmalloc's `sanity_checks` mitigation is for.

The runtime moves to a bounded map over one heap span, so that nothing
reserves the unbounded map's 256 GiB on a strict host (proposals/0000
C5, C100; L11 §2.1). Its frees are of cells its types prove are heap
cells (D10), so the test is a fact known statically, paid on every free.

## Reproduce

Nothing to run: the test is read in the code.

## Patch

`snmalloc.patch`: on the in-range lookup and on `set`, the range test
runs only under `mitigations(sanity_checks)`; without it the lookup is
the base's subtraction and one load, and null still reads the default
entry (`free(nullptr)` stays legal). The possibly-out-of-range lookup
(`get<true>`) keeps its test. Not built.

## Upstreaming plan

Status: carried (2026-10-21); not filed. Bjorn files it, if he chooses
to, as a contribution he has reviewed and answers for (the Microsoft CLA,
as 49's README notes).

- Where: one pull request against microsoft/snmalloc main.
- Upstream test: snmalloc's own tests with a bounded configuration, with
  and without `sanity_checks`.
- The patch goes when a pinned snmalloc release gates the test.
