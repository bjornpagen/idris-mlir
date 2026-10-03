# idr.sharing: the aliases of the dialect's large constants in text, which
# the dialect registers when it is initialized.
idr_library(idr_sharing
	MODULES
		Sharing.cppm
		Aliases.cppm
	LINKS
		idr_mlir
		idr_ods
)
