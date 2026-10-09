module Main

-- Every run-time export of Prelude.Cast, each used (covers): cast, at
-- every implementation the module provides. One line per target type,
-- cast from each source type that has an implementation to it, in the
-- order String, Integer, Int, Char, Double, Nat and the fixed-width
-- types; values out of a fixed-width target's range wrap modulo its
-- width, a Double truncates towards zero, and a negative number is 0 as
-- a Nat. Then Cast a a, and cast passed through a constraint. Each line
-- is printed so that what it computes is checked.

import Prelude

spaced : List String -> String
spaced [] = ""
spaced [s] = s
spaced (s :: ss) = s ++ " " ++ spaced ss

line : String -> List String -> IO ()
line label xs = putStrLn (label ++ ": " ++ spaced xs)

castAll : Cast a b => List a -> List b
castAll = map cast

main : IO ()
main = do
  line "String" $ the (List String)
    [ cast (the Int (-42)), cast (the Integer 123456789012345678901)
    , cast 'q', cast (the Double 2.5), cast (the Nat 7)
    , cast (the Int8 (-8)), cast (the Int16 (-1600)), cast (the Int32 (-320000))
    , cast (the Int64 (-6400000000)), cast (the Bits8 200), cast (the Bits16 60000)
    , cast (the Bits32 4000000000), cast (the Bits64 18000000000000000000) ]
  line "Integer" $ map show $ the (List Integer)
    [ cast "-98765432109876543210", cast (the Int (-42)), cast 'A'
    , cast (the Double (-3.7)), cast (the Double 1.0e20), cast (the Nat 9)
    , cast (the Bits8 255), cast (the Bits16 65535), cast (the Bits32 4294967295)
    , cast (the Bits64 18446744073709551615), cast (the Int8 (-128))
    , cast (the Int16 (-32768)), cast (the Int32 (-2147483648))
    , cast (the Int64 (-9223372036854775808)) ]
  line "Int" $ map show $ the (List Int)
    [ cast "-31", cast (the Integer 18446744073709551621), cast 'z'
    , cast (the Double (-7.9)), cast (the Double 7.9), cast (the Nat 12)
    , cast (the Bits8 128), cast (the Bits16 40000), cast (the Bits32 3000000000)
    , cast (the Bits64 18446744073709551615), cast (the Int8 (-5))
    , cast (the Int16 (-300)), cast (the Int32 (-70000))
    , cast (the Int64 (-5000000000)) ]
  line "Char" $ map show $ the (List Char)
    [ cast (the Integer 66), cast (the Int 65), cast (the Nat 67)
    , cast (the Bits8 68), cast (the Bits16 69), cast (the Bits32 70)
    , cast (the Bits64 71), cast (the Int8 72), cast (the Int16 73)
    , cast (the Int32 74), cast (the Int64 75) ]
  line "Double" $ map show $ the (List Double)
    [ cast "-0.125", cast (the Integer 12345678901234567890), cast (the Int (-3))
    , cast (the Nat 3), cast (the Bits8 255), cast (the Bits16 65535)
    , cast (the Bits32 4294967295), cast (the Bits64 18446744073709551615)
    , cast (the Int8 (-128)), cast (the Int16 (-32768))
    , cast (the Int32 (-2147483648)), cast (the Int64 (-9223372036854775808)) ]
  line "Nat" $ map show $ the (List Nat)
    [ cast "17", cast "-3", cast (the Integer 100000000000000000000)
    , cast (the Int (-5)), cast (the Int 5), cast 'A', cast (the Double 41.99)
    , cast (the Double (-2.5)), cast (the Bits8 255), cast (the Bits16 65535)
    , cast (the Bits32 4294967295), cast (the Bits64 18446744073709551615)
    , cast (the Int8 (-1)), cast (the Int16 300), cast (the Int32 70000)
    , cast (the Int64 5000000000) ]
  line "Bits8" $ map show $ the (List Bits8)
    [ cast "200", cast (the Integer (-1)), cast (the Int 300), cast 'A'
    , cast (the Double 200.9), cast (the Nat 260), cast (the Bits16 513)
    , cast (the Bits32 65791), cast (the Bits64 263), cast (the Int8 (-1))
    , cast (the Int16 (-2)), cast (the Int32 1000), cast (the Int64 (-256)) ]
  line "Bits16" $ map show $ the (List Bits16)
    [ cast "40000", cast (the Integer (-1)), cast (the Int 70000), cast '\9786'
    , cast (the Double 1234.5), cast (the Nat 65536), cast (the Bits8 255)
    , cast (the Bits32 65537), cast (the Bits64 131071), cast (the Int8 (-1))
    , cast (the Int16 (-32768)), cast (the Int32 (-2)), cast (the Int64 70000) ]
  line "Bits32" $ map show $ the (List Bits32)
    [ cast "4000000000", cast (the Integer 4294967299), cast (the Int (-1))
    , cast '\128512', cast (the Double 3000000000.5), cast (the Nat 5)
    , cast (the Bits8 7), cast (the Bits16 65535), cast (the Bits64 4294967297)
    , cast (the Int8 (-128)), cast (the Int16 (-1))
    , cast (the Int32 (-2147483648)), cast (the Int64 (-1)) ]
  line "Bits64" $ map show $ the (List Bits64)
    [ cast "18446744073709551615", cast (the Integer 18446744073709551625)
    , cast (the Int (-1)), cast 'a', cast (the Double 1.0e19)
    , cast (the Nat 18446744073709551616), cast (the Bits8 1), cast (the Bits16 2)
    , cast (the Bits32 4294967295), cast (the Int8 (-1)), cast (the Int16 (-2))
    , cast (the Int32 (-3)), cast (the Int64 (-9223372036854775808)) ]
  line "Int8" $ map show $ the (List Int8)
    [ cast "-100", cast (the Integer (-129)), cast (the Int 200), cast 'A'
    , cast (the Double (-100.9)), cast (the Nat 128), cast (the Bits8 255)
    , cast (the Bits16 384), cast (the Bits32 127)
    , cast (the Bits64 18446744073709551615), cast (the Int16 (-129))
    , cast (the Int32 300), cast (the Int64 (-1)) ]
  line "Int16" $ map show $ the (List Int16)
    [ cast "-30000", cast (the Integer (-32769)), cast (the Int 40000)
    , cast '\9786', cast (the Double 32767.9), cast (the Nat 32768)
    , cast (the Bits8 200), cast (the Bits16 65535), cast (the Bits32 98304)
    , cast (the Bits64 65537), cast (the Int8 (-128)), cast (the Int32 (-70000))
    , cast (the Int64 32767) ]
  line "Int32" $ map show $ the (List Int32)
    [ cast "-2000000000", cast (the Integer 4294967295), cast (the Int 2147483648)
    , cast '\128512', cast (the Double (-2147483648.5)), cast (the Nat 2147483647)
    , cast (the Bits8 255), cast (the Bits16 65535), cast (the Bits32 4294967295)
    , cast (the Bits64 4294967296), cast (the Int8 (-1)), cast (the Int16 (-32768))
    , cast (the Int64 (-4294967297)) ]
  line "Int64" $ map show $ the (List Int64)
    [ cast "-9000000000000000000", cast (the Integer 9223372036854775808)
    , cast (the Int (-1)), cast 'z', cast (the Double (-9.0e18))
    , cast (the Nat 9223372036854775807), cast (the Bits8 255)
    , cast (the Bits16 65535), cast (the Bits32 4294967295)
    , cast (the Bits64 18446744073709551615), cast (the Int8 (-128))
    , cast (the Int16 (-32768)), cast (the Int32 (-2147483648)) ]
  line "same type"
    [ cast "same", show (the Int (cast (the Int 5)))
    , show (the Double (cast (the Double 0.5))), show (the Char (cast 'c')) ]
  printLn (the (List Double) (castAll (the (List Int) [1, -2, 3])))
  printLn (the (List Int) (castAll ['a', 'b', 'c']))
