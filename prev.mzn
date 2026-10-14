include "globals.mzn";

% input vars

int: PALLET_WIDTH;
int: PALLET_HEIGHT;
set of int: GRID_SIZE_X = 1..PALLET_WIDTH;
set of int: GRID_SIZE_Y = 1..PALLET_HEIGHT;

int: GRIPPER_SIZE;
int: GRIPPER_OVERFLOW;

constraint trace("GRIPPER_OVERFLOW: " ++ show(GRIPPER_OVERFLOW) ++ "\n");


int: LOCAL_X_ITEM_SIZE;
int: LOCAL_Y_ITEM_SIZE;

int: N_BOXES;
set of int: BOXES;
int: N_ACTIONS;
set of int: ACTIONS;


array[ACTIONS] of int: actions_orientation;

% bounding boxes
array[ACTIONS] of int: actions_bbox_min_x;
array[ACTIONS] of int: actions_bbox_min_y;
array[ACTIONS] of int: actions_bbox_max_x;
array[ACTIONS] of int: actions_bbox_max_y;

%array[GRID_SIZE_Y, GRID_SIZE_X] of int: input_positions;
% [
% 1,1,1,1,
% 1,1,1,1,
% 1,0,0,1,
% 1,0,0,0,
% 1,1,1,1
% ]);

% 1,1,1,1,1,
% 1,1,1,1,1,
% 1,1,0,1,1,
% 1,1,1,1,1,
% 1,1,1,1,1


% 1,1,1,1,
% 1,1,1,1,
% 1,0,0,1,
% 1,0,0,0,
% 1,0,0,0

% 1,1,1,1,
% 1,1,1,1,
% 1,0,0,1,
% 1,1,1,1,
% 1,0,0,0

% 1,1,1,1,
% 1,1,1,1,
% 1,0,0,1,
% 1,1,1,1,
% 1,1,1,1


% int: LAST_TIMESTEP = N_ACTIONS;
% set of int: TIMESTEPS = 1..LAST_TIMESTEP;

% which side does the gripper open up wrt to the world?
% the gripper always picks up objects by having it's "opening side" on the right,
% but we can rotate the object in order to avoid collisions
% and to also fulfill the position requirements.
enum orientation = { TOP, RIGHT, BOT, LEFT };

set of int: ALLOWED_Y_DROP = GRID_SIZE_Y;
set of int: ALLOWED_X_DROP = GRID_SIZE_X;


int: MIN_DIM = min(LOCAL_X_ITEM_SIZE, LOCAL_Y_ITEM_SIZE);
int: MAX_DIM = max(LOCAL_X_ITEM_SIZE, LOCAL_Y_ITEM_SIZE);


array[ACTIONS] of var bool: active_move;
array[ACTIONS] of var ACTIONS: action_id;
array[ACTIONS] of var orientation: action_rotation;



constraint all_different(action_id);

constraint forall(t in ACTIONS) (
  if (actions_orientation[action_id[t]] == 0) then
    action_rotation[t] = TOP \/ action_rotation[t] = BOT
  else
    action_rotation[t] = RIGHT \/ action_rotation[t] = LEFT
  endif
);


predicate no_boxes_above(var ACTIONS: t, var GRID_SIZE_Y: start_y) =
  let {
    var GRID_SIZE_X: check_end_x = actions_bbox_max_x[action_id[t]];
    var GRID_SIZE_Y: check_end_y = actions_bbox_min_y[action_id[t]];
  } in

  forall(t2 in 1..t-1) (
    (actions_bbox_max_y[action_id[t2]] >= start_y /\ actions_bbox_max_y[action_id[t2]] < check_end_y) ->
      (
        actions_bbox_max_x[action_id[t2]] < actions_bbox_min_x[action_id[t]]
        \/
        actions_bbox_min_x[action_id[t2]] > check_end_x
      )
  )
;

% TODO: al controllo sull' asse va aggiunto il gripper overflow (ocio che x - overflow puo' essere < 1, max)
predicate no_boxes_right(var ACTIONS: t, var GRID_SIZE_X: end_x) =
  true
  /\
  let {
    var GRID_SIZE_X: check_start_x = actions_bbox_max_x[action_id[t]];
    var GRID_SIZE_Y: check_end_y = actions_bbox_max_y[action_id[t]];
  } in

  forall(t2 in 1..t-1) (
    (actions_bbox_min_x[action_id[t2]] > check_start_x /\ actions_bbox_min_x[action_id[t2]] <= end_x) ->
      (
        actions_bbox_max_y[action_id[t2]] < actions_bbox_min_y[action_id[t]]
        \/
        actions_bbox_min_y[action_id[t2]] > check_end_y
      )
  )
;

% TODO: al controllo sull' asse va aggiunto il gripper overflow (ocio che x - overflow puo' essere < 1, max)
predicate no_boxes_left(var ACTIONS: t, var GRID_SIZE_X: start_x) =
  true
  /\
  let {
    var GRID_SIZE_X: check_end_x = actions_bbox_min_x[action_id[t]];
    var GRID_SIZE_Y: check_end_y = actions_bbox_max_y[action_id[t]];
  } in
  
  forall(t2 in 1..t-1) (
    (actions_bbox_max_x[action_id[t2]] >= start_x /\ actions_bbox_max_x[action_id[t2]] < check_end_x) ->
      (
        actions_bbox_max_y[action_id[t2]] < actions_bbox_min_y[action_id[t]]
        \/
        actions_bbox_min_y[action_id[t2]] > check_end_y
      )
  )
