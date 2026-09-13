#!/usr/bin/env bash
# Le os CSVs de medir.sh e imprime as tabelas do relatorio, ja com speed-up e
# eficiencia calculados. Tambem confere se os checksums batem (corretude).
#
#   forte: S(p) = T_seq / T(p)        E(p) = S(p) / p
#   fraca: S(p) = (p * T_seq) / T(p)  E(p) = T_seq / T(p)
#          (na fraca o trabalho cresce junto com p, entao a eficiencia e
#           simplesmente quanto o tempo conseguiu ficar constante)
set -euo pipefail
cd "$(dirname "$0")"

echo "=================== ESCALABILIDADE FORTE ==================="
awk -F';' 'NR>1 {
    if ($1 == "seq") { tseq = $8; ck = $9;
        printf "%-9s %-8s %12s %10s %12s\n", "versao", "threads", "tempo(s)", "speedup", "eficiencia";
        printf "%-9s %-8d %12.3f %10s %12s\n", "seq", 1, tseq, "-", "-";
        next }
    s = tseq / $8; e = s / $2;
    if ($9 != ck) aviso = aviso sprintf("  ATENCAO: checksum difere com %d threads\n", $2);
    printf "%-9s %-8d %12.3f %10.2f %11.1f%%\n", "par", $2, $8, s, e*100
} END { if (aviso != "") printf "\n%s", aviso }' resultados/forte.csv

echo
echo "=================== ESCALABILIDADE FRACA ==================="
awk -F';' 'NR>1 {
    if (NR == 2) { tseq = $8;
        printf "%-8s %-12s %12s %10s %12s\n", "threads", "imagem", "tempo(s)", "speedup", "eficiencia" }
    s = ($2 * tseq) / $8; e = tseq / $8;
    printf "%-8d %-12s %12.3f %10.2f %11.1f%%\n", $2, $5 "x" $6, $8, s, e*100
}' resultados/fraca.csv

echo
echo "============ ESCALONADORES E GRAO (balanceamento) ============"
awk -F';' 'NR>1 {
    if (melhor == 0 || $8 < melhor) melhor = $8;
    linha[NR] = sprintf("%-10s %-8s %12.3f", $3, ($4 == 0 ? "padrao" : $4), $8);
    t[NR] = $8; n = NR
} END {
    printf "%-10s %-8s %12s %12s\n", "schedule", "chunk", "tempo(s)", "vs melhor";
    for (i = 2; i <= n; i++) printf "%s %11.2fx\n", linha[i], t[i]/melhor
}' resultados/sched.csv
