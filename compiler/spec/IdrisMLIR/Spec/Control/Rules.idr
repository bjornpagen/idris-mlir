-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The rewrites of the matches and the join points, rules of the e-graph
||| pass where greedy canonicalization once was: a match and a join point's
||| op are ops of the skeleton, never pure values, so each rule is one-way,
||| a hand class `::idr::egraph::<name>` (`idr/IR/Control/Control.h`) the
||| engine runs where its root op is. Case-of-case chooses per arm, never
||| the whole consumer: the dispatch goes into the arms whose yielded
||| constructor is known, where it folds; each copy moves a dispatch deeper,
||| so it ends by construction.
module IdrisMLIR.Spec.Control.Rules

import IdrisMLIR.Spec.Core.Vocabulary

%default total

||| One rule rooted at each op it rewrites.
rooted : Ident -> List OpRef -> Line -> List SkeletonRule
rooted name roots doc = map (\root => MkSkeletonRule name root doc) roots

export
skeletonRules : List SkeletonRule
skeletonRules = concat
  [ rooted "TakenCase" ["match"]
      "a match whose region a constant, an idr.con or the type's one constructor takes keeps that region alone"
  , rooted "TakenLiteral" ["match_lit"]
      "a literal match on a constant runs the region its literal takes"
  , rooted "LiteralInCase" ["match_lit"]
      "in case k of a literal match, the scrutinee is the literal k"
  , rooted "DeadDefault" ["match"]
      "a default the scrutinee's type leaves no constructor for never runs, and is emptied"
  , rooted "AllExits" ["match", "match_lit"]
      "a match none of whose regions yields gives nothing, and what follows it is dead"
  , rooted "DeadResults" ["match", "match_lit"]
      "a result of a match no op uses goes, with every yield's operand for it"
  , rooted "CaseOfCase" ["match"]
      "a match on another's one result: its cases become join regions; arms of a known constructor take the dispatch"
  , rooted "DeadJoinResults" ["join", "loop"]
      "a result of a join point's op no op uses goes, with every yield's operand for it"
  , rooted "LoopToJoin" ["loop"]
      "an idr.loop whose join regions never jump to its own op is an idr.join"
  , rooted "DeadJoinRegions" ["join"]
      "a join region no jump reaches goes with its token; a group left with none is its body"
  , rooted "DeadLoopRegions" ["loop"]
      "a join region of an idr.loop no jump reaches goes with its tokens"
  , rooted "InlineSingleJump" ["join"]
      "a join region reached by one jump, the body's own end, runs there"
  , rooted "DeadJoinParameters" ["join"]
      "a parameter its join region never reads goes, with every jump's argument for it"
  , rooted "DeadLoopParameters" ["loop"]
      "a parameter of an idr.loop's join region never read goes, with every jump's argument"
  ]
