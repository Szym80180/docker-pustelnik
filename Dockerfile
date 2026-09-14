# ==============================================================================
# Dockerfile for NVIDIA Jetson Orin Nano (ARM64) - Autonomous Rover
# Target Platform: Jetpack 6.2 (L4T R36.x / Ubuntu 22.04 Jammy)
# Compute Capability: 8.7 (NVIDIA Jetson Orin)
# ROS2 Distribution: Humble Hawksbill
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Base Image selection
# ------------------------------------------------------------------------------
# JetPack 6.2 corresponds to L4T R36.x (Ubuntu 22.04 LTS ARM64)
# Primary: nvcr.io/nvidia/l4t-jetpack:r36.3.0 (or r36.2.0)
# Alternative / Fallback: dustynv/ros:humble-ros-base-l4t-r36.2.0
ARG BASE_IMAGE=nvcr.io/nvidia/l4t-jetpack:r36.3.0
FROM ${BASE_IMAGE}

LABEL maintainer="Autonomous Rover Team"
LABEL description="Optimized ROS2 Humble CUDA-accelerated image for Jetson Orin Nano"

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    ROS_DISTRO=humble \
    ROS_ROOT=/opt/ros/humble \
    CUDA_HOME=/usr/local/cuda \
    PATH=/usr/local/cuda/bin:${PATH} \
    LD_LIBRARY_PATH=/usr/local/cuda/lib64:${LD_LIBRARY_PATH} \
    TORCH_CUDA_ARCH_LIST="8.7" \
    CUDA_ARCH_BIN="8.7"

SHELL ["/bin/bash", "-c"]

# Set locale
RUN apt-get update && apt-get install -y --no-install-recommends \
    locales \
    && locale-gen en_US.UTF-8 \
    && update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------------------------
# Core Build Dependencies & Tools Setup
# ------------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
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
    && rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------------------------
# 2. Core ROS2 Humble Setup
# ------------------------------------------------------------------------------
RUN curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o /usr/share/keyrings/ros-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/ros2.list > /dev/null && \
    apt-get update && apt-get install -y --no-install-recommends \
    ros-humble-ros-base \
    ros-dev-tools \
    python3-colcon-common-extensions \
    python3-rosdep \
    python3-vcstool \
    python3-argcomplete \
    && rosdep init || true \
    && rosdep update \
    && rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------------------------
# 3. CUDA-enabled OpenCV (Compiled from Source for Jetson Orin Compute Capability 8.7)
# ------------------------------------------------------------------------------
ENV OPENCV_VERSION=4.8.0

