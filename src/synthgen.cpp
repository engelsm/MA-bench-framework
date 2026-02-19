#include <iostream>
#include <vector>
#include <cstdlib>
#include <algorithm>
#include <ctime>
#include <cmath>
#include <random> // C++11 random for reproducibility

struct CSR_Matrix
{
	int N;
	int nnz;
	double *values;
	int *col_idx;
	int *row_ptr;
};

// Funktion zum Speichern der Matrix im Binärformat
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

	// Header schreiben: Rows, Cols, NNZ
	fwrite(&r, sizeof(int), 1, f);
	fwrite(&c, sizeof(int), 1, f);
	fwrite(&n, sizeof(int), 1, f);

	// CSR Komponenten schreiben
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
				  << " <dimension> <nnz_per_row> <random_factor> <output>\n";
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

	srand(42);

	std::vector<int> row_cols(nnz_per_row);
	std::vector<int> perm(N);

	// Use C++11 MT19937 for reproducible & thread-safe randomness
	// This ensures identical matrix structures across all hosts
	std::mt19937 rng(42);
	std::uniform_int_distribution<int> uniform_dist(0, N - 1);

	for (int i = 0; i < N; i++)
	{
		mtx.row_ptr[i] = i * nnz_per_row;

		// 1. Start with perfect band matrix
		int start = std::max(0, std::min(N - nnz_per_row, i - nnz_per_row / 2));
		for (int j = 0; j < nnz_per_row; j++)
			row_cols[j] = start + j;

		// 2. How many entries to randomize?
		int k = (int)std::round(random_factor * nnz_per_row);

		if (k > 0)
		{
			// Global permutation [0..N)
			for (int j = 0; j < N; j++)
				perm[j] = j;

			// Partial Fisher–Yates shuffle using MT19937
			for (int j = 0; j < k; j++)
			{
				int r = j + (uniform_dist(rng) % (N - j));
				std::swap(perm[j], perm[r]);
			}

			// Replace last k band entries with random columns
			for (int j = 0; j < k; j++)
				row_cols[nnz_per_row - 1 - j] = perm[j];
		}

		std::sort(row_cols.begin(), row_cols.end());

		for (int j = 0; j < nnz_per_row; j++)
		{
			int idx = i * nnz_per_row + j;
			mtx.values[idx] = 1.0;
			mtx.col_idx[idx] = row_cols[j];
		}
	}

	mtx.row_ptr[N] = mtx.nnz;

	save_to_custom_binary(output_file, &mtx);

	delete[] mtx.values;
	delete[] mtx.col_idx;
	delete[] mtx.row_ptr;

	return 0;
}