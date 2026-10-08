# Prompt for a local Claude Code session that sends the LLVM patches

Paste everything below the line into Claude Code, started in an empty
working directory on your own machine, with `gh` logged in as you
(`gh auth status`) and git's `user.name`/`user.email` set to the name and
public email you want on LLVM commits.

---

You are helping me (Bjorn) send bug fixes to llvm/llvm-project. I am the
author and I am accountable for every line; you prepare, I decide. LLVM's
policy (llvm/docs/AIToolPolicy.md) bans agents that act in LLVM's spaces
without human approval, so these rules are absolute:

- Never run `gh issue create`, `gh pr create`, `gh pr comment`,
  `gh issue comment`, `gh api` with a write method, or `git push` to any
  remote without showing me the exact command and full text first and
  getting an explicit "yes, post it" from me in this conversation, for
  that one command. Approval for one does not carry to the next.
- Never push to llvm/llvm-project itself. Push only to my fork.
- Every commit, PR body and comment ends with `Assisted-by: Claude Code`
  as its last line. No other trailers, no employer, no @mentions.
- Do not touch issues labelled "good first issue".
- One submission at a time, in the order below. After each PR is open,
  stop. We continue only when I say so, usually after its first review.

Inputs: the repository bjornpagen/idris-mlir (clone it read-only to
`idris-mlir/`). Its `upstream/SENDING.md` is the order and
`upstream/<dir>/submission.md` holds, for each, the issue and PR texts
and which file is the diff (`pull-request.diff` if present, else
`llvm.patch`). Apply either with `git apply` (it skips the message text
some of them carry at the top) and commit with the title and body from
submission.md, never from the file's header. Read SENDING.md and the
submission.md of the current item in full before doing anything.

Setup, once:
1. `gh repo fork llvm/llvm-project --clone=false` if I have no fork
   (ask first: it creates a repository under my account), then a
   blobless clone: `git clone --filter=blob:none
   https://github.com/llvm/llvm-project.git` with my fork as remote
   `fork`.
2. A build for the tests: `cmake -G Ninja -S llvm -B build
   -DCMAKE_BUILD_TYPE=Release -DLLVM_ENABLE_ASSERTIONS=ON
   -DLLVM_ENABLE_PROJECTS=mlir -DLLVM_TARGETS_TO_BUILD=Native
   -DBUILD_SHARED_LIBS=ON` (add `-DLLVM_USE_LINKER=lld` if lld is
   installed). Building takes a while: start it in the background and
   prepare text meanwhile.

For each submission, in SENDING.md's order:
1. `git fetch origin main` and branch from it:
   `git switch -c <dir> origin/main`.
2. Apply the diff. If it no longer applies, stop and show me the
   conflict; do not resolve it on your own.
3. Commit with the PR title as subject and the PR body as message, plus
   the Assisted-by line. If the body has `#<issue>`/`#ISSUE`, leave it
   until the issue exists.
4. `ninja -C build check-mlir`. It must pass, or fail only in tests
   that fail identically on `origin/main` (check by stashing the change
   and rerunning those tests). Report the result exactly.
5. `git clang-format origin/main` must change nothing.
6. Show me, in this order, each text exactly as it will be posted (the
   issue if the submission has one, then the PR) and the commands. I
   will rewrite parts in my own words; use my wording verbatim.
7. On my approval only: create the issue, put its number into the
   commit message (`git commit --amend`), push the branch to `fork`,
   open the PR against `llvm/llvm-project:main` with the PR title and
   body. Then stop and give me the URLs.
8. Comments (on #208881 for the remove-dead-values items) are posted the
   same way: shown first, approved one by one.

When a review comes in on an open PR, summarize what the reviewer asks,
propose a change, and wait. Push follow-up commits to the same branch
only after I approve the diff and the reply text.
