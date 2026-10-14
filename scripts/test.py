import ctypes
import pathlib
import warnings
import argparse
import os
import sys
from datetime import timedelta
import time
import matplotlib.pyplot as plt
import matplotlib.patches as patches
from minizinc import Instance, Model, Solver, Status, Result
import gen_random_pallet as gen


warnings.filterwarnings("ignore", category=UserWarning, module="minizinc")


is_debug = False

# model input
TEXT_FILENAME = ""
# mzn model
MZN_FILENAME = ""
# optional output directory (html and dot)
OUTPUT_DIRECTORY = None

# model parameters
N_MZN_PARAMS = 8
model_params = None


class c_AABB(ctypes.Structure):
    """struct matching AABB"""
    _fields_ = [('min', ctypes.c_uint32 * 2),
                ('max', ctypes.c_uint32 * 2)]


class c_Action(ctypes.Structure):
    """struct matching Action"""
    _fields_ = [('n_boxes', ctypes.c_uint32),
                ('bbox', c_AABB),
                ('rotation', ctypes.c_int),
                ('mapped_to_cluster', ctypes.c_uint32),
                ('gripper_overflow', ctypes.c_uint32)]


# type corresponding to C Action*
ActionPtr = ctypes.POINTER(c_Action)


class c_FrozenVec(ctypes.Structure):
    """struct matching FrozenVec"""
    _fields_ = [('inner', ctypes.c_void_p),
                ('n', ctypes.c_uint32)]


class c_ModelParams(ctypes.Structure):
    """struct matching ModelParams"""
    _fields_ = [('data', ctypes.c_uint32 * N_MZN_PARAMS)]


def debug_print(s):
    global is_debug
    if is_debug:
        print(s, file=sys.stderr)


def fuzzy_intersect(b1: c_AABB, b2: c_AABB, orient1: int,
                    gripper_overflow: int) -> bool:

    x_overflow = 0 if orient1 == 1 else gripper_overflow
    y_overflow = 0 if orient1 == 0 else gripper_overflow

    is_left: bool = b1.max[0] + x_overflow < b2.min[0]
    is_right: bool = b1.min[0] - x_overflow > b2.max[0]
    is_above: bool = b1.max[1] + y_overflow < b2.min[1]
    is_below: bool = b1.min[1] - y_overflow > b2.max[1]

    return not (is_left or is_right or is_above or is_below)


def graph_from_pallet(actions: c_FrozenVec) -> list[list[int]]:
    """
    gen graph starting from pallet.
    Node A is connected to B if A fuzzy_intersects B.
    (relationship is not symmetric).
    """
    actions_ptr = ctypes.cast(actions.inner, ActionPtr)
    n_actions = actions.n
    adj = [[] for _ in range(n_actions)]

    for i in range(n_actions):
        for j in range(n_actions):

            if i == j:
                continue

            action = actions_ptr[i]
            other_action = actions_ptr[j]

            # directed edge between box and other_box
            if fuzzy_intersect(action.bbox, other_action.bbox,
                               action.rotation, action.gripper_overflow):
                adj[i].append(j)

    debug_print(f"pallet graph adjacency list: {adj}")
    return adj


def visit(graph: list[list[int]], i: int, visiting: list[bool],
          visited: list[bool]):

    assert (visited[i] is False)
    assert (visiting[i] is False)
    visiting[i] = True
    neighbours = graph[i]

    for neighbour in neighbours:
        if visited[neighbour] is True:
            continue

        if visiting[neighbour] is True:
            return True

        if visit(graph, neighbour, visiting, visited):
            return True

    visited[i] = True
    visiting[i] = False
    return False


def is_left_of(action1: c_Action, action2: c_Action) -> bool:
    # vertical box cutting through an horizontal one
    if action2.rotation == 0 and action1.rotation == 1:
        return action1.bbox.max[1] < action2.bbox.min[1]

    # horizontal box cutting through a vertical one
    elif action2.rotation == 1 and action1.rotation == 0:
        return action1.bbox.max[0] < action2.bbox.min[0]

    return False


def is_right_of(action1: c_Action, action2: c_Action) -> bool:
    # vertical box cutting through an horizontal one
    if action2.rotation == 0 and action1.rotation == 1:
        return action1.bbox.min[1] > action2.bbox.max[1]

    # horizontal box cutting through a vertical one
    elif action2.rotation == 1 and action1.rotation == 0:
        return action1.bbox.min[0] > action2.bbox.max[0]

    return False


