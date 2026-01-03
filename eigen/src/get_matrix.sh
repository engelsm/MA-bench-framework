#!/bin/bash

# Downloads, preprocesses, and stores a matrix from the SuiteSparse collection (https://sparse.tamu.edu/).
# Usage: ./get_matrix.sh group/name
GROUP=${1%/*}
NAME=${1#*/}

# 1. Download & Extract .mtx
URL="https://suitesparse-collection-website.herokuapp.com/MM/${GROUP}/${NAME}.tar.gz"
wget -O- "$URL" | tar -xzvO --wildcards "*/*.mtx" > "${NAME}.mtx"

# 2. Get symmetry type
TYPE="general"
grep -iq "symmetric" "${NAME}.mtx" && TYPE="symmetric"

# 3. Setup Folders
MTX_DIR="../matrices/$TYPE/mtx"
BIN_DIR="../matrices/$TYPE/binary"
mkdir -p "$MTX_DIR" "$BIN_DIR"

# 4. Move MTX to destination
mv "${NAME}.mtx" "$MTX_DIR/"

# 5. Run Preprocessor
../build/preprocess_matrix "$MTX_DIR/${NAME}.mtx" "$BIN_DIR/${NAME}.dat"

echo "MTX: $MTX_DIR/${NAME}.mtx"
echo "BIN: $BIN_DIR/${NAME}.dat"