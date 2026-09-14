#!/bin/bash
set -e

# Source ROS2 Humble base setup
if [ -f "/opt/ros/humble/setup.bash" ]; then
    source "/opt/ros/humble/setup.bash"
fi

# Source custom ROS2 workspace setup if built
if [ -f "/ros2_ws/install/setup.bash" ]; then
    source "/ros2_ws/install/setup.bash"
fi

exec "$@"
