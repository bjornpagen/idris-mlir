-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| A value's grade: how often Idris lets it be used, and, on a type that
||| holds references, its hold (`Hold`: who frees what it holds and what is
||| known of its sharing). A lifetime is not part of the grade: it is an SSA
||| value, named by the op that makes a value.
|||
||| The laws are proved here by case split and reach the C++ as the tables
||| of `Declarations`, computed from these functions, never as a second
||| proof.
module IdrisMLIR.Spec.Grades.Grade

import public IdrisMLIR.Spec.Grades.Hold

%default total

--------------------------------------------------------------------------------
-- Uses: Idris's quantities without zero
--------------------------------------------------------------------------------

||| How often a value may be used: exactly once, or any number of times.
||| Quantity 0 has no case: what Idris erased is no value of the module, so
||| no grade, field or operand can say zero.
public export
data Uses = Once | Many

||| Idris's product of quantities: a field of a value is used as often as
||| the value times the field's own quantity, as Idris binds a pattern
||| variable. Once is the unit; many absorbs.
public export
times : Uses -> Uses -> Uses
times Once u = u
times Many _ = Many

||| Uses on two paths that both run: any two uses are many.
public export
plus : Uses -> Uses -> Uses
plus _ _ = Many

export
timesUnitLeft : (u : Uses) -> times Once u = u
timesUnitLeft u = Refl

export
timesUnitRight : (u : Uses) -> times u Once = u
timesUnitRight Once = Refl
timesUnitRight Many = Refl

export
timesCommutes : (a, b : Uses) -> times a b = times b a
timesCommutes Once Once = Refl
timesCommutes Once Many = Refl
timesCommutes Many Once = Refl
timesCommutes Many Many = Refl

export
timesAssociates : (a, b, c : Uses) -> times a (times b c) = times (times a b) c
timesAssociates Once b c = Refl
timesAssociates Many b c = Refl

export
timesAbsorbs : (u : Uses) -> times Many u = Many
timesAbsorbs u = Refl

export
plusCommutes : (a, b : Uses) -> plus a b = plus b a
plusCommutes a b = Refl

export
plusAssociates : (a, b, c : Uses) -> plus a (plus b c) = plus (plus a b) c
plusAssociates a b c = Refl

export
timesDistributes : (a, b, c : Uses) -> times a (plus b c) = plus (times a b) (times a c)
timesDistributes Once b c = Refl
timesDistributes Many b c = Refl

--------------------------------------------------------------------------------
-- What is known of sharing, ordered by how much it claims
--------------------------------------------------------------------------------

||| `Claims a b`: `a` claims no less than `b`. Nothing, then the value's own
||| cells, then everything reached.
public export
data Claims : Unique -> Unique -> Type where
  ClaimsNothing : Claims u None
  ClaimsSelf : Claims Self Self
  DeepClaimsSelf : Claims Deep Self
  ClaimsDeep : Claims Deep Deep

export
claimsReflexive : (u : Unique) -> Claims u u
claimsReflexive None = ClaimsNothing
claimsReflexive Self = ClaimsSelf
claimsReflexive Deep = ClaimsDeep

export
claimsTransitive : Claims a b -> Claims b c -> Claims a c
claimsTransitive _ ClaimsNothing = ClaimsNothing
claimsTransitive ClaimsSelf ClaimsSelf = ClaimsSelf
claimsTransitive DeepClaimsSelf ClaimsSelf = DeepClaimsSelf
claimsTransitive ClaimsDeep DeepClaimsSelf = DeepClaimsSelf
claimsTransitive ClaimsDeep ClaimsDeep = ClaimsDeep

export
claimsAntisymmetric : Claims a b -> Claims b a -> a = b
claimsAntisymmetric ClaimsNothing ClaimsNothing = Refl
claimsAntisymmetric ClaimsSelf ClaimsSelf = Refl
claimsAntisymmetric ClaimsDeep ClaimsDeep = Refl

