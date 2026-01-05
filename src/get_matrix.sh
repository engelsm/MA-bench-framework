#!/bin/bash

# Downloads, preprocesses, and stores a matrix from the SuiteSparse collection (https://sparse.tamu.edu/).
# Usage: ./get_matrix.sh group/name
GROUP=${1%/*}
NAME=${1#*/}

# Download & Extract .mtx
URL="https://suitesparse-collection-website.herokuapp.com/MM/${GROUP}/${NAME}.tar.gz"
wget -O- "$URL" | tar -xzvO --wildcards "*/*.mtx" > "${NAME}.mtx"

# Setup Folders
MTX_DIR="../matrices/$TYPE/mtx"
BIN_DIR="../matrices/$TYPE/binary"
mkdir -p "$MTX_DIR" "$BIN_DIR"

# Move MTX to destination
mv "${NAME}.mtx" "$MTX_DIR/"

# Run Preprocessor and save metadata
../build/preprocess_matrix "$MTX_DIR/${NAME}.mtx" "$BIN_DIR/${NAME}.bin"

echo "Done."