def has_left_colliding_node(x: int, x_in_nodes: list[int], actions: c_FrozenVec) -> bool:
    actions_ptr = ctypes.cast(actions.inner, ActionPtr)

    action = actions_ptr[x]

    for in_node in x_in_nodes:
        other_action = actions_ptr[in_node]

        if is_left_of(other_action, action):
            # directed edge between box and other_box
            if fuzzy_intersect(other_action.bbox, action.bbox,
                               other_action.rotation, other_action.gripper_overflow):
                return True

    return False


# these two functions are looping through the same array twice when they could just use a flag
def has_right_colliding_node(x: int, x_in_nodes: list[int], actions: c_FrozenVec) -> bool:
    actions_ptr = ctypes.cast(actions.inner, ActionPtr)

    action = actions_ptr[x]

    for in_node in x_in_nodes:
        other_action = actions_ptr[in_node]

        if is_right_of(other_action, action):
            # directed edge between box and other_box
            if fuzzy_intersect(other_action.bbox, action.bbox,
                               other_action.rotation, other_action.gripper_overflow):
                return True

    return False


def is_unsat_t_pattern(graph: list[list[int]], actions: c_FrozenVec) -> bool:

    in_nodes = [[] for _ in range(len(graph))]
    check_nodes = []

    for (i, adj_list) in enumerate(graph):
        for node in adj_list:
            in_nodes[node].append(i)
            if len(in_nodes[node]) == 2:
                check_nodes.append(node)

    # print(in_nodes)
    # print(check_nodes)

    for x in check_nodes:
        x_in_nodes = in_nodes[x]
        # print(x_in_nodes)

        left = has_left_colliding_node(x, x_in_nodes, actions)
        right = has_right_colliding_node(x, x_in_nodes, actions)
        # print(f"left: {left}")
        # print(f"right: {right}")
        if left and right:
            return True

    return False


def is_unsat_loops(graph: list[list[int]]) -> bool:
    visited = [False for _ in range(len(graph))]
    visiting = [False for _ in range(len(graph))]

    for i in range(len(graph)):
        if not visited[i]:
            loops = visit(graph, i, visiting, visited)
            if loops:
                return True

    return False


def export_to_dot(graph: list[list[int]], filename="graph.dot"):
    debug_print("\n")
    debug_print("digraph PalletGraph {")
    # Optional: styling for nodes
    debug_print("    node [shape=box, fontname=Arial];")
    for i, neighbours in enumerate(graph):
        # Even if a node has no neighbors, we define it so it shows up
        debug_print(f'    {i} [label="Box {i}"];')
        for neighbour in neighbours:
            debug_print(f"    {i} -> {neighbour};")
    debug_print("}")
    debug_print(f"Successfully wrote graph to {filename}")


def load_lib(filename: str):
    """
    return a handle to the loaded dll
    """
    libname = pathlib.Path().absolute() / filename
    c_lib = ctypes.CDLL(libname)
    return c_lib


def gen_actions(lib, with_extra_constraints: bool) -> c_FrozenVec:
    """
    call the C function that generates the actions that the mzn model will
    try to schedule.
    """

    w = ctypes.c_uint8(with_extra_constraints)
    # if with_extra_constraints:
    #     assert (w != 1)
    # elif not with_extra_constraints:
    #     assert (w == 0)

    lib.gen_actions.restype = c_FrozenVec

    # this call should output a `pallet_input.dzn` file that can be used by the
    # mzn driver
    actions = lib.gen_actions(w)
    debug_print(f"number of actions(py): {actions.n}")

    return actions


def load_model_input_params(lib):
    global model_params

    lib.get_model_params.restype = c_ModelParams
    c_model_params = lib.get_model_params()

    model_params = gen.ModelParams(
        TIMESTEPS=c_model_params.data[0],
        MAX_AVAILABLE_BOXES=c_model_params.data[1],
        GRIPPER_SIZE=c_model_params.data[2],
        PALLET_W=c_model_params.data[3],
        PALLET_H=c_model_params.data[4],
        BOX_W=c_model_params.data[5],
        BOX_H=c_model_params.data[6],
        N_BOXES=c_model_params.data[7],
    )


