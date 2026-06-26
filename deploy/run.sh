#!/usr/bin/env bash
# Launch the whole simulation in a tmux session:
#   window 0 'moveit' : MoveIt2 mock-hardware demo (move_group + RViz, arm in sim)
#   window 1 'servo'  : fake gripper action server
#   window 2 'server' : your motion server (09e2...py)
#   window 3 'vision' : fake detector  (only with --vision)
#   window 4 'client' : your picking client (a898...py)  <- you type commands here
#
#   bash deploy/run.sh             # manual control via the client menu
#   bash deploy/run.sh --vision    # also start the fake detector for auto mode [6]
#
set -uo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/env.sh"

WITH_VISION="${1:-}"
SESSION=nova5

if [ ! -f "$NOVA5_WS/install/setup.bash" ]; then
  echo "!! Workspace not built. Run first:  bash $SCRIPT_DIR/setup.sh"
  exit 1
fi
if ! DISPLAY="$DISPLAY" xset q >/dev/null 2>&1; then
  echo "!! No X display on '$DISPLAY'. Start the desktop first:"
  echo "     bash $SCRIPT_DIR/start-desktop.sh"
  echo "   On a pre-baked VNC image (e.g. tiryoh) the desktop may be on a different"
  echo "   display — try:  export DISPLAY=:0   (then re-run this script)."
  exit 1
fi

SRC="source '$SCRIPT_DIR/env.sh'"

tmux kill-session -t "$SESSION" 2>/dev/null || true
tmux new-session -d -s "$SESSION" -n moveit

# 0) MoveIt mock-hardware demo: move_group + RViz + joint_trajectory_controller.
tmux send-keys -t "$SESSION:moveit" \
  "$SRC; ros2 launch nova5_moveit demo.launch.py" C-m

# 1) Fake gripper server (independent of move_group, safe to start now).
tmux new-window -t "$SESSION" -n servo
tmux send-keys -t "$SESSION:servo" \
  "$SRC; python3 '$SCRIPT_DIR/fake_servo_server.py'" C-m

# 2) Motion server — gate on move_group actually advertising /move_action, so a
#    slow cold boot can't trip the server's 15s internal wait and abort it.
tmux new-window -t "$SESSION" -n server
tmux send-keys -t "$SESSION:server" \
  "$SRC; echo '[server] waiting for move_group node...'; for i in \$(seq 1 180); do ros2 node list --no-daemon 2>/dev/null | grep -q move_group && break; sleep 1; done; sleep 5; python3 '$NOVA5_SERVER_PY'" C-m

# 3) Optional fake detector — needs TF (base_link->Link6), i.e. move_group up.
if [ "$WITH_VISION" = "--vision" ]; then
  tmux new-window -t "$SESSION" -n vision
  tmux send-keys -t "$SESSION:vision" \
    "$SRC; for i in \$(seq 1 180); do ros2 node list --no-daemon 2>/dev/null | grep -q move_group && break; sleep 1; done; sleep 2; python3 '$SCRIPT_DIR/fake_vision_publisher.py'" C-m
fi

# 4) Picking client — gate on the server node being registered on the graph.
tmux new-window -t "$SESSION" -n client
tmux send-keys -t "$SESSION:client" \
  "$SRC; echo '[client] waiting for server node...'; for i in \$(seq 1 120); do ros2 node list --no-daemon 2>/dev/null | grep -q nova5_planner_server && break; sleep 1; done; sleep 1; python3 '$NOVA5_CLIENT_PY'" C-m

echo ">> tmux session '$SESSION' launched."
echo "   RViz appears in your browser desktop (noVNC) within ~20s; the arm moves there."
echo "   Attaching to the CLIENT window — type menu commands ([3]=home, [1]=XYZ move, [6]=auto)."
echo "   Detach: Ctrl-b then d   |   Switch windows: Ctrl-b then 0..4   |   Stop all: bash $SCRIPT_DIR/stop.sh"
tmux select-window -t "$SESSION:client"
tmux attach -t "$SESSION"
