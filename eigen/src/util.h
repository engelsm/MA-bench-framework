#pragma once
#include <Eigen/Sparse>
#include <fstream>
#include <iostream>
#include <vector>

using Scalar = double;
using StorageIndex = int;
using CustomSparseMatrix = Eigen::SparseMatrix<Scalar, Eigen::RowMajor, StorageIndex>;
using CustomVector = Eigen::Matrix<Scalar, Eigen::Dynamic, 1>;

template <typename Scalar>
inline CustomSparseMatrix load_binary_matrix(const std::string &path)
{

    std::ifstream in(path, std::ios::binary);
    if (!in)
    {
        std::cerr << "Cannot open file: " << path << "\n";
        exit(1);
    }

    StorageIndex rows, cols, nnz;
    in.read(reinterpret_cast<char *>(&rows), sizeof(StorageIndex));
    in.read(reinterpret_cast<char *>(&cols), sizeof(StorageIndex));
    in.read(reinterpret_cast<char *>(&nnz), sizeof(StorageIndex));

    CustomSparseMatrix A(rows, cols);

    A.resizeNonZeros(nnz);

    // Now we read directly into the memory allocated by the Eigen matrix
    // This avoids the double-copy of using intermediate std::vectors
    in.read(reinterpret_cast<char *>(A.outerIndexPtr()), sizeof(StorageIndex) * (rows + 1));
    in.read(reinterpret_cast<char *>(A.innerIndexPtr()), sizeof(StorageIndex) * nnz);
    in.read(reinterpret_cast<char *>(A.valuePtr()), sizeof(Scalar) * nnz);

    in.close();

    return A;
}