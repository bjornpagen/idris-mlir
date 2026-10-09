# idr.dialect: the dialect's declarations, which every module unit that
# names an idr op, type or attribute imports. Its library is idr_ods, after
# the ODS records TableGen generates them from, since idr_dialect is the
# aggregate the tools link.
idr_library(idr_ods
	MODULES
		Dialect.cppm
)

# The dialect and the hooks of its ops (verifiers, folders, canonicalizers,
# DRR patterns), and the helpers idr/Idr.h declares around them: TableGen
# and idr/Idr.h declare them in the global module, so they are plain
# translation units for good, which import the modules for the rest
# (idr.canon, idr.ops, idr.ranges, idr.sharing, idr.verify).
target_sources(idr_dialect PRIVATE
	Dialect/Constants.cc
	Dialect/Initialize.cc
	Dialect/Patterns.cc
	Types/Counted.cc
	Types/DestType.cc
	Types/QType.cc
	Attrs/BigAttr.cc
	Attrs/ConAttr.cc
	Grades/ArrayRoot.cc
	Grades/AtQuantity.cc
	Grades/Erased.cc
	Grades/FieldReadOnce.cc
	Grades/FieldType.cc
	Grades/GradeOf.cc
	Grades/Graded.cc
	Grades/HeldAs.cc
	Grades/HoldsLinear.cc
	Grades/IsArray.cc
	Grades/IsErased.cc
	Grades/IsExclusive.cc
	Grades/IsFieldType.cc
	Grades/IsLinear.cc
	Grades/IsOwned.cc
	Grades/IsWorld.cc
	Grades/Linear.cc
	Grades/Owned.cc
	Grades/QuantityOf.cc
	Grades/TakenOnce.cc
	Grades/ThroughLinear.cc
	Grades/Times.cc
	Grades/Unrestricted.cc
	Grades/View.cc
	Grades/World.cc
	Symbols/EliminationAt.cc
	Symbols/GetSumName.cc
	Symbols/ListCons.cc
	Symbols/LookupCtor.cc
	Symbols/LookupData.cc
	Symbols/LookupSymbol.cc
	Verify/Attributes.cc
	Verify/DiscardableAttrs.cc
	Effects/Consumed.cc
	Effects/OnlyAllocates.cc
	Effects/PerformsIO.cc
	Crashes/KnownFinite.cc
	Crashes/KnownNonEmpty.cc
	Crashes/KnownNonZero.cc
	Ops/Arrays.cc
	Ops/Bigs.cc
	Ops/Buffer.cc
	Ops/Bytes.cc
	Ops/Check.cc
	Ops/Closure.cc
	Ops/Con.cc
	Ops/Constant.cc
	Ops/Crash.cc
	Ops/Data.cc
	Ops/Dest.cc
	Ops/Field.cc
	Ops/Generated.cc
	Ops/Lazy.cc
	Ops/Lin.cc
	Ops/Matches.cc
	Ops/Os.cc
	Ops/Regions.cc
	Ops/Scalars.cc
	Ops/Strings.cc
	Ops/Tag.cc
	Registration/PipelineSteps.cc
	Registration/RegisterIdr.cc
	Registration/RegisterIdrPipeline.cc
	Canonicalize/Apply.cc
	Canonicalize/Arrays.cc
	Canonicalize/Con.cc
	Canonicalize/Field.cc
	Canonicalize/Matches.cc
	Canonicalize/Strings.cc
	Canonicalize/WrittenInPieces.cc
)
