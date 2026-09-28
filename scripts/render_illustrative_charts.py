#!/usr/bin/env python3
"""Render deterministic visual mockups using fabricated values only.

These figures are for README/layout illustration, not for statistical analysis.
They do not come from Receita Federal, a CNPJ snapshot, or a fitted model.
They are deliberately kept under docs/illustrative/ and never written to
output/figures/, the folder reserved for real-data analytical outputs.
"""
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
from matplotlib.colors import TwoSlopeNorm

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "docs" / "illustrative"
OUT.mkdir(parents=True, exist_ok=True)
DISCLAIMER = "DADOS SINTÉTICOS • ILUSTRAÇÃO VISUAL • NÃO É RESULTADO DA RECEITA"
NAVY = "#142B43"
BLUE = "#3378A8"
TEAL = "#159A8A"
CORAL = "#D66A5E"
AMBER = "#D99A32"
SLATE = "#62758A"
GRID = "#DCE4EB"
BG = "#FAFCFE"

plt.rcParams.update({
    "font.family": "DejaVu Sans",
    "font.size": 11,
    "axes.titlesize": 17,
    "axes.titleweight": "bold",
    "axes.labelcolor": NAVY,
    "text.color": NAVY,
    "xtick.color": SLATE,
    "ytick.color": SLATE,
    "figure.facecolor": BG,
    "axes.facecolor": BG,
    "savefig.facecolor": BG,
})


def frame(title: str, subtitle: str, figsize=(11, 6.3)):
    fig, ax = plt.subplots(figsize=figsize)
    fig.suptitle(title, x=0.08, y=0.91, ha="left", color=NAVY, fontsize=19, fontweight="bold")
    fig.text(0.08, 0.855, subtitle, ha="left", color=SLATE, fontsize=10.5)
    fig.text(0.5, 0.975, DISCLAIMER, ha="center", va="center", color="white",
             fontsize=10, fontweight="bold",
             bbox={"boxstyle": "round,pad=0.55", "facecolor": CORAL, "edgecolor": CORAL})
    fig.text(0.08, 0.025,
             "Exemplo fabricado para demonstrar o desenho dos gráficos; não usar como achado, estimativa ou citação.",
             ha="left", va="bottom", color=SLATE, fontsize=8.5)
    ax.grid(axis="y", color=GRID, linewidth=0.8)
    ax.set_axisbelow(True)
    for spine in ("top", "right", "left"):
        ax.spines[spine].set_visible(False)
    ax.spines["bottom"].set_color(GRID)
    return fig, ax


def save(fig, name: str):
    fig.savefig(OUT / name, dpi=180, bbox_inches="tight")
    plt.close(fig)


# 1) Fictional annual series, in thousands of registrations.
years = np.arange(2012, 2026)
openings = np.array([74, 81, 93, 107, 121, 134, 139, 113, 128, 142, 156, 164, 173, 181])
closures = np.array([13, 16, 20, 25, 30, 35, 38, 34, 42, 48, 55, 62, 69, 76])
fig, ax = frame("Aberturas e baixas administrativas", "Série anual ilustrativa  •  valores fictícios em milhares")
ax.bar(years, openings, color=BLUE, width=0.68, label="Aberturas (exemplo)", zorder=3)
ax.plot(years, closures, color=CORAL, linewidth=2.8, marker="o", markersize=5.5,
        label="Baixas (exemplo)", zorder=4)
ax.set_ylabel("Registros (milhares — sintético)")
ax.set_xlabel("Ano (escala ilustrativa)")
ax.set_xticks(years[::2])
ax.legend(frameon=False, ncol=2, loc="upper left")
ax.set_ylim(0, 205)
fig.subplots_adjust(top=0.79, bottom=0.16, left=0.11, right=0.96)
save(fig, "annual_openings_closures.png")

# 2) Draw stylized Kaplan–Meier step functions; these are not estimated from observations.
time = np.array([0, 0.4, 0.9, 1.6, 2.5, 3.7, 5.2, 7.0, 9.0])
curves = {
    "Serviços — exemplo": (np.array([1.00, .96, .91, .85, .78, .70, .61, .53, .46]), BLUE),
    "Comércio — exemplo": (np.array([1.00, .94, .87, .79, .70, .61, .51, .42, .35]), TEAL),
    "Construção — exemplo": (np.array([1.00, .92, .83, .74, .65, .55, .46, .38, .30]), AMBER),
}
fig, ax = frame("Curva de sobrevivência cadastral", "Kaplan–Meier estilizado  •  amostra inteiramente sintética", figsize=(11, 6.5))
for label, (survival, color) in curves.items():
    ax.step(time, survival, where="post", linewidth=2.8, color=color, label=label)
    ax.scatter(time[1:], survival[1:], color=color, s=17, zorder=5)
