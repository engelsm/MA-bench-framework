# Fetches a matrix from the SuiteSparse collection (https://sparse.tamu.edu/), converts it to the project’s binary SPMC format, and stores both source and processed files.
#
# Purpose:
# - Automate retrieval and preprocessing of a SuiteSparse matrix identified as `group/name`.
# - Organize generated artifacts into matrix-market (`mtx`) and binary output directories.
#
# What it does:
# - Parses the input argument into `GROUP` and `NAME`.
# - Downloads `${NAME}.tar.gz` from SuiteSparse and extracts `${NAME}.mtx`.
# - Creates output folders under `../matrices/$TYPE/mtx` and `../matrices/$TYPE/binary_spmc`.
# - Moves the extracted `.mtx` file into the MTX directory.
# - Runs `../build/preprocess_matrix` to produce a binary `.bin` file.
# - Prints a completion message including the final binary file size.
#
# Outputs:
# - Matrix Market file: `../matrices/$TYPE/mtx/${NAME}.mtx`
# - Binary matrix file: `../matrices/$TYPE/binary_spmc/${NAME}.bin`
# - Console status line with resulting `.bin` file size.

#!/bin/bash

# Usage: ./get_matrix.sh group/name
GROUP=${1%/*}
NAME=${1#*/}

# Download & Extract .mtx
URL="https://suitesparse-collection-website.herokuapp.com/MM/${GROUP}/${NAME}.tar.gz"
wget -O- "$URL" | tar -xzvO --wildcards "*/${NAME}.mtx" > "${NAME}.mtx"

# Setup Folders
MTX_DIR="../matrices/$TYPE/mtx"
BIN_DIR="../matrices/$TYPE/binary_spmc"
mkdir -p "$MTX_DIR" "$BIN_DIR"

# Move MTX to destination
mv "${NAME}.mtx" "$MTX_DIR/"

# Run Preprocessor and save metadata
../build/preprocess_matrix "$MTX_DIR/${NAME}.mtx" "$BIN_DIR/${NAME}.bin"

echo "Done. Final File Size: $(du -h "$BIN_DIR/${NAME}.bin" | cut -f1)"