public export
claims : (a, b : Unique) -> Dec (Claims a b)
claims a None = Yes ClaimsNothing
claims None Self = No (\case ClaimsNothing impossible)
claims Self Self = Yes ClaimsSelf
claims Deep Self = Yes DeepClaimsSelf
claims None Deep = No (\case ClaimsNothing impossible)
claims Self Deep = No (\case ClaimsNothing impossible)
claims Deep Deep = Yes ClaimsDeep

--------------------------------------------------------------------------------
-- Holds, ordered by where a value may stand
--------------------------------------------------------------------------------

||| `Fits h s`: a value at hold `h` may stand where hold `s` is asked, with
||| no op between: what it claims of its sharing is forgotten down to the
||| slot's, its release kept; and static data stands where a counted value
||| claiming nothing is asked (the runtime's static marker is the one test
||| left, where a callee meets both) and where a value of any lifetime is
||| asked, since static data outlives every lifetime. A counted value never
||| stands where a scoped one is asked: lending it is a region (`idr.lend`),
||| not a forgetting; and a scoped value never stands where a counted one
||| is asked, since its lifetime frees it.
public export
data Fits : Hold -> Hold -> Type where
  CountedForgets : Claims u v -> Fits (Counted u) (Counted v)
  ScopedForgets : Claims u v -> Fits (Scoped u) (Scoped v)
  StaticStays : Fits Static Static
  StaticIsCounted : Fits Static (Counted None)
  StaticIsScoped : Fits Static (Scoped None)

export
fitsReflexive : (h : Hold) -> Fits h h
fitsReflexive (Counted u) = CountedForgets (claimsReflexive u)
fitsReflexive (Scoped u) = ScopedForgets (claimsReflexive u)
fitsReflexive Static = StaticStays

||| Fitting composes: forgetting twice is forgetting, and static data that
||| stands for a value claiming nothing stands for what that value stands
||| for, which claims nothing either.
export
fitsTransitive : Fits a b -> Fits b c -> Fits a c
fitsTransitive (CountedForgets x) (CountedForgets y) = CountedForgets (claimsTransitive x y)
fitsTransitive (ScopedForgets x) (ScopedForgets y) = ScopedForgets (claimsTransitive x y)
fitsTransitive StaticStays f = f
fitsTransitive StaticIsCounted (CountedForgets ClaimsNothing) = StaticIsCounted
fitsTransitive StaticIsScoped (ScopedForgets ClaimsNothing) = StaticIsScoped

export
fitsAntisymmetric : Fits a b -> Fits b a -> a = b
fitsAntisymmetric (CountedForgets x) (CountedForgets y) = cong Counted (claimsAntisymmetric x y)
fitsAntisymmetric (ScopedForgets x) (ScopedForgets y) = cong Scoped (claimsAntisymmetric x y)
fitsAntisymmetric StaticStays StaticStays = Refl

||| Fitting keeps the release, but for static data standing as a value that
||| claims nothing.
public export
fits : (h, s : Hold) -> Dec (Fits h s)
fits (Counted u) (Counted v) = case claims u v of
  Yes c => Yes (CountedForgets c)
  No n => No (\case CountedForgets c => n c)
fits (Scoped u) (Scoped v) = case claims u v of
  Yes c => Yes (ScopedForgets c)
  No n => No (\case ScopedForgets c => n c)
fits Static Static = Yes StaticStays
fits Static (Counted None) = Yes StaticIsCounted
fits Static (Scoped None) = Yes StaticIsScoped
fits Static (Counted Self) = No (\case CountedForgets _ impossible)
fits Static (Counted Deep) = No (\case CountedForgets _ impossible)
fits Static (Scoped Self) = No (\case ScopedForgets _ impossible)
fits Static (Scoped Deep) = No (\case ScopedForgets _ impossible)
fits (Counted u) (Scoped v) = No (\case CountedForgets _ impossible)
fits (Counted u) Static = No (\case CountedForgets _ impossible)
fits (Scoped u) (Counted v) = No (\case ScopedForgets _ impossible)
fits (Scoped u) Static = No (\case ScopedForgets _ impossible)

