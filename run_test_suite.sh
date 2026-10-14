#!/bin/bash

make build

N_TESTS=$(cd test/test_suite/ && ls -1 | wc -l)

echo "running $N_TESTS tests"
echo "----------"
echo

mkdir input_backups
mv pallet_input.txt input_backups/pallet_input.txt

for ((i = 0 ; i < N_TESTS; i++)); do
	echo "running $i-th test";
	cp "test/test_suite/pallet_input${i}.txt" pallet_input.txt
	python scripts/test.py --mzn global_constraints_v.mzn -i pallet_input.txt
	echo ""
done

mv input_backups/pallet_input.txt pallet_input.txt


