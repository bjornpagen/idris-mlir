<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Strengthening the suite: the scripts-runtime lane

## Scope

- The 20 script tests:
  - the six runtime property programs: `runtime-bigs`, `runtime-counting`,
    `runtime-doubles`, `runtime-strings`, `runtime-text`, `runtime-utf8`;
  - `runtime-api`, `runtime-archive-check`, `runtime-container`,
    `runtime-prepared`, `runtime-start`, `runtime-triple`;
  - `big-cell`, `cpu-features-aarch64`, `executable-pages`, `heap-region`,
    `io-buffer`, `page-size-mismatch`, `stack-guard-page`, `static-linking`.
- Their shared machinery in `harness/prop/`: `prop.h` and `prop.sh`.
  Nothing else uses these files.
- The googletest boxes in `foreign/idr/unittests`, test code only.

No compiler code was touched.

## The mechanism: rotating seeds and planted mutants

### Rotating seeds (`harness/prop/prop.sh`)

- `prop_run` no longer takes `--seed 1` from the run script.
- It draws 64 fresh bits from `/dev/urandom` on every run (`prop_seed`).
  When `IDRIS_PROP_SEED` is set, it uses that seed instead, to replay a run.
- The transcript of a passing run names no seed, so `expected` stays
  deterministic.
- When a run fails, the transcript ends with:
  `| seed S: IDRIS_PROP_SEED=S make test only=<test> replays this run`.
- `prop.h`'s own failure line still gives the per-case replay:
  `--seed S --case I --bytes L`.

### Mutants (`harness/prop/prop.h`)

- Each check now takes a `prop::Mutant`: a planted fault, named by what it
  does. This applies to properties (`run.property(name, mutant, body)`) and
  boxes (`run.box(name, count, mutant, body)`).
- The mutant argument is required, so a program with a check that has no
  mutant does not compile.
- The code under test asks `prop::planted(m)` at the place where it reads
  the runtime, or where it states its oracle. The answer is yes only in a
  `--mutants` run, and only inside the check that was given `m`.
- `--mutants` runs each check on the same seed and cases, with its own
  mutant planted. A check counts as having caught its mutant only if it
  failed and the mutant was planted on the way. Otherwise it prints one of:
  - `... is not caught`;
  - `... is never planted`;
  - `... is failing unplanted`.
- The run then prints `mutants: each caught`, or `mutants: k of n not
  caught`.
- `prop_run` runs the properties, then `--mutants`. Each property
  program's transcript gains two lines:
  - `mutants: each caught`
  - `<prog> --mutants: exit 0`
- `prop.h` now checks splitmix64 against its three published outputs before
  any case runs (SEARCH-28). `harness/Gen.idr` checks the same three.
- Every mutant only changes what the check observes, or what its oracle
  states. None of them corrupts the runtime's state, so no planted fault
  can crash a later check.
- Several mutants fire only at an edge: 2^62, 2^63, a tie, the 1e10 layout
  turn, a 64-byte block boundary, the 19th digit. For those, being caught
  is evidence that the cases actually reach that edge.

### Verification

- Each program was built by hand with `prop_build`'s own command
  (scratchpad).
- Each was run on 30 to 40 random seeds in both modes: every check held,
  and every mutant was caught on every seed.
- With 1 to 10 cases, the edge-only mutants are reported as "not caught" or
  "never planted", which shows that the reporting itself works.
- After that, a sweep of 30 fresh seeds per program, in both modes, found
  nothing (see the end of this file).

## Per test: what it checks now that it did not

### runtime-bigs (14 checks, 14 mutants)

- Rotating seeds. The domains already held ±2^62 and their neighbours, the
  int64 and uint64 edges, and ties (bigmodel.h).
