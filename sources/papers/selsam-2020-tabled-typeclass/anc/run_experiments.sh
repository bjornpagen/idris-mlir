sudo docker build -t ijcar2020/ttr . \
   && sudo docker run --rm --entrypoint cat ijcar2020/ttr /root/app/diamond.csv > diamond.csv \
   && python3 plot_results.py --experiment diamond \
   && sudo docker run --rm --entrypoint cat ijcar2020/ttr /root/app/append.csv > append.csv \
   && python3 plot_results.py --experiment append \
   && echo "DONE"
