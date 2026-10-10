set terminal postscript eps enhanced color font 'Helvetica,24'
set output "nbody.eps"
set format y "%g"
set grid xtics
set grid ytics
set grid ztics
set xlabel "Threads"
set xtics 1
set ylabel "Parallel speedup (relative to unverified)"
set datafile separator ","
set key bottom right

nbody_init=system("head -2 allpairs-results.csv | tail -1 | cut -f2 -d,")
reducer_init=system("head -2 IntegerSumReduction-results.csv | tail -1 | cut -f2 -d,")

plot "allpairs_verified-results.csv" using 1:((nbody_init/$2)) \
     with errorlines linewidth 5.0 pointtype 4 pointsize 2.5 \
     title "Verified n-body", \
     "allpairs-results.csv" using 1:((nbody_init/$2)) \
     with errorlines linewidth 5.0 pointtype 7 pointsize 2.5 \
     title "Unverified n-body", \
     "IntegerSumReduction-results.csv" using 1:((reducer_init/$2)) \
     with errorlines linewidth 5.0 pointtype 4 pointsize 2.5 \
     title "Verified reducer", \
     "IntegerSumReductionNoVerification-results.csv" using 1:((reducer_init/$2)) \
     with errorlines linewidth 5.0 pointtype 7 pointsize 2.5 \
     title "Unverified reducer"
