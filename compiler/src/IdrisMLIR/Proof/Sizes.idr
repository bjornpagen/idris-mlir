-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| How much a static argument weighs written, against what the universe of
||| requests lets it weigh (`Proof.Requests.sizeWithin`).
|||
||| An argument written in prefix order is read here as a tree of its heads
||| (`KeyTree`): each node holds the weight of its own symbols, and a head
||| applied to k arguments is one node of k children, as a template reads
||| it. Each child is charged one symbol at its parent, the application that
||| applies the parent to it (`keyWeight`), so a tree charges at least what
||| its symbols weigh (`Keys.writtenWithin`). A tree no higher than h whose
||| nodes have at most a children has at most `nodesWithin (max 1 a) h`
||| nodes (`nodesBelow`); each node, with its charge, weighs at most one more
||| than the heaviest own weight (`weightBelow`); so a tree whose heaviest
||| own weight is at most the heaviest token, or 1, weighs at most
||| `sizeWithin a h e` (`treeWithin`, `lightEnough`), and `sizeWithin` grows
||| with each of its measures (`sizeWithinMono`).
|||
||| Every proof is erased and total, and nothing here runs.
module IdrisMLIR.Proof.Sizes

import IdrisMLIR.Proof.Requests

import Control.Relation
import Data.Nat

%default total

------------------------------------------------------------------------------
-- Trees of heads
------------------------------------------------------------------------------

||| An argument as its key writes it: a node per head, the weight of the
||| head's own symbols, and its children, the arguments it is applied to and
||| the parts it holds.
public export
data KeyTree = KeyNode Nat (List KeyTree)

||| A tree's head applied once more: one more child.
public export
addChild : KeyTree -> KeyTree -> KeyTree
addChild (KeyNode w cs) c = KeyNode w (c :: cs)

mutual
  ||| What a tree charges: each node's own weight, and one for each child,
  ||| the application of its parent to it.
  public export
  keyWeight : KeyTree -> Nat
  keyWeight (KeyNode w cs) = w + childWeights cs

  public export
  childWeights : List KeyTree -> Nat
  childWeights [] = 0
  childWeights (c :: cs) = S (keyWeight c + childWeights cs)

mutual
  ||| A tree's height: one above its tallest child.
  public export
  keyHeight : KeyTree -> Nat
  keyHeight (KeyNode _ cs) = S (keyTallest cs)

  public export
  keyTallest : List KeyTree -> Nat
  keyTallest [] = 0
  keyTallest (c :: cs) = maximum (keyHeight c) (keyTallest cs)

mutual
  ||| The most children of any node.
  public export
  keyArity : KeyTree -> Nat
  keyArity (KeyNode _ cs) = maximum (length cs) (keyWidest cs)

  public export
  keyWidest : List KeyTree -> Nat
  keyWidest [] = 0
  keyWidest (c :: cs) = maximum (keyArity c) (keyWidest cs)

mutual
  ||| The heaviest own weight of any node.
  public export
  keyHeaviest : KeyTree -> Nat
  keyHeaviest (KeyNode w cs) = maximum w (keyHeaviestOf cs)

  public export
  keyHeaviestOf : List KeyTree -> Nat
  keyHeaviestOf [] = 0
  keyHeaviestOf (c :: cs) = maximum (keyHeaviest c) (keyHeaviestOf cs)

mutual
  ||| How many nodes a tree has.
  public export
  keyNodes : KeyTree -> Nat
  keyNodes (KeyNode _ cs) = S (keyNodesOf cs)

  public export
  keyNodesOf : List KeyTree -> Nat
  keyNodesOf [] = 0
  keyNodesOf (c :: cs) = keyNodes c + keyNodesOf cs

------------------------------------------------------------------------------
-- The arithmetic
------------------------------------------------------------------------------

0 lteR : y = y' -> LTE x y -> LTE x y'
lteR Refl le = le

