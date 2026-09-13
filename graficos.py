#!/usr/bin/env python3
"""Gera os graficos de escalabilidade forte e fraca a partir dos CSVs de medir.sh.

    python3 graficos.py [diretorio_de_resultados]

Produz, em resultados/:
    grafico_forte.pdf / .png   speed-up e eficiencia com o problema fixo
    grafico_fraca.pdf / .png   speed-up e eficiencia com a carga por thread fixa

O PDF e vetorial e e o que deve ir para o relatorio (nao perde qualidade no
LaTeX); o PNG serve para conferir rapidamente na tela.
"""
import csv
import os
import sys

import matplotlib
matplotlib.use("Agg")            # sem display: gera arquivo, nao abre janela
import matplotlib.pyplot as plt
from matplotlib.ticker import FuncFormatter

DIR = sys.argv[1] if len(sys.argv) > 1 else "resultados"

# ---------------------------------------------------------------------------
# Paleta. Os tres tons sao slots categoricos validados para daltonismo
# (deuteranopia/protanopia/tritanopia) sobre fundo claro. A ordem e fixa: cada
# escalonador tem sempre a mesma cor nos dois graficos, para que a leitura de
# um se transfira para o outro.
# ---------------------------------------------------------------------------
CORES = ["#2a78d6", "#eb6834", "#1baf7a", "#eda100"]
TINTA_FORTE = "#0b0b0b"     # titulos e numeros
TINTA_FRACA = "#52514e"     # rotulos de eixo
REFERENCIA  = "#9a9892"     # linha do ideal: cinza, recessiva
SUPERFICIE  = "#fcfcfb"

plt.rcParams.update({
    "font.family": "DejaVu Sans",
    "font.size": 9,
    "axes.edgecolor": "#d6d4cd",
    "axes.labelcolor": TINTA_FRACA,
    "xtick.color": TINTA_FRACA,
    "ytick.color": TINTA_FRACA,
    "figure.facecolor": SUPERFICIE,
    "axes.facecolor": SUPERFICIE,
})


def le_csv(nome):
    """Le um CSV de medir.sh. Devolve (linha_sequencial, linhas_paralelas)."""
    caminho = os.path.join(DIR, nome)
    if not os.path.exists(caminho):
        sys.exit(f"nao encontrei {caminho} — rode ./medir.sh antes.")

    seq, par = None, []
    with open(caminho) as f:
        for r in csv.DictReader(f, delimiter=";"):
            reg = {
                "modo": r["modo"],
                "threads": int(r["threads"]),
                "sched": r["schedule"],
                "chunk": int(r["chunk"]),
                "largura": int(r["largura"]),
                "altura": int(r["altura"]),
                "tempo": float(r["tempo"]),
                "checksum": int(r["checksum"]),
            }
            if reg["modo"] == "seq" and seq is None:
                seq = reg
            elif reg["modo"] == "par":
                par.append(reg)
    if seq is None:
        sys.exit(f"{nome}: falta a linha da versao sequencial (T1 de referencia).")
    return seq, par


def series_por_escalonador(linhas, ponto_inicial=None):
    """Agrupa as medicoes paralelas por escalonador, preservando a ordem do CSV.

    ponto_inicial, quando dado, entra no comeco de TODAS as series. E o caso da
    escalabilidade fraca: ali a medicao de 1 thread vem do binario sequencial,
    entao ela e ao mesmo tempo a referencia T(1) e o primeiro ponto da curva.
    Sem isso o grafico comecaria em 2 threads.
    """
    grupos, ordem = {}, []
    for d in linhas:
        rotulo = d["sched"] if d["chunk"] == 0 else f"{d['sched']},{d['chunk']}"
        if rotulo not in grupos:
            grupos[rotulo] = []
            ordem.append(rotulo)
        grupos[rotulo].append(d)
    for r in ordem:
        if ponto_inicial is not None:
            grupos[r].append(ponto_inicial)
        grupos[r].sort(key=lambda x: x["threads"])
    return [(r, grupos[r]) for r in ordem]


def eixo_threads(ax, threads):
    """Escala log2 no eixo x: as contagens de threads dobram a cada ponto, entao
    em escala linear os pontos baixos ficariam espremidos contra a origem."""
    ax.set_xscale("log", base=2)
    ax.set_xticks(threads)
    ax.xaxis.set_major_formatter(FuncFormatter(lambda v, _: f"{int(v)}"))
    ax.set_xlabel("Threads")
    ax.grid(True, which="major", color="#ebe9e3", linewidth=0.8)
    ax.set_axisbelow(True)          # grade atras dos dados, nunca por cima
    for lado in ("top", "right"):
        ax.spines[lado].set_visible(False)


