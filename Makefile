#path to the minizinc binary. If it's in path just use `minizinc`
MZN_PATH := minizinc

build:
	cd gen_actions && ./build.sh && mv gen_actions.so ../gen_actions.so

