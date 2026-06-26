# Shared environment for the Nova5 mandarin-picker simulation.
# Source this (don't execute) from every shell that runs a ROS node:
#     source /path/to/deploy/env.sh
#
# It is safe to source multiple times.

# --- resolve paths relative to this file (works whether sourced from bash) ---
_NOVA5_ENV_SRC="${BASH_SOURCE[0]:-$0}"
NOVA5_DEPLOY_DIR="$( cd "$( dirname "$_NOVA5_ENV_SRC" )" && pwd )"
NOVA5_PROJECT_DIR="$( dirname "$NOVA5_DEPLOY_DIR" )"
export NOVA5_DEPLOY_DIR NOVA5_PROJECT_DIR

# The two application scripts (kept under their original hashed names).
export NOVA5_SERVER_PY="$NOVA5_PROJECT_DIR/09e22577e47fd787fc2ae304d5457362.py"
export NOVA5_CLIENT_PY="$NOVA5_PROJECT_DIR/a898e4d93672bfed57f23a89443b68a3.py"

# Colcon workspace that holds the Dobot Nova5 packages + our custom interfaces.
export NOVA5_WS="${NOVA5_WS:-$HOME/dobot_ws}"

# --- headless rendering: RViz2 over VNC uses Mesa software GL (llvmpipe) ---
export DISPLAY="${DISPLAY:-:1}"
export LIBGL_ALWAYS_SOFTWARE="${LIBGL_ALWAYS_SOFTWARE:-1}"
export QT_X11_NO_MITSHM=1

# --- keep all DDS traffic on this one machine (no ROS over the internet) ---
export ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-42}"
export ROS_LOCALHOST_ONLY="${ROS_LOCALHOST_ONLY:-1}"

# --- source ROS + the built workspace ---
# ROS's setup.bash references unbound vars (e.g. AMENT_TRACE_SETUP_FILES), which
# is fatal if the caller has `set -u` (nounset) on. Disable nounset just for the
# sourcing, then restore whatever the caller had.
case "$-" in *u*) _NOVA5_HAD_NOUNSET=1 ;; *) _NOVA5_HAD_NOUNSET=0 ;; esac
set +u
if [ -f /opt/ros/humble/setup.bash ]; then
  source /opt/ros/humble/setup.bash
fi
if [ -f "$NOVA5_WS/install/setup.bash" ]; then
  source "$NOVA5_WS/install/setup.bash"
fi
[ "$_NOVA5_HAD_NOUNSET" = "1" ] && set -u
unset _NOVA5_HAD_NOUNSET
