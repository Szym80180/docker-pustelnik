# syntax=docker/dockerfile:1.4
# ==============================================================================
# Dockerfile for NVIDIA Jetson Orin Nano (ARM64) - Autonomous Rover
# Target Platform: Jetpack 6.2 (L4T R36.x / Ubuntu 22.04 Jammy)
# Compute Capability: 8.7 (NVIDIA Jetson Orin)
# ROS2 Distribution: Humble Hawksbill
# Optimized with Multi-Stage Build, BuildKit APT/CCache Caching & Ninja
# ==============================================================================

ARG BASE_IMAGE=nvcr.io/nvidia/l4t-jetpack:r36.3.0

# ------------------------------------------------------------------------------
# STAGE 1: Builder Stage (Compiles OpenCV, GTSAM, RTAB-Map, librealsense2)
# ------------------------------------------------------------------------------
FROM ${BASE_IMAGE} AS builder

LABEL maintainer="Autonomous Rover Team"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    ROS_DISTRO=humble \
    ROS_ROOT=/opt/ros/humble \
    CUDA_HOME=/usr/local/cuda \
    PATH=/usr/local/cuda/bin:${PATH} \
    LD_LIBRARY_PATH=/usr/local/cuda/lib64:${LD_LIBRARY_PATH} \
    TORCH_CUDA_ARCH_LIST="8.7" \
    CUDA_ARCH_BIN="8.7" \
    CCACHE_DIR=/root/.cache/ccache

SHELL ["/bin/bash", "-c"]

# Set locale & Core Build Tools (including ccache and ninja)
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    locales \
    build-essential \
    cmake \
    ninja-build \
    ccache \
    git \
    wget \
    curl \
    gnupg2 \
    lsb-release \
    ca-certificates \
    pkg-config \
    python3-dev \
    python3-pip \
    python3-numpy \
    python3-setuptools \
    python3-wheel \
    libtool \
    autoconf \
    automake \
    unzip \
    libusb-1.0-0-dev \
    libssl-dev \
    libudev-dev \
    libjpeg-dev \
    libpng-dev \
    libtiff-dev \
    libv4l-dev \
    libavcodec-dev \
    libavformat-dev \
    libswscale-dev \
    libgstreamer1.0-dev \
    libgstreamer-plugins-base1.0-dev \
    libgtk-3-dev \
    libatlas-base-dev \
    gfortran \
    libpcl-dev \
    liboctomap-dev \
    libsqlite3-dev \
    libfreenect-dev \
    libopenni2-dev \
    && locale-gen en_US.UTF-8 \
    && update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8

# Setup ROS2 Repo and ROS Core build dependencies
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o /usr/share/keyrings/ros-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/ros2.list > /dev/null && \
    apt-get update && apt-get install -y --no-install-recommends \
    ros-humble-ros-base \
    ros-dev-tools \
    python3-colcon-common-extensions \
    python3-rosdep \
    python3-vcstool \
    ros-humble-cv-bridge \
    ros-humble-image-transport \
    ros-humble-tf2 \
    ros-humble-tf2-ros \
    ros-humble-tf2-eigen \
    ros-humble-laser-geometry \
    ros-humble-pcl-conversions \
    ros-humble-pcl-ros \
    ros-humble-octomap-msgs \
    ros-humble-grid-map-ros

