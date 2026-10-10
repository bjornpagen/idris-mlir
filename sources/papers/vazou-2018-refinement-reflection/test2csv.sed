#!/bin/sed
s/OK (\([^s]*\)s)/, \1/g
s/ //g
s/.hs://g
