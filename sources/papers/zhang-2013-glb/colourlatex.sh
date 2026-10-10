#!/bin/sh

#special codes
RESET='[0m'
BOLD='[1m'
DIM='[2m'
UNDERLINE='[4m'
BLINK='[5m'
REVERSE='[7m'
HIDDEN='[8m'

#foreground colours
BLACK='[30m'
RED='[31m'
GREEN='[32m'
YELLOW='[33m'
BLUE='[34m'
MAGENTA='[35m'
CYAN='[36m'
WHITE='[37m'

#background colours
BBLACK='[40m'
BRED='[41m'
BGREEN='[42m'
BYELLOW='[43m'
BBLUE='[44m'
BMAGENTA='[45m'
BCYAN='[46m'
BWHITE='[47m'

($@ ; EXIT_CODE=$?) | sed -e "s/Warning/$BOLD$YELLOW&$RESET/g" \
                          -e "s/\(page\|lines\?\) [0-9]*/$BOLD$WHITE&$RESET/g" \
                          -e "s/ lines? [0-9]*/$BOLD$WHITE&$RESET/g" \
                          -e "s/[0-9]*--[0-9]*/$BOLD$WHITE&$RESET/g" \
                          -e "s/[0-9]\+[.][0-9]*pt/$BOLD$WHITE&$RESET/g" \
                          -e "s/\<l[.][0-9]*\>/$BOLD$WHITE&$RESET/g" \
                          -e "s/\[[0-9]\+\]/$CYAN&$RESET/g" \
                          -e "s/\(Ov\|Und\)erfull/$BOLD$RED&$RESET/g" \
                          -e "s/[a-zA-Z0-9_]*[.]tex/$GREEN&$RESET/g" \
                          -e "s/!/$BOLD$RED&$RESET/g"


exit $?
