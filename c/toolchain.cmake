set(TARGET_TRIPLET arm-linux-gnueabihf)

# the name of the target operating system
set(CMAKE_SYSTEM_NAME Linux)

# which compilers to use for C and C++
set(CMAKE_C_COMPILER ${TARGET_TRIPLET}-gcc)
set(CMAKE_CXX_COMPILER ${TARGET_TRIPLET}-g++)

# where is the target environment located
set(CMAKE_FIND_ROOT_PATH /usr/${TARGET_TRIPLET})

# adjust the default behavior of the FIND_XXX() commands: search programs in the
# host environment
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)

# search headers and libraries in the target environment
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)