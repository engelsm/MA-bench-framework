/**
 * @brief Entry point for converting a Matrix Market file to a binary matrix file.
 *
 * Parses command-line arguments for input and output paths, initializes a
 * sparse matrix container, and invokes the binary write routine.
 *
 * @param argv Command-line arguments:
 *             - argv[1]: Path to input .mtx file
 *             - argv[2]: Path to output binary file
 * @return 0 on success, 1 if required arguments are missing.
 */

#include "util.hpp"
#include <iostream>
#include <string>
#include <iomanip>

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