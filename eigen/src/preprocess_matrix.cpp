#include <iostream>
#include <fstream>
#include <Eigen/Sparse>
#include <fast_matrix_market/app/Eigen.hpp>
#include "util.h"

int main(int argc, char **argv)
{

	if (argc < 3)
	{
		std::cerr << "Usage: " << argv[0] << " <input.mtx> <output.dat>" << std::endl;
		return 1;
	}

	CustomSparseMatrix A;

	// Load MatrixMarket file, symmetry is handled automatically by default settings
	std::ifstream f(argv[1]);
	fast_matrix_market::read_matrix_market_eigen(f, A);

	// Compress the matrix to ensure CSR format
	A.makeCompressed();

	std::ofstream out(argv[2], std::ios::binary);

	StorageIndex rows = (StorageIndex)A.rows();
	StorageIndex cols = (StorageIndex)A.cols();
	StorageIndex nnz = (StorageIndex)A.nonZeros();

	// Write Header
	out.write((char *)&rows, sizeof(StorageIndex));
	out.write((char *)&cols, sizeof(StorageIndex));
	out.write((char *)&nnz, sizeof(StorageIndex));

	// Write CSR Data
	// outerIndexPtr: Start/End indices of each row (Size: rows + 1)
	out.write((char *)A.outerIndexPtr(), sizeof(StorageIndex) * (rows + 1));
	// innerIndexPtr: Column indices for each non-zero element (Size: nnz)
	out.write((char *)A.innerIndexPtr(), sizeof(StorageIndex) * nnz);
	// valuePtr: The actual numerical values (Size: nnz)
	out.write((char *)A.valuePtr(), sizeof(Scalar) * nnz);

	std::cout << "Matrix successfully converted: " << rows << "x" << cols
			  << " with " << nnz << " non-zero entries." << std::endl;

	// Verification: In RowMajor format, innerIndexPtr refers to COLUMNS
	std::cout << "\nFirst 5 entries (Values and their corresponding columns):" << std::endl;
	for (int i = 0; i < 5 && i < A.nonZeros(); ++i)
	{
		std::cout << "Val: " << A.valuePtr()[i] << " | Col: " << A.innerIndexPtr()[i] << std::endl;
	}

	return 0;
}