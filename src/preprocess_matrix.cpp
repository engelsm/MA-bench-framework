#include "util.hpp"
#include <iostream>
#include <string>
#include <iomanip>

/**
 * Matrix Preprocessing Tool
 * This tool converts Matrix Market (.mtx) files into a custom
 * binary CSR format and writes matrix metadata to a CSV file.
 */

int main(int argc, char *argv[])
{
	if (argc < 3)
	{
		std::cerr << "Usage: " << argv[0] << " <input_mtx_path> <output_bin_path>" << std::endl;
		return 1;
	}

	std::string input_mtx = argv[1];
	std::string output_bin = argv[2];
	CustomSparseMatrix A;

	write_binary_matrix(input_mtx, output_bin, A);

	return 0;
}