def with_args():
    parser = argparse.ArgumentParser(
        prog='x',
        description='todo description',
        epilog='todo end')

    parser.add_argument('-i', '--input-file',
                        required=True, type=str, default=None)
    parser.add_argument('-o', '--output-dir', type=str, default=None)
    parser.add_argument('-d', '--debug', action='store_true')
    parser.add_argument('-x', '--extraconstraints', action='store_true')
    parser.add_argument('--mzn', required=True, type=str,
                        help="minizinc file to run")
    return parser


def draw_line(ax, x: list[int], y: list[int]):
    ax.plot(
        x,  # X-coordinates from left to right
        y,      # Y-coordinates (stays at the top edge)
        color='black',
        linewidth=5,  # Increase this to make it thicker
        solid_capstyle='projecting'  # Keeps corners looking sharp
    )


def draw_actions(actions: c_FrozenVec, action_time: list[int],
                 action_rotation: list[str], max_t=0):
    global model_params

    image_filename = OUTPUT_DIRECTORY + f"html/imgs/pallet{max_t}.png"

    actions_ptr = ctypes.cast(actions.inner, ActionPtr)
    n_actions = actions.n

    fig, ax = plt.subplots(
        figsize=(10, (10 * model_params.PALLET_H) / model_params.PALLET_W))

    ax.set_xlim(1, model_params.PALLET_W + 1)
    ax.set_ylim(1, model_params.PALLET_H + 1)

    ax.set_xticks(range(1, model_params.PALLET_W + 1), minor=True)
    ax.set_yticks(range(1, model_params.PALLET_H + 1), minor=True)
    ax.grid(which='minor', color='#CCCCCC', linestyle='--')

    ax.set_xticks([i + 0.5 for i in range(1, model_params.PALLET_W + 1)])
    ax.set_yticks([i + 0.5 for i in range(1, model_params.PALLET_H + 1)])

    ax.set_xticklabels(range(1, model_params.PALLET_W + 1))
    ax.set_yticklabels(range(1, model_params.PALLET_H + 1))

    ax.tick_params(which='major', length=0)

    ax.invert_yaxis()

    cmap = plt.get_cmap('tab20')

    for (action_id, at_t) in enumerate(action_time):
        if at_t-1 > max_t:
            continue

        action = actions_ptr[action_id]
        x = action.bbox.min[0]
        y = action.bbox.min[1]
        w = action.bbox.max[0] - action.bbox.min[0] + 1  # action['w']
        h = action.bbox.max[1] - action.bbox.min[1] + 1  # action['h']

        rect = patches.Rectangle(
            (x, y), w, h,
            linewidth=1,
            edgecolor='black',
            facecolor=cmap(action_id % 20),
            alpha=0.8
        )

        ax.add_patch(rect)

        rotation = action_rotation[action_id]

        if rotation == "TOP":
            draw_line(ax, [x+0.1, x+w-0.1], [y+0.1, y+0.1])
        elif rotation == "BOT":
            draw_line(ax, [x+0.1, x+w-0.1], [y+h-0.1, y+h-0.1])
        elif rotation == "LEFT":
            draw_line(ax, [x+0.1, x+0.1], [y+0.1, y+h-0.1])
        elif rotation == "RIGHT":
            draw_line(ax, [x+w-0.1, x+w-0.1], [y+0.1, y+h-0.1])

        # ax.plot(
        #     [x, x + w],  # X-coordinates from left to right
        #     [y, y],      # Y-coordinates (stays at the top edge)
        #     color='black',
        #     linewidth=3,  # Increase this to make it thicker
        #     solid_capstyle='projecting'  # Keeps corners looking sharp
        # )

        cx = x + w / 2
        cy = y + h / 2
        ax.text(cx, cy, f"t={at_t},\nid={action_id + 1}", color='white',
                ha='center', va='center', fontweight='bold', fontsize=14)

    plt.xlabel("X")
    plt.ylabel("Y")

    plt.savefig(image_filename, bbox_inches='tight')
    plt.close()


