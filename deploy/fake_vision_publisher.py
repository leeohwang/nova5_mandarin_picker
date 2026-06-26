#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Fake vision detector for the Nova5 simulation.

The picking client subscribes to `/realsense_detection_topic` (std_msgs/Int32MultiArray)
and expects each message to be a flat int array:

    [flag, x, y, z, width, height]

where x/y/z are the target position in the CAMERA frame in millimetres and
width/height are the detected object size in pixels. `flag == -1` (or -1000
sentinels) means "no detection".

There is no camera in this simulation, so this node fabricates a single, steady
detection so the client's fully-automatic mode ([6] in the menu) can fire. The
client requires 5 consecutive readings within 10 mm to consider the target
"stable"; publishing a constant point satisfies that.

The target is given in the CAMERA frame; the client transforms it to base_link
using live TF, so whether it ends up reachable depends on the arm's current
pose. If IK fails, the server simply reports failure and the flow aborts
cleanly — tune the cam_*_mm params (or just use the manual menu) if so.

Examples:
    python3 fake_vision_publisher.py
    python3 fake_vision_publisher.py --ros-args -p cam_z_mm:=300 -p width_px:=80
"""

import rclpy
from rclpy.node import Node
from std_msgs.msg import Int32MultiArray

TOPIC = "/realsense_detection_topic"


class FakeVision(Node):
    def __init__(self):
        super().__init__("fake_vision_publisher")

        # Target in the CAMERA frame (mm) + detected size (px).
        # The client treats any flag != -1 as valid (and rejects only when a
        # coord/size hits the -1000 sentinel); 0 is the normal "valid" value.
        self.declare_parameter("flag", 0)          # 0 = valid detection, -1 = none
        self.declare_parameter("cam_x_mm", 0)
        self.declare_parameter("cam_y_mm", 0)
        self.declare_parameter("cam_z_mm", 250)
        self.declare_parameter("width_px", 30)     # < width_threshold(60) -> "small orange"
        self.declare_parameter("height_px", 30)
        self.declare_parameter("rate_hz", 10.0)

        self.pub = self.create_publisher(Int32MultiArray, TOPIC, 10)
        rate = float(self.get_parameter("rate_hz").value)
        self.timer = self.create_timer(1.0 / max(rate, 0.1), self._tick)

        self.get_logger().info(
            f"Fake vision publishing a steady detection on {TOPIC} "
            f"at {rate:.0f} Hz. Tune with -p cam_z_mm:=.. / -p width_px:=.. ."
        )

    def _tick(self):
        g = self.get_parameter
        msg = Int32MultiArray()
        msg.data = [
            int(g("flag").value),
            int(g("cam_x_mm").value),
            int(g("cam_y_mm").value),
            int(g("cam_z_mm").value),
            int(g("width_px").value),
            int(g("height_px").value),
        ]
        self.pub.publish(msg)


def main():
    rclpy.init()
    node = FakeVision()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()


if __name__ == "__main__":
    main()
