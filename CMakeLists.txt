cmake_minimum_required(VERSION 3.10)
project(MA LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
add_compile_options(-O3 -fopenmp)

find_package(OpenMP REQUIRED)

set(EXT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/external")
set(GCC_LIB_DIR "/projects/sw/eb/arch/zen4/software/GCCcore/14.2.0/lib/gcc/x86_64-pc-linux-gnu/14.2.0")
set(STD_LIB_DIR "/projects/sw/eb/arch/zen4/software/GCCcore/14.2.0/lib64")

set(STATIC_LIBS
    "-Wl,--start-group"
    "${STD_LIB_DIR}/libstdc++.a" "${STD_LIB_DIR}/libgomp.a"
    "${GCC_LIB_DIR}/libgcc.a" "${GCC_LIB_DIR}/libgcc_eh.a"
    "-Wl,-Bstatic" "m" "-Wl,-Bdynamic"
    "-Wl,--end-group" "pthread" "c" "dl"
)

# 1. STREAM
add_executable(stream src/stream.c)
target_compile_options(stream PRIVATE -mcmodel=medium)
target_compile_definitions(stream PRIVATE STREAM_ARRAY_SIZE=430080000 NTIMES=100)
target_link_libraries(stream PRIVATE ${STATIC_LIBS})
set_target_properties(stream PROPERTIES LINK_FLAGS "-nodefaultlibs")

# 2. SPMV & 3. SOLVE & helpers
set(PROGRAMS 
    spmv
    solve
    #preprocessmatrix
    synthgen
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