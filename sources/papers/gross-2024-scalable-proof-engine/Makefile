.PHONY: cache all clean zip

COPY_FILES := \
	rewriting.bib \
	rewriting-lower.bib \
	sn-mathphys.bst \
	sn-jnl.cls \
	rewriting.arxiv-aux \
	perf-UnderLetsPlus0.csv \
	perf-UnderLetsPlus0.csv.md5 \
	perf-Plus0Tree.csv \
	perf-Plus0Tree.csv.md5 \
	perf-fiat-crypto.csv \
	perf-fiat-crypto.csv.md5 \
	perf-fiat-crypto-rewriting.csv \
	perf-fiat-crypto-rewriting.csv.md5 \
	bw.pygstyle \
	#

all: rewriting.tex $(COPY_FILES)
	sed -i.bak 's/usepackage{minted}/usepackage[frozencache]{minted}/g; s/finalizecache/frozencache/g' rewriting.tex
	pdflatex rewriting.tex
	bibtex rewriting.aux
	pdflatex rewriting.tex
	pdflatex rewriting.tex

ifneq (,$(wildcard $(shell which gcp 2>/dev/null)))
CPT?=gcp -t
else
CPT?=cp -t
endif

ifneq (,$(wildcard $(shell which ggrep 2>/dev/null)))
GREP?=ggrep
else
GREP?=grep
endif

cache:
	sed -i.bak 's/usepackage{minted}/usepackage[finalizecache]{minted}/g; s/frozencache/finalizecache/g' rewriting.tex
	pdflatex -shell-escape rewriting.tex
	sed -i.bak 's/usepackage{minted}/usepackage[frozencache]{minted}/g; s/finalizecache/frozencache/g' rewriting.tex
	$(GREP) -o '[^(]*/minted[^ )]*' rewriting.log | xargs $(CPT) ./

error_missing_file = $(error Missing original file $(1)!  If you downloaded this from the arXiv, pass IGNORE_MISSING_ORIGINALS=1 to suppress this message.)

IGNORE_MISSING_ORIGINALS?=
ifneq (,$(wildcard ../rewriting.tex))
rewriting.tex: ../rewriting.tex
	cp ../rewriting.tex $@ && patch -p3 $@ diff.patch
else
ifneq (1,$(IGNORE_MISSING_ORIGINALS))
$(call error_missing_file,../rewriting.tex)
endif
endif

define copy-file
endef

PARENT_FILES:=$(addprefix ../,$(COPY_FILES))
MISSING_FILES:=$(strip $(sort $(filter-out $(wildcard $(PARENT_FILES)),$(PARENT_FILES))))
ifeq (,$(MISSING_FILES))
$(COPY_FILES) : % : ../%
	cp $< $@
else
ifneq (1,$(IGNORE_MISSING_ORIGINALS))
$(call error_missing_file,$(MISSING_FILES))
endif
endif

remake-patch:
	{ diff -Naur ../rewriting.tex rewriting.tex; true; } > diff.patch

clean::
	rm -rf *~ \#* rewriting.pdf *.pyg *.out *.aux *.auxlock *.log *.vtc *.blg *.dep *.dpth *.tex.bak *.tex.orig

zip: clean
	rm -f ../arxiv.zip
	zip -r ../arxiv.zip .

bcprules.sty: ../bcprules.sty
	cp $< $@
