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





% which side does the gripper open up wrt to the world?
% the gripper always picks up objects by having it's "opening side" on the right,
% but we can rotate the object in order to avoid collisions
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


predicate no_boxes_above(var ACTIONS: current_action, var TIME: t, var GRID_SIZE_Y: start_y, var GRID_SIZE_X: start_x, var GRID_SIZE_X: end_x) =
  let {
    var GRID_SIZE_Y: check_end_y = actions_bbox_min_y[current_action];
  } in

  forall(other_action in ACTIONS) (
    (action_time[other_action] < t /\ actions_bbox_max_y[other_action] >= start_y /\ actions_bbox_max_y[other_action] < check_end_y) ->
      (
        actions_bbox_max_x[other_action] < start_x
        \/
        actions_bbox_min_x[other_action] > end_x
      )
    )
;

predicate no_boxes_right(var ACTIONS: current_action, var TIME: t, var GRID_SIZE_X: end_x, var GRID_SIZE_Y: start_y, var GRID_SIZE_Y: end_y) =
  let {
    var GRID_SIZE_X: check_start_x = actions_bbox_max_x[current_action];
  } in

  forall(other_action in ACTIONS) (
    (action_time[other_action] < t /\ actions_bbox_min_x[other_action] > check_start_x /\ actions_bbox_min_x[other_action] <= end_x) ->
      (
        actions_bbox_max_y[other_action] < start_y
        \/
        actions_bbox_min_y[other_action] > end_y
      )
  )
;

predicate no_boxes_left(var ACTIONS: current_action, var TIME: t, var GRID_SIZE_X: start_x, var GRID_SIZE_Y: start_y, var GRID_SIZE_Y: end_y) =
  let {
    var GRID_SIZE_X: check_end_x = actions_bbox_min_x[current_action];
  } in
  
  forall(other_action in ACTIONS) (
    (action_time[other_action] < t /\ actions_bbox_max_x[other_action] >= start_x /\ actions_bbox_max_x[other_action] < check_end_x) ->
      (
        actions_bbox_max_y[other_action] < start_y
        \/
        actions_bbox_min_y[other_action] > end_y
      )
  )
;


predicate no_boxes_below(var ACTIONS: current_action, var TIME: t, var GRID_SIZE_Y: end_y, var GRID_SIZE_X: start_x, var GRID_SIZE_X: end_x) =
  let {
    var GRID_SIZE_Y: check_start_y = actions_bbox_max_y[current_action];
  } in
  
  forall(other_action in ACTIONS) (
    (action_time[other_action] < t /\ actions_bbox_min_y[other_action] > check_start_y /\ actions_bbox_min_y[other_action] <= end_y) ->
      (
        actions_bbox_max_x[other_action] < start_x
        \/
        actions_bbox_min_x[other_action] > end_x
      )
  )
;


constraint forall(action in ACTIONS) (

  let {
    var TIME: t = action_time[action];
  } in
  
  if action_rotation[action] == TOP then
    no_boxes_above(action, t, max(1,actions_bbox_min_y[action] - 1),
                   max(actions_bbox_min_x[action] - actions_gripper_overflow[action], 1),              % AABB low x
                   min(actions_bbox_max_x[action] + actions_gripper_overflow[action], PALLET_WIDTH))   % AABB high x

  elseif action_rotation[action] == RIGHT then
    no_boxes_right(action, t, min(PALLET_WIDTH,actions_bbox_max_x[action] + 1),
                   max(actions_bbox_min_y[action] - actions_gripper_overflow[action], 1),              % AABB low y
                   min(actions_bbox_max_y[action] + actions_gripper_overflow[action], PALLET_HEIGHT))  % AABB high y

  elseif action_rotation[action] == LEFT then
    no_boxes_left(action, t, max(1,actions_bbox_min_x[action] - 1),
                  max(actions_bbox_min_y[action] - actions_gripper_overflow[action], 1),               % AABB low y
                  min(actions_bbox_max_y[action] + actions_gripper_overflow[action], PALLET_HEIGHT))   % AABB high y

  else
    no_boxes_below(action, t, min(PALLET_HEIGHT,actions_bbox_max_y[action] + 1),
                   max(actions_bbox_min_x[action] - actions_gripper_overflow[action], 1),              % AABB low x
                   min(actions_bbox_max_x[action] + actions_gripper_overflow[action], PALLET_WIDTH))   % AABB high x

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

    no_boxes_left(action, t, left_lower_bound_x, actions_bbox_min_y[action], actions_bbox_max_y[action])
    /\
    no_boxes_right(action, t, right_upper_bound_x, actions_bbox_min_y[action], actions_bbox_max_y[action])


  elseif action_rotation[action] == LEFT \/ action_rotation[action] == RIGHT then
    let {
      var TIME: t = action_time[action];
      var GRID_SIZE_Y: above_lower_bound_y =
        max(actions_bbox_min_y[action] - actions_gripper_overflow[action], 1);
      var GRID_SIZE_Y: below_upper_bound_y =
        min(actions_bbox_max_y[action] + actions_gripper_overflow[action], PALLET_HEIGHT);
    } in

    no_boxes_above(action, t, above_lower_bound_y, actions_bbox_min_x[action], actions_bbox_max_x[action])
    /\
    no_boxes_below(action, t, below_upper_bound_y, actions_bbox_min_x[action], actions_bbox_max_x[action])

  endif

);


% first action has orientation TOP or RIGHT (remove symmetries that start with BOT or LEFT)
constraint action_rotation[action_id[1]] = TOP \/ action_rotation[action_id[1]] = RIGHT;


constraint forall(action in ACTIONS) (
  let {
    var TIME: t = action_time[action];
  } in
  (action_rotation[action] == LEFT -> not no_boxes_right(action, t, min(PALLET_WIDTH,actions_bbox_max_x[action] + 1),
                                                         max(actions_bbox_min_y[action] - actions_gripper_overflow[action], 1),              % AABB low y
                                                         min(actions_bbox_max_y[action] + actions_gripper_overflow[action], PALLET_HEIGHT))) % AABB high y
  /\
  (action_rotation[action] == BOT  -> not no_boxes_above(action, t, max(1,actions_bbox_min_y[action] - 1),
                                                         max(actions_bbox_min_x[action] - actions_gripper_overflow[action], 1),              % AABB low x
                                                         min(actions_bbox_max_x[action] + actions_gripper_overflow[action], PALLET_WIDTH)))  % AABB high x
);



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



% constraint increasing([map_id_to_cluster[action] | action in action_id where action != 0]);

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
