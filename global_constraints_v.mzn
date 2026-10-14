
include "globals.mzn";

% input vars

int: PALLET_WIDTH;
int: PALLET_HEIGHT;
set of int: GRID_SIZE_X = 1..PALLET_WIDTH;
set of int: GRID_SIZE_Y = 1..PALLET_HEIGHT;

int: GRIPPER_SIZE;

int: LOCAL_X_ITEM_SIZE;
int: LOCAL_Y_ITEM_SIZE;

int: N_BOXES;
set of int: BOXES;
int: N_ACTIONS;
set of int: ACTIONS;
int: MAX_TIME;
set of int: TIME;

set of int: ACTIONS_WITH_DEFAULT;

int: N_MAX_AVAILABLE_BOXES;
set of int: MAX_AVAILABLE_BOXES = 0..N_MAX_AVAILABLE_BOXES;

array[ACTIONS_WITH_DEFAULT] of int: actions_num_boxes;
array[ACTIONS] of int: actions_orientation;
array[ACTIONS] of int: actions_gripper_overflow;

% bounding boxes
array[ACTIONS] of int: actions_bbox_min_x;
array[ACTIONS] of int: actions_bbox_min_y;
array[ACTIONS] of int: actions_bbox_max_x;
array[ACTIONS] of int: actions_bbox_max_y;

array[ACTIONS] of GRID_SIZE_X: actions_width;
array[ACTIONS] of GRID_SIZE_Y: actions_height;


set of int: GRIPPER_OVERFLOW = 0..GRIPPER_SIZE - 1;




% GRIPPER_SIZE = 2;
% PALLET_WIDTH = 9;
% PALLET_HEIGHT = 9;
% LOCAL_X_ITEM_SIZE = 2;
% LOCAL_Y_ITEM_SIZE = 1;
% N_BOXES = 30;
% BOXES = 0..N_BOXES;
% N_MAX_AVAILABLE_BOXES = 6;
% N_ACTIONS = 23;
% ACTIONS = 1..N_ACTIONS;
% ACTIONS_WITH_DEFAULT = 0..N_ACTIONS;
% MAX_TIME = 25;
% TIME = 1..MAX_TIME;
% actions_num_boxes = array1d(ACTIONS_WITH_DEFAULT, [
% 	0,2,1,2,1,2,1,2,1,2,1,1,1,1,2,1,1,1,1,1,1,1,2,1
% ]);
% actions_gripper_overflow = array1d(ACTIONS, [
% 	0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
% ]);
% actions_orientation = array1d(ACTIONS, [
% 	0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,1,1,1
% ]);
% actions_bbox_min_x = array1d(ACTIONS, [
% 	1,7,6,7,1,8,2,8,1,7,2,8,2,5,3,6,1,1,3,4,5,6,9
% ]);
% actions_bbox_min_y = array1d(ACTIONS, [
% 	1,1,2,3,4,4,5,5,6,6,7,7,8,8,9,9,2,7,2,7,2,4,8
% ]);
% actions_bbox_max_x = array1d(ACTIONS, [
% 	4,8,9,8,4,9,5,9,4,8,3,9,3,8,4,7,1,1,3,4,5,6,9
% ]);
% actions_bbox_max_y = array1d(ACTIONS, [
% 	1,1,2,3,4,4,5,5,6,6,7,7,8,8,9,9,3,8,3,8,3,7,9
% ]);
% actions_width = array1d(ACTIONS, [
% 	4,2,4,2,4,2,4,2,4,2,2,2,2,4,2,2,1,1,1,1,1,1,1
% ]);
% actions_height = array1d(ACTIONS, [
% 	1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,2,2,2,2,2,4,2
% ]);


% which side does the gripper open up wrt to the world?
% We can rotate the object in order to avoid collisions
% and to also fulfill the position requirements.
enum orientation = { TOP, RIGHT, BOT, LEFT };

set of int: ALLOWED_Y_DROP = GRID_SIZE_Y;
set of int: ALLOWED_X_DROP = GRID_SIZE_X;


int: MIN_DIM = min(LOCAL_X_ITEM_SIZE, LOCAL_Y_ITEM_SIZE);
int: MAX_DIM = max(LOCAL_X_ITEM_SIZE, LOCAL_Y_ITEM_SIZE);


array[TIME] of var BOXES: n_boxes_waiting;
array[TIME] of var MAX_AVAILABLE_BOXES: n_available_boxes;

array[TIME] of var bool: active_move;
array[TIME] of var ACTIONS_WITH_DEFAULT: action_id;
array[ACTIONS] of var TIME: action_time;
array[ACTIONS] of var orientation: action_rotation;


constraint n_available_boxes[1] = min(N_MAX_AVAILABLE_BOXES, N_BOXES);
constraint n_boxes_waiting[1] = N_BOXES - n_available_boxes[1];

