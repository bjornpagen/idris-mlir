-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| A value's grade: how often Idris lets it be used, and, on a type that
||| holds references, who frees what it holds and what is known of its
||| sharing. Two axes of the hold, never one enum: who frees a value decides
||| whether a count is touched, what is known of its sharing decides whether
||| a cell may be rebuilt in place, and every pair of them is meaningful but
||| one, a claim of uniqueness on static data, which is shared by
||| definition and has no constructor here. A lifetime is not part of the
||| grade: it is an SSA value, named by the op that makes a value.
|||
||| The laws are proved here by case split and reach the C++ as the tables
||| of `Declarations`, computed from these functions, never as a second
||| proof.
module IdrisMLIR.Spec.Grades.Grade


%default total

--------------------------------------------------------------------------------
-- The axes
--------------------------------------------------------------------------------

||| How often a value may be used: exactly once, or any number of times.
||| Quantity 0 has no case: what Idris erased is no value of the module, so
||| no grade, field or operand can say zero.
public export
data Uses = Once | Many

||| Who frees what a value holds: its count, when it reaches zero; the end
||| of the lifetime the op that made it names; or nothing, for static data,
||| which lives for the whole run.
namespace Release
  public export
  data Release = Counted | Scoped | Static

||| What is known of a value's sharing: nothing; that its own family's cells
||| are reached through it alone (through every recursive field of its
||| family); or that nothing it reaches is shared.
public export
data Unique = None | Self | Deep

||| What a value that holds references holds: who frees it and, where
||| something frees it, what is known of its sharing. Static data is shared
||| by every reader of it, so its case takes no claim: `static unique deep`
||| has no constructor.
namespace Hold
  public export
  data Hold = Counted Unique | Scoped Unique | Static

||| Who frees a value at a hold.
public export
release : Hold -> Release
release (Counted _) = Counted
release (Scoped _) = Scoped
release Static = Static

||| What a hold claims of sharing: static data claims nothing.
public export
claim : Hold -> Unique
claim (Counted u) = u
claim (Scoped u) = u
claim Static = None

--------------------------------------------------------------------------------
-- Uses: Idris's quantities without zero
--------------------------------------------------------------------------------

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

||| `Claims a b`: `a` claims no less than `b`. Nothing, then a family's own
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

||| Whether a field is of its family's own recursive group (a `self[...]`
||| field) or of another type.
public export
data Recursion = OwnFamily | Other

||| What is known of a field's sharing, read from a value: everything it
||| reaches is unshared if nothing the value reaches is; its family's own
||| cells, for a field of that family, if the value's are; nothing else.
public export
readUnique : Recursion -> Unique -> Unique
readUnique _ Deep = Deep
readUnique OwnFamily Self = Self
readUnique Other Self = None
readUnique _ None = None

||| The hold of a field read from a value: freed as the value is (a field of
||| static data is static, a field of a scoped value lives in its lifetime),
||| with what is known of its sharing read by `readUnique`. Never more than
||| the value claims: a field of a record that is not unique deep is never
||| unique deep, whatever its own quantity.
public export
readHold : Recursion -> Hold -> Hold
readHold rec (Counted u) = Counted (readUnique rec u)
readHold rec (Scoped u) = Scoped (readUnique rec u)
readHold _ Static = Static

export
readClaimsNoMore : (rec : Recursion) -> (u : Unique) -> Claims u (readUnique rec u)
readClaimsNoMore _ Deep = ClaimsDeep
readClaimsNoMore OwnFamily Self = ClaimsSelf
readClaimsNoMore Other Self = ClaimsNothing
readClaimsNoMore _ None = ClaimsNothing

||| A value stands where its field's hold is asked of its parts.
export
readFits : (rec : Recursion) -> (h : Hold) -> Fits h (readHold rec h)
readFits rec (Counted u) = CountedForgets (readClaimsNoMore rec u)
readFits rec (Scoped u) = ScopedForgets (readClaimsNoMore rec u)
readFits _ Static = StaticStays

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
-- The grade, by what its carrier holds
--------------------------------------------------------------------------------

||| Whether a carrier holds references: a fact of the carrier, computed when
||| its type is made, never asked of the grade.
public export
data Refs = Words | References

||| A grade, indexed by its carrier's fact: a carrier that holds no
||| reference has uses alone, so an owned word cannot be written; one that
||| holds references has uses and a hold, so no hold is ever undecided.
public export
data Grade : Refs -> Type where
  OnWords : Uses -> Grade Words
  OnReferences : Uses -> Hold -> Grade References

||| The grade a bare type has, so it is never written as a graded type: a
||| word used freely (the form upstream's ops take); a value that holds
||| references, used freely, counted, claiming nothing (every such value
||| before counting, and what a pass that learns nothing leaves).
public export
bare : (r : Refs) -> Grade r
bare Words = OnWords Many
bare References = OnReferences Many (Counted None)

||| The uses of a grade.
public export
uses : Grade r -> Uses
uses (OnWords u) = u
uses (OnReferences u _) = u

||| The grade of a field bound from a value, as a match binds it: the
||| value's uses times the field's own (a declaration's field carries its
||| uses alone, no hold), and, for a field that holds references, the hold
||| read from the value's.
public export
fieldGrade : Recursion -> Grade References -> (field : Uses) -> (r : Refs) -> Grade r
fieldGrade _ v u Words = OnWords (times (uses v) u)
fieldGrade rec (OnReferences vu vh) u References = OnReferences (times vu u) (readHold rec vh)
