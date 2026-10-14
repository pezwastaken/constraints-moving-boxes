#!/bin/bash

N_TESTS=${1:-100}

make build

echo "running $N_TESTS tests"
echo "----------"
echo

echo > results/t.txt

for ((i = 0 ; i < N_TESTS; i++)); do
	echo "running $i-th test";

	python test.py -d 2>/dev/null 1>> results/t.txt
	python test.py pallet_input.txt -d -x 2>/dev/null 1>>results/t.txt
	echo >> results/t.txt
done

