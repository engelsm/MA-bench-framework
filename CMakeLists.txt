cmake_minimum_required(VERSION 3.10)
project(EigenBenchmarks)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O3 -march=znver4 -g -fno-omit-frame-pointer -DNDEBUG -DEIGEN_USE_OMP")
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -O3 -march=znver4 -fopenmp")
endif()

list(APPEND CMAKE_PREFIX_PATH "/projects/sw/eb/arch/zen4/software/Eigen/3.4.0-GCCcore-13.3.0")
find_package(Eigen3 REQUIRED)
find_package(OpenMP REQUIRED)


set(SPECTRA_INCLUDE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/external/spectra/include")
set(FMM_INCLUDE_DIR     "${CMAKE_CURRENT_SOURCE_DIR}/external/fast_matrix_market/include")
set(GEN_DIR             "${CMAKE_CURRENT_SOURCE_DIR}/external/artificial-matrix-generator") 

add_library(matrix_gen STATIC
    ${GEN_DIR}/artificial_matrix_generation.c
    ${GEN_DIR}/ordered_set.c
    ${GEN_DIR}/artificial_matrix.c 
)
target_include_directories(matrix_gen PUBLIC ${GEN_DIR})
target_link_libraries(matrix_gen PRIVATE OpenMP::OpenMP_C)

add_executable(matgen src/matgen.c)
target_include_directories(matgen PRIVATE ${GEN_DIR})
target_link_libraries(matgen PRIVATE matrix_gen m)

set(PROGRAMS 
    solve
    spmv
)

foreach(PROG ${PROGRAMS})
    add_executable(${PROG} src/${PROG}.cpp)
    target_link_libraries(${PROG} PRIVATE Eigen3::Eigen OpenMP::OpenMP_CXX)
    target_include_directories(${PROG} PRIVATE 
        src 
        ${SPECTRA_INCLUDE_DIR}
        ${FMM_INCLUDE_DIR}
        ${GEN_DIR} 
    )
endforeach()