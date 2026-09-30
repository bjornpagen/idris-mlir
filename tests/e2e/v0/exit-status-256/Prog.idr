module Prog

-- A parent sees only the low 8 bits of an exit status, so exiting with 256
-- would read as success. main's value is the exit status only from 0 to
-- 255; any other ends the program as a crash that names it.
main : Int
main = 256
