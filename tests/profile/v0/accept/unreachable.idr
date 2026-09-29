-- exit: 1
module Main

-- An unreachable definition outside the profile is neither checked nor compiled.
big : Integer
big = 12345678901234567890

main : Int
main = 1
