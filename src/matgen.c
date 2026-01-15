#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "artificial_matrix_generation.h"

/**
 * Converts CSR to symmetric by mirroring entries (i, j) -> (j, i).
 */
struct csr_matrix *make_symmetric(struct csr_matrix *M)
{
	if (!M)
		return NULL;

	// Use COO as intermediate step; worst case doubles NNZ
	unsigned int max_nnz = M->nr_nzeros * 2;
	int *rows = malloc(max_nnz * sizeof(int));
	int *cols = malloc(max_nnz * sizeof(int));
	double *vals = malloc(max_nnz * sizeof(double));

	if (!rows || !cols || !vals)
	{
		fprintf(stderr, "Allocation failed during symmetrization\n");
		exit(1);
	}

	unsigned int current_nnz = 0;
	for (int i = 0; i < (int)M->nr_rows; i++)
	{
		for (int j = M->row_ptr[i]; j < M->row_ptr[i + 1]; j++)
		{
			int col = M->col_ind[j];
			double val = M->values[j];

			rows[current_nnz] = i;
			cols[current_nnz] = col;
			vals[current_nnz] = val;
			current_nnz++;

			// Mirror non-diagonal entries
			if (i != col)
			{
				rows[current_nnz] = col;
				cols[current_nnz] = i;
				vals[current_nnz] = val;
				current_nnz++;
			}
		}
	}

	struct csr_matrix *symM = malloc(sizeof(struct csr_matrix));
	symM->nr_rows = M->nr_rows;
	symM->nr_cols = M->nr_cols;
	symM->nr_nzeros = current_nnz;
	symM->row_ptr = calloc(M->nr_rows + 1, sizeof(int));
	symM->col_ind = malloc(current_nnz * sizeof(int));
	symM->values = malloc(current_nnz * sizeof(double));

	// Convert COO back to CSR
	for (unsigned int i = 0; i < current_nnz; i++)
	{
		symM->row_ptr[rows[i] + 1]++;
	}
	for (int i = 0; i < (int)symM->nr_rows; i++)
	{
		symM->row_ptr[i + 1] += symM->row_ptr[i];
	}

	int *temp_ptr = malloc((M->nr_rows + 1) * sizeof(int));
	memcpy(temp_ptr, symM->row_ptr, (M->nr_rows + 1) * sizeof(int));

	for (unsigned int i = 0; i < current_nnz; i++)
	{
		int r = rows[i];
		int dest = temp_ptr[r]++;
		symM->col_ind[dest] = cols[i];
		symM->values[dest] = vals[i];
	}

	free(rows);
	free(cols);
	free(vals);
	free(temp_ptr);
	return symM;
}

void save_to_custom_binary(const char *filename, struct csr_matrix *M)
{
	FILE *f = fopen(filename, "wb");
	if (!f)
	{
		perror("Failed to open output file");
		exit(1);
	}

	int r = (int)M->nr_rows;
	int c = (int)M->nr_cols;
	int n = (int)M->nr_nzeros;

	// Write header: rows, cols, nnz
	fwrite(&r, sizeof(int), 1, f);
	fwrite(&c, sizeof(int), 1, f);
	fwrite(&n, sizeof(int), 1, f);

	// Write CSR components
	fwrite(M->row_ptr, sizeof(int), r + 1, f);
	fwrite(M->col_ind, sizeof(int), n, f);
	fwrite(M->values, sizeof(double), n, f);

	fclose(f);
}

/**
 * Generates an exact band matrix with k subdiagonals.
 */
struct csr_matrix *generate_perfect_band(int n, int k)
{
	struct csr_matrix *M = malloc(sizeof(struct csr_matrix));
	M->nr_rows = n;
	M->nr_cols = n;

	// Count total NNZ for the requested bandwidth
	unsigned int total_nnz = 0;
	for (int i = 0; i < n; i++)
	{
		for (int j = i - k; j <= i + k; j++)
		{
			if (j >= 0 && j < n)
				total_nnz++;
		}
	}

	M->nr_nzeros = total_nnz;
	M->row_ptr = calloc(n + 1, sizeof(int));
	M->col_ind = malloc(total_nnz * sizeof(int));
	M->values = malloc(total_nnz * sizeof(double));

	unsigned int current = 0;
	for (int i = 0; i < n; i++)
	{
		M->row_ptr[i] = current;
		for (int j = i - k; j <= i + k; j++)
		{
			if (j >= 0 && j < n)
			{
				M->col_ind[current] = j;
				M->values[current] = 1.0;
				current++;
			}
		}
	}
	M->row_ptr[n] = current;
	return M;
}

int main(int argc, char **argv)
{
	if (argc < 13)
	{
		printf("Usage: %s <n> <avg_nnz> <std_nnz> <dist> <seed> <placement> <bw> <skew> <neighbors> <sim> <symmetric> <out_file>\n", argv[0]);
		return 1;
	}

	long n = atol(argv[1]);
	char *placement = argv[6];
	double bw = atof(argv[7]);
	const char *path = argv[12];

	struct csr_matrix *M = NULL;

	// Deterministic band vs stochastic generation
	if (strcmp(placement, "perfect") == 0)
	{
		int k = (int)(bw * n + 0.5); // Round to nearest k
		if (k < 1)
			k = 1;
		printf("Generating perfect band (k=%d)...\n", k);
		M = generate_perfect_band(n, k);
	}
	else
	{
		M = artificial_matrix_generation(n, n, atof(argv[2]), atof(argv[3]),
										 argv[4], atoi(argv[5]), placement, bw, atof(argv[8]),
										 atof(argv[9]), atof(argv[10]));
	}

	if (M)
	{
		// Symmetrization logic (skip if 'perfect' as its symmetric by design)
		if (atoi(argv[11]) && strcmp(placement, "perfect") != 0)
		{
			struct csr_matrix *symM = make_symmetric(M);
			free_csr_matrix(M);
			M = symM;
		}

		save_to_custom_binary(path, M);
		printf("Success: %s | NNZ: %u\n", path, M->nr_nzeros);
		free_csr_matrix(M);
	}

	return 0;
}