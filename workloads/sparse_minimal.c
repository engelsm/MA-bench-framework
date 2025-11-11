// sparse_minimal.c
#include <stdio.h>
#include <stdlib.h>

typedef struct {
    int row, col;
    double val;
} Entry;

int main(int argc, char *argv[]) {
    // --------------------------------------------------------------
    // Setup
    // --------------------------------------------------------------
    if (argc < 2) {
        fprintf(stderr, "Usage: %s matrix.mtx\n", argv[0]);
        return 1;
    }

    FILE *f = fopen(argv[1], "r");
    if (!f) {
        perror("Error opening file");
        return 1;
    }

    // skip comments
    char line[256];
    do {
        if (!fgets(line, sizeof(line), f)) {
            fprintf(stderr, "Invalid file\n");
            return 1;
        }
    } while (line[0] == '%');

    //.mtx files should contain header with matrix dimensions
    int nrows, ncols, nnz;
    if (sscanf(line, "%d %d %d", &nrows, &ncols, &nnz) != 3) {
        fprintf(stderr, "Invalid header\n");
        return 1;
    }

    Entry *A = malloc(sizeof(Entry) * nnz);
    for (int i = 0; i < nnz; i++) {
        if (fscanf(f, "%d %d %lf", &A[i].row, &A[i].col, &A[i].val) != 3) { //handle invalid lines to make compiler happy
            fprintf(stderr, "Error: invalid or incomplete line at entry %d\n", i);
            free(A);
            fclose(f);
            return 1;
        }
        A[i].row--;  // convert to 0-based indexing
        A[i].col--;
    }
    fclose(f);

    //vector y for multiplication
    double *y = calloc(nrows, sizeof(double));

    // --------------------------------------------------------------
    // Sparse matrix-vector multiplication
    // --------------------------------------------------------------

    // Multiply by vector of 1's: y = A * 1
    for (int i = 0; i < nnz; i++) {
        y[A[i].row] += A[i].val;
    }
    // --------------------------------------------------------------
    // Result verification and cleanup
    // --------------------------------------------------------------

    // Print checksum (sum of results)
    double checksum = 0.0;
    for (int i = 0; i < nrows; i++) checksum += y[i];

    printf("Checksum: %.6f\n", checksum);

    free(A);
    free(y);
    return 0;
}