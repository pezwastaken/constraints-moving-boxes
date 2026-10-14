#!/bin/bash

make build

mkdir input_backups
mv pallet_input.txt input_backups/pallet_input.txt

# for ((i = 0 ; i < N_TESTS; i++)); do
# 	echo "running $i-th test";
# 	cp "test/test_suite/pallet_input${i}.txt" pallet_input.txt
# 	python scripts/test.py -d --mzn template.mzn -i pallet_input.txt
# done

TEST_SUITE_DIR="test/onpallet_test_suite/"

cd "$TEST_SUITE_DIR" || { echo "Error: Could not find directory $TEST_SUITE_DIR"; exit 1; }

for dir in */; do
	dirname="${dir%/}" # Remove trailing slash

	echo "------------------------------------------"
	echo "Processing Directory: $dirname"

	# Loop through txt files in this subdirectory
	# We use "$dir"*.txt because we are currently just outside the subdirs
	for file in "$dir"*.txt; do
		if [ -f "$file" ]; then

			filename=$(basename "$file")

			echo "  Target: $filename"
			cp "${dir}${filename}" ../../pallet_input.txt
			cd ../../
			python scripts/test.py --mzn template.mzn -i pallet_input.txt
			cd "$TEST_SUITE_DIR"
			echo
		fi
	done
	echo
done

cd ../../
mv input_backups/pallet_input.txt pallet_input.txt




