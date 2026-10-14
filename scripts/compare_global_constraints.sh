#!/bin/bash

N_TESTS=${1:-100}

make build

echo "running $N_TESTS tests"
echo "----------"
echo

echo > results/compare_global_constraints_output.txt

for ((i = 0 ; i < N_TESTS; i++)); do
	echo "running $i-th test";

	python scripts/gen_random_pallet.py -o pallet_input.txt

	echo "default" >>results/compare_global_constraints_output.txt
	python scripts/test.py --mzn template.mzn -i pallet_input.txt 1>>results/compare_global_constraints_output.txt

	echo "global" >>results/compare_global_constraints_output.txt
	python scripts/test.py --mzn global_constraints_v.mzn -i pallet_input.txt 1>>results/compare_global_constraints_output.txt
	echo >> results/compare_global_constraints_output.txt
done
