<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# upstream/

Bugs this repository found in the upstreams it pins (LLVM/MLIR, clang,
lld, Idris 2, and the runtime's simdutf and snmalloc), the patches it carries for them, and what to send
upstream. If you
are an agent pointed at this file with no other instructions, this file
is your task: read it all, then follow **Sending** from the first
directory whose README's status says "send next".

## Layout

Each `NN-<bug>/` is one bug. `NN` is the order to file in: lower first.

- `README.md`: the local report: symptom, reproducer, cause, what the
  patch does, when it is dropped. Its `## Upstreaming plan` says the
  status. `tests/upstream-patches` requires `## Upstreaming plan`,
  and `## Patch` with a `*.patch` file or `## Why there is no patch`
  without one.
- `submission.md`: the exact texts to post, in LLVM's review language:
  the issue (when one is needed), the pull request title and body, any
  comment, and which file is the diff.
- `llvm.patch`: the change applied to the pinned source, a commit of
  llvm main (`toolchain.lock.json`), so for a bug we send it is the pull
  request itself. `tools/bootstrap.sh` applies every
  `upstream/*/llvm.patch` in the order of their numbers (100 after 99)
  to a copy of the pinned llvm-project when it builds the toolchain;
  `tests/upstream-patches` checks they apply.
- `snmalloc.patch`: the same for the runtime's snmalloc, against
  third_party/snmalloc's gitlink (the lock's revision), which the
  bootstrap's `snmalloc` step applies, in the order of their numbers, to
  its export of the checkout for the runtime's build
  (`.toolchain/snmalloc/src`).
- `simdutf.patch`: the same for the runtime's simdutf, against
  third_party/simdutf's gitlink, which the bootstrap's `simdutf` step
  applies to its export (`.toolchain/simdutf/src`).
- `idris.patch`: the same for Idris 2, against third_party/Idris2's
  gitlink, which the bootstrap's `idris` step applies, in the order of
  their numbers, to its copy of the checkout (the checkout itself stays
  unmodified). The stock Idris builds stage 0 (the type checker, the
  frontend, the specification, the libraries and the test runner) and the
  benchmarks' Chez baseline; where it gets that code of ours wrong it is
  patched, and our code is not bent around it (D121). What elaborates
  programs, prelude and base is our type checker in compiler/checker,
  Idris's checker copied into our tree, whose fixes are our own code (its
  README). Nothing goes to Idris (**Idris** under **Rules for
  sending**).
- `pull-request.diff`: for LLVM, the pull request for a change this
  repository does not carry as a patch, since nothing in the tree reaches
  its bug (**When nothing reaches the bug** below), which the bootstrap
  therefore never applies; apply it with `git apply`, and take the commit
  message from `submission.md`, never from the file's header. For
  simdutf, the pull request to that project, which nothing reaches.
- `tests/upstream-<bug>/` (bug name without the number): this repository's
  check that the pinned tools still need the patch.
- `PINS.md`, entry `## <bug>` (or the name it gives): why we carry it and
  when it goes.

## Rules for sending

These are not optional.

