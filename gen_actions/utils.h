#pragma once

#include <inttypes.h>

#define false 0
#define true 1

#define i64 int64_t
#define i32 int32_t
#define usize size_t
#define u32 uint32_t
#define u8 uint8_t

#define USIZE_MAX (((usize)0) - 1U)
#define U32_MAX (((u32)0) - 1U)

#define println(s...) printf(s); printf("\n")

// "constraint forall(t1, t2 in ACTIONS)(action_id[t1] == %u /\\ action_id[t2] == %u -> t1 < t2);\n"
#define CONSTRAINT_FORMAT \
"constraint action_time[%u] < action_time[%u];\n"


#define UNREACHABLE assert(false)

#define Tuple(type) \
typedef struct { \
  type x; \
  type y; \
} type##_tuple

typedef struct {
  void* inner;
  u32 n;
} FrozenVec;

typedef enum Rotation {
  H = 0,
  V,
} Rotation;

typedef struct Box {
  u32 x;
  u32 y;
  Rotation r;
} Box;

typedef struct AABB {
  u32 min[2];
  u32 max[2];
} AABB;

typedef struct Action {
  u32 n_boxes;
  AABB bbox;
  Rotation rotation;
  u32 mapped_to_cluster; //for symmetry breaking (unused right now)
  u32 gripper_overflow;
} Action;


typedef struct StringSlice {
  char* inner;
  u32 offset;
} StringSlice;

typedef Box* BoxPtr;

Tuple(u32);
Tuple(BoxPtr);
Tuple(FrozenVec);

void frozenvec_dealloc(FrozenVec f);


