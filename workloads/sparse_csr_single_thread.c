
#include <stdio.h>
#include <stdlib.h>
#include <omp.h>

typedef struct {
    int row, col;
    double val;
} Entry;

int cmp_entries(const void *a, const void *b) {
    const Entry *ea = a, *eb = b;
    if (ea->row != eb->row) return ea->row - eb->row;
    return ea->col - eb->col;
}

int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s matrix.mtx\n", argv[0]);
        return 1;
    }

    // --------------------------------------------------------------
    // Read .mtx (COO format)
    // --------------------------------------------------------------

    FILE *f = fopen(argv[1], "r");
    if (!f) { perror("Error opening file"); return 1; }

    char line[256];
    do {
        if (!fgets(line, sizeof(line), f)) {
            fprintf(stderr, "Invalid file\n");
            return 1;
        }
    } while (line[0] == '%');

    int nrows, ncols, nnz;
    if (sscanf(line, "%d %d %d", &nrows, &ncols, &nnz) != 3) {
        fprintf(stderr, "Invalid header\n"); return 1;
    }

    Entry *coo = malloc(sizeof(Entry) * nnz);

    for (int i = 0; i < nnz; i++) {
        if (fscanf(f, "%d %d %lf", &coo[i].row, &coo[i].col, &coo[i].val) != 3) {
            fprintf(stderr, "Invalid line at entry %d\n", i);
            return 1;
        }
        coo[i].row--;
        coo[i].col--;
    }
    fclose(f);

    // --------------------------------------------------------------
    // Convert COO → CSR
    // --------------------------------------------------------------

    // sort by row (and col)
    qsort(coo, nnz, sizeof(Entry), cmp_entries);

    int *rowptr = calloc(nrows + 1, sizeof(int));
    int *colidx = malloc(nnz * sizeof(int));
    double *vals = malloc(nnz * sizeof(double));

    // count entries per row
    for (int i = 0; i < nnz; i++)
        rowptr[coo[i].row + 1]++;

    // prefix sum -> rowptr
    for (int r = 0; r < nrows; r++)
        rowptr[r + 1] += rowptr[r];

    // fill CSR arrays
    int *offset = calloc(nrows, sizeof(int));
    for (int i = 0; i < nnz; i++) {
        int r = coo[i].row;
        int dst = rowptr[r] + offset[r]++;
        colidx[dst] = coo[i].col;
        vals[dst] = coo[i].val;
    }

    free(offset);
    free(coo);

    // --------------------------------------------------------------
    // Allocate output vector
    // --------------------------------------------------------------

    double *y = calloc(nrows, sizeof(double));

    // --------------------------------------------------------------
    // Parallel CSR SpMV: y = A * 1
    // --------------------------------------------------------------

    #pragma omp parallel for schedule(static)
    for (int r = 0; r < nrows; r++) {
        double sum = 0.0;
        for (int idx = rowptr[r]; idx < rowptr[r+1]; idx++) {
            sum += vals[idx];   // val * 1
        }
        y[r] = sum;
    }

    // --------------------------------------------------------------
    // Checksum
    // --------------------------------------------------------------

    double checksum = 0.0;
    for (int i = 0; i < nrows; i++)
        checksum += y[i];

    printf("Checksum: %.6f\n", checksum);

    free(rowptr);
    free(colidx);
    free(vals);
    free(y);
    return 0;
}