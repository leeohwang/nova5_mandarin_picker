#!/usr/bin/env bash
# Launch the FULL Gazebo-physics simulation in a tmux session (separate from the
# mock-hardware run.sh). Windows:
#   0 'gazebo' : Gazebo physics + robot + ros2_control controllers (gzserver)
#   1 'moveit' : move_group + RViz   (nova5_moveit/moveit_gazebo.launch.py)
#   2 'servo'  : fake gripper action server
#   3 'server' : your motion server (09e2...py)
#   4 'client' : your picking client (a898...py)  <- type commands here
#
#   bash deploy/run-gazebo.sh           # headless Gazebo (gzclient killed) + RViz
#   bash deploy/run-gazebo.sh --gui     # also keep the heavy Gazebo GUI (slow!)
#
# Why headless by default: on a no-GPU box RViz already renders via software GL
# (~5 FPS); gzclient on top is near-unusable. gzserver (physics) runs fine on
# CPU, and you watch the robot in RViz instead. Pass --gui only if you must.
#
# NOTE: the stock Gazebo world has NO camera, so auto/vision mode (client [6])
# has no detections here — use the manual menu ([1] XYZ, [3] home, [5] release).
set -uo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/env.sh"

WANT_GUI="${1:-}"
SESSION=nova5gz
export DOBOT_TYPE="${DOBOT_TYPE:-nova5}"

if [ ! -f "$NOVA5_WS/install/setup.bash" ]; then
  echo "!! Workspace not built. Run first:  bash $SCRIPT_DIR/setup.sh"
  exit 1
fi
if ! DISPLAY="$DISPLAY" xset q >/dev/null 2>&1; then
  echo "!! No X display on '$DISPLAY'. Start the desktop first:"
  echo "     bash $SCRIPT_DIR/start-desktop.sh"
  exit 1
fi

SRC="source '$SCRIPT_DIR/env.sh'; export DOBOT_TYPE='$DOBOT_TYPE'"

tmux kill-session -t "$SESSION" 2>/dev/null || true
tmux new-session -d -s "$SESSION" -n gazebo

# 0) Gazebo physics + robot + controllers. By default we keep gzserver but kill
#    gzclient as it appears (for ~40s, covering the slow software-GL startup).
if [ "$WANT_GUI" = "--gui" ]; then
  GZCMD="$SRC; ros2 launch dobot_gazebo gazebo_moveit.launch.py"
else
  GZCMD="$SRC; (for i in \$(seq 1 13); do sleep 3; pkill -f gzclient 2>/dev/null; done) & ros2 launch dobot_gazebo gazebo_moveit.launch.py"
fi
tmux send-keys -t "$SESSION:gazebo" "$GZCMD" C-m

# 1) move_group + RViz. move_group uses sim time, so it blocks until Gazebo
#    publishes /clock — gate on that so it doesn't spin waiting for time.
tmux new-window -t "$SESSION" -n moveit
tmux send-keys -t "$SESSION:moveit" \
  "$SRC; echo '[moveit] waiting for Gazebo /clock...'; for i in \$(seq 1 180); do ros2 topic list --no-daemon 2>/dev/null | grep -q '^/clock' && break; sleep 1; done; sleep 3; ros2 launch nova5_moveit moveit_gazebo.launch.py" C-m

# 2) Fake gripper server.
tmux new-window -t "$SESSION" -n servo
tmux send-keys -t "$SESSION:servo" \
  "$SRC; python3 '$SCRIPT_DIR/fake_servo_server.py'" C-m

# 3) Motion server — gate on move_group advertising /move_action.
tmux new-window -t "$SESSION" -n server
tmux send-keys -t "$SESSION:server" \
  "$SRC; echo '[server] waiting for move_group node...'; for i in \$(seq 1 240); do ros2 node list --no-daemon 2>/dev/null | grep -q move_group && break; sleep 1; done; sleep 5; python3 '$NOVA5_SERVER_PY'" C-m

# 4) Picking client — gate on the server node being on the graph.
tmux new-window -t "$SESSION" -n client
tmux send-keys -t "$SESSION:client" \
  "$SRC; echo '[client] waiting for server node...'; for i in \$(seq 1 120); do ros2 node list --no-daemon 2>/dev/null | grep -q nova5_planner_server && break; sleep 1; done; sleep 1; python3 '$NOVA5_CLIENT_PY'" C-m

echo ">> tmux session '$SESSION' launched (Gazebo physics)."
echo "   RViz appears in your browser desktop (noVNC). Gazebo runs HEADLESS"
echo "   (gzserver only) unless you passed --gui."
echo "   Detach: Ctrl-b then d  |  Windows: Ctrl-b then 0..4  |  Stop: bash $SCRIPT_DIR/stop.sh"
tmux select-window -t "$SESSION:client"
tmux attach -t "$SESSION"
