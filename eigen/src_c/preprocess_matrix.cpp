#include <Eigen/Sparse>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>

using namespace Eigen;

SparseMatrix<double> load_mtx(const std::string& path)
{
    std::ifstream f(path);
    if(!f)
    {
        std::cerr << "Cannot open file: " << path << "\n";
        exit(1);
    }

    int rows, cols, nnz;
    std::string line;

    while (std::getline(f, line))
        if (line[0] != '%') break;

    std::stringstream(line) >> rows >> cols >> nnz;

    SparseMatrix<double> A(rows, cols);
    A.reserve(nnz);

    int i, j;
    double v;
    while(f >> i >> j >> v)
        A.insert(i-1, j-1) = v;

    A.makeCompressed();
    return A;
}

void save_compressed(const SparseMatrix<double>& A, const std::string& path)
{
    std::ofstream out(path, std::ios::binary);
    if(!out)
    {
        std::cerr << "Cannot open output file: " << path << "\n";
        exit(1);
    }

    int rows = A.rows();
    int cols = A.cols();
    int nnz  = A.nonZeros();

    out.write(reinterpret_cast<char*>(&rows), sizeof(int));
    out.write(reinterpret_cast<char*>(&cols), sizeof(int));
    out.write(reinterpret_cast<char*>(&nnz), sizeof(int));

    out.write(reinterpret_cast<const char*>(A.outerIndexPtr()), sizeof(int)*(A.outerSize()+1));
    out.write(reinterpret_cast<const char*>(A.innerIndexPtr()), sizeof(int)*nnz);
    out.write(reinterpret_cast<const char*>(A.valuePtr()), sizeof(double)*nnz);

    out.close();
    std::cout << "Saved compressed matrix to " << path << "\n";
}

int main(int argc, char** argv)
{
    if(argc != 3)
    {
        std::cerr << "Usage: preprocess_matrix <matrix.mtx> <output_binary.dat>\n";
        return 1;
    }

    auto A = load_mtx(argv[1]);
    save_compressed(A, argv[2]);

    return 0;
}
