#!/usr/bin/env bash
# Coleta os tempos dos tres experimentos do trabalho e grava CSVs.
#   resultados/forte.csv   escalabilidade forte  (problema fixo, threads 1..16)
#   resultados/fraca.csv   escalabilidade fraca  (problema cresce com as threads)
#   resultados/sched.csv   comparacao de escalonadores e tamanhos de chunk
#
# Cada ponto e medido REPS vezes e guardamos a MEDIANA, nao a media: uma unica
# execucao contaminada por outro processo no no distorce a media, mas nao a
# mediana.
set -euo pipefail

# Descobre quantos nucleos FISICOS o no tem e monta a escada 1,2,4,8,...,N.
# Deixar isso fixo em 16 desperdicaria os nucleos de um no maior, e o enunciado
# pede explicitamente a maquina com o maior numero de nucleos possivel.
# Contamos nucleos fisicos (e nao nproc) porque hyper-threads compartilham as
# unidades de execucao: incluir a segunda thread de cada nucleo nao acrescenta
# capacidade real de calculo e achataria artificialmente o speed-up.
nucleos_fisicos() {
    local c s
    c=$(LC_ALL=C lscpu | awk -F: '/^Core\(s\) per socket/{gsub(/ /,"",$2); print $2}')
    s=$(LC_ALL=C lscpu | awk -F: '/^Socket\(s\)/{gsub(/ /,"",$2); print $2}')
    if [ -n "$c" ] && [ -n "$s" ]; then echo $((c * s)); else nproc; fi
}

escada_threads() {
    local n=$1 t=1 lista=""
    while [ "$t" -lt "$n" ]; do lista="$lista $t"; t=$((t * 2)); done
    echo "$lista $n"
}

NUCLEOS=${NUCLEOS:-$(nucleos_fisicos)}
THREADS=${THREADS:-$(escada_threads "$NUCLEOS")}
REPS=${REPS:-3}
ITER=${ITER:-2000}          # iteracoes maximas por pixel
LADO=${LADO:-4096}          # lado da imagem na escalabilidade FORTE
LADO_BASE=${LADO_BASE:-1024}  # lado por thread na escalabilidade FRACA
SCHED_FORTE=${SCHED_FORTE:-dynamic}
CHUNK_FORTE=${CHUNK_FORTE:-1}

cd "$(dirname "$0")"
mkdir -p resultados

# Fixa as threads nos nucleos e evita que o SO as migre entre os dois sockets
# do no. Sem isso os tempos oscilam de execucao para execucao.
export OMP_PLACES=cores
export OMP_PROC_BIND=close

echo "no: $(hostname) | nucleos fisicos: $NUCLEOS | nproc: $(nproc)"
echo "threads testadas:$THREADS | reps: $REPS | iteracoes: $ITER"
echo

# Roda o comando REPS vezes e devolve a linha CSV com a mediana do tempo.
mediana() {
    local saidas=()
    local i
    for ((i = 0; i < REPS; i++)); do
        saidas+=("$("$@")")
    done
    printf '%s\n' "${saidas[@]}" | sort -t';' -k8 -g | sed -n "$(( (REPS + 1) / 2 ))p"
}

cabecalho='modo;threads;schedule;chunk;largura;altura;max_iter;tempo;checksum'

# ---------------------------------------------------------------- forte -----
# Tamanho do problema FIXO. T(1) vem do binario sequencial de verdade, sem
# OpenMP, como pede o enunciado.
echo "$cabecalho" > resultados/forte.csv
echo ">> escalabilidade forte: ${LADO}x${LADO}, ${ITER} iteracoes"
echo -n "   seq ... "
mediana ./mandelbrot_seq -w "$LADO" -a "$LADO" -i "$ITER" >> resultados/forte.csv
tail -1 resultados/forte.csv | cut -d';' -f8

for t in $THREADS; do
    echo -n "   ${t} threads ... "
    mediana env OMP_NUM_THREADS="$t" ./mandelbrot_par \
        -w "$LADO" -a "$LADO" -i "$ITER" \
        -s "$SCHED_FORTE" -c "$CHUNK_FORTE" >> resultados/forte.csv
    tail -1 resultados/forte.csv | cut -d';' -f8
done

# ---------------------------------------------------------------- fraca -----
# Trabalho POR THREAD constante: o numero de pixels cresce por um fator p, logo
# cada lado cresce por sqrt(p). A janela do plano complexo continua a mesma, so
# a resolucao aumenta, entao o custo medio por pixel nao muda.
echo "$cabecalho" > resultados/fraca.csv
echo ">> escalabilidade fraca: ${LADO_BASE}x${LADO_BASE} por thread"
for t in $THREADS; do
    lado=$(awk -v b="$LADO_BASE" -v p="$t" 'BEGIN{printf "%d", int(b*sqrt(p)+0.5)}')
    echo -n "   ${t} threads (${lado}x${lado}) ... "
    if [ "$t" -eq 1 ]; then
        # Referencia da escalabilidade fraca: o sequencial de verdade.
        mediana ./mandelbrot_seq -w "$lado" -a "$lado" -i "$ITER" \
            >> resultados/fraca.csv
    else
        mediana env OMP_NUM_THREADS="$t" ./mandelbrot_par \
            -w "$lado" -a "$lado" -i "$ITER" \
            -s "$SCHED_FORTE" -c "$CHUNK_FORTE" >> resultados/fraca.csv
    fi
    tail -1 resultados/fraca.csv | cut -d';' -f8
done

# ------------------------------------------------------------ escalonador ---
# Com todas as threads, varre escalonadores e granularidades. E o dado que
# sustenta a analise de balanceamento de carga exigida na rubrica.
maior=$(echo "$THREADS" | tr ' ' '\n' | sort -n | tail -1)
echo "$cabecalho" > resultados/sched.csv
echo ">> escalonadores com ${maior} threads (${LADO}x${LADO})"
for combo in "static 0" "static 1" "static 8" "static 64" \
             "dynamic 1" "dynamic 8" "dynamic 64" \
             "guided 0" "guided 1"; do
    set -- $combo
    echo -n "   $1 chunk=$2 ... "
    mediana env OMP_NUM_THREADS="$maior" ./mandelbrot_par \
        -w "$LADO" -a "$LADO" -i "$ITER" -s "$1" -c "$2" >> resultados/sched.csv
    tail -1 resultados/sched.csv | cut -d';' -f8
done

echo
echo "pronto. CSVs em resultados/"
