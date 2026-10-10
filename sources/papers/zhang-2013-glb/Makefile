.SUFFIXES: .eps .pdf
LATEX=./colourlatex.sh latex
BIBTEX=bibtex
FIG2DEV=fig2dev

NAME=glbx10
BIBNAME=x10

all: $(NAME).pdf

#FIGSEPS=$(shell ls -1 figs/*.eps)

#RESULTSEPS=$(shell ls -1 results/*.eps)

#EPS=$(FIGSEPS) $(RESULTSEPS)
TEX=$(NAME).tex \
    $(BIBNAME).bib \

$(NAME).dvi: $(TEX) $(EPS) $(BIBNAME).bbl
	@echo Compiling $(NAME)
	@$(LATEX) $(NAME)
	@$(MAKE) fixlabels

$(NAME).pdf: $(NAME).dvi
	@dvipdfmx -p letter $(NAME).dvi

$(NAME).ps: $(NAME).dvi
	@dvips $(NAME).dvi
	@pkill -HUP -f "^gv .*$@" || true


fixlabels:
ifneq ($(shell grep -s -c 'Label(s) may have changed. Rerun to get cross-references right.' $(NAME).log),0)
	@echo $(NAME) Compiling again to fix labels
	@$(LATEX) $(NAME)
else
	@echo $(NAME) Labels are correct
endif

$(BIBNAME).bbl: $(BIBNAME).bib
	@echo Compiling required EPS files
	#@make -C figs
	@echo Compiling main for bibliography
	@$(LATEX) $(NAME)
	@echo Generating bibliography
	@$(BIBTEX) $(NAME)
	@echo Recompiling main after generating bibliography
	@$(LATEX)  $(NAME)
	@$(MAKE) fixlabels

%.eps.pdf: %.eps
	@echo "	" Converting $< to $(@)
	@epstopdf --outfile=figs/$(@) $<

clean:
	#@make -C figs clean
	@/bin/rm -f $(NAME).ps $(NAME).pdf *.aux *.dvi *.log *.bbl *.blg figs/*.pdf *.toc *.out *.bak
