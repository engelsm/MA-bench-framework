cmake_minimum_required(VERSION 3.10)
project(EigenBenchmarks)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
  add_compile_options(-O3 -march=znver4 -g -fno-omit-frame-pointer)
endif()
find_package(OpenMP REQUIRED)

set(SPECTRA_INCLUDE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/external/spectra/include")
set(FMM_INCLUDE_DIR     "${CMAKE_CURRENT_SOURCE_DIR}/external/fast_matrix_market/include")
set(GEN_DIR             "${CMAKE_CURRENT_SOURCE_DIR}/external/artificial-matrix-generator") 
set(EIGEN_SUBMODULE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/external/eigen")

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
    preprocess_matrix
    spmv_likwid
    testlikwid
    synthgen
)
find_path(LIKWID_INCLUDE_DIR NAMES likwid-marker.h PATHS /usr/local/include /usr/include)
find_library(LIKWID_LIBRARY NAMES likwid PATHS /usr/local/lib /usr/lib)

if(LIKWID_INCLUDE_DIR AND LIKWID_LIBRARY)
    message(STATUS "LIKWID found: ${LIKWID_LIBRARY}")
else()
    message(FATAL_ERROR "LIKWID not found! Bitte installieren oder Pfade anpassen.")
endif()

foreach(PROG ${PROGRAMS})
    add_executable(${PROG} src/${PROG}.cpp)
    target_link_libraries(${PROG} PRIVATE OpenMP::OpenMP_CXX)
    target_include_directories(${PROG} PRIVATE 
        src 
        ${SPECTRA_INCLUDE_DIR}
        ${FMM_INCLUDE_DIR}
        ${GEN_DIR} 
        ${EIGEN_SUBMODULE_DIR}   
    )

    if(PROG STREQUAL "spmv_likwid" OR PROG STREQUAL "testlikwid")
        target_compile_definitions(${PROG} PRIVATE LIKWID_PERFMON)
        target_include_directories(${PROG} PRIVATE ${LIKWID_INCLUDE_DIR})
        target_link_libraries(${PROG} PRIVATE ${LIKWID_LIBRARY})
    endif()
endforeach()
