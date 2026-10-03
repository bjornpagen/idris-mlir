# idr.dialect: the dialect's declarations, which every module unit that
# names an idr op, type or attribute imports. Its library is idr_ods, after
# the ODS records TableGen generates them from, since idr_dialect is the
# aggregate the tools link.
idr_library(idr_ods
	MODULES
		Dialect.cppm
)

# The dialect and the hooks of its ops (verifiers, folders, canonicalizers,
# DRR patterns): TableGen declares them in the global module, so they are
# plain translation units for good.
target_sources(idr_dialect PRIVATE
	BigRanges.cc
	Sharing.cc
	Canonicalize/Apply.cc
	Canonicalize/CaseOfCase.cc
	Canonicalize/Con.cc
	Canonicalize/Field.cc
	Canonicalize/Matches.cc
	Canonicalize/Meet.cc
	Canonicalize/Merge.cc
	Canonicalize/Sink.cc
	Canonicalize/Strings.cc
	Dialect.cc
	Ops.cc
)
