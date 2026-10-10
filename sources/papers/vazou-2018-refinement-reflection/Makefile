all: pdf

pdf:
	latexmk -pdf main.tex

cont: continuous
continuous:
	latexmk -pvc -pdf main.tex

chop:
	rm -f anon-supplemental.pdf anon-submission.pdf
	cp main.pdf anon-supplemental.pdf
	if which cpdf; \
         then cpdf  anon-supplemental.pdf "1-28" -o anon-submission.pdf; \
         else pdftk anon-supplemental.pdf cat 1-28 output anon-submission.pdf; fi

plain:
	touch no-editing-marks
	$(MAKE) clean
	$(MAKE) 

ed:
	rm -f no-editing-marks
	$(MAKE) clean
	$(MAKE)

clean:
	latexmk -c main.tex

cleanall:
	latexmk -C -bibtex main.tex

.PHONY: all pdf clean cleanall cont continuous plain ed
