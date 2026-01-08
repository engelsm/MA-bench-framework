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
	const std::string metadata_csv = "/home/mengelsl/MA-bench-framework/matrices/matrix_metadata.csv"; // hardcoded for now
	MtxFlags mtx_flags = get_mtx_flags(input_mtx);

	CustomSparseMatrix A;
	write_mtx_to_bin(input_mtx, output_bin, A);

	double reg = compute_regularity(A, 8);

	save_matrix_metadata(metadata_csv,
						 output_bin,
						 mtx_flags,
						 A.rows(),
						 A.cols(),
						 A.nonZeros(), // This counts explicitly stored zeros as well
						 reg);
	return 0;
}