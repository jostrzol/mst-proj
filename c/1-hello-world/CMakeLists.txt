# ===== BUILD =================================================================
add_executable(1-hello-world main.c)
target_compile_options(1-hello-world PRIVATE -Wall -Wextra -Wpedantic -Werror)
target_link_libraries(1-hello-world libgpiod)
