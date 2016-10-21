#!/bin/sh

echo "left offset: "; read leftOffset;
echo "top offset: "; read topOffset;
echo "width: "; read width;
echo "height: "; read height;
echo "target sub-folder: "; read folderName;
echo "target format: "; read format;

mkdir $folderName;

for fileName in "$@"
do
  echo "Cropping file $fileName...";
  convert -crop ${width}x$height+$leftOffset+$topOffset \
    "$fileName" "$folderName/$fileName.$format";
done

echo "Done cropping $# files";

