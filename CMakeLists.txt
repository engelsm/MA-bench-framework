cmake_minimum_required(VERSION 3.10)
project(MA LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
add_compile_options(-O3 -fopenmp)

find_package(OpenMP REQUIRED)

set(EXT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/external")
set(GCC_LIB_DIR "/projects/sw/eb/arch/zen4/software/GCCcore/14.2.0/lib/gcc/x86_64-pc-linux-gnu/14.2.0")
set(STD_LIB_DIR "/projects/sw/eb/arch/zen4/software/GCCcore/14.2.0/lib64")

# --- Static System Library Linking Configuration ---
# 1. --start-group/--end-group: Forces the linker to recursively scan enclosed 
#    archives to resolve circular dependencies common in static linking.
# 2. libstdc++.a / libgomp.a: Statically links the C++ Standard Library and 
#    the OpenMP (GNU Offloading and Multi-Processing) runtime for portability.
# 3. libgcc.a / libgcc_eh.a: Statically links GCC internal helpers and 
#    Exception Handling routines.
# 4. -Bstatic m -Bdynamic: Temporarily switches to static mode to pull in the 
#    math library (libm), then reverts to dynamic for system-level libs.
# 5. pthread / c / dl: Explicitly links POSIX threads, the C Standard Library, 
#    and the dynamic linking interface.
set(STATIC_LIBS
    "-Wl,--start-group"
    "${STD_LIB_DIR}/libstdc++.a" "${STD_LIB_DIR}/libgomp.a"
    "${GCC_LIB_DIR}/libgcc.a" "${GCC_LIB_DIR}/libgcc_eh.a"
    "-Wl,-Bstatic" "m" "-Wl,-Bdynamic"
    "-Wl,--end-group" "pthread" "c" "dl"
)

# 1. STREAM
add_executable(stream src/stream.c)
target_compile_options(stream PRIVATE -O -mcmodel=medium)
target_compile_definitions(stream PRIVATE STREAM_ARRAY_SIZE=430080000 NTIMES=100)
target_link_libraries(stream PRIVATE ${STATIC_LIBS})
set_target_properties(stream PROPERTIES LINK_FLAGS "-nodefaultlibs")

# 2. SPMV & 3. SOLVE & helpers
set(PROGRAMS 
    spmv
    krylov
    preprocess_matrix
    synthgen
    IO_Performance
)

foreach(PROG ${PROGRAMS})
    add_executable(${PROG} src/${PROG}.cpp)
    target_link_libraries(${PROG} PRIVATE ${STATIC_LIBS})
    set_target_properties(${PROG} PROPERTIES LINK_FLAGS "-nodefaultlibs")
    target_include_directories(${PROG} PRIVATE 
        src 
        ${EXT_DIR}/spectra/include 
        ${EXT_DIR}/fast_matrix_market/include 
        ${EXT_DIR}/eigen
    )
endforeach()

# 4. DYNAMIC SPMV
add_executable(spmv_DYNAMIC src/spmv.cpp)

target_link_libraries(spmv_DYNAMIC PRIVATE OpenMP::OpenMP_CXX)

target_include_directories(spmv_DYNAMIC PRIVATE 
    src 
    ${EXT_DIR}/spectra/include 
    ${EXT_DIR}/fast_matrix_market/include 
    ${EXT_DIR}/eigen
)

target_compile_options(spmv_DYNAMIC PRIVATE -march=native)