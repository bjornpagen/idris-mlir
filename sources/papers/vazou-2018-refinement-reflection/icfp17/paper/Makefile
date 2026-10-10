all:
	latexmk -pdf main.tex

continuous:
	latexmk -pvc -pdf -interaction=nonstopmode main.tex

.PHONY: clean continuous
clean:
	latexmk -c main.tex
