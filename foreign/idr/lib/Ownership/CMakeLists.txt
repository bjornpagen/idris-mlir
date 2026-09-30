# Ownership, as plain translation units: not yet a module.
target_sources(idr_dialect PRIVATE
	Borrow.cc
	Counting.cc
	Counts.cc
	Exclusive.cc
	Ops.cc
	Rc.cc
	ResetReuse.cc
	Take.cc
	Verify.cc
)