--------------------------------------------------------------------------------
-- What a field read gives, and what a pass may learn
--------------------------------------------------------------------------------

||| How far a value's claim on its own cells reaches into one of its fields,
||| read off the field's declaration: through a field of the value's own
||| family (a `self[...]` field); through a field of an `in_place` family,
||| whose own cells are among the value's own cells, so a linear record's
||| claim covers the spine of the linear list it holds; and through a buffer
||| an own cell holds, whose storage is among the value's own cells and whose
||| elements never are, so a linear array's claim covers the buffer it
||| writes in place and none of the values in its slots; not through any
||| other field. The three that reach read alike; they differ in which cells
||| they reach, a member of the value's group, another group's own cells, or
||| a buffer's storage, which no family member is.
public export
data FieldReach = OwnFamily | InPlaceFamily | HeldBuffer | Other

||| What is known of a field's sharing, read from a value at `uses`, the
||| uses the read gives the field: at many uses nothing, since a value used
||| many times may be duplicated and so shared; at one use, everything it
||| reaches is unshared if nothing the value reaches is, and its own cells,
||| for a field the value's claim on its own cells reaches, if the value's
||| are; nothing else.
public export
readUnique : FieldReach -> Uses -> Unique -> Unique
readUnique _ Many _ = None
readUnique _ Once None = None
readUnique OwnFamily Once Self = Self
readUnique InPlaceFamily Once Self = Self
readUnique HeldBuffer Once Self = Self
readUnique Other Once Self = None
readUnique _ Once Deep = Deep

||| The hold of a field read from a value: freed as the value is (a field of
||| static data is static, a field of a scoped value lives in its lifetime),
||| with what is known of its sharing read by `readUnique`. Never more than
||| the value claims: a field of a record that is not unique deep is never
||| unique deep, whatever its own quantity.
public export
readHold : FieldReach -> Uses -> Hold -> Hold
readHold reach uses (Counted u) = Counted (readUnique reach uses u)
readHold reach uses (Scoped u) = Scoped (readUnique reach uses u)
readHold _ _ Static = Static

||| Split on every argument, so each case reduces whatever order the
||| definition splits in.
export
readClaimsNoMore : (reach : FieldReach) -> (uses : Uses) -> (u : Unique) ->
                   Claims u (readUnique reach uses u)
readClaimsNoMore OwnFamily Many None = ClaimsNothing
readClaimsNoMore OwnFamily Many Self = ClaimsNothing
readClaimsNoMore OwnFamily Many Deep = ClaimsNothing
readClaimsNoMore InPlaceFamily Many None = ClaimsNothing
readClaimsNoMore InPlaceFamily Many Self = ClaimsNothing
readClaimsNoMore InPlaceFamily Many Deep = ClaimsNothing
readClaimsNoMore HeldBuffer Many None = ClaimsNothing
readClaimsNoMore HeldBuffer Many Self = ClaimsNothing
readClaimsNoMore HeldBuffer Many Deep = ClaimsNothing
readClaimsNoMore Other Many None = ClaimsNothing
readClaimsNoMore Other Many Self = ClaimsNothing
readClaimsNoMore Other Many Deep = ClaimsNothing
readClaimsNoMore OwnFamily Once None = ClaimsNothing
readClaimsNoMore OwnFamily Once Self = ClaimsSelf
readClaimsNoMore OwnFamily Once Deep = ClaimsDeep
readClaimsNoMore InPlaceFamily Once None = ClaimsNothing
readClaimsNoMore InPlaceFamily Once Self = ClaimsSelf
readClaimsNoMore InPlaceFamily Once Deep = ClaimsDeep
readClaimsNoMore HeldBuffer Once None = ClaimsNothing
readClaimsNoMore HeldBuffer Once Self = ClaimsSelf
readClaimsNoMore HeldBuffer Once Deep = ClaimsDeep
readClaimsNoMore Other Once None = ClaimsNothing
readClaimsNoMore Other Once Self = ClaimsNothing
readClaimsNoMore Other Once Deep = ClaimsDeep

