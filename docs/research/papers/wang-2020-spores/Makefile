PAPER=vldb2020

all:  ## Compile paper
	pdflatex $(PAPER); bibtex $(PAPER); pdflatex --pdf $(PAPER); pdflatex --pdf $(PAPER)

clean:  ## Clean output files
	latexmk -c; rm *bbl; rm vldb2020.pdf