;


% TODO: al controllo sull' asse va aggiunto il gripper overflow (ocio che x - overflow puo' essere < 1, max)
predicate no_boxes_below(var ACTIONS: t, var GRID_SIZE_Y: end_y) =
  true
  /\
  let {
    var GRID_SIZE_X: check_end_x = actions_bbox_max_x[action_id[t]];
    var GRID_SIZE_X: check_start_x = actions_bbox_min_x[action_id[t]];
    var GRID_SIZE_Y: check_start_y = actions_bbox_max_y[action_id[t]];
  } in
  
  forall(t2 in 1..t-1) (
    (actions_bbox_min_y[action_id[t2]] > check_start_y /\ actions_bbox_min_y[action_id[t2]] <= end_y) ->
      (
        actions_bbox_max_x[action_id[t2]] < check_start_x
        \/
        actions_bbox_min_x[action_id[t2]] > check_end_x
      )
  )
;

constraint forall(t in ACTIONS) (
  true
  /\
  
  if action_rotation[t] == TOP then
    true
    /\
    no_boxes_above(t, max(1,actions_bbox_min_y[action_id[t]] - 1))

  elseif action_rotation[t] == RIGHT then
    no_boxes_right(t, min(PALLET_WIDTH,actions_bbox_max_x[action_id[t]] + 1))

  elseif action_rotation[t] == LEFT then
    no_boxes_left(t, max(1,actions_bbox_min_x[action_id[t]] - 1))

  else
    no_boxes_below(t, min(PALLET_HEIGHT,actions_bbox_max_y[action_id[t]] + 1))

  endif
);



% gripper "overflow" doesn't collide with any boxes
constraint forall(t in ACTIONS) (

  if action_rotation[t] == TOP \/ action_rotation[t] == BOT then
    let {
      var GRID_SIZE_X: left_lower_bound_x = max(actions_bbox_min_x[action_id[t]] - GRIPPER_OVERFLOW, 1);
      var GRID_SIZE_X: right_upper_bound_x = min(actions_bbox_max_x[action_id[t]] + GRIPPER_OVERFLOW, PALLET_WIDTH);
    } in

    no_boxes_left(t, left_lower_bound_x)
    /\
    no_boxes_right(t, right_upper_bound_x)

  
  elseif action_rotation[t] == LEFT \/ action_rotation[t] == RIGHT then
    let {
      var GRID_SIZE_Y: above_lower_bound_y = max(actions_bbox_min_y[action_id[t]] - GRIPPER_OVERFLOW, 1);
      var GRID_SIZE_Y: below_upper_bound_y = min(actions_bbox_max_y[action_id[t]] + GRIPPER_OVERFLOW, PALLET_HEIGHT);
    } in

    no_boxes_above(t, above_lower_bound_y)
    /\
    no_boxes_below(t, below_upper_bound_y)
  
  endif
  
);


constraint forall(t in ACTIONS) (
  (action_rotation[t] == LEFT -> not no_boxes_right(t, actions_bbox_max_x[action_id[t]] + 1))
  /\
  (action_rotation[t] == BOT  -> not no_boxes_above(t, actions_bbox_min_y[action_id[t]] - 1))
);


% this doesn't work with -O4
% constraint strictly_increasing([x | x in action_id where actions_orientation[x] == 0]);

% constraint forall(t1, t2 in ACTIONS where t1 < t2) (
%     (actions_orientation[action_id[t1]] == 0 /\ actions_orientation[action_id[t2]] == 0)
%     ->
%     action_id[t1] < action_id[t2]
% );

% constraint forall(t1, t2 in ACTIONS where t1 < t2) (
%     (actions_orientation[action_id[t1]] == 1 /\ actions_orientation[action_id[t2]] == 1)
%     ->
%     action_id[t1] < action_id[t2]
% );

solve :: int_search(action_id++enum2int(action_rotation),
                    input_order,
                    indomain_min
                    ) satisfy;


output
       [ "action id(\(t)) = \(action_id[t])\n" | t in ACTIONS] ++ ["\n\n"] ++
       [ "drop rotation(\(action_id[t])) = \(action_rotation[t])\n" | t in ACTIONS] ++ ["\n"]
;

% output
%        [ "drop place(\(t)) = (\(drop_place_x[t]), \(drop_place_y[t]))\n" | t in TIMESTEPS] ++ ["\n\n"] ++
%        [ "drop orientation(\(t)), width and height = (\(drop_r[t]), \(picked_item_width[t]), \(picked_item_height[t]))\n" | t in TIMESTEPS] ++ ["\n"] ++
% %        [ "\npicked_item(\(t)) = \(picked_item[t]);" | t in TIMESTEPS] ++ ["\n\n"] ++
% %        [ "\ninput_belt(\(t)) = \(input_belt[t]);\n" | t in 0..LAST_TIMESTEP] ++ ["\n\n"] ++
%        [ "\(pallet_state[t,i,j])" ++ if j + i == side_x + side_y then "\npallet_state(\(t))\n\n" else if j == side_x then "\n" else " " endif endif| t in 0..LAST_TIMESTEP, i in GRID_SIZE_Y, j in GRID_SIZE_X ];



