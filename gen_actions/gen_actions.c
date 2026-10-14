#include <assert.h>
#include <math.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "utils.h"

void frozenvec_dealloc(FrozenVec f)
{
  free(f.inner);
}

FrozenVec gen_actions(u8 with_extra_constraints);

typedef struct {
  u32 timesteps;
  u32 max_available_boxes;

  u32 gripper_size;

  u32 pallet_width;
  u32 pallet_height;

  u32 box_width;
  u32 box_height;

  u32 n_boxes;
} ModelParams;

ModelParams get_model_params(void);

static const FrozenVec DEFAULT_FROZEN_VEC = {.inner = NULL, .n = 0};

static char* buffer = NULL;
static ModelParams model_params = {0};

static inline u32 u32_min(u32 a, u32 b)
{
  return (a <= b) ? a : b;
}

static inline u32 u32_max(u32 a, u32 b)
{
  return (a >= b) ? a : b;
}

static inline u32 u32_clamp(u32 a, u32 lb, u32 ub)
{
  if (a < lb)
    return lb;

  else if (a > ub)
    return ub;

  return a;
}

static usize read_file(void) {
  FILE *file = fopen("pallet_input.txt", "rb");
  if (file == NULL) {
    perror("error opening file");
    exit(1);
  }

  fseek(file, 0, SEEK_END);
  usize file_size = (usize)ftell(file);
  rewind(file);

  buffer = (char *)malloc(file_size + 1U);
  if (buffer == NULL) {
    perror("Memory allocation failed");
    fclose(file);
    exit(1);
  }

  size_t result = fread(buffer, 1, file_size, file);
  if (result != file_size) {
    perror("Reading error");
    free(buffer);
    fclose(file);
    exit(1);
  }

  buffer[file_size] = '\0';

  // printf("File content:\n%s\n", buffer);

  fclose(file);
  return file_size;
}


static char slice_at(StringSlice slice, u32 i)
{
  return slice.inner[slice.offset + i];
}

static StringSlice slice_reslice(StringSlice slice, u32 i)
{
  StringSlice s = {.inner = slice.inner, .offset = slice.offset + i};
  return s;
}

static u32 index_of(const char* s, char c) {
  char* p = strchr(s, c);
  if (p == NULL)  return U32_MAX;
  assert(p >= s);
  return (u32) (p - s);
}

static u32 slice_index_of(StringSlice slice, char c)
{
  char* p = strchr(slice.inner + slice.offset, c);
  if (p == NULL)  return U32_MAX;
  assert(p >= (slice.inner + slice.offset));
  return (u32) (p - (slice.inner + slice.offset));
}

static i32 parse_int(StringSlice slice)
{
  return atoi(slice.inner + slice.offset);
}

static void parse_size(void) {
  assert(buffer[0] == 't');

  model_params.timesteps = (u32)atoi(buffer + 2);

  const char* avail_boxes_row = buffer + index_of(buffer, '\n') + 1;
  u32 avail_boxes_idx = index_of(avail_boxes_row, ' ') + 1;
  model_params.max_available_boxes = (u32)atoi(avail_boxes_row + avail_boxes_idx);

  const char* gripper_size_row = avail_boxes_row + index_of(avail_boxes_row, '\n') + 1;
  u32 gripper_size_idx = index_of(gripper_size_row, ' ') + 1;
  model_params.gripper_size = (u32)atoi(gripper_size_row + gripper_size_idx);

  const char* pallet_row = gripper_size_row + index_of(gripper_size_row, '\n') + 1;

  u32 x = index_of(pallet_row, ',');

  model_params.pallet_width = (u32)atoi(pallet_row);
  model_params.pallet_height = (u32)atoi(pallet_row + x + 1);

  x = index_of(pallet_row, '\n');
  model_params.box_width = (u32) atoi(pallet_row + x + 1);

  const char* box_row = pallet_row  + x + 1;

  u32 box_height_idx = index_of(box_row, ',') + 1;
  model_params.box_height = (u32) atoi(box_row + box_height_idx);

}

static Box read_row(StringSlice slice) {
  u32 drop_place_x = (u32) parse_int(slice);

  u32 x = slice_index_of(slice, ',');
  StringSlice from_comma = slice_reslice(slice, x+1U);
  u32 drop_place_y = (u32) parse_int(from_comma);

  x = slice_index_of(slice, ' ');
  char r_char = slice_at(slice, x+1);

  Rotation r = V;
  if (r_char == 'h') {
     r = H;
  }

  Box box = {.x = drop_place_x, .y = drop_place_y, .r = r};
  return box;
}

