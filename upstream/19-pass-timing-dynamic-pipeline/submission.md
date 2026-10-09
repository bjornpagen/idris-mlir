# Submission

Where: a comment on https://github.com/llvm/llvm-project/pull/169615
(open; its change to `PassTiming.cpp` is what `llvm.patch` carries). It
answers the question its review left open, how the change is tested: the
pull request's test passes at HEAD. No new issue (#169443 is the report),
no pull request of our own while #169615 is open (README.md, Upstreaming
plan). Author is Bjorn, as an individual, work done outside any employer.
No @mentions. The comment ends with `Assisted-by: Claude Code` as its last
line (llvm/docs/AIToolPolicy.md).

The text below is ready to paste: each prose paragraph is one line, since
GitHub renders a single newline in a comment as a line break. The diff is
the change to #169615's own `pass-timing.mlir` (head 85925cbf6bc5, blob
2b8c3068); it also applies to main's file with #169615's test hunk
applied. Its `+` side is the test hunk of `llvm.patch`.

Paste everything between the markers.

----- paste -----

This test passes at HEAD because FileCheck canonicalizes horizontal whitespace unless it runs with `--strict-whitespace`, so the indentation in the check lines is never compared, and the rows come in the same order whether the inliner's `'func.func' Pipeline` is nested in it or printed beside it. With `--strict-whitespace`, FileCheck still strips the leading whitespace of a check, so the checks below start at the `%)` that ends the time column; the indentation of each name is then matched exactly.

With this change to the test, both RUN lines fail at HEAD:

```
pass-timing.mlir:116:27: error: DYNAMIC-PIPELINE-NEXT: expected string not found in input
// DYNAMIC-PIPELINE-NEXT: %)    'func.func' Pipeline
                          ^
<stdin>:15:37: note: scanning from here
    0.0000 (  0.8%)    (A) CallGraph
                                    ^
<stdin>:16:18: note: possible intended match here
    0.0000 (  4.3%)  'func.func' Pipeline
                 ^
```

and both pass with this PR's change to PassTiming.cpp. I checked this with an mlir-opt from 7208ba24 (plus unrelated local patches), where PassTiming.cpp and pass-timing.mlir are the same as on main today, linked once with the PassTiming.cpp of main and once with this PR's. With the PR's, each of the two RUN lines passed 300 runs out of 300. I have not run check-mlir.