def rotula_fim(ax, x, y, texto, cor, dy=0):
    """Rotulo direto no fim da linha.

    Faz o papel da legenda e, ao mesmo tempo, atende a regra de acessibilidade:
    a identidade da serie nao pode depender so da cor. Tambem e o 'relevo'
    exigido pelo tom verde-agua, cujo contraste sobre fundo claro fica abaixo
    de 3:1.
    """
    ax.annotate(texto, xy=(x, y), xytext=(6, dy), textcoords="offset points",
                va="center", ha="left", fontsize=8, color=cor, weight="bold",
                clip_on=False)


def desenha(nome_arquivo, titulo, seq, linhas, fraca):
    """Monta a figura de dois paineis: speed-up a esquerda, eficiencia a direita.

    Os dois paineis sao eixos SEPARADOS de proposito. Speed-up (adimensional,
    cresce ate p) e eficiencia (percentual, teto em 100%) tem escalas
    diferentes; sobrepor os dois num eixo duplo e o erro classico de grafico e
    tornaria as duas curvas ilegiveis.
    """
    series = series_por_escalonador(linhas, ponto_inicial=seq if fraca else None)
    threads = sorted({d["threads"] for _, pontos in series for d in pontos})
    tseq = seq["tempo"]

    fig, (ax_s, ax_e) = plt.subplots(1, 2, figsize=(9.2, 3.6))

    # ---- Linha do ideal -----------------------------------------------------
    # Nao e uma serie de dados, e uma referencia: cinza e tracejada, para nao
    # competir com as curvas medidas.
    ax_s.plot(threads, threads, linestyle="--", linewidth=1.4,
              color=REFERENCIA, zorder=1)
    rotula_fim(ax_s, threads[-1], threads[-1], "ideal", REFERENCIA)

    ax_e.axhline(100, linestyle="--", linewidth=1.4, color=REFERENCIA, zorder=1)
    rotula_fim(ax_e, threads[-1], 100, "ideal", REFERENCIA, dy=7)

    for i, (rotulo, pontos) in enumerate(series):
        cor = CORES[i % len(CORES)]
        xs = [d["threads"] for d in pontos]

        if fraca:
            # Escalabilidade fraca: o trabalho cresce junto com p, entao
            # S(p) = p * Tseq / T(p)  e  E(p) = Tseq / T(p) — a eficiencia mede
            # o quanto o tempo conseguiu ficar constante.
            sp = [d["threads"] * tseq / d["tempo"] for d in pontos]
            ef = [100.0 * tseq / d["tempo"] for d in pontos]
        else:
            # Escalabilidade forte: problema fixo.
            sp = [tseq / d["tempo"] for d in pontos]
            ef = [100.0 * (tseq / d["tempo"]) / d["threads"] for d in pontos]

        for ax, ys in ((ax_s, sp), (ax_e, ef)):
            ax.plot(xs, ys, marker="o", markersize=5, linewidth=2,
                    color=cor, label=rotulo, zorder=3,
                    markeredgecolor=SUPERFICIE, markeredgewidth=1.2)
        rotula_fim(ax_s, xs[-1], sp[-1], rotulo, cor)

    ax_s.set_ylabel("Speed-up")
    ax_s.set_title("Fator de aceleração", fontsize=9.5, color=TINTA_FORTE,
                   loc="left", pad=8)
    ax_s.set_ylim(0, max(threads) * 1.08)

    ax_e.set_ylabel("Eficiência (%)")
    ax_e.set_title("Eficiência", fontsize=9.5, color=TINTA_FORTE,
                   loc="left", pad=8)
    ax_e.set_ylim(0, 115)

    for ax in (ax_s, ax_e):
        eixo_threads(ax, threads)

    # Legenda sempre presente com 2+ series; os rotulos diretos repetem a
    # informacao para quem imprime em preto e branco.
    if len(series) > 1:
        ax_e.legend(frameon=False, fontsize=8, loc="lower left",
                    labelcolor=TINTA_FRACA)

    fig.suptitle(titulo, fontsize=11, color=TINTA_FORTE, x=0.008, ha="left",
                 weight="bold")
    fig.tight_layout(rect=[0, 0, 0.965, 0.93])

    for ext in ("pdf", "png"):
        saida = os.path.join(DIR, f"{nome_arquivo}.{ext}")
        fig.savefig(saida, dpi=200, facecolor=SUPERFICIE)
        print("gerado:", saida)
    plt.close(fig)


def main():
    seq_f, par_f = le_csv("forte.csv")
    mpix = seq_f["largura"] * seq_f["altura"] / 1e6
    desenha("grafico_forte",
            f"Escalabilidade forte — imagem fixa de {seq_f['largura']}×"
            f"{seq_f['altura']} ({mpix:.1f} Mpixels)".replace(".", ","),
            seq_f, par_f, fraca=False)

    seq_w, par_w = le_csv("fraca.csv")
    desenha("grafico_fraca",
            f"Escalabilidade fraca — {seq_w['largura']}×{seq_w['altura']} "
            f"pixels por thread",
            seq_w, par_w, fraca=True)


if __name__ == "__main__":
    main()
