#include <stdio.h>
#include <stdlib.h>
#include "artificial_matrix_generation.h"

void save_to_custom_binary(const char *filename, struct csr_matrix *M)
{
	FILE *f = fopen(filename, "wb");
	if (!f)
	{
		perror("Fehler beim Oeffnen");
		exit(1);
	}

	int r = (int)M->nr_rows;
	int c = (int)M->nr_cols;
	int n = (int)M->nr_nzeros;

	fwrite(&r, sizeof(int), 1, f);
	fwrite(&c, sizeof(int), 1, f);
	fwrite(&n, sizeof(int), 1, f);

	fwrite(M->row_ptr, sizeof(int), r + 1, f);
	fwrite(M->col_ind, sizeof(int), n, f);
	fwrite(M->values, sizeof(double), n, f);

	fclose(f);
}

int main(int argc, char **argv)
{
	if (argc < 11)
	{
		printf("Usage: %s <size> <nnz_row> <bw> <skew> <neighbors> <sim> <placement> <dist> <seed> <out_file>\n", argv[0]);
		printf("Placements: diagonal, random\n");
		printf("Distributions: normal, uniform\n");
		return 1;
	}

	long n = atol(argv[1]);
	double nnz_row = atof(argv[2]);
	double bw = atof(argv[3]);
	double skew = atof(argv[4]);
	double neighbors = atof(argv[5]);
	double sim = atof(argv[6]);
	char *placement = argv[7];
	char *dist = argv[8];
	int seed = atoi(argv[9]);
	const char *path = argv[10];

	struct csr_matrix *M = artificial_matrix_generation(
		n, n, nnz_row, 1.0,
		dist,
		seed,
		placement,
		bw, skew, neighbors, sim);

	if (M)
	{
		save_to_custom_binary(path, M);
		printf("Erfolg: %s | NNZ: %u | BW: %.2f | Skew: %.2f\n", path, M->nr_nzeros, bw, skew);
		free_csr_matrix(M);
	}

	return 0;
}