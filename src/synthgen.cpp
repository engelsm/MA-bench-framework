/**
 * @brief Generates a synthetic CSR matrix with banded structure and optional random column perturbations,
 *        then writes it to a custom binary file.
 *
 * @param argv The array of command-line argument strings:
 *             argv[1] = matrix dimension (N),
 *             argv[2] = nonzeros per row,
 *             argv[3] = randomization factor,
 *             argv[4] = optional output file path.
 *
 * @return 0 on success; nonzero if the arguments are invalid or matrix generation fails validation.
 */
#include <iostream>
#include <vector>
#include <cstdlib>
#include <algorithm>
#include <ctime>
#include <cmath>
#include <random>
#include <omp.h>
#include <cstdio>

struct CSR_Matrix
{
	int N;
	int nnz;
	double *values;
	int *col_idx;
	int *row_ptr;
};

void save_to_custom_binary(const char *filename, struct CSR_Matrix *M)
{
	FILE *f = fopen(filename, "wb");
	if (!f)
	{
		perror("Failed to open output file");
		exit(1);
	}

	int r = M->N;
	int c = M->N;
	int n = M->nnz;

	fwrite(&r, sizeof(int), 1, f);
	fwrite(&c, sizeof(int), 1, f);
	fwrite(&n, sizeof(int), 1, f);

	fwrite(M->row_ptr, sizeof(int), r + 1, f);
	fwrite(M->col_idx, sizeof(int), n, f);
	fwrite(M->values, sizeof(double), n, f);

	fclose(f);
	std::cout << "Successfully saved to " << filename << std::endl;
}

int main(int argc, char **argv)
{
	if (argc < 4)
	{
		std::cerr << "Usage: " << argv[0]
				  << " <dimension> <nnz_per_row> <random_factor> [output_file]\n";
		return 1;
	}

	int N = atoi(argv[1]);
	int nnz_per_row = atoi(argv[2]);
	double random_factor = atof(argv[3]);
	const char *output_file = (argc >= 5) ? argv[4] : "generated_matrix.bin";

	if (N < nnz_per_row)
	{
		std::cerr << "ERROR: N must be >= nnz_per_row\n";
		return 1;
	}

	CSR_Matrix mtx;
	mtx.N = N;
	mtx.nnz = N * nnz_per_row;
	mtx.values = new double[mtx.nnz];
	mtx.col_idx = new int[mtx.nnz];
	mtx.row_ptr = new int[N + 1];

	std::cout << "Generating matrix (N=" << N << ", nnz=" << mtx.nnz << ")..." << std::endl;

	// Pre-calculate row pointers (O(N) serial is fine)
	for (int i = 0; i <= N; i++)
	{
		mtx.row_ptr[i] = i * nnz_per_row;
	}

// Parallel generation of rows
#pragma omp parallel
	{
		// Thread-local resources: allocated ONCE per thread
		int tid = omp_get_thread_num();
		std::mt19937 rng(42 + tid);
		std::uniform_int_distribution<int> dist(0, N - 1);
		std::vector<int> current_row_cols(nnz_per_row);

#pragma omp for schedule(static)
		for (int i = 0; i < N; i++)
		{
			// 1. Create a base band matrix structure
			// Center the band around the diagonal where possible
			int start = std::max(0, std::min(N - nnz_per_row, i - nnz_per_row / 2));
			for (int j = 0; j < nnz_per_row; j++)
			{
				current_row_cols[j] = start + j;
			}

			// 2. Randomize entries based on random_factor
			int k = (int)std::round(random_factor * nnz_per_row);
			if (k > 0)
			{
				// Replace the last k entries of the band with random column indices
				for (int j = 0; j < k; j++)
				{
					current_row_cols[nnz_per_row - 1 - j] = dist(rng);
				}
			}

			// 3. CSR requires column indices to be sorted within each row
			std::sort(current_row_cols.begin(), current_row_cols.end());

			// 4. Copy to global arrays
			for (int j = 0; j < nnz_per_row; j++)
			{
				int global_idx = i * nnz_per_row + j;
				mtx.col_idx[global_idx] = current_row_cols[j];
				mtx.values[global_idx] = 1.0; // Standard weight
			}
		}
	}

	save_to_custom_binary(output_file, &mtx);

	// Cleanup
	delete[] mtx.values;
	delete[] mtx.col_idx;
	delete[] mtx.row_ptr;

	return 0;
}