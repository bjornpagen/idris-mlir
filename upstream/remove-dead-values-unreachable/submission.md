Approach changed: the old patch added three inline poison loops at the three erase sites; now one helper, replaceUsesWithPoison, is the only way the pass removes a use, so no erased value can leave a null operand behind.

# Submission

Status: file. Three texts, in this order: a comment on the open pull
request https://github.com/llvm/llvm-project/pull/208881, a short comment
on https://github.com/llvm/llvm-project/issues/206920 and
https://github.com/llvm/llvm-project/issues/203226, and a follow-up pull
request stacked on #208881. There is no new issue.

Author: Bjorn, as an individual; the work was done outside any employer.
No employer, no Assisted-by or Co-authored-by trailer, no Contributed-by
line, no @mentions. LLVM reviews on GitHub pull requests (Phabricator is
read-only, not Bugzilla); a pull request is one commit, squash-merged with
the title and body below as its message.

`@address_taken_callee` is posted on #208881 by
`remove-dead-values-address-taken`. It is not repeated here.

Which part of `llvm.patch` is whose:

- #208881 (jjppp's, unchanged): the hunk at `cleanUpDeadVals` step 4 that
  replaces the uses of a dead function argument with `ub.poison`, and the
  test module `@unreachable_func_with_for_loops`.
- Offered to #208881 in the comment: the test module `@call_in_dead_region`.
- From `remove-dead-values-address-taken`: the test module
  `@address_taken_callee`.
- The follow-up pull request: everything else, which is the diff under
  "Follow-up pull request" below. It applies to the head of #208881 as it
  is (both #208881's files start from the blobs at llvmorg-23.1.2:
  `6e55bc390` and `390a44806`).

## Comment on #208881

----- paste -----

The same null operand comes up in reachable functions as well, so I think poisoning the uses at the point the pass erases a value is the right fix, rather than erasing the body of an uncalled function. Since #153973, liveness marks every value in code that dead-code analysis rules out as dead. The pass keeps two kinds of ops there that may still use such a value: calls, which the walk skips, and region branch ops with side effects, whose non-forwarded operands it does not touch. Function arguments are one of three places where the cleanup calls `dropAllUses`. The other two are block arguments (step 2) and op results (`dropUsesAndEraseResults`, step 6). These fail the same way at llvmorg-23.1.2, and after this PR as well:

```mlir
func.func private @ext(i32)
func.func private @never() -> i1 {
  %false = arith.constant false
  return %false : i1
}
func.func @main(%v: i32) {
  %no = func.call @never() : () -> i1
  cf.br ^bb1(%v : i32)
^bb1(%a: i32):
  scf.if %no {
    func.call @ext(%a) : (i32) -> ()   // null operand found
  }
  return
}
```

```mlir
func.func private @ext(i32)
func.func private @never() -> i1 {
  %false = arith.constant false
  return %false : i1
}
func.func private @f() -> i32 {
  %c = arith.constant 1 : i32
  return %c : i32
}
func.func @main() {
  %r = func.call @f() : () -> i32
  %no = func.call @never() : () -> i1
  scf.if %no {
    %s = func.call @f() : () -> i32
    func.call @ext(%s) : (i32) -> ()   // null operand found
  }
  return
}
```

I'll put up a follow-up stacked on this PR. It moves the poison replacement into one helper, which all four places that erase a value use (function arguments, block arguments, op results and erased ops), so the pass has no `dropAllUses` left. Here is one more test for this PR, if you want it. The surviving user is a call rather than an `scf.for`, and `@g` does have a caller, just in a region that is never executed:

