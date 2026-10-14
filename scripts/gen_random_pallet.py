import random
import os
import math
import argparse
from typing import NamedTuple


class ModelParams(NamedTuple):
    TIMESTEPS: int
    MAX_AVAILABLE_BOXES: int
    GRIPPER_SIZE: int
    PALLET_W: int
    PALLET_H: int
    BOX_W: int
    BOX_H: int
    N_BOXES: int


class point2(NamedTuple):
    x: int
    y: int


class AABB(NamedTuple):
    a: point2
    b: point2


class PalletGenerator:
    def __init__(self, model_params):
        self.model_params = model_params
        # 0 represents empty, 1 represents occupied
        # Using a list of lists for the grid (row-major: grid[y][x])
        self.grid = [[0 for _ in range(model_params.PALLET_W)]
                     for _ in range(model_params.PALLET_H)]
        self.placed_boxes = []
        self.pallet_graph = []
        # self.

    def is_valid_position(self, x, y, eff_w, eff_h):
        """
        Check if placing a box of size eff_w * eff_h at (x, y)
        is within bounds and does not overlap existing boxes.
        """
        # Check bounds
        if x + eff_w > self.model_params.PALLET_W or y + eff_h > self.model_params.PALLET_H:
            return False

        # Check for collisions
        for r in range(y, y + eff_h):
            for c in range(x, x + eff_w):
                if self.grid[r][c] != 0:
                    return False
        return True

    def mark_grid(self, x, y, eff_w, eff_h):
        """Marks the grid cells as occupied."""
        for r in range(y, y + eff_h):
            for c in range(x, x + eff_w):
                self.grid[r][c] = 1

    def generate(self, attempts_per_box=50):
        """
        Tries to place up to max_boxes.
        """
        for _ in range(self.model_params.N_BOXES):
            placed = False
            # Try a few times to place a single box randomly
            for _ in range(attempts_per_box):
                # Randomly decide orientation
                orientation = random.choice(['h', 'v'])

                if orientation == 'h':
                    eff_w, eff_h = self.model_params.BOX_W, self.model_params.BOX_H
                else:
                    eff_w, eff_h = self.model_params.BOX_H, self.model_params.BOX_W  # Swap for vertical

                # Random coordinate (0-indexed internally)
                max_x = self.model_params.PALLET_W - eff_w
                max_y = self.model_params.PALLET_H - eff_h

                if max_x < 0 or max_y < 0:
                    continue

                x = random.randint(0, max_x)
                y = random.randint(0, max_y)

                if self.is_valid_position(x, y, eff_w, eff_h):
                    self.mark_grid(x, y, eff_w, eff_h)

                    aabb = AABB(a=point2(x=x+1, y=y+1),
                                b=point2(x=x+eff_w, y=y+eff_h))

                    # print(
                    #     f"aabb: [({aabb.a.x}, {aabb.a.y}), ({aabb.b.x}, {aabb.b.y})]")

                    self.placed_boxes.append({
                        'x': x + 1,
                        'y': y + 1,
                        'w': eff_w,
                        'h': eff_h,
                        'orient': orientation,
                        'aabb': aabb,
                    })

                    placed = True
                    break

            if not placed:
                break

    def write_to_file(self, filename):
        """Writes the configuration to the specified file."""
        try:
            with open(filename, 'w') as f:
                f.write(f"t {self.model_params.TIMESTEPS}\n")
                f.write(
                    f"max_avail_boxes {self.model_params.MAX_AVAILABLE_BOXES}\n")
                f.write(f"g {self.model_params.GRIPPER_SIZE}\n")
                f.write(f"{self.model_params.PALLET_W},{
                        self.model_params.PALLET_H}\n")
                f.write(f"{self.model_params.BOX_W},{
                        self.model_params.BOX_H}\n")
                f.write("-\n")

                for box in self.placed_boxes:
                    f.write(f"{box['x']},{box['y']} {box['orient']}\n")

                f.write("-\n")
            print(f"Successfully wrote {
                len(self.placed_boxes)} boxes to '{filename}'")
        except IOError as e:
            print(f"Error writing to file: {e}")


def with_args():
    parser = argparse.ArgumentParser(
        prog='gen random pallet',
        description='todo description',
        epilog='todo end')

    # parser.add_argument('filename', nargs='?', default=None)
    parser.add_argument('-o', '--output', required=True, type=str)
    return parser


def gen_pallet():
    random.seed()

    parser = with_args()
    args = parser.parse_args()

    TEXT_FILENAME = args.output

    timesteps = 30
    max_available_boxes = 6
    gripper_size = 2
    pallet_w = 9
    pallet_h = 9
    box_w = 2
    box_h = 1
    n_boxes = 30

    model_params = ModelParams(
        TIMESTEPS=timesteps,
        MAX_AVAILABLE_BOXES=max_available_boxes,
        GRIPPER_SIZE=gripper_size,
        PALLET_W=pallet_w,
        PALLET_H=pallet_h,
        BOX_W=box_w,
        BOX_H=box_h,
        N_BOXES=n_boxes,
    )

    generator = PalletGenerator(model_params)
    generator.generate()
    generator.write_to_file(TEXT_FILENAME)


if __name__ == "__main__":
    gen_pallet()
# EOF