# Install OpenCV pre-requisites and image/video I/O libraries
RUN apt-get update && apt-get install -y --no-install-recommends \
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
    && rm -rf /var/lib/apt/lists/*

RUN cd /tmp && \
    git clone --depth 1 --branch ${OPENCV_VERSION} https://github.com/opencv/opencv.git && \
    git clone --depth 1 --branch ${OPENCV_VERSION} https://github.com/opencv/opencv_contrib.git && \
    mkdir -p opencv/build && cd opencv/build && \
    cmake \
        -D CMAKE_BUILD_TYPE=RELEASE \
        -D CMAKE_INSTALL_PREFIX=/usr/local \
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
        -D PYTHON3_PACKAGES_PATH=$(python3 -c "import site; print(site.getsitepackages()[0])") \
        .. && \
    make -j$(nproc) && \
    make install && \
    ldconfig && \
    rm -rf /tmp/opencv /tmp/opencv_contrib

# ------------------------------------------------------------------------------
# 4. CUDA-enabled RTAB-Map & rtabmap_ros (Compiled with CUDA acceleration)
# ------------------------------------------------------------------------------
# Install RTAB-Map dependencies available in Ubuntu 22.04 & ROS2 Humble
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpcl-dev \
    liboctomap-dev \
    libsqlite3-dev \
    libfreenect-dev \
    libopenni2-dev \
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

# Compile GTSAM from source for optimization support in RTAB-Map
RUN cd /tmp && \
    git clone --depth 1 --branch 4.2a0 https://github.com/borglab/gtsam.git gtsam && \
    mkdir -p gtsam/build && cd gtsam/build && \
    cmake \
        -D CMAKE_BUILD_TYPE=Release \
        -D CMAKE_INSTALL_PREFIX=/usr/local \
        -D GTSAM_BUILD_WITH_MARCH_NATIVE=OFF \
        -D GTSAM_USE_SYSTEM_EIGEN=ON \
        -D GTSAM_BUILD_EXAMPLES_ALWAYS=OFF \
        -D GTSAM_BUILD_TESTS=OFF \
        .. && \
    make -j$(nproc) && \
    make install && \
    ldconfig && \
    rm -rf /tmp/gtsam

# Compile RTAB-Map library with CUDA support
RUN cd /tmp && \
    git clone --depth 1 --branch master https://github.com/introlab/rtabmap.git rtabmap && \
    mkdir -p rtabmap/build && cd rtabmap/build && \
    cmake \
        -D CMAKE_BUILD_TYPE=Release \
        -D CMAKE_INSTALL_PREFIX=/usr/local \
        -D WITH_CUDA=ON \
        -D CUDA_ARCH_BIN=8.7 \
        -D WITH_QT=OFF \
        -D WITH_PYTHON=ON \
        -D WITH_GTSAM=ON \
        -D WITH_OCTOMAP=ON \
        .. && \
    make -j$(nproc) && \
    make install && \
    ldconfig && \
    rm -rf /tmp/rtabmap

# Compile rtabmap_ros in ROS2 workspace
RUN mkdir -p /ros2_ws/src && cd /ros2_ws/src && \
    git clone --depth 1 --branch humble-devel https://github.com/introlab/rtabmap_ros.git && \
    cd /ros2_ws && \
    source /opt/ros/humble/setup.bash && \
    colcon build --symlink-install --cmake-args -DCMAKE_BUILD_TYPE=Release && \
    rm -rf /ros2_ws/build /ros2_ws/log

# ------------------------------------------------------------------------------
# 5. Hardware Integration: Realsense2 SDK (librealsense2) & ROS2 wrapper (realsense2_camera)
# Note: librealsense2 is compiled from source with RSUSB backend for ARM64/Jetson compatibility
# and realsense2_camera / realsense2_description installed via ROS2 humble apt repos.
# ------------------------------------------------------------------------------
ENV REALSENSE_VERSION=2.54.2

RUN cd /tmp && \
    git clone --depth 1 --branch v${REALSENSE_VERSION} https://github.com/IntelRealSense/librealsense.git && \
    mkdir -p librealsense/build && cd librealsense/build && \
    cmake \
        -D CMAKE_BUILD_TYPE=Release \
        -D CMAKE_INSTALL_PREFIX=/usr/local \
        -D FORCE_RSUSB_BACKEND=ON \
        -D BUILD_PYTHON_BINDINGS:bool=true \
        -D BUILD_EXAMPLES=OFF \
        -D BUILD_GRAPHICAL_EXAMPLES=OFF \
        .. && \
    make -j$(nproc) && \
    make install && \
    ldconfig && \
    rm -rf /tmp/librealsense

RUN apt-get update && apt-get install -y --no-install-recommends \
    ros-humble-realsense2-camera \
    ros-humble-realsense2-description \
    && rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------------------------
# 6. Navigation & SLAM Stack
# ------------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    ros-humble-navigation2 \
    ros-humble-nav2-bringup \
    ros-humble-slam-toolbox \
    ros-humble-robot-localization \
    && rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------------------------
# 7. Cleanup & Final Environment Configuration
# ------------------------------------------------------------------------------
RUN apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

COPY ros_entrypoint.sh /ros_entrypoint.sh
RUN chmod +x /ros_entrypoint.sh

ENTRYPOINT ["/ros_entrypoint.sh"]
CMD ["bash"]
