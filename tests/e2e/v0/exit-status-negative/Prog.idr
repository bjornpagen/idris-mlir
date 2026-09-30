module Prog

-- -1 is no exit status: its low 8 bits would read as 255. It ends the
-- program as a crash that names it.
main : Int
main = -1
