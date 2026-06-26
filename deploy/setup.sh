#!/usr/bin/env bash
# One-time setup on a fresh ROS 2 Humble (Ubuntu 22.04) machine / instance.
# Installs deps, clones the Dobot Nova5 packages, adds our custom interfaces,
# and builds just what the simulation needs.
#
#   bash deploy/setup.sh
#
set -uo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/env.sh"

if [ "$(id -u)" -ne 0 ]; then SUDO=sudo; else SUDO=; fi

# [0/5] Install ROS 2 Humble itself if it's not already on the box (a plain
# Ubuntu 22.04 instance won't have it; the osrf/ros image already does).
if [ ! -f /opt/ros/humble/setup.bash ]; then
  echo ">> [0/5] ROS 2 Humble not found — installing base (adds the ROS apt repo)"
  export DEBIAN_FRONTEND=noninteractive
  $SUDO apt-get update
  $SUDO apt-get install -y software-properties-common curl gnupg lsb-release locales
  $SUDO add-apt-repository -y universe
  $SUDO locale-gen en_US en_US.UTF-8 || true
  $SUDO curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
    -o /usr/share/keyrings/ros-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu $(. /etc/os-release && echo "$UBUNTU_CODENAME") main" \
    | $SUDO tee /etc/apt/sources.list.d/ros2.list >/dev/null
  $SUDO apt-get update
  $SUDO apt-get install -y ros-humble-desktop
  # make this shell ROS-aware for the build step below
  source /opt/ros/humble/setup.bash
else
  echo ">> [0/5] ROS 2 Humble already installed — skipping base install"
fi

echo ">> [1/5] apt dependencies (ROS 2 control, MoveIt, tf, VNC desktop stack)"
$SUDO apt-get update
$SUDO apt-get install -y --no-install-recommends \
  ros-humble-moveit \
  ros-humble-joint-trajectory-controller ros-humble-ros2-control \
  ros-humble-ros2-controllers ros-humble-controller-manager \
  ros-humble-tf-transformations python3-transforms3d \
  ros-humble-gazebo-ros-pkgs ros-humble-gazebo-ros2-control \
  python3-colcon-common-extensions python3-rosdep git tmux \
  tigervnc-standalone-server tigervnc-common novnc python3-websockify \
  openbox tint2 dbus-x11 x11-xserver-utils xfonts-base \
  mesa-utils libgl1-mesa-dri libgl1-mesa-glx

echo ">> [2/5] Dobot Nova5 ROS 2 packages (DOBOT_6Axis_ROS2_V4, branch feature/v4-optimization)"
mkdir -p "$NOVA5_WS/src"
cd "$NOVA5_WS/src"
if [ ! -d DOBOT_6Axis_ROS2_V4 ]; then
  git clone -b feature/v4-optimization \
    https://github.com/Dobot-Arm/DOBOT_6Axis_ROS2_V4.git
else
  echo "   (Dobot repo already cloned — skipping)"
fi

echo ">> [3/5] install custom dobot_interfaces package (ServoControl action)"
rm -rf "$NOVA5_WS/src/dobot_interfaces"
cp -r "$SCRIPT_DIR/dobot_interfaces" "$NOVA5_WS/src/dobot_interfaces"

echo ">> [4/5] rosdep"
$SUDO rosdep init >/dev/null 2>&1 || true
rosdep update || true
cd "$NOVA5_WS"
rosdep install --from-paths \
  src/DOBOT_6Axis_ROS2_V4/nova5_moveit src/dobot_interfaces \
  --ignore-src -r -y || true

echo ">> [5/5] colcon build (nova5_moveit + dobot_interfaces + dobot_gazebo)"
# Building the *whole* Dobot repo pulls in the C++ TCP/IP driver packages that
# the simulation does not need (and that often fail to build). We build only the
# MoveIt config, the robot description it depends on, our interfaces, and the
# Gazebo package (which drags in cra_description) for the physics sim.
# ROS's setup.bash trips `set -u` (references AMENT_TRACE_SETUP_FILES etc.),
# so disable nounset just for the source, then restore it.
set +u
source /opt/ros/humble/setup.bash
set -u
colcon build --packages-up-to nova5_moveit dobot_interfaces dobot_gazebo

echo
echo ">> Setup complete."
echo "   Next:"
echo "     bash $SCRIPT_DIR/start-desktop.sh   # virtual desktop + noVNC (skip on tiryoh image)"
echo "     bash $SCRIPT_DIR/run.sh             # launch sim + server + client"