- The mutants:

  | check | its planted fault |
  | --- | --- |
  | add, sub, mul | a small path that misses overflow and wraps to 63 bits |
  | div, mod | C's truncated division |
  | and, or, xor | sign-magnitude bitwise operations |
  | shl, shr | a negative `shr` that rounds toward zero |
  | neg, cmp, nat_from_big, pred | `cmp` on the low 64 bits |
  | from_int_s, from_int_u, to_int | `from_int_u` read as signed |
  | to_double | rounding toward zero |
  | from_double | floor instead of truncation |
  | laws | 2^62 − 1 taken for `and`'s identity |
  | shifts compose and undo | `shl` keeping 64 bits |
  | small path = large path | the small path wraps where the large one does not |
  | edge-pair box | the overflow test `> 2^62` instead of `≥`, so 2^62 wraps to −2^62; only the edge pairs reach it |
  | edge-shift box | a small `shl` as a 64-bit word |
  | ownership | a leak of every large result |

### runtime-doubles (13 checks, 13 mutants)

- Two new families of doubles:
  - "words": ±0.0, ±inf, and quiet and signalling NaNs of the least and the
    most payload, both signs;
  - "word edges": within 4 ulp of 2^52, 2^53, 2^62, 2^63, 2^64, 2^116 and
    2^117, where `to_int` wraps or loses its low bits.
- The mutants:

  | check | its planted fault |
  | --- | --- |
  | reads back | the shortest text's last digit dropped |
  | no shorter text | %.17g's digits |
  | nearest of the shortest | the other same-length text that reads back |
  | layout | the scientific form at 1e9 instead of 1e10 |
  | put_double | −0.0 written as 0.0 |
  | strtod's double | the digits past the 19th significant one read as zeros (fast path) |
  | integer literals | the literal read modulo 2^64 |
  | inf, infinity and nan | lowercase-only words |
  | malformed texts | `.5` read as strtod reads it |
  | round trip | %.16g |
  | to_int | x86's −2^63 for any value out of range |
  | exponent box | subnormals written as zero |
  | ownership | one reference too many |

- Most text mutants are planted in one place, `showOf`, where they write
  the text back through the runtime's own layout.

### runtime-strings (9 checks, 9 mutants)

| check | its planted fault |
| --- | --- |
| length, index, head | the length counted in bytes |
| tail, cons, from_char, append | `tail` drops one byte instead of one scalar |
| reverse | reverses bytes instead of scalars |
| substr | a negative start counted from the end |
| cmp | bytes compared as signed chars |
| results | an operand given back without its extra reference |
| box | a `substr` that runs past the end gives the empty string; only the box's start and length grid reaches it |
| ownership | a reference kept on a counted operand |
| the empty string | a second empty string |

### runtime-text (8 checks, 8 mutants)

- `drawWord`'s edges now include ±2^62, each with one either side.
- The mutants:

  | check | its planted fault |
  | --- | --- |
  | show_s, show_u | `show_u` signed from 2^63 up |
  | put_int | `put_int_u` signed from 2^63 up |
  | big_show | a large big shown from its low 64 bits |
  | grammar literals | a literal read through a signed word |
  | malformed literals | a trailing underscore accepted |
  | round trip | −2^63's text read as 0; only the edge family reaches it |
  | box | `0B` and `0O` read as prefixes |
  | ownership | a reference kept on its counted operand |

### runtime-utf8 (6 checks, 7 mutants)

| check | its planted fault |
| --- | --- |
| the model's box (the Standard's example) | U+FFFD per byte instead of per maximal subpart; the mutant is planted in the model itself |
| from_bytes | a Latin-1 fallback |
| box of at most 2 bytes | Java's overlong `C0 80` read as NUL |
| box of pairs across a block boundary | a first byte at a block's last offset read as stray |
| box of Table 3-7's rows | a 3- or 4-byte sequence across a boundary read as ill-formed |
| from_utf8, utf8_count | `utf8_count` as UTF-16 counts |
| ownership | a leak |

### runtime-counting (1 property, 1 mutant)

- The mutant is planted in the model: it counts only the 254 slots a
  header's `objs` field can count of a wide cell. The runtime counts every
  slot, so the two disagree once a wide cell holds an object past slot 254.

### big-cell

- What it covers now:
  - a table of values: 0, 2^62 − 1 and −2^62 (odd words), 2^62 and
    −2^62 − 1 (one limb), 2^64 − 1 (one limb), ±2^64 (two limbs), and
    2^200 + 5;
  - each value is read in both directions: the test reads the runtime's
    cell through the layout, and the runtime reads a cell the test lays
    out (`big_cmp` and `big_show` give the value);
  - a planted cell whose lowest limb is one off must read as another value;
  - 2^62 − 1 + 1 must leave the small range as a one-limb cell.
