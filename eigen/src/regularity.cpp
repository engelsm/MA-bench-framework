#include <iostream>
#include <iomanip>
#include <algorithm>
#include <vector>
#include <cmath>
#include "util.h"

struct RegularityMetrics
{
	double median_jump;
	double stress_rate;
};

/**
 * Analyzes the structural regularity of a sparse matrix in CSR format.
 * Focuses on the column index jumps which determine the cache efficiency
 * of the vector x during SpMV (y = Ax). A is stored consecutively in memory,
 * but the access pattern to x depends on the column indices of A.
 */
RegularityMetrics compute_regularity(const CustomSparseMatrix &A, int elements_per_cache_line = 8)
{
	std::vector<StorageIndex> all_jumps;
	all_jumps.reserve(A.nonZeros());

	const StorageIndex *outer = A.outerIndexPtr();
	const StorageIndex *inner = A.innerIndexPtr();

	long long stress_count = 0;
	long long total_jumps = 0;

	for (StorageIndex i = 0; i < A.rows(); ++i)
	{
		StorageIndex row_start = outer[i];
		StorageIndex row_end = outer[i + 1];

		// We need at least two elements in a row to calculate a jump distance.
		for (StorageIndex j = row_start; j < row_end - 1; ++j)
		{
			// Calculate absolute distance between consecutive column indices.
			StorageIndex jump = std::abs(inner[j + 1] - inner[j]);
			all_jumps.push_back(jump);

			// If the jump exceeds the cache line capacity,
			// the access of vector x at that position is likely to cause a cache miss.
			if (jump > elements_per_cache_line)
				stress_count++;

			total_jumps++;
		}
	}

	// Compute median of all jumps.
	double median = 0;
	if (!all_jumps.empty())
	{
		std::sort(all_jumps.begin(), all_jumps.end());
		size_t size = all_jumps.size();
		if (size % 2 == 0)
			median = (all_jumps[size / 2 - 1] + all_jumps[size / 2]) / 2.0;
		else
			median = all_jumps[size / 2];
	}

	// Stress rate: percentage of jumps that likely cause cache misses.
	double stress_rate = (total_jumps > 0) ? (static_cast<double>(stress_count) / total_jumps * 100.0) : 0.0;

	return {median, stress_rate};
}

int main(int argc, char *argv[])
{
	if (argc < 2)
	{
		std::cerr << "Usage: " << argv[0] << " <matrix_file.dat>" << std::endl;
		return 1;
	}

	// Equivalent to 64 Bytes cache line / 8 Bytes double = 8 elements.
	int cache_threshold = 8;

	std::string filename = argv[1];

	CustomSparseMatrix A = load_binary_matrix(filename);
	RegularityMetrics reg = compute_regularity(A, cache_threshold);

	std::cout << "FILE: " << filename << std::endl;
	std::cout << "DIM:  " << A.rows() << "x" << A.cols() << " (NNZ: " << A.nonZeros() << ")" << std::endl;
	std::cout << "THRES: " << cache_threshold << " elements" << std::endl;
	std::cout << "REG:  MedianJump=" << reg.median_jump
			  << ", SME-Stress-Rate=" << std::fixed << std::setprecision(2) << reg.stress_rate << "%" << std::endl;

	return 0;
}