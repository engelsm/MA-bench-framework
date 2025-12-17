#include <iostream>
#include <fstream>
#include <Eigen/Sparse>
#include <fast_matrix_market/app/Eigen.hpp>

using namespace Eigen;

int main(int argc, char **argv)
{
	if (argc < 3)
	{
		std::cerr << "Usage: " << argv[0] << " <input.mtx> <output.dat>" << std::endl;
		return 1;
	}

	SparseMatrix<double> A;

	std::ifstream f(argv[1]);
	fast_matrix_market::read_matrix_market_eigen(f, A);

	A.makeCompressed();

	std::ofstream out(argv[2], std::ios::binary);
	int rows = A.rows();
	int cols = A.cols();
	int nnz = A.nonZeros();

	out.write((char *)&rows, sizeof(int));
	out.write((char *)&cols, sizeof(int));
	out.write((char *)&nnz, sizeof(int));

	out.write((char *)A.outerIndexPtr(), sizeof(int) * (cols + 1));
	out.write((char *)A.innerIndexPtr(), sizeof(int) * nnz);
	out.write((char *)A.valuePtr(), sizeof(double) * nnz);

	// For verification, print first 5 non-zero entries
	for (int i = 0; i < 5 && i < A.nonZeros(); ++i)
	{
		std::cout << "Val: " << A.valuePtr()[i]
				  << " | Row: " << A.innerIndexPtr()[i] << std::endl;
	}
	return 0;
}