static u32_tuple read_rows(StringSlice slice, Box* horizontal_boxes, Box* vertical_boxes) {
  assert(slice.inner != NULL);
  assert(slice.offset == 0);

  u32 n_h_boxes = 0;
  u32 n_v_boxes = 0;

  while(true)
  {
    if (slice_at(slice, 0) == '-') break;

    Box box = read_row(slice);
    if (box.r == H)
    {
      horizontal_boxes[n_h_boxes] = box;
      ++n_h_boxes;
    }
    else
    {
      vertical_boxes[n_v_boxes] = box;
      ++n_v_boxes;
    }

    usize next_row_idx = slice_index_of(slice, '\n');
    if (next_row_idx == USIZE_MAX)
    {
      fprintf(stderr, "something went wrong :)\n");
      u32_tuple z = {0};
      return z;
    }

    slice.offset += next_row_idx + 1;
  }

  u32_tuple n_boxes = {.x = n_h_boxes, .y = n_v_boxes};
  return n_boxes;
}

static int greater_than(const void* b1, const void* b2)
{
  const Box* box1 = (const Box*) b1;
  const Box* box2 = (const Box*) b2;

  u32 v1;
  u32 v2;
  if(box1->r == H)
  {
    v1 = box1->y * model_params.pallet_width + box1->x;
    v2 = box2->y * model_params.pallet_width + box2->x;
  }
  else
  {
    assert(box1->r == V);
    v1 = box1->x * model_params.pallet_height + box1->y;
    v2 = box2->x * model_params.pallet_height + box2->y;
  }

  return (int) (v1 - v2);
}

static u8 is_adjacent_right(const Box* b1, const Box* b2)
{
  return (b1->r == H && b1->r == H && b1->x+model_params.box_width == b2->x && b1->y == b2->y);
}

static u8 is_adjacent_below(const Box* b1, const Box* b2)
{
  return (b1->r == V && b1->r == V && b1->y+model_params.box_width == b2->y && b1->x == b2->x);
}


static u8 pair_with(const Box* left, const Box* right)
{
  if (right->r == H)
  {
    if (is_adjacent_right(left, right))
      return true;
  }
  else
  {
    if (is_adjacent_below(left, right))
      return true;
  }
  return false;
}

static void print_arr(u32* arr, u32 n)
{
  for (u32 i = 0; i < n; ++i)
  {
    printf("%u, ", arr[i]);
  }
  printf("\n");
}

static void print_boxes(const Box* boxes, u32 n)
{
  for (u32 i = 0; i < n; ++i)
  {
    println("(%u, %u), %u, ", boxes[i].x, boxes[i].y, boxes[i].r);
  }
  printf("\n");
}

static inline u32 compute_gripper_overflow(u32 size)
{
    return (u32)(ceil((model_params.gripper_size - size) / 2.0));
}

static void action_set_gripper_overflow(Action* action)
{
  const u32 gripper_size = model_params.gripper_size;

  switch (action->rotation)
  {
  case H:
  {
    u32 action_width = action->bbox.max[0] - action->bbox.min[0] + 1;
    action->gripper_overflow = (gripper_size > action_width) ?
          compute_gripper_overflow(action_width) : 0;
    break;
  }
  case V:
  {
    u32 action_height = action->bbox.max[1] - action->bbox.min[1] + 1;
    action->gripper_overflow = (gripper_size > action_height) ?
          compute_gripper_overflow(action_height) : 0;
    break;
  }
  default:
    UNREACHABLE;
  }
}

