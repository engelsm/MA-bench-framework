#pragma once
#include <Eigen/Sparse>
#include <fstream>
#include <iostream>
#include <vector>
#include <fast_matrix_market/app/Eigen.hpp>
#include <numeric>
#include <algorithm>
#include <cmath>
#include <filesystem>

/**
 * CUSTOM BINARY CSR FORMAT
 *
 * TODO : explain the "why" behind this format (performance, parallelization, etc.)
 *
 * LAYOUT IN MEMORY
 * (With 4 Byte StorageIndex=int and 8 Byte Scalar=double)
 * Data is stored in three consecutive sections without any padding:
 * * [1] HEADER
 * - Rows        (4 Bytes)
 * - Cols        (4 Bytes)
 * - NNZ         (4 Bytes)
 * * [2] STRUCTURE
 * - Row-Starts (4 Bytes * [Rows + 1])
 * - Col-ID     (4 Bytes * NNZ)
 * * [3] VALUES
 * - Numbers    (8 Bytes * NNZ)
 */

// Data type for CustomSparseMatrix entries.
using Scalar = double;
// Data type for CustomSparseMatrix indexing. This type needs to be large enough to hold the total number of NNZ.
using StorageIndex = int;
using CustomSparseMatrix = Eigen::SparseMatrix<Scalar, Eigen::RowMajor, StorageIndex>;
using CustomVector = Eigen::Matrix<Scalar, Eigen::Dynamic, 1>;

// Write a .mtx matrix file from mtx_path to a custom binary CSR format file at bin_path.
// Returns 0 on success, 1 on failure.
inline int write_binary_matrix(const std::string &mtx_path, const std::string &bin_path, CustomSparseMatrix &out_mat)
{
    std::ifstream f(mtx_path);
    if (!f)
    {
        std::cerr << "Cannot open MTX file: " << mtx_path << "\n";
        return 1;
    }
    fast_matrix_market::read_matrix_market_eigen(f, out_mat);

    out_mat.makeCompressed();

    std::ofstream out(bin_path, std::ios::binary);
    if (!out)
    {
        std::cerr << "Cannot create binary file: " << bin_path << "\n";
        return 1;
    }

    // Get matrix metadata
    StorageIndex rows = static_cast<StorageIndex>(out_mat.rows());
    StorageIndex cols = static_cast<StorageIndex>(out_mat.cols());
    StorageIndex nnz = static_cast<StorageIndex>(out_mat.nonZeros());

    // Write matrix metadata
    out.write(reinterpret_cast<const char *>(&rows), sizeof(StorageIndex));
    out.write(reinterpret_cast<const char *>(&cols), sizeof(StorageIndex));
    out.write(reinterpret_cast<const char *>(&nnz), sizeof(StorageIndex));

    // Write CSR data
    out.write(reinterpret_cast<const char *>(out_mat.outerIndexPtr()), sizeof(StorageIndex) * (rows + 1));
    out.write(reinterpret_cast<const char *>(out_mat.innerIndexPtr()), sizeof(StorageIndex) * nnz);
    out.write(reinterpret_cast<const char *>(out_mat.valuePtr()), sizeof(Scalar) * nnz);

    std::cout << "Matrix successfully converted: " << rows << "x" << cols
              << " with " << nnz << " non-zero entries." << std::endl;

    return 0;
}

// Load a custom binary CSR format matrix from bin_path and return it as CustomSparseMatrix. Optimize Linux first-touch NUMA policy if NUMA_optimize is true.
// NUMA_optimize=true only works as intended if the process calling this function has a NUMA policy that allocates memory locally (e.g., not interleaved,etc.)
inline CustomSparseMatrix load_binary_matrix(const std::string &bin_path, bool NUMA_optimize)
{
    // Potentially improve alignment as Eigen apparently only guarantees 16-byte (not 64) alignment, which sucks for AVX.
    std::ifstream in(bin_path, std::ios::binary);
    if (!in)
    {
        std::cerr << "Cannot open file: " << bin_path << "\n";
        exit(1);
    }

    StorageIndex rows, cols, nnz;
    in.read(reinterpret_cast<char *>(&rows), sizeof(StorageIndex));
    in.read(reinterpret_cast<char *>(&cols), sizeof(StorageIndex));
    in.read(reinterpret_cast<char *>(&nnz), sizeof(StorageIndex));

    CustomSparseMatrix A(rows, cols);
    A.resizeNonZeros(nnz);

    StorageIndex *outer = A.outerIndexPtr();
    StorageIndex *inner = A.innerIndexPtr();
    Scalar *vals = A.valuePtr();

    if (NUMA_optimize)
    {
#pragma omp parallel
        {
#pragma omp for schedule(static)
            for (StorageIndex i = 0; i <= rows; ++i)
            {
                outer[i] = 0;
            }

#pragma omp for schedule(static)
            for (StorageIndex i = 0; i < nnz; ++i)
            {
                inner[i] = 0;
                vals[i] = 0.0;
            }
        }
    }

    in.read(reinterpret_cast<char *>(outer), sizeof(StorageIndex) * (rows + 1));
    in.read(reinterpret_cast<char *>(inner), sizeof(StorageIndex) * nnz);
    in.read(reinterpret_cast<char *>(vals), sizeof(Scalar) * nnz);

    in.close();
    return A;
}