Approach changed: the old diff toggled two lookup paths with one flag and broke create(); now the process's symbols live only in the LLJIT's process-symbols JITDylib, which always exists, and the option decides only whether it holds the process generator.

# Filing

File one pull request, and nothing else. Do not open a GitHub issue. Do
not file a Bugzilla bug. LLVM reviews on GitHub, and this pull request is
the report.

- Repository: https://github.com/llvm/llvm-project
- Base: `main`
- Diff: `pull-request.diff` in this directory, one commit. It has no
  `From:` line: apply it with `git apply` and commit it as yourself with
  the title and body below.

The author is Bjorn, as an individual, outside any employer. The commit
and the pull request name no employer. No `Assisted-by` trailer. No
`@` mentions in the title, the body, or a comment.

GitHub squash-merges, and the landed commit is the pull request title
plus the full pull request body, so set them to the text below when
opening the pull request.

## Title

```
[mlir][ExecutionEngine] Make linking the process's symbols optional
```

## Body

```
ExecutionEngine::create resolves the process's symbols twice: it adds a
DynamicLibrarySearchGenerator for the current process to the main
JITDylib, and LLJITBuilder creates its own "<Process Symbols>" JITDylib,
linked after main and the platform. Both open the process through the
dynamic loader (dlopen(NULL)), and create() aborts in cantFail when that
fails, as it always does in a statically linked executable. There is no
way to create an engine whose code calls only the symbols it is given.

The process's symbols now come from one place: the LLJIT's
process-symbols JITDylib, which create() sets up itself, and the new
ExecutionEngineOptions::enableProcessSymbols (true by default) decides
whether it holds the generator. The JITDylib always exists, since the
generic IR platform links it and does not start without it. Whether
JIT-compiled code may reach the host process is the caller's choice, as
it is in LLJITBuilder, so it stays an option.

ExecutionEngine::lookup now searches the main JITDylib's link order,
which ends with the process-symbols JITDylib, so it resolves a name the
way the JIT-compiled code does. With the default options it returns
what it returned before; the platform JITDylib in between defines only
ORC's own __lljit.* helpers. A failure to build the LLJIT, opening the
process included, is returned from create() instead of aborting, as
create() already does when it cannot detect the host.

Test: WithoutProcessSymbols in mlir/unittests/ExecutionEngine/Invoke.cpp
calls labs from JIT-compiled code and looks it up. Both succeed with the
process's symbols and fail without them, and the call reaches the
registered function when one is registered under that name.
```
