import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import struct
import os
import argparse
import glob


def load_matrix_data(filename):
    with open(filename, "rb") as f:
        n_rows, n_cols, nnz = struct.unpack("iii", f.read(12))
        indptr = np.frombuffer(f.read((n_rows + 1) * 4), dtype=np.int32)
        indices = np.frombuffer(f.read(nnz * 4), dtype=np.int32)
        row_indices = np.repeat(np.arange(n_rows), np.diff(indptr))
    return n_rows, n_cols, nnz, indices, row_indices


def main():
    parser = argparse.ArgumentParser()
    """Generate PNG visualizations of sparse matrix data from `.bin` files.

    Parses command-line arguments from `sys.argv`:
        - `-d/--indir`: input directory containing `.bin` matrix files
        - `-o/--outdir`: output directory for generated `.png` images
        - `-s/--size`: marker size for scatter plots (default: `1.0`)

    For each input file, the function loads matrix metadata and coordinates,
    renders either a scatter plot (small matrices) or 2D histogram (large matrices),
    and saves the resulting image to the output directory.

    Returns:
        None
    """
    parser.add_argument("-d", "--indir", required=True)
    parser.add_argument("-o", "--outdir", required=True)
    parser.add_argument("-s", "--size", type=float, default=1.0)
    args = parser.parse_args()

    if not os.path.exists(args.outdir):
        os.makedirs(args.outdir)

    files = sorted(glob.glob(os.path.join(args.indir, "*.bin")))

    if not files:
        print("No files found.")
        return

    for file in files:
        print(f"Processing {file}...")
        n_r, n_c, nnz, idx, row_idx = load_matrix_data(file)

        fig, ax = plt.subplots(figsize=(5, 5))

        if n_r <= 5000:
            ax.scatter(
                idx, row_idx, s=args.size, c="black", marker="s", edgecolors="none"
            )
        else:
            ax.hist2d(idx, row_idx, bins=150, cmap="Greys")

        # No ticks, no labels
        ax.set_xticks([])
        ax.set_yticks([])

        # Clean border
        for spine in ax.spines.values():
            spine.set_visible(True)
            spine.set_linewidth(0.8)

        # Proper limits
        ax.set_xlim(0, n_c)
        ax.set_ylim(n_r, 0)
        ax.set_aspect("equal")

        plt.tight_layout()

        # Save as PNG (high resolution)
        base = os.path.splitext(os.path.basename(file))[0]
        out_path = os.path.join(args.outdir, f"{base}.png")
        plt.savefig(out_path, dpi=300, bbox_inches="tight")
        plt.close()

        print(f"Saved: {out_path}")


if __name__ == "__main__":
    main()