||| A value stands where its field's hold is asked of its parts.
export
readFits : (reach : FieldReach) -> (uses : Uses) -> (h : Hold) -> Fits h (readHold reach uses h)
readFits reach uses (Counted u) = CountedForgets (readClaimsNoMore reach uses u)
readFits reach uses (Scoped u) = ScopedForgets (readClaimsNoMore reach uses u)
readFits _ _ Static = StaticStays

||| The lesser of two claims: what both allow.
public export
lesser : Unique -> Unique -> Unique
lesser None _ = None
lesser Self None = None
lesser Self Self = Self
lesser Self Deep = Self
lesser Deep v = v

||| Each claims what the lesser does.
export
lesserClaimedByLeft : (a, b : Unique) -> Claims a (lesser a b)
lesserClaimedByLeft None _ = ClaimsNothing
lesserClaimedByLeft Self None = ClaimsNothing
lesserClaimedByLeft Self Self = ClaimsSelf
lesserClaimedByLeft Self Deep = ClaimsSelf
lesserClaimedByLeft Deep None = ClaimsNothing
lesserClaimedByLeft Deep Self = DeepClaimsSelf
lesserClaimedByLeft Deep Deep = ClaimsDeep

export
lesserClaimedByRight : (a, b : Unique) -> Claims b (lesser a b)
lesserClaimedByRight None _ = ClaimsNothing
lesserClaimedByRight Self None = ClaimsNothing
lesserClaimedByRight Self Self = ClaimsSelf
lesserClaimedByRight Self Deep = DeepClaimsSelf
lesserClaimedByRight Deep v = claimsReflexive v

||| And it is the most both claim.
export
lesserGreatest : Claims a u -> Claims b u -> Claims (lesser a b) u
lesserGreatest ClaimsNothing _ = ClaimsNothing
lesserGreatest ClaimsSelf ClaimsSelf = ClaimsSelf
lesserGreatest ClaimsSelf DeepClaimsSelf = ClaimsSelf
lesserGreatest DeepClaimsSelf ClaimsSelf = ClaimsSelf
lesserGreatest DeepClaimsSelf DeepClaimsSelf = DeepClaimsSelf
lesserGreatest ClaimsDeep ClaimsDeep = ClaimsDeep

||| The most a fresh value may claim, built of a part its claim on its own
||| cells reaches as `reach`, the part claiming `given`: the greatest claim
||| whose read of the part at one use, the read that gives most, gives no
||| more than the part holds (`freshestReads`, `freshestGreatest`). A part
||| outside the value's own cells bounds only a deep claim, so a value built
||| of a shared one still claims its own cells; a part its own cells reach
||| bounds it to what the part claims.
public export
freshest : FieldReach -> Unique -> Unique
freshest _ Deep = Deep
freshest Other _ = Self
freshest OwnFamily u = u
freshest InPlaceFamily u = u
freshest HeldBuffer u = u

||| A fresh value at that claim reads out of the part no more than the part
||| holds. Split on every argument, so each case reduces whatever order the
||| definitions split in.
export
freshestReads : (reach : FieldReach) -> (given : Unique) ->
                Claims given (readUnique reach Once (freshest reach given))
freshestReads OwnFamily None = ClaimsNothing
freshestReads OwnFamily Self = ClaimsSelf
freshestReads OwnFamily Deep = ClaimsDeep
freshestReads InPlaceFamily None = ClaimsNothing
freshestReads InPlaceFamily Self = ClaimsSelf
freshestReads InPlaceFamily Deep = ClaimsDeep
freshestReads HeldBuffer None = ClaimsNothing
freshestReads HeldBuffer Self = ClaimsSelf
freshestReads HeldBuffer Deep = ClaimsDeep
freshestReads Other None = ClaimsNothing
freshestReads Other Self = ClaimsNothing
freshestReads Other Deep = ClaimsDeep

