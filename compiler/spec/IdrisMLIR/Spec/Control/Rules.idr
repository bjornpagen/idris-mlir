-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The rewrites of the matches and the join points, rules of the e-graph
||| pass where greedy canonicalization once was: a match and a join point's
||| op are ops of the skeleton, never pure values, so each rule is one-way,
||| a hand class `::idr::egraph::<name>` (`idr/IR/Control/Control.h`) the
||| engine runs where its root op is. Case-of-case chooses per arm, never
||| the whole consumer: the dispatch goes into the arms where it costs less
||| than the shared one, where it folds; each copy moves a dispatch deeper,
||| so it ends by construction.
module IdrisMLIR.Spec.Control.Rules

import IdrisMLIR.Spec.Core.Vocabulary

import Data.List1

%default total

||| The header that declares every rule here, which the generator includes
||| once.
controlHeader : Path
controlHeader = "idr" ::: ["IR", "Control", "Control.h"]

||| One rule rooted at each op it rewrites.
rooted : Ident -> List OpRef -> Line -> List SkeletonRule
rooted name roots doc = map (\root => MkSkeletonRule name controlHeader root doc) roots

export
skeletonRules : List SkeletonRule
skeletonRules = concat {t = List}
  [ rooted "TakenCase" ["data.match"]
      "a match whose region a constant, an idr.data.con or the type's one constructor takes keeps that region alone"
  , rooted "TakenLiteral" ["lit.match"]
      "a literal match on a constant runs the region its literal takes"
  , rooted "LiteralInCase" ["lit.match"]
      "in case k of a literal match, the scrutinee is the literal k"
  , rooted "EmptyStringCase" ["lit.match"]
      "a string that is never empty never takes the case of the empty string, which goes"
  , rooted "DeadDefault" ["data.match"]
      "a default the scrutinee's type leaves no constructor for never runs, and is emptied"
  , rooted "IdenticalRegions" ["data.match", "lit.match"]
      "a case that does what the default does, reading nothing it binds, is left to the default; cases of an exhaustive match that do the same become its default"
  , rooted "AllExits" ["data.match", "lit.match"]
      "a match none of whose regions yields gives nothing, and what follows it is dead"
  , rooted "DeadResults" ["data.match", "lit.match"]
      "a result of a match no op uses goes, with every yield's operand for it"
  , rooted "YieldedFields" ["data.match", "lit.match"]
      "a result every region builds as one constructor and every use reads a field of is yielded as its fields, the constructor built once after"
  , rooted "CaseOfCase" ["data.match"]
      "a match on another's one result: its cases become join regions; an arm takes the dispatch where that costs less than sharing it"
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
