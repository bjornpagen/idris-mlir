<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Submission

Status: ready to file, not filed. One pull request to llvm/llvm-project,
no issue: the pull request carries the reproducer as its unit test.

The author is Bjorn, as an individual, outside any employer: his name and
the public email of his GitHub account, no employer, no `Co-authored-by`,
no `@` mentions. The last line of the commit message and of the pull
request body is `Assisted-by: Claude Code` (llvm/docs/AIToolPolicy.md).

The diff is `pull-request.diff`, one commit. It applies with no offset to
llvm main at b43c0361 (2026-10-15) and to the pin, 7208ba24; the files it
touches are the same at both. The squash commit message is the pull
request title, a blank line, and the pull request body. Apply the diff
with `git apply` and take the message from here, never from the diff.

## Checklist before posting

- [ ] Search llvm/llvm-project issues and pull requests again for
  `wasRegistered`, "bytecode properties" and "bytecode unregistered".
  On 2026-10-15 nothing covered it; the open bytecode pull requests
  (#229910, #229735) touch other hunks of `BytecodeReader.cpp`.
- [ ] `git fetch origin main`, `git switch -c bytecode-unregistered-properties origin/main`,
  `git apply --check` then `git apply` the diff. If it does not apply,
  stop and show the conflict.
- [ ] Commit with the title and body below.
- [ ] `git clang-format origin/main` changes nothing. Not run here (no
  clang-format on the machine that prepared this); the C++ lines are
  within 80 columns.
- [ ] Bjorn decides whether to see the test fail without the
  `BytecodeReader.cpp` hunks before posting. Not observed: no
  `MLIRIRTests` was built for this (upstream/README.md, **CI decides**).
  The body says only what the code does.
- [ ] Show Bjorn the title, the body and each command; one "yes, post it"
  per command. Push to his fork, open the pull request against `main`.
- [ ] Read the pre-merge CI (`check-mlir`, which runs `MLIRIRTests`)
  before anything else. A failure that also happens on main without the
  change is reported in the pull request.
- [ ] Afterwards: the pull request number into upstream/README.md's row
  and this directory's README `## Upstreaming plan`.

## Pull request title

```
[mlir][bytecode] Read properties as written for ops emitted unregistered
```

## Pull request body

```
The bytecode writer stores the properties of an unregistered operation
as an attribute, and those of a registered one in the encoding its
BytecodeOpInterface controls. Either way the operation refers to an
entry of the properties section, and the operation name records whether
the op was registered when it was written (the `wasRegistered` flag,
present from version 5 on).

The reader decides instead by whether the op is registered where the
file is read. PropertiesSectionReader::read uses the op's
BytecodeOpInterface if it has one, fails if the op is registered without
one, and reads an attribute only if the op is not registered. So an op
written where its dialect was not loaded, and read where it is, either
fails with "has properties but missing BytecodeOpInterface" or has its
native property decoder run over an attribute number.

parseOpWithoutRegions meant to follow the writer: for an op written
unregistered it reads an attribute from the op's own encoding. But it
tests the std::optional<bool> itself, `if (wasRegistered)`, which holds
whenever the flag is present, and it has already returned an error when
the flag is absent. That branch is dead. Made live with
`*wasRegistered`, it would read from the wrong place: the writer puts
the properties index in the op's encoding and the attribute in the
properties section.

This passes the writer's flag to PropertiesSectionReader::read, which
reads the entry as an attribute when the op was written unregistered and
dispatches as before otherwise, and removes the dead branch.
Operation::create sets properties read this way with
setPropertiesFromAttribute, as for an op parsed from the generic form.

Unchanged: an op written registered and read where its dialect is not
loaded still has its native encoding read as an attribute. Nothing can
decode that encoding without the dialect; that is a separate change.

The new OpPropertiesTest.BytecodeWrittenUnregistered writes
test_op_properties.op_with_properties to bytecode in a context that
allows unregistered dialects and does not load the dialect, reads it
back in one that loads it, and checks the properties. It needs two
contexts, so it is a unit test.

Assisted-by: Claude Code
```

## Patch file

`pull-request.diff`
