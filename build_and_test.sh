#!/bin/bash

make build

# cp pallet_input.txt previous_pallet_input.txt
# python scripts/gen_random_pallet.py -o pallet_input.txt

TIMESTAMP="$(date +%Y-%m-%d-%H.%M.%S)"
OUT_DIR="output/${TIMESTAMP}/"

mkdir -p "${OUT_DIR}/html/imgs"

cp scripts/template_index.html "${OUT_DIR}/html/index.html"

python scripts/test.py --mzn template.mzn -d -i pallet_input2.txt -o "${OUT_DIR}"