constraint forall(t in TIME) (n_available_boxes[t] <= N_MAX_AVAILABLE_BOXES);

constraint all_different_except_0(action_id);

% link the two models together
constraint forall(action in ACTIONS) (
  action_id[ action_time[action] ] = action
);
% constraint inverse(action_time, action_id);
constraint forall(t in TIME) (
  active_move[t] == false -> action_id[t] = 0
);
constraint forall(t in TIME) (
  active_move[t] == true -> action_id[t] != 0
);


% if an action has time t, then time t should be an "active_move"
constraint forall(action in ACTIONS) (
  active_move[ action_time[action] ] = true
);


% action `a` can only be executed when there are enough available boxes
constraint forall(action in ACTIONS) (
  n_available_boxes[ action_time[action] ] >= actions_num_boxes[action]
);

% number of boxes at time `t+1` is equal to the number of boxes at `t` - <number of boxes used by action at time `t`> + 1.
% +1 because one box arrives at each time `t'`.
constraint forall(t in 2..MAX_TIME) (
  let {
    var BOXES: requested_boxes = actions_num_boxes[action_id[t-1]];
  } in
    n_available_boxes[t] = n_available_boxes[t-1] - requested_boxes + min(n_boxes_waiting[t-1], 1)
);


constraint forall(t in 2..MAX_TIME) (
  n_boxes_waiting[t] = max(n_boxes_waiting[t-1] - 1, 0)
);



constraint all_different(action_time);

constraint forall(action in ACTIONS) (
  if (actions_orientation[action] == 0) then
    action_rotation[action] = TOP \/ action_rotation[action] = BOT
  else
    action_rotation[action] = RIGHT \/ action_rotation[action] = LEFT
  endif
);




predicate no_boxes_above_global(var ACTIONS: current_action, var TIME: t, var GRIPPER_OVERFLOW: extend_by) =
  let {
    var GRID_SIZE_X: origin_x = actions_bbox_min_x[current_action];
    var GRID_SIZE_Y: origin_y = max(1, actions_bbox_min_y[current_action] - extend_by);
    var GRID_SIZE_X: size_x = actions_width[current_action];

    var GRID_SIZE_Y: max_y = actions_bbox_max_y[current_action];
    var GRID_SIZE_Y: size_y = max_y - origin_y + 1;

  } in

  forall(other_action in ACTIONS) (
    (action_time[other_action] < t) ->
      diffn([origin_x, actions_bbox_min_x[other_action]], [origin_y, actions_bbox_min_y[other_action]], [size_x, actions_width[other_action]], [size_y, actions_height[other_action]])
  )
;

predicate no_boxes_below_global(var ACTIONS: current_action, var TIME: t, var GRIPPER_OVERFLOW: extend_by) =
  let {
    var GRID_SIZE_X: origin_x = actions_bbox_min_x[current_action];
    var GRID_SIZE_Y: origin_y = actions_bbox_min_y[current_action];
    var GRID_SIZE_X: size_x = actions_width[current_action];
    
    var GRID_SIZE_Y: max_y = min(PALLET_HEIGHT, actions_bbox_max_y[current_action] + extend_by);
    var GRID_SIZE_Y: size_y = max_y - origin_y + 1;
    
  } in

  forall(other_action in ACTIONS) (
    (action_time[other_action] < t) ->
      diffn([origin_x, actions_bbox_min_x[other_action]], [origin_y, actions_bbox_min_y[other_action]], [size_x, actions_width[other_action]], [size_y, actions_height[other_action]])
    )
;

predicate no_boxes_right_global(var ACTIONS: current_action, var TIME: t, var GRIPPER_OVERFLOW: extend_by) =
  let {
    var GRID_SIZE_X: origin_x = actions_bbox_min_x[current_action];
    var GRID_SIZE_Y: origin_y = actions_bbox_min_y[current_action];
    var GRID_SIZE_Y: size_y = actions_height[current_action];
    
    var GRID_SIZE_Y: max_x = min(PALLET_WIDTH, actions_bbox_max_x[current_action] + extend_by);
    var GRID_SIZE_Y: size_x = max_x - origin_x + 1;
    
  } in

  forall(other_action in ACTIONS) (
    (action_time[other_action] < t) ->
      diffn([origin_x, actions_bbox_min_x[other_action]], [origin_y, actions_bbox_min_y[other_action]], [size_x, actions_width[other_action]], [size_y, actions_height[other_action]])
    )
;

