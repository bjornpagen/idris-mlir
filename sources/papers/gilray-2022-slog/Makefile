PACKAGE=icse23
JPACKAGE=toplas

all:  $(PACKAGE).pdf $(JPACKAGE).pdf

%.pdf: %.tex
	pdflatex $<
	- bibtex $*
	pdflatex $<
	- makeindex -s gind.ist -o $*.ind $*.idx
	- makeindex -s gglo.ist -o $*.gls $*.glo
	pdflatex $<
	while ( grep -q '^LaTeX Warning: Label(s) may have changed' $*.log) \
	do pdflatex $<; done

clean:
	$(RM)  *.pdf *.aux *.log *.out *.bbl *.blg *~* *#*

.PHONY: all docclean clean archive zip