```diff
diff --git a/mlir/test/Pass/pass-timing.mlir b/mlir/test/Pass/pass-timing.mlir
--- a/mlir/test/Pass/pass-timing.mlir
+++ b/mlir/test/Pass/pass-timing.mlir
@@ -5,8 +5,8 @@
 // RUN: mlir-opt %s -mlir-disable-threading=false -verify-each=true -pass-pipeline='builtin.module(func.func(cse,canonicalize,cse))' -mlir-timing -mlir-timing-display=list 2>&1 | FileCheck -check-prefix=MT_LIST %s
 // RUN: mlir-opt %s -mlir-disable-threading=false -verify-each=true -pass-pipeline='builtin.module(func.func(cse,canonicalize,cse))' -mlir-timing -mlir-timing-display=tree 2>&1 | FileCheck -check-prefix=MT_PIPELINE %s
 // RUN: mlir-opt %s -mlir-disable-threading=true -verify-each=false -test-pm-nested-pipeline -mlir-timing -mlir-timing-display=tree 2>&1 | FileCheck -check-prefix=NESTED_PIPELINE %s
-// RUN: mlir-opt %s -mlir-disable-threading=true -verify-each=true -pass-pipeline='builtin.module(func.func(cse,canonicalize,cse),inline)' -mlir-timing -mlir-timing-display=tree 2>&1 | FileCheck -check-prefix=DYNAMIC-PIPELINE %s
-// RUN: mlir-opt %s -mlir-disable-threading=false -verify-each=true -pass-pipeline='builtin.module(func.func(cse,canonicalize,cse),inline)' -mlir-timing -mlir-timing-display=tree 2>&1 | FileCheck -check-prefix=DYNAMIC-PIPELINE %s
+// RUN: mlir-opt %s -mlir-disable-threading=true -verify-each=true -pass-pipeline='builtin.module(func.func(cse,canonicalize,cse),inline)' -mlir-timing -mlir-timing-display=tree 2>&1 | FileCheck -check-prefix=DYNAMIC-PIPELINE --strict-whitespace %s
+// RUN: mlir-opt %s -mlir-disable-threading=false -verify-each=true -pass-pipeline='builtin.module(func.func(cse,canonicalize,cse),inline)' -mlir-timing -mlir-timing-display=tree 2>&1 | FileCheck -check-prefix=DYNAMIC-PIPELINE --strict-whitespace %s
 
 // LIST: Execution time report
 // LIST: Total Execution Time:
@@ -97,23 +97,27 @@
 // NESTED_PIPELINE-NEXT: Rest
 // NESTED_PIPELINE-NEXT: Total
 
+// The inliner runs its default pipeline on each callable as a dynamic pipeline,
+// which is timed within the inliner's timer. FileCheck compares the nesting
+// only with --strict-whitespace: each check starts at the "%)" that ends the
+// time column, so that the indentation of the name is matched exactly.
 // DYNAMIC-PIPELINE: Execution time report
 // DYNAMIC-PIPELINE: Total Execution Time:
 // DYNAMIC-PIPELINE: Name
-// DYNAMIC-PIPELINE-NEXT: Parser
-// DYNAMIC-PIPELINE-NEXT: 'func.func' Pipeline
-// DYNAMIC-PIPELINE-NEXT:   CSE
-// DYNAMIC-PIPELINE-NEXT:     (A) DominanceInfo
-// DYNAMIC-PIPELINE-NEXT:   Canonicalizer
-// DYNAMIC-PIPELINE-NEXT:   CSE
-// DYNAMIC-PIPELINE-NEXT:     (A) DominanceInfo
-// DYNAMIC-PIPELINE-NEXT: Inliner
-// DYNAMIC-PIPELINE-NEXT:   (A) CallGraph
-// DYNAMIC-PIPELINE-NEXT:   'func.func' Pipeline
-// DYNAMIC-PIPELINE-NEXT:     Canonicalizer
-// DYNAMIC-PIPELINE-NEXT: Output
-// DYNAMIC-PIPELINE-NEXT: Rest
-// DYNAMIC-PIPELINE-NEXT: Total
+// DYNAMIC-PIPELINE-NEXT: %)  Parser
+// DYNAMIC-PIPELINE-NEXT: %)  'func.func' Pipeline
+// DYNAMIC-PIPELINE-NEXT: %)    CSE
+// DYNAMIC-PIPELINE-NEXT: %)      (A) DominanceInfo
+// DYNAMIC-PIPELINE-NEXT: %)    Canonicalizer
+// DYNAMIC-PIPELINE-NEXT: %)    CSE
+// DYNAMIC-PIPELINE-NEXT: %)      (A) DominanceInfo
+// DYNAMIC-PIPELINE-NEXT: %)  Inliner
+// DYNAMIC-PIPELINE-NEXT: %)    (A) CallGraph
+// DYNAMIC-PIPELINE-NEXT: %)    'func.func' Pipeline
+// DYNAMIC-PIPELINE-NEXT: %)      Canonicalizer
+// DYNAMIC-PIPELINE-NEXT: %)  Output
+// DYNAMIC-PIPELINE-NEXT: %)  Rest
+// DYNAMIC-PIPELINE-NEXT: %)  Total
 
 func.func @foo() {
   return
```

The change also fixes a second symptom, in case it is useful for the description: a dynamic pipeline run from inside another one on the same op name. With `-pass-pipeline='builtin.module(composite-fixed-point-pass{name=Outer pipeline="composite-fixed-point-pass{name=Inner pipeline=canonicalize}"})'`, both op-agnostic pipelines nest under the root with the same key at HEAD, so they share one `'any' Pipeline` row whose timer is started a second time before it stops; with the change, each is nested in its own pass.

Assisted-by: Claude Code

----- end -----
