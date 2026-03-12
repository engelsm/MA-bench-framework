cmake_minimum_required(VERSION 3.10)
project(EigenBenchmarks)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
  add_compile_options(-O3 -march=znver4)
endif()
find_package(OpenMP REQUIRED)

set(SPECTRA_INCLUDE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/external/spectra/include")
set(FMM_INCLUDE_DIR     "${CMAKE_CURRENT_SOURCE_DIR}/external/fast_matrix_market/include")
set(EIGEN_SUBMODULE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/external/eigen")

set(PROGRAMS 
    solve
    spmv
    preprocess_matrix
    synthgen
)

foreach(PROG ${PROGRAMS})
    add_executable(${PROG} src/${PROG}.cpp)
    target_link_libraries(${PROG} PRIVATE OpenMP::OpenMP_CXX)
    target_include_directories(${PROG} PRIVATE 
        src 
        ${SPECTRA_INCLUDE_DIR}
        ${FMM_INCLUDE_DIR}
        ${EIGEN_SUBMODULE_DIR}   
    )

endforeach()