-- A product grows with either factor.
0 timesLeft : {n : Nat} -> LTE a b -> LTE (a * n) (b * n)
timesLeft LTEZero = LTEZero
timesLeft (LTESucc le) = plusLteMonotoneLeft n _ _ (timesLeft {n} le)

0 timesRight : (c : Nat) -> LTE x y -> LTE (c * x) (c * y)
timesRight Z _ = LTEZero
timesRight (S c) le = plusLteMonotone le (timesRight c le)

-- An arity is at most one more than its predecessor, which is the
-- branching `sizeWithin` counts nodes by.
0 predAbove : (a : Nat) -> LTE a (S (pred a))
predAbove Z = LTEZero
predAbove (S a) = reflexive

0 predMono : LTE a a' -> LTE (pred a) (pred a')
predMono LTEZero = LTEZero
predMono (LTESucc le) = le

0 maxOneBelow : (e : Nat) -> LTE (maximum 1 e) (S e)
maxOneBelow Z = reflexive
maxOneBelow (S e) = lteSuccRight reflexive

------------------------------------------------------------------------------
-- What a tree weighs
------------------------------------------------------------------------------

||| A head applied once more charges one more, and the child's.
export
0 addChildWeight : (t, c : KeyTree) -> keyWeight (addChild t c) = S (keyWeight t + keyWeight c)
addChildWeight (KeyNode w cs) c =
  trans (sym (plusSuccRightSucc w (keyWeight c + childWeights cs)))
        (cong S (trans (cong (w +) (plusCommutative (keyWeight c) (childWeights cs)))
                       (plusAssociative w (childWeights cs) (keyWeight c))))

||| Every tree is at least one high.
export
0 keyTall : (t : KeyTree) -> LTE 1 (keyHeight t)
keyTall (KeyNode _ _) = LTESucc LTEZero

mutual
  ||| A tree charges less than one more than k at each of its nodes, for
  ||| any k at least its heaviest own weight: a node's charge is its own
  ||| weight and one for each child, and each child has a node of its own.
  export
  0 weightBelow : {k : Nat} -> (t : KeyTree) -> LTE (keyHeaviest t) k -> LTE (S (keyWeight t)) (S k * keyNodes t)
  weightBelow (KeyNode w cs) le =
    lteR (sym (multRightSuccPlus (S k) (keyNodesOf cs))) $
      plusLteMonotone (LTESucc (transitive (maximumLeftUpperBound w (keyHeaviestOf cs)) le))
                      (childrenBelow {k} cs (transitive (maximumRightUpperBound w (keyHeaviestOf cs)) le))

  0 childrenBelow : {k : Nat} -> (cs : List KeyTree) -> LTE (keyHeaviestOf cs) k ->
                    LTE (childWeights cs) (S k * keyNodesOf cs)
  childrenBelow [] le = LTEZero
  childrenBelow (c :: cs) le =
    lteR (sym (multDistributesOverPlusRight (S k) (keyNodes c) (keyNodesOf cs))) $
      plusLteMonotone (weightBelow {k} c (transitive (maximumLeftUpperBound (keyHeaviest c) (keyHeaviestOf cs)) le))
                      (childrenBelow {k} cs (transitive (maximumRightUpperBound (keyHeaviest c) (keyHeaviestOf cs)) le))

