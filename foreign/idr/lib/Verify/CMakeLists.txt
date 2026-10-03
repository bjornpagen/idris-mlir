# idr.verify: the rules of a program as a whole, which the dialect's
# verifier of `idr.program` (a plain unit of lib/Dialect) calls.
idr_library(idr_verify
	MODULES
		Verify.cppm
		Linearity.cppm
		Program.cppm
	LINKS
		idr_mlir
		idr_ods
)