static FrozenVec group_moves(const Box* boxes, u32 n) {

  if (n == 0)
  {
    return DEFAULT_FROZEN_VEC;
  }

  const u32 max_picked_length = model_params.gripper_size + model_params.box_width;

  u32 action_id = 0;
  u32* box_mapped_to_action = (u32*)calloc(n, n * sizeof(u32));
  u32* n_boxes_mapped_to_action = (u32*)calloc(n, n * sizeof(u32));
  n_boxes_mapped_to_action[0] = 1;

  for (u32 i = 1; i < n; ++i)
  {
    const Box* current_box = &boxes[i];

    //TODO: add gripper size check
    u8 same_cluster = pair_with(&boxes[i-1], current_box);
    u32 previous_action_id = box_mapped_to_action[i-1]; //valid iff same_cluster
    const u32 action_length_if_added =
      n_boxes_mapped_to_action[previous_action_id] * model_params.box_width
        + model_params.box_width;

    if (same_cluster && action_length_if_added <= max_picked_length)
    {
      box_mapped_to_action[i] = previous_action_id;
      ++n_boxes_mapped_to_action[previous_action_id];
    }
    else
    {
      ++action_id;
      box_mapped_to_action[i] = action_id;
      n_boxes_mapped_to_action[action_id] = 1;
    }
  }

  const u32 n_actions = action_id + 1;
  Action* actions = (Action*) calloc(n_actions, n_actions * sizeof(Action));

  // generate actions from clusters
  for(u32 i = 0; i < n; ++i)
  {
    u32 action_idx = box_mapped_to_action[i];
    Action* current_action = &actions[action_idx];

    // initialize action
    if (current_action->n_boxes == 0)
    {
      u32 bbox_width = (boxes[i].r == H) ?
        (model_params.box_width) : (model_params.box_height);
      u32 bbox_height = (boxes[i].r == V) ?
        (model_params.box_width) : (model_params.box_height);

      u32 min_x = boxes[i].x;
      u32 min_y = boxes[i].y;
      u32 max_x = min_x + bbox_width - 1;
      u32 max_y = min_y + bbox_height - 1;

      AABB bbox = {
        .min = {min_x, min_y},
        .max = {max_x, max_y}
      };
      Action action =
      {
        .n_boxes = 1,
        .bbox = bbox,
        .rotation = boxes[i].r,
      };
      *current_action = action;
    }
    // action already initialized, just increase the box count,
    // meaning we are picking up more than one box at a time.
    else
    {
      if (current_action->rotation == H)
      {
        current_action->bbox.max[0] += model_params.box_width;
      }
      else
      {
        current_action->bbox.max[1] += model_params.box_width;
      }

      ++(current_action->n_boxes);
    }

  }

  for (u32 i = 0; i < n_actions; ++i)
  {
    action_set_gripper_overflow(&actions[i]);
  }

  FrozenVec actions_vec = {.inner = actions, .n = n_actions};
  return actions_vec;
}

static u8 action_fuzzy_intersect(const Action* a1, const Action* a2)
{
  if (a1->rotation == a2->rotation) return false;

  const u32 x_overflow = (a1->rotation == V) ? 0 : a1->gripper_overflow;
  const u32 y_overflow = (a1->rotation == H) ? 0 : a1->gripper_overflow;

  u8 is_left = a1->bbox.max[0] + x_overflow < a2->bbox.min[0];
  u8 is_right = a1->bbox.min[0] - x_overflow > a2->bbox.max[0];
  u8 is_above = a1->bbox.max[1] + y_overflow < a2->bbox.min[1];
  u8 is_below = a1->bbox.min[1] - y_overflow > a2->bbox.max[1];

  return !(is_left || is_right || is_above || is_below);
}

static u8 aabb_collide(const AABB* bbox1, const AABB* bbox2)
{
  u8 is_left  = bbox1->max[0] < bbox2->min[0];
  u8 is_right = bbox1->min[0] > bbox2->max[0];
  u8 is_above = bbox1->max[1] < bbox2->min[1];
  u8 is_below = bbox1->min[1] > bbox2->max[1];

  return !(is_left || is_right || is_above || is_below);
}


static void dump_aabb(const AABB* aabb)
{
  println("[(%u, %u), (%u, %u)]", aabb->min[0], aabb->min[1], aabb->max[0], aabb->max[1]);
}

// static void dump_actions_debug(FrozenVec actions, const char* orientation)
// {
//   const Action* inner = (const Action*) actions.inner;
//   for(u32 i = 0; i < actions.n; ++i)
//   {
//     fprintf(stderr, "\tpicking up %u boxes with gripper overflow: %u \n",
//             inner[i].n_boxes, inner[i].gripper_overflow);
//     dump_aabb(&(inner[i].bbox));
//   }
//   fprintf(stderr, "]\n");
// }