- Every check names its value.

### cpu-features-aarch64

- New property: no test name and no LLVM name belongs to two features.
- The bits check is a function, and it is shown refusing five planted
  lists:
  - a bit skipped;
  - a bit twice;
  - a 65th bit;
  - a test name twice;
  - an LLVM name twice.

### executable-pages

- The page-layout check and the `__PAGEZERO` check are now functions.
- Each is shown refusing planted segment tables, whatever the host's object
  format:
  - for the page layout: an incongruent ELF segment, one aligned under a
    page, and a Mach-O segment off a page;
  - for `__PAGEZERO`: one below 4 GiB, one not at address 0, and none.

### heap-region

- The "grows past the region" claim is now checked: some of the 2 GiB of
  later arrays must lie outside the first cell's 4 GiB region. Before, the
  count only showed that addresses inside matched.

### io-buffer

- New inputs:
  - a `\r` that ends no line, at every offset from 0 to 8;
  - a last line with no `\n` whose final byte is a `\r`, which
    `idris_rt_io_get_line` keeps;
  - no input at all (`echo-empty`).
- The default-size oracle is now written by the same awk that writes the
  input, line by line. Before, it was `tr -d '\r'`, which could not tell a
  line's own `\r` from a line ending.
- Sizes 4 and 7 are compared on the empty input too.

### page-size-mismatch

- Pages at half, a quarter, twice and four times the system's page. Before,
  it used half and four times.
- stderr is now compared exactly with the runtime's one crash line,
  `idris-mlir: the runtime is built for a N-byte page, and this system has a
  P-byte page`. Before, it only checked that two numbers appeared somewhere.

### runtime-api

- `IDRIS_RT_LIVE` at its edges: empty, `0`, `01` and `1 `, besides `1`,
  unset, `yes` and `11`. Only exactly `1` reports.

### runtime-archive-check

- New rows:
  - a static destructor: the wrapper names `dtor.o`; ELF names
    `.fini_array`; Mach-O names `__mod_init_func`, because Darwin registers
    a destructor from a constructor;
  - an archive of a clean member followed by a bad one, so the check must
    read every member, not just the first;
  - an empty archive, a check that reads nothing.

### runtime-container

- The program now also sums k·2^60, so the prepared runtime runs the large
  bigs past 2^62. It prints `28 32281802128991715328`.
- The "no executable carries bitcode" search is shown finding bitcode in the
  prepared runtime's own bitcode, so a search that finds nothing is not
  mistaken for a pass.

### runtime-prepared

- The allowlist matcher is shown refusing `dlopen`, `dlsym`, `_Znwm`,
  `__cxa_throw`, `__cxa_atexit` and a symbol of no library. This states as
  a check AGENTS' rule that nothing of ours is loaded at run time and that
  the C++ runtime is never needed.

### runtime-start

- main's value at the edges:
  - 0;
  - 2^32 and 2^32 + 255, which a 32-bit truncation would turn into 0 and
    255;
  - INT64_MIN.
- `IDRIS_RT_STACK` at its edges: empty, `0`, `-1`, ` 1`, and 2^64, which
  overflows `size_t`.
- A processor test that lacks two bits names both.
- `start.c` now takes any decimal mode as the value body returns.

### runtime-triple

- New row for another operating system.
- The environment row now replaces the triple's own environment: `gnu` and
  `musl` swap, and a three-part triple gets `-simulator`. The old row,
  `$arch-unknown-linux-gnu`, is the target itself on x86_64 or arm64 Linux
  and would have been accepted there. That was a per-target bug in the test.
- The member's triple is now matched as clang writes it into the module,
  read from `-S -emit-llvm`. The old `(\.0)*` pattern could not match a
  version that clang normalized in the middle of a triple.

### stack-guard-page

- New stacks and guards:
  - a guard of a page and a byte (two pages);
  - four whole pages, which must not round up;
  - one byte under four pages.
