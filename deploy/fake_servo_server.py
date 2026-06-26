#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Fake gripper / servo action server for the Nova5 simulation.

The real robot's gripper is driven through `dobot_interfaces/action/ServoControl`
on the action name `servo_control`. That hardware action server does not exist
in simulation, so this stub stands in for it: it accepts every goal, logs the
requested action_name, waits briefly, and reports success. This keeps the
client's `call_servo` / `call_servo_nowait` calls from failing in sim.
"""

import time

import rclpy
from rclpy.node import Node
from rclpy.action import ActionServer

from dobot_interfaces.action import ServoControl


class FakeServoServer(Node):
    def __init__(self):
        super().__init__("fake_servo_server")
        self._server = ActionServer(
            self, ServoControl, "servo_control", self.execute_callback
        )
        self.get_logger().info(
            "Fake gripper action server is up on 'servo_control' "
            "(type dobot_interfaces/action/ServoControl)."
        )

    def execute_callback(self, goal_handle):
        name = goal_handle.request.action_name
        self.get_logger().info(f"[gripper] received goal: action_name='{name}'")

        # Emulate the gripper physically taking a moment to open/close.
        time.sleep(0.4)

        goal_handle.succeed()
        result = ServoControl.Result()
        result.success = True
        result.message = f"fake gripper executed '{name}'"
        self.get_logger().info(f"[gripper] done: '{name}'")
        return result


def main():
    rclpy.init()
    node = FakeServoServer()
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
