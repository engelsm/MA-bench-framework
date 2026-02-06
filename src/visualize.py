import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import struct
import os
import argparse
import glob
import math


def load_matrix_data(filename):
    with open(filename, "rb") as f:
        n_rows, n_cols, nnz = struct.unpack("iii", f.read(12))
        indptr = np.frombuffer(f.read((n_rows + 1) * 4), dtype=np.int32)
        indices = np.frombuffer(f.read(nnz * 4), dtype=np.int32)
        row_indices = np.repeat(np.arange(n_rows), np.diff(indptr))
    return n_rows, n_cols, nnz, indices, row_indices


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-d", "--indir", required=True, help="Ordner mit .bin Dateien")
    parser.add_argument(
        "-o", "--outdir", required=True, help="Zielordner für das Ergebnis"
    )
    parser.add_argument("-s", "--size", type=float, default=1.0, help="Punktgröße")
    parser.add_argument(
        "--name", default="matrix_comparison.png", help="Dateiname der Grafik"
    )
    args = parser.parse_args()

    if not os.path.exists(args.outdir):
        os.makedirs(args.outdir)

    files = sorted(glob.glob(os.path.join(args.indir, "*.bin")))
    num_files = len(files)

    if num_files == 0:
        print("Keine Dateien gefunden.")
        return

    # Raster berechnen (z.B. 2 Spalten)
    cols = 4
    rows = math.ceil(num_files / cols)

    fig, axes = plt.subplots(rows, cols, figsize=(6 * cols, 5 * rows))
    axes = np.array(axes).flatten()  # Sicherstellen, dass es ein Array ist

    for i, file in enumerate(files):
        print(f"Lade {file}...")
        n_r, n_c, nnz, idx, row_idx = load_matrix_data(file)

        ax = axes[i]
        if n_r <= 5000:
            ax.scatter(
                idx, row_idx, s=args.size, c="black", marker="s", edgecolors="none"
            )
        else:
            ax.hist2d(idx, row_idx, bins=150, cmap="Greys")

        ax.set_title(f"{os.path.basename(file)}\nN={n_r}, NNZ={nnz}")
        ax.set_xlim(0, n_c)
        ax.set_ylim(n_r, 0)
        ax.set_aspect("equal")
        ax.grid(True, linestyle=":", alpha=0.4)

    # Leere Subplots verstecken
    for j in range(i + 1, len(axes)):
        axes[j].axis("off")

    plt.tight_layout()
    output_path = os.path.join(args.outdir, args.name)
    plt.savefig(output_path, dpi=150)
    print(f"\nFERTIG: Gesamtbild gespeichert unter {output_path}")


if __name__ == "__main__":
    main()
