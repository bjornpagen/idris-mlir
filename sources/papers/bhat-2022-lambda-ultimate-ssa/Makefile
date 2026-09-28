.PHONY: spag zip
# Source Latex files
TEX_MAIN = paper.tex

TEX_MAIN_DRAFT = draft.tex
TEX_MAIN_GRAMMARLY = grammarly.tex
TEX_MAIN_BLIND = blind.tex
TEX_MAIN_CAMERA_IEEE = cameraIEEE.tex


# Generate PDF files
PDF_DRAFT = draft.pdf
PDF_PAPER = paper.pdf
PDF_GRAMMARLY = grammarly.pdf
PDF_CAMERA_IEEE = cameraIEEE.pdf



PDF_BLIND = blind.pdf
IMAGES := $(wildcard images/*.jpg images/*.pdf images/*.png)

${PDF_CAMERA_IEEE}: ${TEX_MAIN_CAMERA_IEEE} ${TEX_MAIN} ${IMAGES}
	latexmk ${TEX_MAIN_CAMERA_IEEE}

all: ${PDF_PAPER}

spag: paper.tex
	# allowed to fail since it throws error if we have grammar mistakes
	-textidote --check en_UK --output html paper.tex > index.html
	python3 -m http.server

${PDF_DRAFT}: ${TEX_MAIN_DRAFT} ${TEX_MAIN} ${IMAGES}
	latexmk ${TEX_MAIN_DRAFT}

${PDF_GRAMMARLY}: ${TEX_MAIN_GRAMMARLY} ${TEX_MAIN} ${IMAGES}
	latexmk ${TEX_MAIN_GRAMMARLY}

${PDF_PAPER}: ${TEX_MAIN_PAPER} ${TEX_MAIN} ${IMAGES}
	latexmk ${TEX_MAIN_PAPER}


${PDF_BLIND}: ${TEX_MAIN_BLIND} ${TEX_MAIN} ${IMAGES}
	latexmk ${TEX_MAIN_BLIND}


blind: ${PDF_BLIND}

draft: ${PDF_DRAFT}

grammarly: ${PDF_GRAMMARLY}

paper: ${PDF_PAPER}

conscience:
	latexmk conscience.tex

view-draft: ${TEX_MAIN_DRAFT} ${TEX_MAIN} ${IMAGES}
	latexmk -pvc ${TEX_MAIN_DRAFT}

view-grammarly: ${TEX_MAIN_BLIND} ${TEX_MAIN} ${IMAGES}
	latexmk -pvc ${TEX_MAIN_GRAMMARLY}

view-paper: ${TEX_MAIN_PAPER} ${TEX_MAIN} ${IMAGES}
	latexmk -pvc ${TEX_MAIN_PAPER}

clean:
	latexmk -C

zip:
	zip paper-zip.zip ./paper.* ./IEEEtran.*   ./references.bib *.bbl ./Makefile ./images/*.pdf ./plots/*.pdf minted-cache/*