- Two planted modes judge the runner by a stack it cannot reach, or by one
  it goes past. Each must exit 11, which shows the handler's judgement can
  fail.

### static-linking

- The two rules (Mach-O and ELF) are now functions. Each is shown, on both
  formats whatever the host's, allowing the system's libraries and refusing
  each planted other:
  - a shared libc++;
  - `@rpath/libLLVM.dylib`;
  - a third party's library (`/opt/local`);
  - `libstdc++.so.6`;
  - `libgmp.so.10`;
  - `libLLVM.so`.

## The googletest boxes (`foreign/idr/unittests`)

### What changed

- They hold no seeds, since every box is exhaustive. Their domains already
  held the 2^62 edges (`Box.h`'s B and D64).
- Hooks and HooksCompare are the boxes whose check is one-sided:
  containment in a stated range, or agreement where a hook decides. A hook
  that states nothing would pass those checks.
- Each of their tests now also runs its check with a counting judge (a
  local `Mutant` struct) on a runtime with a planted fault, and expects at
  least one failure:

  | test | its planted fault |
  | --- | --- |
  | Pred | a predecessor that gives back its operand |
  | NatFromBig | keeps a negative |
  | NatToBig | adds one |
  | Cmp | the order swapped |
  | ToInt | the word plus one |

- To support this, the bodies became templates over the judge
  (`checkUnary`, `checkCmp`, `checkToInt`).
- `Cycles.cpp`: the judgement became `judge(Oracle, most, report)`. The new
  test `CallCycles.EachMutantOracleIsCaught` shows it failing two planted
  oracles:
  - reachability through one call only;
  - a call of itself in tail position taken for recursion.
- `Box.h` (in `foreign/idr/include`) was not edited.

### How they were verified

- I built the analyses and hooks boxes by hand in the scratchpad: each
  changed unit was compiled with its `compile_commands.json` line,
  `-Werror` included, and linked with the box's link line from
  `build.ninja`.
- All tests pass:
  - analyses: 6 tests;
  - hooks: 5 tests.
- The boxes in `build/dev` are still the old binaries until the next
  `make build`, so `make test-unit` does not run these changes yet.

## Runs

| command | result |
| --- | --- |
| `make test only=<the 20 tests> threads=2` | 20/20 pass, before and after |
| sweep: 30 fresh seeds per property program, both modes | no check failed, every mutant caught |
| hand-built `idr-box-analyses`, `idr-box-hooks` | 6/6, 5/5 |
| `make check` | 26/33: dialect-text, driver-shape, emit-dialects, facts-in-types, file-size, frontend-imports and zones fail on other lanes' files (zones lists `tests/driver-shape/witness` and `near-miss`, file-size the C++ units); none names a file of this lane |

## Compiler and runtime bugs found

None. Every strengthened check holds on the runtime as built.

### Observations

- A wrong `--runtime` is still reported as `idris-mlir: internal error:`.
  This covers a member of another triple, a missing file, and a file that
  is not an archive. SUMMARY §5 already lists it as item 36. The driver has
  no verdict for a user's bad input: every error that names no rule is
  internal (`Outcome.cpp`, `verdictOf`). No check here pins either form.
- With two unnamed bits, the processor refusal reads `this processor lacks
  bit 61 bit 63, which ...`. That is the runtime's wording, pinned as it
  is.
- On macOS, an empty `__attribute__((destructor))` is optimized away, and a
  non-empty one becomes a `__mod_init_func` constructor that calls
  `__cxa_atexit`. The archive check reports it as a constructor, which is
  right.

## Not done

- prop.h's shrinker still halves the byte length (SEARCH-20).
- The classes are still coarse (REPO-17).
- The report goes to `$work`, which is deleted at the end of the run.
- Mutants for the two-sided boxes (Ranges, Words, Constants, Fits32).
  Their checks are equalities against `__int128`, the runtime or MLIR's
  folder, so a planted fault would be caught trivially.
- Linux could not be run here. Two changes need a Linux run to confirm:
  - `page-size-mismatch`'s quarter page (1024 bytes at 4 KiB);
  - `runtime-triple`'s environment row (`-musl`).
