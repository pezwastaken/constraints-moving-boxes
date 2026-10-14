#!/bin/bash

N_TESTS=${1:-20}

echo "generating $N_TESTS tests"
echo "----------"
echo

rm -r test/test_suite
mkdir test/test_suite

for ((i = 0 ; i < N_TESTS; i++)); do
	echo "generating $i-th test";
	python scripts/gen_random_pallet.py -o "test/test_suite/pallet_input${i}.txt"
done

