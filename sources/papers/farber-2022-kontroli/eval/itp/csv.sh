#!/bin/bash
CMD='[.results[0].mean, .results[0].stddev] | @tsv'
echo -e "Conf\tMean\tStddev"
echo -n 'DK'             ; jq -r '["", .results[0].mean, .results[0].stddev] | @tsv' $1/dk.json
echo -n 'DK$\cap p$'     ; jq -r '["", .results[0].mean, .results[0].stddev] | @tsv' $1/dkp.json
echo -n 'KO'             ; jq -r '["", .results[0].mean, .results[0].stddev] | @tsv' $1/ko.json
echo -n 'KO$\cap p$'     ; jq -r '["", .results[0].mean, .results[0].stddev] | @tsv' $1/koosh.json
echo -n 'DK$_{t=\infty}$'; jq -r '["", .results[0].mean, .results[0].stddev] | @tsv' $1/dkj.json
echo -n 'KO$_{p=1}$'     ; jq -r '["", .results[0].mean, .results[0].stddev] | @tsv' $1/kop.json
echo -n 'KO$_{c=1}$'     ; jq -r '["", .results[0].mean, .results[0].stddev] | @tsv' $1/ko1.json
echo -n 'KO$_{c=2}$'     ; jq -r '["", .results[0].mean, .results[0].stddev] | @tsv' $1/ko2.json
echo -n 'KO$_{c=4}$'     ; jq -r '["", .results[0].mean, .results[0].stddev] | @tsv' $1/ko4.json
echo -n 'KO$_{c=8}$'     ; jq -r '["", .results[0].mean, .results[0].stddev] | @tsv' $1/ko8.json
echo -n 'KO$\setminus c$'; jq -r '["", .results[0].mean, .results[0].stddev] | @tsv' $1/koi.json