||| And no greater claim does: any claim whose read the part holds is one
||| the fresh value's claim covers.
export
freshestGreatest : (reach : FieldReach) -> (given, u : Unique) ->
                   Claims given (readUnique reach Once u) -> Claims (freshest reach given) u
freshestGreatest _ _ None _ = ClaimsNothing
freshestGreatest OwnFamily None Self ClaimsNothing impossible
freshestGreatest OwnFamily Self Self _ = ClaimsSelf
freshestGreatest OwnFamily Deep Self _ = DeepClaimsSelf
freshestGreatest InPlaceFamily None Self ClaimsNothing impossible
freshestGreatest InPlaceFamily Self Self _ = ClaimsSelf
freshestGreatest InPlaceFamily Deep Self _ = DeepClaimsSelf
freshestGreatest HeldBuffer None Self ClaimsNothing impossible
freshestGreatest HeldBuffer Self Self _ = ClaimsSelf
freshestGreatest HeldBuffer Deep Self _ = DeepClaimsSelf
freshestGreatest Other None Self _ = ClaimsSelf
freshestGreatest Other Self Self _ = ClaimsSelf
freshestGreatest Other Deep Self _ = DeepClaimsSelf
freshestGreatest OwnFamily None Deep ClaimsNothing impossible
freshestGreatest OwnFamily Self Deep ClaimsNothing impossible
freshestGreatest OwnFamily Deep Deep _ = ClaimsDeep
freshestGreatest InPlaceFamily None Deep ClaimsNothing impossible
freshestGreatest InPlaceFamily Self Deep ClaimsNothing impossible
freshestGreatest InPlaceFamily Deep Deep _ = ClaimsDeep
freshestGreatest HeldBuffer None Deep ClaimsNothing impossible
freshestGreatest HeldBuffer Self Deep ClaimsNothing impossible
freshestGreatest HeldBuffer Deep Deep _ = ClaimsDeep
freshestGreatest Other None Deep ClaimsNothing impossible
freshestGreatest Other Self Deep ClaimsNothing impossible
freshestGreatest Other Deep Deep _ = ClaimsDeep

||| What a fresh value may claim, built of its parts, each reached by its
||| claim on its own cells as its declaration says and claiming what it
||| holds (everything, where it holds no reference, so it bounds nothing):
||| the least any of them bounds it to (`freshest`). A constructor's claim
||| on the cell it makes, which the dialect folds over the table of
||| `freshest` and the frontend writes on the value it builds.
public export
freshClaim : List (FieldReach, Unique) -> Unique
freshClaim [] = Deep
freshClaim ((reach, given) :: parts) = lesser (freshest reach given) (freshClaim parts)

||| What exclusivity writes once it proves a value's sharing: the claim set
||| to `v` where something frees the value; static data has no sharing
||| level, and is left as it is.
public export
refine : Unique -> Hold -> Hold
refine v (Counted _) = Counted v
refine v (Scoped _) = Scoped v
refine _ Static = Static

||| A refinement keeps the release.
export
refineKeepsRelease : (v : Unique) -> (h : Hold) -> release (refine v h) = release h
refineKeepsRelease v (Counted _) = Refl
refineKeepsRelease v (Scoped _) = Refl
refineKeepsRelease v Static = Refl

||| A value refined to claim no less than it did stands where it stood.
export
refineFits : (h : Hold) -> Claims v (claim h) -> Fits (refine v h) h
refineFits (Counted u) c = CountedForgets c
refineFits (Scoped u) c = ScopedForgets c
refineFits Static _ = StaticStays

--------------------------------------------------------------------------------
-- What a carrier holds
--------------------------------------------------------------------------------

||| Whether a carrier holds references: a fact of the carrier, computed when
||| its type is made, never asked of the grade. A grade has a hold exactly
||| when its carrier holds references.
public export
data Refs = Words | References
