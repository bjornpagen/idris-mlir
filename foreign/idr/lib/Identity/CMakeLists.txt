# idr.identity: the functions that give back one of their arguments once
# Idris's indices are erased, and their calls made that argument; the pass
# glue (the TableGen-declared base of idr-identity) is a plain unit that
# imports it.
idr_library(idr_identity
	MODULES
		Identity.cppm
		Parts.cppm
		Rebuilds.cppm
		Identities.cppm
	GLUE
		Pass.cc
	LINKS
		idr_mlir
		idr_ods
		idr_facts
)
