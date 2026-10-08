# Filing

File one pull request, and nothing else. Do not open a GitHub issue. Do
not file a Bugzilla bug. LLVM reviews on GitHub, and this pull request is
the report.

- Repository: https://github.com/llvm/llvm-project
- Base: `main`
- Diff: `pull-request.diff` in this directory. Apply that file as the
  single commit of the branch (`git am`). Do not rewrite it.

The author is Bjorn, as an individual, outside any employer. The commit
and the pull request name no employer. No `Assisted-by` trailer. No
`@` mentions in the title, the body, or a comment.

GitHub squash-merges, and the landed commit is the pull request title
plus the full pull request body. The message of the branch commit is not
what lands, and a contributor without write access cannot edit the
message at merge time, so set the title and the body to the text below
when opening the pull request. The title is the subject line, tagged
`[mlir]`. The body is the rest: why the change is needed, and the unit
test `pull-request.diff` adds, `WithoutProcessSymbols` in
`mlir/unittests/ExecutionEngine/Invoke.cpp`
(`TEST(MLIRExecutionEngine, SKIP_WITHOUT_JIT(WithoutProcessSymbols))`).

## Title

```
[mlir] ExecutionEngine: an option to leave out the process's symbols
```

## Body

```
mlir::ExecutionEngine::create always adds a generator for the current
process's symbols, and LLJITBuilder links a process-symbols JITDylib by
default; both look the process up through the dynamic loader
(dlopen(NULL)), and create() aborts in cantFail when that fails, as it
always does in a statically linked executable. There is no way to create
an engine whose code calls only what the caller registers.

- ExecutionEngineOptions::linkProcessSymbols, true by default (today's
  behaviour). False: create() adds no process-symbol generator and builds
  the LLJIT with setLinkProcessSymbolsByDefault(false), so JIT-compiled
  code resolves symbols from sharedLibPaths and registerSymbols alone.
- A failure to build the LLJIT or to open the process's symbols is
  returned from create() as an error instead of aborting.

Test: WithoutProcessSymbols in mlir/unittests/ExecutionEngine/Invoke.cpp
creates engines without the process's symbols; a call of a registered
function runs, a call of abs, which the process has, fails to resolve.
```