```mlir
// Verify that a call in an unreachable function keeps its operand: @g is only
// called from a region that is never executed, so the liveness analysis does
// not visit @g and its argument is dead. The use of the argument by the call
// of @ext is replaced with poison.
// CHECK-LABEL: module @call_in_dead_region
// CHECK:         func.func private @g() {
// CHECK-NEXT:      %[[P:.*]] = ub.poison : i32
// CHECK-NEXT:      call @ext(%[[P]]) : (i32) -> ()
// CHECK-CANONICALIZE-LABEL: module @call_in_dead_region
// CHECK-CANONICALIZE:         func.func private @g() {
// CHECK-CANONICALIZE-NEXT:      %[[P:.*]] = ub.poison : i32
// CHECK-CANONICALIZE-NEXT:      call @ext(%[[P]]) : (i32) -> ()
module @call_in_dead_region {
  func.func private @ext(i32)
  func.func private @g(%x: i32) {
    func.call @ext(%x) : (i32) -> ()
    return
  }
  func.func @main(%v: i32) {
    %false = arith.constant false
    scf.if %false {
      func.call @g(%v) : (i32) -> ()
    }
    return
  }
}
```

----- end -----

## Comment on #206920 and #203226

Paste the same text on both.

----- paste -----

I checked this against llvmorg-23.1.2. The reproducer here no longer crashes with #208881 applied. The same null operand also comes from a dead block argument or a dead call result that is used only in code that is never executed. A follow-up stacked on #208881 covers those two.

----- end -----

## Follow-up pull request

Open it after #208881 is merged, or stacked on its branch before that.
Once it has a number, add "Follow-up: #N" to the issue comment above.

### Title

```
[mlir] Poison remaining uses of every value remove-dead-values erases
```

### Body

```
The liveness analysis marks every value in code that it finds unreachable
as dead, but remove-dead-values keeps some ops there that may still use
such a value: calls, which the walk skips, and region branch ops with side
effects, whose non-forwarded operands it does not touch. #208881 replaces
the uses of an erased function argument with ub.poison, as the pass already
did for the results of an erased op. The cleanup of a dead block argument
and of a dead op result still drops the uses, and leaves such an op with a
null operand ("null operand found"). This happens when the block argument
is used only in a region that is never executed, or when the result of a
call is erased because it is dead at every reachable call of the callee
but a call in such a region still uses it.

Add replaceUsesWithPoison, which replaces all uses of a value with a
ub.poison created at the value's definition, and use it for every value
the pass erases: function arguments, block arguments, op results and the
results of erased ops. The pass no longer calls dropAllUses.

Tests: @dead_result_used_in_unreachable_code and
@dead_block_argument_used_in_unreachable_code in remove-dead-values.mlir.
```

### Diff

This is the commit's diff against the head of #208881. It is the same
change as the follow-up part of `llvm.patch`, without the test modules that
belong to #208881 and to `remove-dead-values-address-taken`.

