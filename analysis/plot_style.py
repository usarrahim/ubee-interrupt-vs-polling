"""Shared matplotlib style for all figures."""
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

COLORS = {"poll": "#2a78d6", "irq": "#eb6834", "irq_slow": "#1baf7a", "grey": "#8a8984"}
LABELS = {"poll": "Polling", "irq": "Interrupt", "irq_slow": "Interrupt, slow ISR"}
TEXT, TEXT2 = "#0b0b0b", "#52514e"

plt.rcParams.update({
    "figure.facecolor": "white", "axes.facecolor": "white", "savefig.facecolor": "white",
    "font.size": 10, "axes.titlesize": 11, "axes.titleweight": "bold", "axes.labelsize": 10,
    "axes.edgecolor": "#c9c8c2", "axes.labelcolor": TEXT, "text.color": TEXT,
    "xtick.color": TEXT2, "ytick.color": TEXT2, "axes.grid": True, "grid.color": "#e6e5e0",
    "grid.linewidth": 0.8, "axes.spines.top": False, "axes.spines.right": False,
    "lines.linewidth": 2.0, "lines.markersize": 6, "legend.frameon": False, "savefig.dpi": 160,
})


def save(fig, path):
    fig.tight_layout()
    fig.savefig(path, bbox_inches="tight")
    plt.close(fig)
    print("figure:", path)
