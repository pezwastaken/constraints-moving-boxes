# Robot Movement Planning (MiniZinc)

A constraint programming model that schedules the movements of a robotic arm loading rectangular boxes onto a pallet, fed by a continuous conveyor belt.

Given the final position and orientation of every box on the pallet, the solver decides **when** each box (or group of boxes) is picked up and dropped, so that no collision occurs and the whole process fits in the available time steps. If no valid schedule exists, the instance is reported as unsatisfiable.

## The problem

- `k` boxes of identical size `x × y` (each can be rotated by 90°) must be placed on an `n × m` pallet. The final configuration is given and is guaranteed to be non-overlapping.
- Boxes arrive on a conveyor belt and enter a finite *retrieving area*, from which the gripper can pick them up. When not enough boxes are available the gripper must wait (**NULL-move**).
- The gripper is made of two parallel plates of size `S`. It can pick several boxes at once if they are contiguous in the final configuration and `S + x <= T`, where `T` is the total length of the picked boxes.
- Boxes are released by opening **one** plate at a time, with the gripper optionally rotated by 90°. The opening must not collide with boxes already placed.
- **Gripper overflow** (`S` larger than the box being placed) can cause extra collisions with neighbouring boxes, which constrains the admissible order of placement.

## Approach

The solution is a two-step pipeline:

1. **Action generation (C, `gen_actions/`)**: reads the pallet configuration, clusters adjacent boxes with the same orientation into *actions* (an orientation plus an AABB that tightly contains the boxes), and emits a MiniZinc data file. It also generates redundant ordering constraints by detecting the "T" patterns caused by gripper overflow.
2. **Scheduling (MiniZinc)**: a CSP that assigns a time step to every action (`action_time`), links it with the inverse view (`action_id`), models the conveyor belt (waiting queue and retrieving area), allows NULL-moves, and checks collisions between axis-aligned bounding boxes.

Main modeling choices:

- Bounding-box representation of the goal instead of a cell matrix, so the solver only decides *timing*, not drop locations.
- Search variable `action_time` (time of each action) instead of `action_id` (action at each time), which gave a large speedup.
- NULL-moves are allowed only when no action is executable, which removes padding symmetries.
- Optional collision checking with the global constraint `diffn`.
- Partial symmetry breaking on gripper rotations (TOP and RIGHT preferred).

## Repository structure

<!-- TODO: double-check these descriptions against the actual files -->

| Path | Description |
|------|-------------|
| `gen_actions/` | C code that clusters boxes into actions and generates the MiniZinc input |
| `template.mzn` | Main MiniZinc model |
| `global_constraints_v.mzn` | Variant of the model using the global constraint `diffn` |
| `prev.mzn` | Previous model (`action_id` representation), kept for comparison |
| `pallet_input.txt`, `pallet_input2.txt` | Example pallet configurations |
| `scripts/` | Helper scripts |
| `test/` | Test instances |
| `Makefile` | Builds the action generator |
| `build_and_test.sh` | Builds the project and runs the tests |
| `run_test_suite.sh` | Runs the test suite |
| `run_onpallet_test_suite.sh` | Runs the instances generated with [OnPallet](https://www.onpallet.com/index.php) |

## Requirements

- [MiniZinc](https://www.minizinc.org/) with a solver (e.g. Gecode, Chuffed)
- A C compiler and `make`
- Bash

## Usage

<!-- TODO: replace with the exact commands/arguments -->

Build the action generator:

```bash
make
```

Generate the MiniZinc data from a pallet configuration and solve it:

```bash
# 1. generate actions from a pallet configuration
./gen_actions/<executable> pallet_input.txt > instance.dzn

# 2. solve
minizinc template.mzn instance.dzn
```

Run the test suites:

```bash
./build_and_test.sh
./run_test_suite.sh
./run_onpallet_test_suite.sh
```

## Input format

<!-- TODO: describe the format of pallet_input.txt: pallet size, box size, gripper size, box positions and orientations -->

## Results

Instances generated with OnPallet, gripper width equal to the box width (to force satisfiability), 300 s timeout.

| Configuration (box_pallet) | Without global: SAT / Timeout / Avg (s) | With global: SAT / Timeout / Avg (s) |
|----------------------------|------------------------------------------|---------------------------------------|
| b200x100_p500x500 | 5/5 / 0 / 0.36 | 5/5 / 0 / 0.36 |
| b200x100_p900x500 | 3/3 / 0 / 4.80 | 3/3 / 0 / 4.17 |
| b200x100_p900x700 | 1/2 / 1 / 288.00 | 1/2 / 1 / 246.14 |
| b200x100_p900x900 | 0/2 / 2 / 300.28 | 1/2 / 1 / 229.68 |
| b300x100_p700x700 | 4/4 / 0 / 0.39 | 4/4 / 0 / 0.40 |
| b400x200_p1100x1100 | 5/5 / 0 / 0.37 | 5/5 / 0 / 0.37 |

## Automated testing

Expected results for random pallets are approximated by detecting unsatisfiable configurations directly on a graph, before running the CSP. An edge `a1 -> a2` exists when the (gripper-extended) bounding box of `a1` collides with `a2`, meaning `a2` must be placed first. Two patterns guarantee unsatisfiability:

- **Loops** in the graph;
- the **double "T"** pattern: a node with incoming edges from both its left and its right.

The check is sound but not complete: if it reports UNSAT the CSP is UNSAT, but the CSP may also be UNSAT in cases it does not catch.

## Report

The full write-up (modeling steps, symmetry breaking attempts, benchmarks) is available in the project report: *Robot Movement Planning*.

## Authors

- Andrea Pezzuolo
- Andrea Agnetti

## References

- OnPallet, *Pallet loading software*. https://www.onpallet.com/index.php