mutual
  ||| A tree no higher than h, no node of which has more than m + 1
  ||| children, has at most `nodesWithin (S m) h` nodes: level k of it at
  ||| most (m + 1)^k.
  export
  0 nodesBelow : {m, h : Nat} -> (t : KeyTree) -> LTE (keyHeight t) h -> LTE (keyArity t) (S m) ->
                 LTE (keyNodes t) (nodesWithin (S m) h)
  nodesBelow {h = Z} (KeyNode _ cs) high _ = void (succNotLTEzero high)
  nodesBelow {h = S h'} (KeyNode _ cs) (LTESucc high) wide =
    LTESucc (transitive (childrenNodesBelow {m} {h = h'} cs high
                           (transitive (maximumRightUpperBound (length cs) (keyWidest cs)) wide))
                        (timesLeft {n = nodesWithin (S m) h'}
                           (transitive (maximumLeftUpperBound (length cs) (keyWidest cs)) wide)))

  0 childrenNodesBelow : {m, h : Nat} -> (cs : List KeyTree) -> LTE (keyTallest cs) h -> LTE (keyWidest cs) (S m) ->
                         LTE (keyNodesOf cs) (length cs * nodesWithin (S m) h)
  childrenNodesBelow [] _ _ = LTEZero
  childrenNodesBelow (c :: cs) high wide =
    plusLteMonotone (nodesBelow {m} {h} c (transitive (maximumLeftUpperBound (keyHeight c) (keyTallest cs)) high)
                                         (transitive (maximumLeftUpperBound (keyArity c) (keyWidest cs)) wide))
                    (childrenNodesBelow {m} {h} cs (transitive (maximumRightUpperBound (keyHeight c) (keyTallest cs)) high)
                                                   (transitive (maximumRightUpperBound (keyArity c) (keyWidest cs)) wide))

||| A tree no higher than h, no node of which has more than a children, none
||| of whose own weights reaches 2h + e, charges at most `sizeWithin a h e`.
export
0 treeWithin : {a, h, e : Nat} -> (t : KeyTree) -> LTE (keyHeight t) h -> LTE (keyArity t) a ->
               LTE (S (keyHeaviest t)) (2 * h + e) -> LTE (keyWeight t) (sizeWithin a h e)
treeWithin t high wide light =
  transitive (lteSuccRight reflexive) $
  transitive (weightBelow {k = keyHeaviest t} t reflexive) $
  transitive (timesLeft {n = keyNodes t} light) $
  timesRight (2 * h + e) (nodesBelow {m = pred a} {h} t high (transitive wide (predAbove a)))

||| A heaviest own weight at most the heaviest token, or 1, falls short of
||| 2h + e at any height h of at least 1: a literal's or a hole marker's
||| weight is its token's, and every other symbol weighs 1.
export
0 lightEnough : {h, e, k : Nat} -> LTE 1 h -> LTE k (maximum 1 e) -> LTE (S k) (2 * h + e)
lightEnough one light =
  transitive (LTESucc (transitive light (maxOneBelow e)))
             (plusLteMonotoneRight e (2 * 1) (2 * h) (timesRight 2 one))

------------------------------------------------------------------------------
-- What the universe lets a key weigh
------------------------------------------------------------------------------

-- The count of nodes grows with the branching and the height.
0 nodesMono : {m, m', h, h' : Nat} -> LTE m m' -> LTE h h' -> LTE (nodesWithin (S m) h) (nodesWithin (S m') h')
nodesMono wide LTEZero = LTEZero
nodesMono {h = S h0} {h' = S h1} wide (LTESucc high) =
  LTESucc (transitive (timesLeft {n = nodesWithin (S m) h0} (LTESucc wide))
                      (timesRight (S m') (nodesMono {m} {m'} {h = h0} {h' = h1} wide high)))

||| `sizeWithin` grows with each of its measures: a position's bound below
||| its parameter's height in the universe lets a key weigh no more there.
export
0 sizeWithinMono : {a, a', h, h', e, e' : Nat} -> LTE a a' -> LTE h h' -> LTE e e' ->
                   LTE (sizeWithin a h e) (sizeWithin a' h' e')
sizeWithinMono wide high heavy =
  transitive (timesLeft {n = nodesWithin (S (pred a)) h} (plusLteMonotone (timesRight 2 high) heavy))
             (timesRight (2 * h' + e') (nodesMono {m = pred a} {m' = pred a'} {h} {h'} (predMono wide) high))
