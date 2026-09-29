# The dialect and the hooks of its ops (verifiers, folders, canonicalizers,
# DRR patterns): TableGen declares them in the global module, so they are
# plain translation units for good.
target_sources(idr_dialect PRIVATE
	Canonicalize/Apply.cc
	Canonicalize/Calls.cc
	Canonicalize/CaseOfCase.cc
	Canonicalize/Field.cc
	Canonicalize/Matches.cc
	Canonicalize/Meet.cc
	Canonicalize/Merge.cc
	Canonicalize/Sink.cc
	Canonicalize/Strings.cc
	Dialect.cc
	Ops.cc
)
