#!/usr/bin/sh
filename=diagram-$1.mp
targetname=diagram-$1.mps

if [ -e $filename ]
then
    echo "File $filename already exists!"
    exit 1
else
    echo Generating "$filename"...
    cp diagram-template.mp "$filename"
    echo "beginfig("$1")" >> "$filename"
    cat diagram-template-end.mp >> "$filename"
    echo $targetname >> diagram_list
fi