predicate no_boxes_left_global(var ACTIONS: current_action, var TIME: t, var GRIPPER_OVERFLOW: extend_by) =
  let {
    var GRID_SIZE_X: origin_x = max(1, actions_bbox_min_x[current_action] - 1);
    var GRID_SIZE_Y: origin_y = actions_bbox_min_y[current_action];
    var GRID_SIZE_Y: size_y = actions_height[current_action];
    
    var GRID_SIZE_Y: max_x = actions_bbox_max_x[current_action];
    var GRID_SIZE_Y: size_x = max_x - origin_x + 1;
    
  } in

  forall(other_action in ACTIONS) (
    (action_time[other_action] < t) ->
      diffn([origin_x, actions_bbox_min_x[other_action]], [origin_y, actions_bbox_min_y[other_action]], [size_x, actions_width[other_action]], [size_y, actions_height[other_action]])
    )
;


constraint forall(action in ACTIONS) (

  let {
    var TIME: t = action_time[action];
  } in

  if action_rotation[action] == TOP then
    no_boxes_above_global(action, t, 1)

  elseif action_rotation[action] == RIGHT then
    no_boxes_right_global(action, t, 1)

  elseif action_rotation[action] == LEFT then
    no_boxes_left_global(action, t, 1)

  else
    no_boxes_below_global(action, t, 1)

  endif
);



% gripper "overflow" doesn't collide with any boxes
constraint forall(action in ACTIONS) (

  if action_rotation[action] == TOP \/ action_rotation[action] == BOT then
    let {
      var TIME: t = action_time[action];
      var GRID_SIZE_X: left_lower_bound_x =
        max(actions_bbox_min_x[action] - actions_gripper_overflow[action], 1);
      var GRID_SIZE_X: right_upper_bound_x =
        min(actions_bbox_max_x[action] + actions_gripper_overflow[action], PALLET_WIDTH);
    } in

    no_boxes_left_global(action, t, actions_gripper_overflow[action])
    /\
    no_boxes_right_global(action, t, actions_gripper_overflow[action])


  elseif action_rotation[action] == LEFT \/ action_rotation[action] == RIGHT then
    let {
      var TIME: t = action_time[action];
      var GRID_SIZE_Y: above_lower_bound_y =
        max(actions_bbox_min_y[action] - actions_gripper_overflow[action], 1);
      var GRID_SIZE_Y: below_upper_bound_y =
        min(actions_bbox_max_y[action] + actions_gripper_overflow[action], PALLET_HEIGHT);
    } in

    no_boxes_above_global(action, t, actions_gripper_overflow[action])
    /\
    no_boxes_below_global(action, t, actions_gripper_overflow[action])

  endif

);


% first action has orientation TOP or RIGHT (remove symmetries that start with BOT or LEFT)
constraint action_rotation[action_id[1]] = TOP \/ action_rotation[action_id[1]] = RIGHT;


constraint forall(action in ACTIONS) (
  let {
    var TIME: t = action_time[action];
  } in
  (action_rotation[action] == LEFT -> not no_boxes_right_global(action, t, 1))
  /\
  (action_rotation[action] == BOT  -> not no_boxes_above_global(action, t, 1))
);



% predicate is_executable(var ACTIONS: action, var TIME: t) =
%   n_available_boxes[t] >= actions_num_boxes[action]
% ;

% constraint forall(t in TIME) (
%   (active_move[t] == false) ->
%   forall(a in ACTIONS where action_time[a] > t) (
%       not is_executable(a, t)
%   )
% );



% symmetries: padding moves at the end when there are surely no boxes left
constraint (
  N_BOXES < MAX_TIME ->
    let {
      var TIME: time_empty_queue = N_BOXES + 1;
    } in
    sum([bool2int(active_move[t]) | t in time_empty_queue..MAX_TIME]) = 0
);


% symmetries: no padding moves when "available queue" is full (an action can always be done when the queue is full)
constraint forall(t in TIME) (
  n_available_boxes[t] == N_MAX_AVAILABLE_BOXES ->
    active_move[t] == true
);



solve :: int_search(action_time,
                    input_order,
                    indomain_min
                    ) satisfy;

output
       [ "action time(\(action)) = \(action_time[action])\n" | action in ACTIONS] ++ ["\n\n"] ++
       [ "drop rotation(action=\(action)) = \(action_rotation[action])\n" | action in ACTIONS] ++ ["\n"] ++
       [ "active_move(\(t)) = \(active_move[t])\n" | t in TIME] ++ ["\n\n"] ++
       [ "action_id(\(t)) = \(action_id[t])\n" | t in TIME] ++ ["\n\n"] ++
       [ "num_boxes_available(time=\(t)) = \(n_available_boxes[t])\n" | t in TIME] ++ ["\n"] ++
       [ "n boxes in queue(time=\(t)) = \(n_boxes_waiting[t])\n" | t in TIME] ++ ["\n"] ++
       [ "n requested boxes (time=\(t)) = \(actions_num_boxes[action_id[t]])\n" | t in TIME] ++ ["\n"]
;

