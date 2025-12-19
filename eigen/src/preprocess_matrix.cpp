#include "util.h"
#include <iostream>
#include <string>

int main(int argc, char *argv[])
{
	if (argc < 3)
	{
		std::cerr << "Usage: " << argv[0] << " <input_mtx_path> <output_bin_path>" << std::endl;
		return 1;
	}

	std::string input_mtx = argv[1];
	std::string output_bin = argv[2];

	std::cout << "Starting conversion..." << std::endl;

	int status = write_binary_matrix(input_mtx, output_bin);

	if (status == 0)
	{
		std::cout << "Conversion finished successfully." << std::endl;
	}
	else
	{
		std::cerr << "Conversion failed!" << std::endl;
		return 1;
	}

	return 0;
}