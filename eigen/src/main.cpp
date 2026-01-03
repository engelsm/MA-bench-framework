#include "solvers.hpp"
#include <iostream>
#include <string>

int main(int argc, char *argv[])
{
	if (argc < 3)
	{
		std::cerr << "Usage: " << argv[0] << " <matrix.bin> <algo>" << std::endl;
		return 1;
	}

	std::string bin_path = argv[1];
	std::string algo = argv[2];

	CustomSparseMatrix A = load_binary_matrix(bin_path);

	if (algo == "power")
	{
		Scalar lambda = power_iteration(A, 100);
		std::cout << "\nLambda " << lambda << std::endl;
	}

	return 0;
}