def draw_conveyor_belt(
    mzn_result,
    n_available,
    n_waiting,
    box_width=1.0,
    box_height=1.0,
    gap=0.2,
    i=0
):
    """
    Draws a vertical conveyor belt (Top -> Bottom).
    Waiting boxes at top, Available boxes at bottom.
    """

    image_filename = OUTPUT_DIRECTORY + f"html/imgs/belt{i}.png"

    # --- Configuration ---
    max_drawn_waiting = 3

    # Belt Dimensions
    # Belt "width" is the visual width on plot (x-axis dimension)
    belt_width = box_width * 1.5
    belt_x = -belt_width / 2  # Center belt at x=0

    # Length of sections
    # Available (Bottom) - goes downwards
    section_bottom_len = n_available * (box_height + gap) + gap
    # Waiting (Top) - goes upwards
    section_top_len = (max_drawn_waiting + 1) * (box_height + gap)

    # Setup Plot
    # Figure size needs to be taller than wide now
    fig, ax = plt.subplots(figsize=(6, 10))

    # --- Draw The Belt Background ---
    # Available Section (Bottom, y < 0)
    # Rectangle(xy, width, height) - xy is bottom-left corner.
    rect_avail = patches.Rectangle(
        (belt_x, -section_bottom_len),
        belt_width,
        section_bottom_len,
        linewidth=0, facecolor='#e0e0e0', zorder=0
    )
    ax.add_patch(rect_avail)

    # Waiting Section (Top, y > 0)
    rect_wait = patches.Rectangle(
        (belt_x, 0),
        belt_width,
        section_top_len,
        linewidth=0, facecolor='#f0f0f0', zorder=0
    )
    ax.add_patch(rect_wait)

    # Separator Line (at y=0)
    plt.axhline(y=0, color='black', linestyle='--', linewidth=2, zorder=1)

    # Belt Edges (Left and Right lines)
    plt.vlines([belt_x, belt_x + belt_width], -section_bottom_len,
               section_top_len, colors='gray', linewidth=2, zorder=1)

    # --- Helper: Color Generator ---
    cmap = plt.get_cmap('viridis')

    def get_color(i, total):
        return cmap(i / max(total, 1))

    total_boxes = n_available + n_waiting

    # --- Draw Available Boxes (Bottom Side) ---
    # These flow downwards from the separator (y=0)
    for i in range(n_available):
        # Center horizontally
        x_pos = -box_width / 2

        # Vertical position: Stack downwards
        # y_pos is the bottom-left corner of the box
        y_pos = - (gap + i * (box_height + gap)) - box_height

        box = patches.Rectangle(
            (x_pos, y_pos),
            box_width, box_height,
            linewidth=1, edgecolor='black',
            facecolor=get_color(i, total_boxes),
            zorder=2
        )
        ax.add_patch(box)

        # Label
        ax.text(0, y_pos + box_height/2, str(i+1),
                ha='center', va='center', color='white', fontweight='bold', fontsize=12, zorder=3)

    # --- Draw Waiting Boxes (Top Side) ---
    # These approach from the top.
    boxes_to_draw = min(n_waiting, max_drawn_waiting)

    for i in range(boxes_to_draw):
        x_pos = -box_width / 2

        # Position: Stack upwards from the gap
        y_pos = gap + i * (box_height + gap)

        box = patches.Rectangle(
            (x_pos, y_pos),
            box_width, box_height,
            linewidth=1, edgecolor='black', linestyle=':',
            facecolor=get_color(n_available + i, total_boxes),
            alpha=0.7, zorder=2
        )
        ax.add_patch(box)

    # --- Annotations ---
    text_x_offset = belt_width / 2 + 0.5

    # Available Label
    ax.text(text_x_offset, -section_bottom_len / 2,
            f"AVAILABLE FOR PICKUP\n(Total: {n_available})",
            ha='left', va='center', fontsize=12, color='green')

    # Waiting Label
    ax.text(text_x_offset, section_top_len / 3,
            f"IN QUEUE\n(Total: {n_waiting})",
            ha='left', va='center', fontsize=12, color='blue')

    # "More" indicator
    if n_waiting > max_drawn_waiting:
        hidden_count = n_waiting - max_drawn_waiting
        y_top_draw = gap + boxes_to_draw * (box_height + gap)
        ax.text(0, y_top_draw + 0.5,
                f"... +{hidden_count} more ",
                ha='center', va='bottom', fontsize=12, fontstyle='italic')

    # --- Final Plot Adjustments ---
    ax.set_aspect('equal')
    # Set X limits to show the text clearly
    ax.set_xlim(-belt_width - 1, belt_width + 4)
    ax.set_ylim(-section_bottom_len, section_top_len)

    ax.axis('off')
    # plt.title("Vertical Conveyor Status", fontsize=16)
    plt.tight_layout(pad=0)
    plt.savefig(image_filename, bbox_inches='tight')


