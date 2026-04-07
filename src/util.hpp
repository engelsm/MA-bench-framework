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

// Load a custom binary CSR format matrix from bin_path and return it as CustomSparseMatrix.
inline CustomSparseMatrix load_binary_matrix(const std::string &bin_path)
{
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

    in.read(reinterpret_cast<char *>(outer), sizeof(StorageIndex) * (rows + 1));
    in.read(reinterpret_cast<char *>(inner), sizeof(StorageIndex) * nnz);
    in.read(reinterpret_cast<char *>(vals), sizeof(Scalar) * nnz);

    in.close();
    return A;
}

/**
 * Perform Sparse Matrix-Vector Multiplication (SpMV) using CSR format.
 * https://en.wikipedia.org/wiki/Sparse_matrix#Compressed_sparse_row_(CSR,_CRS_or_Yale_format)
 */
inline void spmv_csr(int rows, const int *row_ptr, const int *col_idx, const Scalar *values, const CustomVector &x, CustomVector &y)
{
#pragma omp parallel for schedule(static)
    for (int i = 0; i < rows; i++)
    {
        Scalar sum = 0;
        for (int j = row_ptr[i]; j < row_ptr[i + 1]; j++)
            sum += values[j] * x[col_idx[j]];
        y[i] = sum;
    }
}

inline double calculate_gflops(long long nnz, double seconds)
{
    if (seconds <= 0)
        return 0;
    return (2.0 * nnz) / (seconds * 1e9);
}