# 1. Compile CUDA-enabled OpenCV 4.8.0 with Ninja and CCache
ENV OPENCV_VERSION=4.8.0
RUN --mount=type=cache,target=/root/.cache/ccache \
    cd /tmp && \
    git clone --depth 1 --branch ${OPENCV_VERSION} https://github.com/opencv/opencv.git && \
    git clone --depth 1 --branch ${OPENCV_VERSION} https://github.com/opencv/opencv_contrib.git && \
    mkdir -p opencv/build && cd opencv/build && \
    cmake -G Ninja \
        -D CMAKE_C_COMPILER_LAUNCHER=ccache \
        -D CMAKE_CXX_COMPILER_LAUNCHER=ccache \
        -D CMAKE_BUILD_TYPE=RELEASE \
        -D CMAKE_INSTALL_PREFIX=/opt/rover/deps \
        -D OPENCV_EXTRA_MODULES_PATH=/tmp/opencv_contrib/modules \
        -D WITH_CUDA=ON \
        -D WITH_CUDNN=ON \
        -D OPENCV_DNN_CUDA=ON \
        -D ENABLE_FAST_MATH=1 \
        -D CUDA_FAST_MATH=1 \
        -D CUDA_ARCH_BIN=8.7 \
        -D CUDA_ARCH_PTX="" \
        -D WITH_GSTREAMER=ON \
        -D WITH_LIBV4L=ON \
        -D WITH_OPENGL=ON \
        -D WITH_QT=OFF \
        -D BUILD_EXAMPLES=OFF \
        -D BUILD_TESTS=OFF \
        -D BUILD_PERF_TESTS=OFF \
        -D BUILD_opencv_python3=ON \
        -D PYTHON3_EXECUTABLE=$(which python3) \
        -D PYTHON3_INCLUDE_DIR=$(python3 -c "import sysconfig; print(sysconfig.get_path('include'))") \
        -D PYTHON3_PACKAGES_PATH=/opt/rover/deps/lib/python3.10/site-packages \
        .. && \
    ninja install && \
    rm -rf /tmp/opencv /tmp/opencv_contrib

# 2. Compile GTSAM with Ninja and CCache
RUN --mount=type=cache,target=/root/.cache/ccache \
    cd /tmp && \
    git clone --depth 1 --branch 4.2a0 https://github.com/borglab/gtsam.git gtsam && \
    mkdir -p gtsam/build && cd gtsam/build && \
    cmake -G Ninja \
        -D CMAKE_C_COMPILER_LAUNCHER=ccache \
        -D CMAKE_CXX_COMPILER_LAUNCHER=ccache \
        -D CMAKE_BUILD_TYPE=Release \
        -D CMAKE_INSTALL_PREFIX=/opt/rover/deps \
        -D GTSAM_BUILD_WITH_MARCH_NATIVE=OFF \
        -D GTSAM_USE_SYSTEM_EIGEN=ON \
        -D GTSAM_BUILD_EXAMPLES_ALWAYS=OFF \
        -D GTSAM_BUILD_TESTS=OFF \
        .. && \
    ninja install && \
    rm -rf /tmp/gtsam

# 3. Compile CUDA-enabled RTAB-Map
RUN --mount=type=cache,target=/root/.cache/ccache \
    cd /tmp && \
    git clone --depth 1 --branch master https://github.com/introlab/rtabmap.git rtabmap && \
    mkdir -p rtabmap/build && cd rtabmap/build && \
    cmake -G Ninja \
        -D CMAKE_C_COMPILER_LAUNCHER=ccache \
        -D CMAKE_CXX_COMPILER_LAUNCHER=ccache \
        -D CMAKE_BUILD_TYPE=Release \
        -D CMAKE_INSTALL_PREFIX=/opt/rover/deps \
        -D GTSAM_DIR=/opt/rover/deps/lib/cmake/GTSAM \
        -D OpenCV_DIR=/opt/rover/deps/lib/cmake/opencv4 \
        -D WITH_CUDA=ON \
        -D CUDA_ARCH_BIN=8.7 \
        -D WITH_QT=OFF \
        -D WITH_PYTHON=ON \
        -D WITH_GTSAM=ON \
        -D WITH_OCTOMAP=ON \
        .. && \
    ninja install && \
    rm -rf /tmp/rtabmap

# 4. Compile librealsense2 with RSUSB backend
ENV REALSENSE_VERSION=2.54.2
RUN --mount=type=cache,target=/root/.cache/ccache \
    cd /tmp && \
    git clone --depth 1 --branch v${REALSENSE_VERSION} https://github.com/IntelRealSense/librealsense.git && \
    mkdir -p librealsense/build && cd librealsense/build && \
    cmake -G Ninja \
        -D CMAKE_C_COMPILER_LAUNCHER=ccache \
        -D CMAKE_CXX_COMPILER_LAUNCHER=ccache \
        -D CMAKE_BUILD_TYPE=Release \
        -D CMAKE_INSTALL_PREFIX=/opt/rover/deps \
        -D FORCE_RSUSB_BACKEND=ON \
        -D BUILD_PYTHON_BINDINGS:bool=true \
        -D BUILD_EXAMPLES=OFF \
        -D BUILD_GRAPHICAL_EXAMPLES=OFF \
        .. && \
    ninja install && \
    rm -rf /tmp/librealsense

