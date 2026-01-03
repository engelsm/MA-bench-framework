#pragma once
#include <Eigen/Sparse>
#include <fstream>
#include <iostream>
#include <vector>
#include <fast_matrix_market/app/Eigen.hpp>

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
inline int write_binary_matrix(const std::string &mtx_path, const std::string &bin_path)
{
    CustomSparseMatrix A;
    std::ifstream f(mtx_path);
    if (!f)
    {
        std::cerr << "Cannot open MTX file: " << mtx_path << "\n";
        return 1;
    }
    fast_matrix_market::read_matrix_market_eigen(f, A);

    A.makeCompressed();

    std::ofstream out(bin_path, std::ios::binary);
    if (!out)
    {
        std::cerr << "Cannot create binary file: " << bin_path << "\n";
        return 1;
    }

    // Get matrix metadata
    StorageIndex rows = static_cast<StorageIndex>(A.rows());
    StorageIndex cols = static_cast<StorageIndex>(A.cols());
    StorageIndex nnz = static_cast<StorageIndex>(A.nonZeros());

    // Write matrix metadata
    out.write(reinterpret_cast<const char *>(&rows), sizeof(StorageIndex));
    out.write(reinterpret_cast<const char *>(&cols), sizeof(StorageIndex));
    out.write(reinterpret_cast<const char *>(&nnz), sizeof(StorageIndex));

    // Write CSR data
    // outerIndexPtr() points at the row pointer array for CSR
    out.write(reinterpret_cast<const char *>(A.outerIndexPtr()), sizeof(StorageIndex) * (rows + 1));
    // innerIndexPtr() points at the column indices array for CSR
    out.write(reinterpret_cast<const char *>(A.innerIndexPtr()), sizeof(StorageIndex) * nnz);
    // valuePtr() points at the values array
    out.write(reinterpret_cast<const char *>(A.valuePtr()), sizeof(Scalar) * nnz);

    std::cout << "Matrix successfully converted: " << rows << "x" << cols
              << " with " << nnz << " non-zero entries." << std::endl;

    return 0;
}

// Load a custom binary CSR format matrix from bin_path and return it as CustomSparseMatrix.
inline CustomSparseMatrix load_binary_matrix(const std::string &bin_path)
{
    // This data stream reads and contains the matrix in a simple binary format.
    std::ifstream in(bin_path, std::ios::binary);
    if (!in)
    {
        std::cerr << "Cannot open file: " << bin_path << "\n";
        exit(1);
    }

    StorageIndex rows, cols, nnz;
    // Read matrix metadata and store in variables.
    in.read(reinterpret_cast<char *>(&rows), sizeof(StorageIndex));
    in.read(reinterpret_cast<char *>(&cols), sizeof(StorageIndex));
    in.read(reinterpret_cast<char *>(&nnz), sizeof(StorageIndex));

    CustomSparseMatrix A(rows, cols);

    // This is an internal (does not appear in official docs) Eigen function that allocates
    // the necessary memory for the sparse matrix. We need this as we directly write binary data
    // into the matrix buffers instead of using the Eigen interface.
    A.resizeNonZeros(nnz);

    // Read CSR data and write into matrix A.
    in.read(reinterpret_cast<char *>(A.outerIndexPtr()), sizeof(StorageIndex) * (rows + 1));
    in.read(reinterpret_cast<char *>(A.innerIndexPtr()), sizeof(StorageIndex) * nnz);
    in.read(reinterpret_cast<char *>(A.valuePtr()), sizeof(Scalar) * nnz);

    in.close();

    return A;
}

// Perform a parallel sparse matrix-vector multiplication y = A * x using OpenMP.
// This can be optimized further, but for the purpose of analysis it is sufficient.
inline void spmv(const CustomSparseMatrix &A, const CustomVector &x, CustomVector &y)
{
    const StorageIndex *row_ptr = A.outerIndexPtr();
    const StorageIndex *col_idx = A.innerIndexPtr();
    const Scalar *values = A.valuePtr();
    const int rows = A.rows();

#pragma omp parallel for schedule(static)
    for (int i = 0; i < rows; ++i)
    {
        Scalar sum = 0;
        for (StorageIndex k = row_ptr[i]; k < row_ptr[i + 1]; ++k)
        {
            sum += values[k] * x(col_idx[k]);
        }
        y(i) = sum;
    }
}