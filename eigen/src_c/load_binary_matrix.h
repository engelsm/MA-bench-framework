#pragma once
#include <Eigen/Sparse>
#include <fstream>
#include <iostream>
#include <vector>

using namespace Eigen;

inline SparseMatrix<double> load_binary_matrix(const std::string& path)
{
    std::ifstream in(path, std::ios::binary);
    if(!in)
    {
        std::cerr << "Cannot open file: " << path << "\n";
        exit(1);
    }

    int rows, cols, nnz;
    in.read(reinterpret_cast<char*>(&rows), sizeof(int));
    in.read(reinterpret_cast<char*>(&cols), sizeof(int));
    in.read(reinterpret_cast<char*>(&nnz), sizeof(int));

    std::vector<int> outer(cols+1);
    std::vector<int> inner(nnz);
    std::vector<double> values(nnz);

    in.read(reinterpret_cast<char*>(outer.data()), sizeof(int)*(cols+1));
    in.read(reinterpret_cast<char*>(inner.data()), sizeof(int)*nnz);
    in.read(reinterpret_cast<char*>(values.data()), sizeof(double)*nnz);
    in.close();

    SparseMatrix<double> A(rows, cols);
    A.reserve(nnz);
    std::memcpy(A.outerIndexPtr(), outer.data(), sizeof(int)*(cols+1));
    std::memcpy(A.innerIndexPtr(), inner.data(), sizeof(int)*nnz);
    std::memcpy(A.valuePtr(), values.data(), sizeof(double)*nnz);
    A.finalize(); // fix internal pointers

    return A;
}
