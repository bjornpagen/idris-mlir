module Main

-- One function of thirty clauses whose first argument alternates between
-- constructors and a wildcard. The case tree compiles each run of
-- constructors with the tree of the clauses after it as its fallthrough,
-- and copied that tree whole into every alternative, each copy keeping the
-- alternatives the alternative it sits in rules out, so the tree, and every
-- walk over it, grew exponentially in the runs: the pinned Idris did not
-- check this in two minutes. Each copy now keeps, of its cases on the
-- variable just split, only the alternatives that can still be taken, and
-- this checks within the step limit. Partial, so the time is the tree's
-- whatever the coverage check decides.
-- The stock Idris is patched for it (upstream/105-case-tree-fallthrough-
-- copies); the type checker has the change as its own code, and this test
-- checks it.

import Prelude
import Data.List.Elem

data State = Root | Frame | Heap | Contents | Count | MemoState | Identity
           | Io | RuntimeState | Exit | Crash | Divergence

data Kind = Read | Write | Allocate | Free

admitted : State -> List Kind
admitted Root = []
admitted Frame = [Allocate]
admitted Heap = [Allocate, Free]
admitted Contents = [Read, Write]
admitted Count = [Read, Write, Free]
admitted MemoState = [Read, Write]
admitted Identity = [Allocate]
admitted Io = [Read, Write]
admitted RuntimeState = [Read]
admitted Exit = [Write]
admitted Crash = [Write]
admitted Divergence = [Write]

partial
f : (k : Kind) -> (s : State) -> Elem k (admitted s) -> Nat
f _ Root e = absurd e
f Allocate Frame Here = 1
f _ Frame (There e) = absurd e
f Allocate Heap Here = 2
f Free Heap (There Here) = 3
f _ Heap (There (There e)) = absurd e
f Read Contents Here = 4
f Write Contents (There Here) = 5
f _ Contents (There (There e)) = absurd e
f Read Count Here = 6
f Write Count (There Here) = 7
f Free Count (There (There Here)) = 8
f _ Count (There (There (There e))) = absurd e
f Read MemoState Here = 9
f Write MemoState (There Here) = 10
f _ MemoState (There (There e)) = absurd e
f Allocate Identity Here = 11
f _ Identity (There e) = absurd e
f Read Io Here = 12
f Write Io (There Here) = 13
f _ Io (There (There e)) = absurd e
f Read RuntimeState Here = 14
f _ RuntimeState (There e) = absurd e
f Write Exit Here = 15
f _ Exit (There e) = absurd e
f Write Crash Here = 16
f _ Crash (There e) = absurd e
f Write Divergence Here = 17
f _ Divergence (There e) = absurd e

partial
main : IO ()
main = do
  printLn (f Allocate Frame Here)
  printLn (f Free Heap (There Here))
  printLn (f Free Count (There (There Here)))
  printLn (f Write Io (There Here))
  printLn (f Read RuntimeState Here)
  printLn (f Write Divergence Here)
