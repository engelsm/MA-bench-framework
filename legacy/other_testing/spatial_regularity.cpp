#include <iostream>
#include <iomanip>
#include <algorithm>
#include <vector>
#include <cmath>
#include <numeric>
#include "util.hpp"

// Simple CLI interface to get some binary matrix statistics.
int main(int argc, char *argv[])
{
	if (argc < 2)
	{
		std::cerr << "Usage: " << argv[0] << " <matrix_file.bin>" << std::endl;
		return 1;
	}

	std::string filename = argv[1];

	CustomSparseMatrix A = load_binary_matrix(filename);
	double stressA = compute_l1_stress(A, 8);
	double stressB = compute_l3_stress(A, 1000000);
	// L3 cache is 32MiB
	double stressC = compute_x_ram_probability(A, 524288, 8); // 32 * 1024 * 1024 / 64

	std::cout << "FILE: " << filename << std::endl;
	std::cout << "DIM:  " << A.rows() << "x" << A.cols() << " (NNZ: " << A.nonZeros() << ")" << std::endl;
	std::cout << "REG:  " << std::fixed << std::setprecision(2)
			  << ", Stress-Rate=" << stressA << " : " << stressB << " : " << stressC << "%" << std::endl;

	return 0;
}