ax.set_xlim(0, 9)
ax.set_ylim(0.2, 1.03)
ax.set_xlabel("Anos desde a abertura (eixo ilustrativo)")
ax.set_ylabel("Probabilidade sem baixa (valor sintético)")
ax.legend(frameon=False, loc="lower left")
ax.grid(axis="x", color=GRID, linewidth=0.6)
fig.subplots_adjust(top=0.79, bottom=0.16, left=0.12, right=0.96)
save(fig, "survival_by_sector.png")

# 3) Fictional city counts and administrative-closure proportions.
cities = ["Santo André", "São Bernardo", "Diadema", "Mauá", "São Caetano", "Ribeirão Pires", "Rio Grande da Serra"]
counts = np.array([45, 59, 31, 28, 19, 11, 5])
shares = np.array([19, 22, 24, 21, 17, 18, 23])
order = np.argsort(counts)
fig, ax = plt.subplots(figsize=(11, 6.5))
fig.suptitle("Comparação entre municípios", x=0.08, y=0.91, ha="left", color=NAVY, fontsize=19, fontweight="bold")
fig.text(0.08, 0.855, "Exemplo de volume e proporção  •  valores fictícios, sem vínculo com a RFB", ha="left", color=SLATE, fontsize=10.5)
fig.text(0.5, 0.975, DISCLAIMER, ha="center", va="center", color="white", fontsize=10, fontweight="bold",
         bbox={"boxstyle": "round,pad=0.55", "facecolor": CORAL, "edgecolor": CORAL})
ax.set_facecolor(BG)
ax.grid(axis="x", color=GRID, linewidth=0.8)
ax.set_axisbelow(True)
for spine in ("top", "right", "left"):
    ax.spines[spine].set_visible(False)
ax.spines["bottom"].set_color(GRID)
pos = np.arange(len(cities))
ax.barh(pos, counts[order], color=BLUE, height=0.58, label="Matrizes MPE (milhares — sintético)")
ax.set_yticks(pos, [cities[i] for i in order])
ax.set_xlabel("Contagem ilustrativa (milhares)")
ax.set_xlim(0, 75)
ax2 = ax.twiny()
ax2.scatter(shares[order], pos, color=CORAL, edgecolor="white", linewidth=1.2, s=85,
            marker="D", label="Baixa observada (%)")
ax2.set_xlim(0, 40)
ax2.set_xlabel("Baixas administrativas observadas — exemplo (%)", color=CORAL)
ax2.tick_params(axis="x", colors=CORAL)
handles1, labels1 = ax.get_legend_handles_labels()
handles2, labels2 = ax2.get_legend_handles_labels()
ax.legend(handles1 + handles2, labels1 + labels2, frameon=False, loc="lower right", fontsize=9)
fig.text(0.08, 0.025, "Série e proporções inventadas somente para mostrar o layout; não comparar nem citar.", ha="left", color=SLATE, fontsize=8.5)
fig.subplots_adjust(top=0.79, bottom=0.15, left=0.25, right=0.91)
save(fig, "municipality_comparison.png")

# 4) Fictional standardized feature heatmap for a possible segment/profile view.
profiles = ["Perfil de exemplo A", "Perfil de exemplo B", "Perfil de exemplo C", "Perfil de exemplo D", "Perfil de exemplo E"]
features = ["MEI (%)", "Baixa até 2 anos", "Idade média", "Capital social"]
z = np.array([
    [1.2, 0.4, -0.8, -0.6],
    [0.5, 1.1, -0.3, -0.4],
    [-0.7, 0.2, 1.0, 0.7],
    [-0.2, -0.8, 0.6, 1.3],
    [0.8, -0.4, -1.0, -0.7],
])
fig, ax = frame("Perfis setoriais padronizados", "Heatmap ilustrativo de variáveis z-score  •  valores sintéticos", figsize=(11, 6.1))
norm = TwoSlopeNorm(vmin=-1.5, vcenter=0, vmax=1.5)
im = ax.imshow(z, cmap="RdYlBu_r", norm=norm, aspect="auto")
ax.set_xticks(np.arange(len(features)), features, rotation=12, ha="right")
ax.set_yticks(np.arange(len(profiles)), profiles)
ax.grid(False)
for i in range(z.shape[0]):
    for j in range(z.shape[1]):
        color = "white" if abs(z[i, j]) > 0.9 else NAVY
        ax.text(j, i, f"{z[i, j]:+.1f}σ", ha="center", va="center", color=color, fontweight="bold", fontsize=10)
cbar = fig.colorbar(im, ax=ax, fraction=0.035, pad=0.025)
cbar.set_label("Desvio padronizado fictício")
fig.subplots_adjust(top=0.79, bottom=0.19, left=0.24, right=0.93)
save(fig, "sector_profile_heatmap.png")

print(f"Rendered four synthetic chart mockups to {OUT}")
