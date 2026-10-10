DATAS = matita_sttfa hol_stdlib_u isabelle_hol

all: $(DATAS:%=%.dat)

%.dat:
	./csv.sh $* > $@
