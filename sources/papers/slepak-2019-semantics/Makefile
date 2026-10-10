.SUFFIXES: .pdf .ps $(.SUFFIXES)
.PHONY: all clean realclean bib

all: paper.pdf tutorial.pdf

# Crowbar TEXINPUTS to use *only* packages in this dir and standard packages.
# That way we know the paper will build in a portable way -- no non-standard
# external dependencies.
export TEXINPUTS
TEXINPUTS=.:./texlib//:./inactive//:

# Likewise for BSTINPUTS and bibtex:
export BSTINPUTS
BSTINPUTS=.:./texlib:

BIB = bibtex
PAPERTEX = paper.tex \
	   decls.tex figs.tex \
	   intro.tex tutorial.tex formalism.tex soundness.tex type_erasure.tex

#PAPERSRC = $(PAPERTEX) bib.bib
PAPERSRC = $(PAPERTEX)

paper.pdf: $(PAPERSRC)
tutorial.pdf: tutorial.tex decls.tex

TAGS: $(PAPERSRC)
	etags $^

# Phony targets
###############

# clean: Remove intermediate files, but not final products.
# realclean: Even remove paper.{zip,pdf,ps}.

clean:
	latexmk -c paper.tex
	-rm comment.cut 2>/dev/null || true
#	-rm *.log *.aux *.pdf

realclean: clean
	latexmk -C paper.tex
#	-rm paper.{pdf,dvi,ps} TAGS 2>/dev/null || true

bib:
	$(RUBBER) --clean paper
	latex paper.tex
	$(BIB) paper

# Implicit rules
################

.tex.pdf:
	latexmk -pdf $<
#	pdflatex $<
#	pdflatex $<

.tex.dvi:
	latexmk -dvi $<

.tex.ps:
	latexmk -ps $<

