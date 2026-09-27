PAPER = arxiv_version
TEX = $(wildcard *.tex figures/*.tex)
BIB = references.bib
INC = $(wildcard img/*.pdf img/*.png graphs/*.pdf graphs/*.png *.td)
BUILDDIR = build

.PHONY: all clean

$(PAPER).pdf: $(TEX) $(BIB) $(INC) *.mlir
	echo $(INC)
	mkdir -p $(BUILDDIR)
	pdflatex -output-directory $(BUILDDIR) -interaction=nonstopmode -halt-on-error $(PAPER)
	TEXMFOUTPUT=$(BUILDDIR) bibtex $(BUILDDIR)/$(PAPER)
	pdflatex -output-directory $(BUILDDIR) -interaction=nonstopmode -halt-on-error $(PAPER)
	pdflatex -output-directory $(BUILDDIR) -interaction=nonstopmode -halt-on-error $(PAPER)
	ln -sf $(BUILDDIR)/$(PAPER).pdf $(PAPER).pdf

clean:
	rm -rf $(BUILDDIR)/ $(PAPER).pdf
