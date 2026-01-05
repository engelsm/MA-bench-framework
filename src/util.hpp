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

    in.read(reinterpret_cast<char *>(A.outerIndexPtr()), sizeof(StorageIndex) * (rows + 1));
    in.read(reinterpret_cast<char *>(A.innerIndexPtr()), sizeof(StorageIndex) * nnz);
    in.read(reinterpret_cast<char *>(A.valuePtr()), sizeof(Scalar) * nnz);

    in.close();
    return A;
}

/**
 * Analyzes the structural regularity of a sparse matrix in CSR format.
 * (This is not to be confused with numerical regularity.)
 * Focuses on the column index jumps which determine the cache efficiency
 * of the vector x during SpMV (y = Ax). A is stored consecutively in memory,
 * but the access pattern to x depends on the column indices of A.
 * Even though consecutive values might trigger additional cache loads, they are not
 * counted as stress-inducing jumps, because the hardware prefetcher can
 * handle them efficiently.
 */
inline double compute_regularity(const CustomSparseMatrix &A, int elements_per_cache_line = 8)
{
    std::vector<StorageIndex> all_jumps;
    all_jumps.reserve(A.nonZeros());

    const StorageIndex *outer = A.outerIndexPtr();
    const StorageIndex *inner = A.innerIndexPtr();

    long long stress_count = 0;
    long long total_jumps = 0;

    for (StorageIndex i = 0; i < A.rows(); ++i)
    {
        StorageIndex row_start = outer[i];
        StorageIndex row_end = outer[i + 1];

        // We need at least two elements in a row to calculate a jump distance.
        for (StorageIndex j = row_start; j < row_end - 1; ++j)
        {
            // Calculate absolute distance between consecutive column indices.
            StorageIndex jump = std::abs(inner[j + 1] - inner[j]);
            all_jumps.push_back(jump);

            // If the jump exceeds the cache line capacity,
            // the access of vector x at that position is likely to cause a cache miss.
            if (jump > elements_per_cache_line)
                stress_count++;

            total_jumps++;
        }
    }

    double stress_rate = (total_jumps > 0) ? (static_cast<double>(stress_count) / total_jumps * 100.0) : 0.0;
    return stress_rate;
}

struct MtxFlags
{
    std::string field, symmetry;
};

inline MtxFlags get_mtx_flags(const std::string &mtx_path)
{
    std::ifstream f(mtx_path);
    fast_matrix_market::matrix_market_header header;
    fast_matrix_market::read_header(f, header);

    return {
        fast_matrix_market::field_map.at(header.field),
        fast_matrix_market::symmetry_map.at(header.symmetry)};
}

inline void save_matrix_metadata(const std::string &csv_path, const std::string &bin_path,
                                 const MtxFlags &f, int r, int c, int n, double stress)
{
    bool is_new = !std::filesystem::exists(csv_path);
    std::ofstream csv(csv_path, std::ios::app);

    if (is_new)
        csv << "matrix,rows,cols,nnz,size_mb,stress_pct,field,symmetry\n";

    double mb = (double)std::filesystem::file_size(bin_path) / (1024.0 * 1024.0);

    csv << std::filesystem::path(bin_path).stem().string() << ","
        << r << "," << c << "," << n << "," << mb << "," << stress << ","
        << f.field << "," << f.symmetry << "\n";
}