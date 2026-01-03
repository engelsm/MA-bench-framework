#First load:
#module load compiler/GCCcore/13.3.0
#module load math/Eigen/3.4.0-GCCcore-13.3.0

cmake_minimum_required(VERSION 3.10)
project(EigenBenchmarks)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O3 -march=znver4 -g -fno-omit-frame-pointer -DNDEBUG -DEIGEN_USE_OMP")
endif()
list(APPEND CMAKE_PREFIX_PATH "/projects/sw/eb/arch/zen4/software/Eigen/3.4.0-GCCcore-13.3.0")
find_package(Eigen3 REQUIRED)
find_package(OpenMP REQUIRED)

set(SPECTRA_INCLUDE_DIR "/home/mengelsl/libs/spectra/include")
set(FMM_INCLUDE_DIR "/home/mengelsl/libs/fast_matrix_market/include")

set(PROGRAMS 
    preprocess_matrix
    solve
    spatial_regularity
)

foreach(PROG ${PROGRAMS})
    add_executable(${PROG} src/${PROG}.cpp)
    
    target_link_libraries(${PROG} Eigen3::Eigen OpenMP::OpenMP_CXX)
    
    target_include_directories(${PROG} PRIVATE 
        src 
        ${SPECTRA_INCLUDE_DIR}
        ${FMM_INCLUDE_DIR}
    )
endforeach()