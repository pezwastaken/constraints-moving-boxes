#!/bin/bash

N_TESTS=${1:-100}

make build

echo "running $N_TESTS tests"
echo "----------"
echo

rm backups/fuzzy_inputs.txt

./scripts/gen_test_suite.sh "${N_TESTS}"

for ((i = 0 ; i < N_TESTS; i++)); do
	echo "running $i-th test";
	# RES=$(python test.py -d 2>/dev/null)

	cp "test/test_suite/pallet_input${i}.txt" pallet_input.txt
	RES=$(python scripts/test.py --mzn template.mzn -i pallet_input.txt | tail -n 2)

	echo "$RES"

	# if [[ "$RES" == *"models agree"* ]]; then
	# 	echo "models agreed ${i}, exiting now. check the pallet_input${i}.txt file"
	# fi

	if [[ "$RES" == *"graph returned"* ]]; then
		echo "graph and mzn didn't agree during test ${i}, exiting now. check the pallet_input${i}.txt file"
		break
	fi
done

echo "done!"


