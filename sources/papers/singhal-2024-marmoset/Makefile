
# Point this at the name of the main paper file:
# Typically use something descriptive for this name.
PAPER=paper

UNAME := $(shell uname)
# Sometimes it helps to point latexmk at a subdir, like ./build:
BUILDDIR	= ./
LATEXMK_FLAGS	= -outdir=${BUILDDIR}

# Token files that are used to control build mode:
EDMARK=activateeditingmarks
# ^ Usually I leave this checked into the repo at the beginning of
# paper writing, and delete it later.
GREYMARK=activategreybg


OUTDIR= ./build
MKOPTS= -outdir=${OUTDIR} -pdflatex='pdflatex --synctex=1' -pdf
LATEXMK=latexmk ${MKOPTS}

paper: ${OUTDIR}
	${LATEXMK} ${PAPER}.tex


report: ${OUTDIR}
	pdflatex ${MKOPTS}  ${PAPER}.tex
	bibtex   ${PAPER}.aux
	pdflatex ${MKOPTS}  ${PAPER}.tex
	pdflatex ${MKOPTS}  ${PAPER}.tex
	mv *.out ./build/. 
	mv *.aux ./build/.
	mv *.bbl ./build/.
	mv *.log ./build/.
	mv *.blg ./build/.
	mv ${PAPER}.pdf ./build/.

# Continuous building
cont: continuous
continuous: ${OUTDIR}
	${LATEXMK} -pvc ${PAPER}.tex

${OUTDIR}:
	mkdir -p ${OUTDIR}

# Build with editorial markup rather than the final pdf:
# ============================================================
ed: editingmarks
editingmarks:
	touch $(EDMARK)
	${LATEXMK} -g ${PAPER}.tex

plain:
	rm -f $(EDMARK)
	${LATEXMK} -g ${PAPER}.tex

both:
	touch $(EDMARK)
	${LATEXMK} -g ${PAPER}.tex
	cp ${OUTDIR}/${PAPER}.pdf ./wmarks.pdf

	rm -f $(EDMARK)
	${LATEXMK} -g ${PAPER}.tex
	cp ${OUTDIR}/${PAPER}.pdf ./plain.pdf

# A little shorthand for Ryan.  Easier on the eyes:
grey:
	touch $(GREYMARK)
	${MAKE} paper
white:
	rm -f $(GREYMARK)
	${MAKE} paper

# ============================================================

UNAME := $(shell uname)

# Open the PDF in a viewer after building:
open: ${OUTDIR}/${PAPER}.pdf
ifeq (${UNAME}, Darwin)
	open ${OUTDIR}/${PAPER}.pdf
endif
ifeq (${UNAME}, Linux)
	evince ${OUTDIR}/${PAPER}.pdf &
endif

# Skim is great for auto-reloading papers on Mac OS, even if it isn't
# set up as the default:
skim:
	open -a skim ${OUTDIR}/${PAPER}.pdf

clean:
	cd ${OUTDIR}; rm -f *.out *.aux *.bbl *.log *.blg *.fls *.fdb_latexmk ${PAPER}.pdf

.PHONY: editingmarks ed paper plain both grey white continuous cont skim clean
