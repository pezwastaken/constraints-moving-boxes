#!/bin/bash

N_TESTS=${1:-100}

make build

echo "running $N_TESTS tests"
echo "----------"
echo

echo > results/compare_csp_representations_output.txt

mkdir tmp

for ((i = 0 ; i < N_TESTS; i++)); do
	echo "running $i-th test";

	mv template.mzn tmp/x.mzn
	cp prev.mzn template.mzn

	echo "prev" >>results/compare_csp_representations_output.txt
	python test_prev.py -d 2>/dev/null 1>>results/compare_csp_representations_output.txt

	mv tmp/x.mzn template.mzn
	echo "new" >>results/compare_csp_representations_output.txt
	python test.py pallet_input.txt -d 2>/dev/null 1>>results/compare_csp_representations_output.txt
	echo >> results/compare_csp_representations_output.txt
done

cp tmp/x.mzn template.mzn