# 5. Compile rtabmap_ros in workspace
RUN --mount=type=cache,target=/root/.cache/ccache \
    mkdir -p /ros2_ws/src && cd /ros2_ws/src && \
    git clone --depth 1 --branch humble-devel https://github.com/introlab/rtabmap_ros.git && \
    cd /ros2_ws && \
    source /opt/ros/humble/setup.bash && \
    export CMAKE_PREFIX_PATH=/opt/rover/deps:${CMAKE_PREFIX_PATH} && \
    colcon build --cmake-args \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_PREFIX_PATH=/opt/rover/deps \
        -DGTSAM_DIR=/opt/rover/deps/lib/cmake/GTSAM \
        -DRTABMap_DIR=/opt/rover/deps/lib/cmake/RTABMap \
        -DOpenCV_DIR=/opt/rover/deps/lib/cmake/opencv4 && \
    rm -rf /ros2_ws/build /ros2_ws/log


# ------------------------------------------------------------------------------
# STAGE 2: Final Minimal Runtime Image
# ------------------------------------------------------------------------------
FROM ${BASE_IMAGE} AS runtime

LABEL maintainer="Autonomous Rover Team"
LABEL description="Optimized ROS2 Humble CUDA-accelerated image for Jetson Orin Nano"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    ROS_DISTRO=humble \
    ROS_ROOT=/opt/ros/humble \
    CUDA_HOME=/usr/local/cuda \
    PATH=/usr/local/cuda/bin:/opt/rover/deps/bin:${PATH} \
    LD_LIBRARY_PATH=/usr/local/cuda/lib64:/opt/rover/deps/lib:${LD_LIBRARY_PATH} \
    PYTHONPATH=/opt/rover/deps/lib/python3.10/site-packages:${PYTHONPATH} \
    TORCH_CUDA_ARCH_LIST="8.7" \
    CUDA_ARCH_BIN="8.7"

SHELL ["/bin/bash", "-c"]

# Set locale
RUN apt-get update && apt-get install -y --no-install-recommends \
    locales \
    curl \
    gnupg2 \
    lsb-release \
    ca-certificates \
    python3-pip \
    python3-numpy \
    libv4l-0 \
    libgstreamer1.0-0 \
    libgstreamer-plugins-base1.0-0 \
    libusb-1.0-0 \
    libpcl-dev \
    liboctomap-dev \
    libsqlite3-dev \
    libfreenect-dev \
    libopenni2-dev \
    && locale-gen en_US.UTF-8 \
    && update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

# ROS2 Humble & Robotics Packages (Nav2, SLAM, Localization, Realsense Camera)
RUN curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o /usr/share/keyrings/ros-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/ros2.list > /dev/null && \
    apt-get update && apt-get install -y --no-install-recommends \
    ros-humble-ros-base \
    ros-humble-navigation2 \
    ros-humble-nav2-bringup \
    ros-humble-slam-toolbox \
    ros-humble-robot-localization \
    ros-humble-realsense2-camera \
    ros-humble-realsense2-description \
    ros-humble-cv-bridge \
    ros-humble-image-transport \
    ros-humble-tf2 \
    ros-humble-tf2-ros \
    ros-humble-tf2-eigen \
    ros-humble-laser-geometry \
    ros-humble-pcl-conversions \
    ros-humble-pcl-ros \
    ros-humble-octomap-msgs \
    ros-humble-grid-map-ros \
    && rm -rf /var/lib/apt/lists/*

# Copy built compiled artifacts from builder stage
COPY --from=builder /opt/rover/deps /opt/rover/deps
COPY --from=builder /ros2_ws /ros2_ws

RUN ldconfig /opt/rover/deps/lib && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

COPY ros_entrypoint.sh /ros_entrypoint.sh
RUN chmod +x /ros_entrypoint.sh

ENTRYPOINT ["/ros_entrypoint.sh"]
CMD ["bash"]
