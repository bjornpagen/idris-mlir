module Fallthrough

import Data.List.Elem

data State = Root | Frame | Heap | Contents | Count | MemoState | Identity
           | IO | RuntimeState | Exit | Crash | Divergence

data Kind = Read | Write | Allocate | Free

admitted : State -> List Kind
admitted Root = []
admitted Frame = [Allocate]
admitted Heap = [Allocate, Free]
admitted Contents = [Read, Write]
admitted Count = [Read, Write, Free]
admitted MemoState = [Read, Write]
admitted Identity = [Allocate]
admitted IO = [Read, Write]
admitted RuntimeState = [Read]
admitted Exit = [Write]
admitted Crash = [Write]
admitted Divergence = [Write]

-- Thirty clauses whose first argument alternates between a constructor and
-- a wildcard. Partial, so the time is the case tree's whatever the coverage
-- checker decides.
partial
f : (k : Kind) -> (s : State) -> Elem k (admitted s) -> ()
f _ Root e = absurd e
f Allocate Frame Here = ()
f _ Frame (There e) = absurd e
f Allocate Heap Here = ()
f Free Heap (There Here) = ()
f _ Heap (There (There e)) = absurd e
f Read Contents Here = ()
f Write Contents (There Here) = ()
f _ Contents (There (There e)) = absurd e
f Read Count Here = ()
f Write Count (There Here) = ()
f Free Count (There (There Here)) = ()
f _ Count (There (There (There e))) = absurd e
f Read MemoState Here = ()
f Write MemoState (There Here) = ()
f _ MemoState (There (There e)) = absurd e
f Allocate Identity Here = ()
f _ Identity (There e) = absurd e
f Read IO Here = ()
f Write IO (There Here) = ()
f _ IO (There (There e)) = absurd e
f Read RuntimeState Here = ()
f _ RuntimeState (There e) = absurd e
f Write Exit Here = ()
f _ Exit (There e) = absurd e
f Write Crash Here = ()
f _ Crash (There e) = absurd e
f Write Divergence Here = ()
f _ Divergence (There e) = absurd e
