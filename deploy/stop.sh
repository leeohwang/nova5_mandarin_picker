#!/usr/bin/env bash
# Stop the simulation (tmux session + ALL ROS/Gazebo nodes). Leaves the VNC
# desktop (Xvnc + noVNC) running so your browser view stays connected.
#
#   bash deploy/stop.sh
#
tmux kill-session -t nova5 2>/dev/null || true
tmux kill-session -t nova5gz 2>/dev/null || true

# Mock-demo + app nodes, then Gazebo + the launch/controller machinery.
for p in demo.launch.py move_group ros2_control_node rviz2 \
         fake_servo_server.py fake_vision_publisher.py \
         09e22577e47fd787fc2ae304d5457362.py a898e4d93672bfed57f23a89443b68a3.py \
         gazebo gzserver gzclient gazebo_ros robot_state_publisher \
         spawner controller_manager 'ros2 launch' 'ros2 run' \
         component_container parameter_bridge; do
  pkill -f "$p" 2>/dev/null || true
done
sleep 1
# Anything stubborn (e.g. gzserver that ignored SIGTERM) gets a hard kill.
for p in gzserver gzclient gazebo; do pkill -9 -f "$p" 2>/dev/null || true; done

# Reset ROS 2 discovery so a fresh launch starts from a clean graph.
ros2 daemon stop >/dev/null 2>&1 || true

echo ">> Stopped all nova5 ROS/Gazebo nodes (VNC desktop left running)."
echo "   Verify it's clean:  pgrep -af 'gzserver|move_group|rviz2'   # should print nothing"
