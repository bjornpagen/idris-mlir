module Libraries.Utils.String

%default total

export
stripSurrounds : (lead : Nat) -> (tail : Nat) -> String -> String
stripSurrounds lead tail str = substr lead (length str `minus` (lead + tail)) str

export
stripQuotes : String -> String
stripQuotes = stripSurrounds 1 1

export
lowerFirst : String -> Bool
lowerFirst "" = False
lowerFirst str = isLower $ assert_total $ prim__strHead str