static void dump_actions_dzn(FrozenVec actions)
{

  FILE *f = fopen("pallet_input.dzn", "w");
  if (f == NULL)
  {
      printf("error opening file.\n");
      exit(1);
  }

  const Action* inner = (const Action*) actions.inner;
  const u32 n = actions.n;

  fprintf(f, "GRIPPER_SIZE = %u;\n", model_params.gripper_size);

  fprintf(f, "PALLET_WIDTH = %u;\n", model_params.pallet_width);
  fprintf(f, "PALLET_HEIGHT = %u;\n", model_params.pallet_height);

  fprintf(f, "LOCAL_X_ITEM_SIZE = %u;\n", model_params.box_width);
  fprintf(f, "LOCAL_Y_ITEM_SIZE = %u;\n", model_params.box_height);

  fprintf(f, "N_BOXES = %u;\n", model_params.n_boxes);
  fprintf(f, "BOXES = 0..N_BOXES;\n");
  fprintf(f, "N_MAX_AVAILABLE_BOXES = %u;\n", model_params.max_available_boxes);
  fprintf(f, "N_ACTIONS = %u;\n", n);
  fprintf(f, "ACTIONS = 1..N_ACTIONS;\n");
  fprintf(f, "ACTIONS_WITH_DEFAULT = 0..N_ACTIONS;\n");

  fprintf(f, "MAX_TIME = %u;\n", model_params.timesteps);
  fprintf(f, "TIME = 1..MAX_TIME;\n");


  fprintf(f, "actions_num_boxes = array1d(ACTIONS_WITH_DEFAULT, [\n\t");
  fprintf(f, "0,");
  for(u32 i = 0; i < n - 1; ++i)
  {
    fprintf(f, "%u,", inner[i].n_boxes);
  }
  fprintf(f, "%u", inner[n-1].n_boxes);
  fprintf(f, "\n]);\n");

  fprintf(f, "actions_gripper_overflow = array1d(ACTIONS, [\n\t");
  for(u32 i = 0; i < n - 1; ++i)
  {
    fprintf(f, "%u,", inner[i].gripper_overflow);
  }
  fprintf(f, "%u", inner[n-1].gripper_overflow);
  fprintf(f, "\n]);\n");

  //dump rotation
  fprintf(f, "actions_orientation = array1d(ACTIONS, [\n\t");
  for(u32 i = 0; i < n - 1; ++i)
  {
    fprintf(f, "%u,", inner[i].rotation);
  }
  fprintf(f, "%u", inner[n-1].rotation);
  fprintf(f, "\n]);\n");

  // dump bbox min x
  fprintf(f, "actions_bbox_min_x = array1d(ACTIONS, [\n\t");
  for(u32 i = 0; i < n - 1; ++i)
  {
    fprintf(f, "%u,", inner[i].bbox.min[0]);
  }
  fprintf(f, "%u", inner[n-1].bbox.min[0]);
  fprintf(f, "\n]);\n");

  //dump bbox min y
  fprintf(f, "actions_bbox_min_y = array1d(ACTIONS, [\n\t");
  for(u32 i = 0; i < n - 1; ++i)
  {
    fprintf(f, "%u,", inner[i].bbox.min[1]);
  }
  fprintf(f, "%u", inner[n-1].bbox.min[1]);
  fprintf(f, "\n]);\n");

  //dump bbox max x
  fprintf(f, "actions_bbox_max_x = array1d(ACTIONS, [\n\t");
  for(u32 i = 0; i < n - 1; ++i)
  {
    fprintf(f, "%u,", inner[i].bbox.max[0]);
  }
  fprintf(f, "%u", inner[n-1].bbox.max[0]);
  fprintf(f, "\n]);\n");

  //dump bbox max y
  fprintf(f, "actions_bbox_max_y = array1d(ACTIONS, [\n\t");
  for(u32 i = 0; i < n - 1; ++i)
  {
    fprintf(f, "%u,", inner[i].bbox.max[1]);
  }
  fprintf(f, "%u", inner[n-1].bbox.max[1]);
  fprintf(f, "\n]);\n");


  //dump aabb width (for global constraint diffn)
  fprintf(f, "actions_width = array1d(ACTIONS, [\n\t");
  for(u32 i = 0; i < n - 1; ++i)
  {
    fprintf(f, "%u,", inner[i].bbox.max[0] - inner[i].bbox.min[0] + 1);
  }
  fprintf(f, "%u", inner[n-1].bbox.max[0] - inner[n-1].bbox.min[0] + 1);
  fprintf(f, "\n]);\n");

  //dump aabb height (for global constraint diffn)
  fprintf(f, "actions_height = array1d(ACTIONS, [\n\t");
  for(u32 i = 0; i < n - 1; ++i)
  {
    fprintf(f, "%u,", inner[i].bbox.max[1] - inner[i].bbox.min[1] + 1);
  }
  fprintf(f, "%u", inner[n-1].bbox.max[1] - inner[n-1].bbox.min[1] + 1);
  fprintf(f, "\n]);\n");

  //dump action clusters (symmetry breaking)
  // fprintf(f, "map_id_to_cluster = array1d(ACTIONS, [\n\t");
  // for(u32 i = 0; i < n - 1; ++i)
  // {
  //   fprintf(f, "%u,", inner[i].mapped_to_cluster);
  // }
  // fprintf(f, "%u", inner[n-1].mapped_to_cluster);
  // fprintf(f, "\n]);\n");

  fclose(f);
}


