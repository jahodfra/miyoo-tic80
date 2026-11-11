# CMake toolchain file for the Miyoo Mini / Mini+ (Cortex-A7, glibc 2.28).
# Used inside the aemiii91/miyoomini-toolchain Docker image.
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR arm)
set(TC /opt/miyoomini-toolchain/usr)
set(CMAKE_C_COMPILER   ${TC}/bin/arm-linux-gnueabihf-gcc)
set(CMAKE_CXX_COMPILER ${TC}/bin/arm-linux-gnueabihf-g++)
set(CMAKE_AR     ${TC}/bin/arm-linux-gnueabihf-gcc-ar CACHE FILEPATH "")
set(CMAKE_RANLIB ${TC}/bin/arm-linux-gnueabihf-gcc-ranlib CACHE FILEPATH "")
set(CMAKE_SYSROOT ${TC}/arm-linux-gnueabihf/sysroot)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
