# Reproducible image for the Nova5 mandarin-picker simulation.
#
# IMPORTANT: build from the PROJECT ROOT (so the two app scripts are in context):
#     docker build -f deploy/Dockerfile -t <dockerhub-user>/nova5-sim:humble .
#     docker push     <dockerhub-user>/nova5-sim:humble
# Then put that image name in your vast.ai instance template (see README_DEPLOY.md).
#
# This is the "bake it once, rent it anywhere" path. The alternative is to rent a
# plain ROS image and run deploy/setup.sh live — both end up identical.

FROM osrf/ros:humble-desktop

SHELL ["/bin/bash", "-lc"]
ENV DEBIAN_FRONTEND=noninteractive
ENV WS=/root/dobot_ws

# --- system + ROS deps + headless VNC desktop stack ---
RUN apt-get update && apt-get install -y --no-install-recommends \
      ros-humble-moveit \
      ros-humble-joint-trajectory-controller ros-humble-ros2-control \
      ros-humble-ros2-controllers ros-humble-controller-manager \
      ros-humble-tf-transformations python3-transforms3d \
      ros-humble-gazebo-ros-pkgs \
      python3-colcon-common-extensions python3-rosdep git tmux \
      tigervnc-standalone-server tigervnc-common novnc python3-websockify \
      openbox tint2 dbus-x11 x11-xserver-utils xfonts-base \
      mesa-utils libgl1-mesa-dri libgl1-mesa-glx \
    && rm -rf /var/lib/apt/lists/*

# --- Dobot Nova5 ROS 2 (Humble) packages ---
RUN mkdir -p $WS/src && cd $WS/src \
    && git clone -b feature/v4-optimization \
       https://github.com/Dobot-Arm/DOBOT_6Axis_ROS2_V4.git

# --- custom interfaces (ServoControl) — not in Dobot's official repo ---
COPY deploy/dobot_interfaces $WS/src/dobot_interfaces

# --- build only what the sim needs ---
RUN cd $WS && source /opt/ros/humble/setup.bash \
    && colcon build --packages-up-to nova5_moveit dobot_interfaces

# --- the picker scripts + the kit (paths match deploy/env.sh expectations) ---
COPY 09e22577e47fd787fc2ae304d5457362.py /root/kit/
COPY a898e4d93672bfed57f23a89443b68a3.py /root/kit/
COPY deploy /root/kit/deploy

ENV DISPLAY=:1 LIBGL_ALWAYS_SOFTWARE=1 QT_X11_NO_MITSHM=1 \
    ROS_DOMAIN_ID=42 ROS_LOCALHOST_ONLY=1

EXPOSE 5901 6080

# Default: bring up the VNC desktop and idle. Then `docker exec`/ssh in and run
#   bash /root/kit/deploy/run.sh
CMD ["/bin/bash", "-lc", "/root/kit/deploy/start-desktop.sh && tail -f /dev/null"]