def dump_html(actions: c_FrozenVec, mzn_result):
    if OUTPUT_DIRECTORY is None:
        return

    HTML_ROW_TEMPLATE = """
    <div class="row-container">
        <div class="image-grid">
            <img src="imgs/belt.png" alt="img1_a">
            <img src="imgs/pallet.png" alt="img1_b">
        </div>
    </div>

    """

    HTML_ROW_UNSAT_TEMPLATE = """
    <div class="row-container">
        <div class="image-grid">
            <img src="imgs/pallet.png" alt="img1_b">
        </div>
    </div>

    """

    mzn_solution_found = mzn_result.status is Status.SATISFIED

    html_index_file = OUTPUT_DIRECTORY + "/html/index.html"

    with open(html_index_file, "a") as f:
        if not mzn_solution_found:
            n = actions.n
            tmp = [i for i in range(1, n+1)]
            draw_actions(actions, tmp, tmp, len(tmp))

            html_body_row = HTML_ROW_UNSAT_TEMPLATE.replace("pallet.png",
                                                            f"pallet{len(tmp)}.png")

            f.write(html_body_row)

        else:
            debug_print(f"n available boxes: {
                        mzn_result["n_available_boxes"]}")
            debug_print(f"n waiting boxes: {mzn_result["n_boxes_waiting"]}")

            n_boxes_available_forall_t = mzn_result["n_available_boxes"]
            n_boxes_waiting_forall_t = mzn_result["n_boxes_waiting"]

            for i in range(len(mzn_result["action_id"])):

                draw_actions(actions, mzn_result["action_time"],
                             mzn_result["action_rotation"], i)

                n_available = n_boxes_available_forall_t[i]
                n_waiting = n_boxes_waiting_forall_t[i]

                draw_conveyor_belt(mzn_result, n_available=n_available,
                                   n_waiting=n_waiting, box_width=1.5, box_height=1.2, i=i)

                html_body_row = HTML_ROW_TEMPLATE.replace(
                    "belt.png", f"belt{i}.png").replace("pallet.png", f"pallet{i}.png")

                f.write(html_body_row)

            f.write("</body>")
            f.write("</html>")

        debug_print("html done")


def run_mzn() -> Result:
    model = Model("run_tmp/tmp.mzn")
    # Find the MiniZinc solver configuration for Gecode
    gecode = Solver.lookup("chuffed")
    # Create an Instance of the n-Queens model for Gecode
    instance = Instance(gecode, model)

    instance.add_file("pallet_input.dzn")

    solve_timeout = timedelta(minutes=5)
    result = instance.solve(timeout=solve_timeout, free_search=True)
    # result = instance.solve()

    print(f"MZN result status: {result.status}")

    return result


def main():
    global is_debug
    global model_params
    global TEXT_FILENAME
    global MZN_FILENAME
    global OUTPUT_DIRECTORY

    parser = with_args()
    args = parser.parse_args()

    is_debug = args.debug is True
    with_extra_constraints = args.extraconstraints is True
    MZN_FILENAME = args.mzn
    TEXT_FILENAME = args.input_file
    OUTPUT_DIRECTORY = args.output_dir

    os.system(f"cp {MZN_FILENAME} run_tmp/tmp.mzn")

    # load .so
    c_lib = load_lib("gen_actions.so")

    start_time = time.time()

    # call `gen_actions`
    actions = gen_actions(c_lib, with_extra_constraints)

    #
    mzn_result = run_mzn()
    elapsed = time.time() - start_time

    # get model parameters directly from the c lib
    load_model_input_params(c_lib)
    debug_print(f"\nmodel_params: {model_params}\n")

    # generate html
    dump_html(actions, mzn_result)

    #
    # compare expected output
    graph = graph_from_pallet(actions)
    export_to_dot(graph)
    unsat = is_unsat_loops(graph) or is_unsat_t_pattern(graph, actions)
    debug_print(f"(graph double-check) is unsat: {unsat}")

    if ((unsat and mzn_result.status is Status.UNSATISFIABLE)
            or (not unsat and mzn_result.status is Status.SATISFIED)):
        print(f"models agree ({mzn_result.status})")
    if unsat and mzn_result.status is Status.SATISFIED:
        print("graph returned unsat but mzn returned sat")

    c_lib.frozenvec_dealloc(actions)
    print(elapsed)

    return


if __name__ == "__main__":
    main()


# EOF