- **Idris.** Nothing written here goes to idris-lang/Idris2: no issue,
  pull request, commit or comment. Its CONTRIBUTING.md ("Things We Will
  Not Accept", at the pin and on main as of 2026-10-13) wants all of
  them written and submitted by humans and will not consider anything
  that arises from generative AI or a coding agent. A bug of Idris's is
  fixed in our type checker (compiler/checker) as our own code where the
  checker has it, and patched in the stock Idris (`idris.patch`) where
  what the stock Idris builds meets it. Whether Bjorn
  reports such a bug is their call, in their own words; nothing is drafted
  for it, and no agent posts there.
- **Author.** Bjorn, as an individual, outside any employer: their own
  name and the public email on their GitHub account, no employer anywhere,
  no Co-authored-by, no @mentions.
- **Tool use is labelled.** llvm/docs/AIToolPolicy.md: content with
  substantial tool-generated parts is labelled, and the contributor has
  read and understood every line and can answer for it in review. Every
  commit message, pull request body and comment ends with
  `Assisted-by: Claude Code` as its last line. Bjorn rewrites in their own
  words whatever they would not have written; their wording is used verbatim.
- **A human approves every post.** The same policy bans agents that act
  in LLVM's spaces without human approval. An agent never runs
  `gh issue create`, `gh pr create`, `gh pr comment`, `gh issue comment`,
  a writing `gh api` call, or `git push`, without first showing Bjorn the
  exact command and full text and getting an explicit "yes, post it" for
  that one command. One approval covers one command.
- **Only to Bjorn's fork.** Never push to llvm/llvm-project.
- **No "good first issue".** Never work on an issue with that label.
- **One at a time.** Send one submission, stop, and continue only when
  Bjorn says so, normally after its first review. Adjust the rest by what
  that review asked for.
- **Trunk only.** Every pull request is against llvm main. No backports.
- **CI decides.** LLVM is not built locally for a submission (Bjorn,
  2026-10-09). Before a pull request, its diff applies to current main
  (`git apply --check`) and `git clang-format origin/main` changes nothing;
  `check-mlir` is LLVM's pre-merge CI's, on the pull request. A CI failure
  is read before anything else: one that also fails on main without the
  change is reported in the pull request, not ignored.

## Sending

Run this on Bjorn's machine, in a local Claude Code session with `gh`
logged in as them (`gh auth status`) and git's `user.name`/`user.email`
set to the name and public email for LLVM commits.

Once:
1. Clone this repository (read only) and llvm: `git clone
   --filter=blob:none https://github.com/llvm/llvm-project.git`. If Bjorn
   has no fork, ask before `gh repo fork llvm/llvm-project
   --clone=false`; add the fork as remote `fork`.

For the next submission (the first directory whose README's status says
"send next", or, after Bjorn says to go on, the next ready one):
1. Read its `README.md` and `submission.md` in full.
2. `git fetch origin main`; `git switch -c <bug> origin/main`.
3. `git apply` its `llvm.patch` (08: `pull-request.diff`). If it does
   not apply, stop and show the conflict; do not resolve it alone.
4. Commit: subject = PR title, body = PR body, last line
   `Assisted-by: Claude Code`. Leave `#<issue>` (or `#ISSUE`, `#PR`) in
   place until the number exists.
5. `git clang-format origin/main` must change nothing. No local
   `check-mlir`: the pull request's pre-merge CI runs it (**CI decides**).
6. Show Bjorn each text exactly as it will be posted (issue, PR, comment)
   and each command. Take their edits verbatim.
7. On their approval of each command: file the issue; put its number into
   the commit (`git commit --amend`); push the branch to `fork`; open the
   PR against `llvm/llvm-project:main`. Post comments the same way.
8. Stop. Give Bjorn the URLs.
9. Update this repository: the directory's `README.md` `## Upstreaming
   plan`, with the issue and PR numbers. Commit that.

Reviews: summarize what the reviewer asks, propose a change and a reply,
and wait. Push follow-ups to the same branch only after Bjorn approves
the diff and the reply. When the change on main differs from the pin's
`llvm.patch` in substance, update `llvm.patch` to match what landed.

## After a pull request lands

The patch stays until the pin moves past the merged commit. When it
does: delete `NN-<bug>/llvm.patch` (or the directory, with its
`tests/upstream-<bug>/` check and PINS.md entry, if nothing else is
left), and rebuild the toolchain (`tools/bootstrap.sh llvm`).

## When nothing reaches the bug

A patch also goes when nothing in the tree reaches its bug any more
(AGENTS.md), as 02, 16 and 22 went when the pipeline cutover deleted the
simplify rounds, the one loop of ours that met them. The report stays, as
a submission (an Idris report goes with its patch, since nothing is sent
to Idris):
- `llvm.patch` becomes `pull-request.diff` (`mv`, the same bytes), so the
  bootstrap no longer applies it and the pull request is still the diff
  to send;
- the README's `## Patch` becomes `## The fix`, and a `## Why there is no
  patch` says what reached the bug and why nothing does now;
- the `PINS.md` entry goes, since nothing of ours stands in for the
  patch;
- its `tests/upstream-<bug>/` check goes;
- the toolchain is rebuilt without the patch (`tools/bootstrap.sh llvm`).

## Adding a bug

A new bug gets a directory numbered by when it should be filed; renumber
with `git mv` and update every `upstream/NN-<bug>` path (`git grep`)
when the order changes. Reduce it to upstream dialects and tools first;
if it does not reproduce there, it is ours, not upstream's. Add the
report, reproducer, patch, `tests/upstream-<bug>/` check and PINS.md
entry in one change, and a `submission.md` once it is ready to send.

## This repository's toolchain

The LLVM pin is llvm main at 416f328b939fe1373ddc9060f6773ad4c5039f59
(LLVM 24.0.0git, llvmorg-24-init-15655, `toolchain.lock.json`), moved
from 7208ba24 on 2026-10-21, so that the patch we carry for a bug we send
is its pull request (PINS.md); every dependency moves to its latest about
weekly. One recipe builds the toolchain on all four targets:
`tools/bootstrap.sh llvm` (stage 1, the target's C library, the runtimes
and stage 2, into `.toolchain/llvm`, with LLVM's and MLIR's assertions
on in every stage) applies every
`upstream/*/llvm.patch` in the order of their numbers to the one tree
stage 1, the runtimes and stage 2 build from, and their stamps record each by
SHA-256; `tools/bootstrap.sh snmalloc` and `tools/bootstrap.sh simdutf`
do the same for `upstream/*/snmalloc.patch` and `upstream/*/simdutf.patch`
on exports of third_party/snmalloc and third_party/simdutf. No toolchain
is built yet with the patches carried now, on any target, and `make build`
refuses until one is. That is this repository's
build, not a precondition for sending anything upstream.
