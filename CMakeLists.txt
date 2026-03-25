cmake_minimum_required(VERSION 3.10)
project(MA)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON) # for vscode compile_commands.json

add_compile_options(-O3 -fopenmp)
find_package(OpenMP REQUIRED)

set(SPECTRA_INCLUDE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/external/spectra/include")
set(FMM_INCLUDE_DIR     "${CMAKE_CURRENT_SOURCE_DIR}/external/fast_matrix_market/include")
set(EIGEN_SUBMODULE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/external/eigen")
set(PROGRAMS 
    solve
    spmv
    #preprocess_matrix
    synthgen
)
set(GCC_LIB_DIR "/projects/sw/eb/arch/zen4/software/GCCcore/14.2.0/lib/gcc/x86_64-pc-linux-gnu/14.2.0")
set(STD_LIB_DIR "/projects/sw/eb/arch/zen4/software/GCCcore/14.2.0/lib64")

foreach(PROG ${PROGRAMS})
    add_executable(${PROG} src/${PROG}.cpp)
    
    target_link_libraries(${PROG} PRIVATE 
        "-Wl,--start-group"
        "${STD_LIB_DIR}/libstdc++.a"
        "${STD_LIB_DIR}/libgomp.a"
        "${GCC_LIB_DIR}/libgcc.a"
        "${GCC_LIB_DIR}/libgcc_eh.a"
        "-Wl,-Bstatic"      
        "m" 
        "-Wl,-Bdynamic"     
        "-Wl,--end-group"
        "pthread"
        "c"
        "dl"
    )

    set_target_properties(${PROG} PROPERTIES LINK_FLAGS "-nodefaultlibs")
    
    target_include_directories(${PROG} PRIVATE 
        src 
        ${SPECTRA_INCLUDE_DIR}
        ${FMM_INCLUDE_DIR}
        ${EIGEN_SUBMODULE_DIR}   
    )
endforeach()