typedef struct
{
  u32 i;
  u32 j;
} ExtraConstraint;

static ExtraConstraint gen_constraint(u32 action_1, u32 action_2)
{
  ExtraConstraint c =
  {
    .i = action_1,
    .j = action_2,
  };
  return c;
}

static FrozenVec gen_additional_constraints(const FrozenVec* actions)
{
  const Action* inner_actions = (Action*)actions->inner;

  ExtraConstraint* extra_constraints = (ExtraConstraint*)
    calloc(actions->n, actions->n * sizeof(ExtraConstraint));
  u32 n_extra_constraints = 0;

  for (u32 i = 0; i < actions->n; ++i)
  {
    for (u32 j = 0; j < actions->n; ++j)
    {
      if (i == j) continue;

      const Action* a1 = &inner_actions[i];
      const Action* a2 = &inner_actions[j];

      if (action_fuzzy_intersect(a1, a2))
      {
        ExtraConstraint extra = gen_constraint(i + 1, j + 1);
        extra_constraints[n_extra_constraints] = extra;
        ++n_extra_constraints;
      }
    }
  }

  FrozenVec f =
  {
    .inner = extra_constraints,
    .n = n_extra_constraints,
  };

  return f;
}

static u8 dump_additional_constraints(const FrozenVec* extra_constraints)
{
  const u32 n = extra_constraints->n;
  const ExtraConstraint* constraints = (const ExtraConstraint*)
    extra_constraints->inner;

  FILE* mzn_file = fopen("tmp.mzn", "a");
  if (mzn_file == NULL)
  {
    fprintf(stderr, "couldn't open tmp.mzn file");
    return false;
  }

  for (u32 i = 0; i < n; ++i) {
    const ExtraConstraint extra_constraint = constraints[i];
    fprintf(mzn_file, CONSTRAINT_FORMAT, extra_constraint.i, extra_constraint.j);
  }

  fclose(mzn_file);
  return true;
}


FrozenVec gen_actions(u8 with_extra_constraints) {
  (void) read_file();

  parse_size();

  //skip to first char of first row
  usize offset = index_of(buffer, '-') + 2;
  StringSlice body = {.inner = (buffer + offset), .offset = 0};

  Box horizontal_boxes[100] = {0};
  Box vertical_boxes[100] = {0};

  u32_tuple read_boxes =
    read_rows(body, horizontal_boxes, vertical_boxes);
  u32 n_h_boxes = read_boxes.x;
  u32 n_v_boxes = read_boxes.y;

  model_params.n_boxes = n_h_boxes + n_v_boxes;

  qsort(horizontal_boxes, n_h_boxes, sizeof(Box), greater_than);
  qsort(vertical_boxes, n_v_boxes, sizeof(Box), greater_than);

  FrozenVec h_actions_vec = group_moves(horizontal_boxes, n_h_boxes);
  // dump_actions_debug(h_actions_vec, "horizontal");

  FrozenVec v_actions_vec = group_moves(vertical_boxes, n_v_boxes);
  // dump_actions_debug(v_actions_vec, "vertical");

  //copy all actions into a single vector
  Action* full_actions = (Action*)
    calloc(h_actions_vec.n + v_actions_vec.n,
           (h_actions_vec.n + v_actions_vec.n) * sizeof(Action));

  memcpy(full_actions, (Action*)h_actions_vec.inner,
         h_actions_vec.n * sizeof(Action));

  memcpy(full_actions + h_actions_vec.n,
         (Action*)v_actions_vec.inner, v_actions_vec.n * sizeof(Action));


  FrozenVec full_actions_vec = {full_actions, h_actions_vec.n + v_actions_vec.n};
  // dump_actions_debug(full_actions_vec, "total");

  dump_actions_dzn(full_actions_vec);

  if (with_extra_constraints)
  {
    fprintf(stderr, "generating extra constraints\n");
    FrozenVec extra_constraints = gen_additional_constraints(&full_actions_vec);
    u8 ok = dump_additional_constraints(&extra_constraints);
    if (!ok)
    {
      fprintf(stderr, "couldn't append any extra constraint to tmp.mzn file");
    }
    frozenvec_dealloc(extra_constraints);
  }

  free(buffer);
  free(h_actions_vec.inner);
  free(v_actions_vec.inner);

  return full_actions_vec;
}

ModelParams get_model_params(void)
{
  return model_params;
}

// EOF