```diff
diff --git a/mlir/lib/Transforms/RemoveDeadValues.cpp b/mlir/lib/Transforms/RemoveDeadValues.cpp
index 247c66a..4bcd97f 100644
--- a/mlir/lib/Transforms/RemoveDeadValues.cpp
+++ b/mlir/lib/Transforms/RemoveDeadValues.cpp
@@ -196,15 +196,38 @@ static void collectNonLiveValues(DenseSet<Value> &nonLiveSet, ValueRange range,
   }
 }
 
-/// Drop the uses of the i-th result of `op` and then erase it iff toErase[i]
-/// is 1.
-static void dropUsesAndEraseResults(RewriterBase &rewriter, Operation *op,
-                                    BitVector toErase) {
+/// Create a ub.poison op for the given value. If it has no uses, return an
+/// "empty" value.
+static Value createPoisonedValue(OpBuilder &b, Value value) {
+  if (value.use_empty())
+    return Value();
+  return ub::PoisonOp::create(b, value.getLoc(), value.getType()).getResult();
+}
+
+/// Replace all uses of `value`, which is about to be erased, with a ub.poison
+/// value. Every value that the liveness analysis does not reach is dead, so an
+/// op that this pass keeps in code that the analysis found unreachable (e.g., a
+/// call or a region branch op with side effects) may still use a value that
+/// this pass erases. Dropping such a use would leave a null operand behind.
+static void replaceUsesWithPoison(RewriterBase &rewriter, Value value) {
+  OpBuilder::InsertionGuard guard(rewriter);
+  if (Operation *defOp = value.getDefiningOp())
+    rewriter.setInsertionPoint(defOp);
+  else
+    rewriter.setInsertionPointToStart(cast<BlockArgument>(value).getOwner());
+  if (Value poison = createPoisonedValue(rewriter, value))
+    rewriter.replaceAllUsesWith(value, poison);
+}
+
+/// Replace the uses of the i-th result of `op` with poison and then erase it
+/// iff toErase[i] is 1.
+static void poisonUsesAndEraseResults(RewriterBase &rewriter, Operation *op,
+                                      BitVector toErase) {
   assert(op->getNumResults() == toErase.size() &&
          "expected the number of results in `op` and the size of `toErase` to "
          "be the same");
   for (auto idx : toErase.set_bits())
-    op->getResult(idx).dropAllUses();
+    replaceUsesWithPoison(rewriter, op->getResult(idx));
   rewriter.eraseOpResults(op, toErase);
 }
 
@@ -516,14 +539,6 @@ static void processBranchOp(BranchOpInterface branchOp, RunLivenessAnalysis &la,
   }
 }
 
-/// Create a ub.poison op for the given value. If it has no uses, return an
-/// "empty" value.
-static Value createPoisonedValue(OpBuilder &b, Value value) {
-  if (value.use_empty())
-    return Value();
-  return ub::PoisonOp::create(b, value.getLoc(), value.getType()).getResult();
-}
-
 namespace {
 /// A listener that keeps track of ub.poison ops.
 struct TrackingListener : public RewriterBase::Listener {
@@ -594,7 +609,7 @@ static void cleanUpDeadVals(MLIRContext *ctx, RDVFinalCleanupList &list) {
     for (int i = b.nonLiveArgs.size() - 1; i >= 0; --i) {
       if (!b.nonLiveArgs[i])
         continue;
-      b.b->getArgument(i).dropAllUses();
+      replaceUsesWithPoison(rewriter, b.b->getArgument(i));
       b.b->eraseArgument(i);
     }
   }
@@ -640,20 +655,8 @@ static void cleanUpDeadVals(MLIRContext *ctx, RDVFinalCleanupList &list) {
       llvm::interleaveComma(f.nonLiveRets.set_bits(), os);
       os << "]";
     });
-    // Replace remaining uses of the dead arguments with poison values. Simply
-    // dropping the uses would leave null operands behind in ops that survive
-    // the pass (e.g. a side-effecting op in an unreachable function, whose
-    // values are initialized as dead by the liveness analysis).
-    for (auto deadIdx : f.nonLiveArgs.set_bits()) {
-      BlockArgument arg = f.funcOp.getArgument(deadIdx);
-      // Avoid creating an unused poison value if there are no uses to replace.
-      if (arg.use_empty())
-        continue;
-      rewriter.setInsertionPointToStart(arg.getOwner());
-      Value poison =
-          ub::PoisonOp::create(rewriter, arg.getLoc(), arg.getType());
-      rewriter.replaceAllUsesWith(arg, poison);
-    }
+    for (auto deadIdx : f.nonLiveArgs.set_bits())
+      replaceUsesWithPoison(rewriter, f.funcOp.getArgument(deadIdx));
     // Some functions may not allow erasing arguments or results. These calls
     // return failure in such cases without modifying the function, so it's okay
     // to proceed.
@@ -729,7 +732,7 @@ static void cleanUpDeadVals(MLIRContext *ctx, RDVFinalCleanupList &list) {
          << OpWithFlags(r.op,
                         OpPrintingFlags().skipRegions().printGenericOpForm());
     });
-    dropUsesAndEraseResults(rewriter, r.op, r.nonLive);
+    poisonUsesAndEraseResults(rewriter, r.op, r.nonLive);
   }
 
   // 7. Operations
@@ -753,19 +756,8 @@ static void cleanUpDeadVals(MLIRContext *ctx, RDVFinalCleanupList &list) {
     // it's a poison value which will be cleaned up later if it can be cleaned
     // up. This keeps the IR valid for further simplification and
     // canonicalization.
-    auto opResults = op->getResults();
-    for (Value opResult : opResults) {
-      // Early continue for the case where the op result has no uses. No need to
-      // create a poison op here.
-      if (opResult.use_empty())
-        continue;
-
-      rewriter.setInsertionPoint(op);
-      Value poisonedValue = createPoisonedValue(rewriter, opResult);
-      rewriter.replaceAllUsesWith(opResult, poisonedValue);
-    }
-
-    op->dropAllUses();
+    for (Value result : op->getResults())
+      replaceUsesWithPoison(rewriter, result);
     rewriter.eraseOp(op);
   }
 
diff --git a/mlir/test/Transforms/remove-dead-values.mlir b/mlir/test/Transforms/remove-dead-values.mlir
index 207ce48..aa8d709 100644
--- a/mlir/test/Transforms/remove-dead-values.mlir
+++ b/mlir/test/Transforms/remove-dead-values.mlir
@@ -944,3 +944,71 @@ module @unreachable_func_with_for_loops {
     return
   }
 }
+
+// -----
+
+// Verify that the uses of a dead result in unreachable code are replaced with
+// poison. The result of @f is dead at the only call that the liveness analysis
+// visits, so it is erased from every call of @f, including the call in the
+// region that is never executed (@never returns false).
+// CHECK-LABEL: module @dead_result_used_in_unreachable_code
+// CHECK:         scf.if
+// CHECK-NEXT:      %[[P:.*]] = ub.poison : i32
+// CHECK-NEXT:      func.call @f() : () -> ()
+// CHECK-NEXT:      func.call @ext(%[[P]]) : (i32) -> ()
+// CHECK-CANONICALIZE-LABEL: module @dead_result_used_in_unreachable_code
+// CHECK-CANONICALIZE:         scf.if
+// CHECK-CANONICALIZE-NEXT:      %[[P:.*]] = ub.poison : i32
+// CHECK-CANONICALIZE-NEXT:      func.call @f() : () -> ()
+// CHECK-CANONICALIZE-NEXT:      func.call @ext(%[[P]]) : (i32) -> ()
+module @dead_result_used_in_unreachable_code {
+  func.func private @ext(i32)
+  func.func private @never() -> i1 {
+    %false = arith.constant false
+    return %false : i1
+  }
+  func.func private @f() -> i32 {
+    %c = arith.constant 1 : i32
+    return %c : i32
+  }
+  func.func @main() {
+    %r = func.call @f() : () -> i32
+    %no = func.call @never() : () -> i1
+    scf.if %no {
+      %s = func.call @f() : () -> i32
+      func.call @ext(%s) : (i32) -> ()
+    }
+    return
+  }
+}
+
+// -----
+
+// Verify that the uses of a dead block argument in unreachable code are
+// replaced with poison. %a is only used in a region that is never executed.
+// CHECK-LABEL: module @dead_block_argument_used_in_unreachable_code
+// CHECK:         ^bb1:
+// CHECK-NEXT:      %[[P:.*]] = ub.poison : i32
+// CHECK-NEXT:      scf.if
+// CHECK-NEXT:        func.call @ext(%[[P]]) : (i32) -> ()
+// CHECK-CANONICALIZE-LABEL: module @dead_block_argument_used_in_unreachable_code
+// CHECK-CANONICALIZE:         ^bb1:
+// CHECK-CANONICALIZE-NEXT:      %[[P:.*]] = ub.poison : i32
+// CHECK-CANONICALIZE-NEXT:      scf.if
+// CHECK-CANONICALIZE-NEXT:        func.call @ext(%[[P]]) : (i32) -> ()
+module @dead_block_argument_used_in_unreachable_code {
+  func.func private @ext(i32)
+  func.func private @never() -> i1 {
+    %false = arith.constant false
+    return %false : i1
+  }
+  func.func @main(%v: i32) {
+    %no = func.call @never() : () -> i1
+    cf.br ^bb1(%v : i32)
+  ^bb1(%a: i32):
+    scf.if %no {
+      func.call @ext(%a) : (i32) -> ()
+    }
+    return
+  }
+}
```
