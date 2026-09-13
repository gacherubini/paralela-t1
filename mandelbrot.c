/*
 * Conjunto de Mandelbrot - Trabalho 1 de Computacao Paralela
 * Grupo 20 (cp32020) - PUCRS 2026/2
 *
 * Um unico arquivo gera as DUAS versoes exigidas pelo enunciado:
 *
 *   gcc -O2 -o mandelbrot_seq mandelbrot.c -lm            -> versao sequencial
 *   gcc -O2 -fopenmp -o mandelbrot_par mandelbrot.c -lm   -> versao paralela
 *
 * Sem a flag -fopenmp o compilador simplesmente ignora os pragmas, entao o
 * tempo de referencia (T1) vem exatamente do mesmo codigo e do mesmo nivel de
 * otimizacao da versao paralela. Isso evita o erro classico de comparar um
 * sequencial mal compilado com um paralelo bem compilado e inflar o speed-up.
 *
 * O programa imprime uma linha CSV no stdout com os tempos e um checksum, que
 * o script de medicao coleta. O checksum (soma de todas as iteracoes) deve ser
 * IDENTICO entre a versao sequencial e a paralela: e a prova de corretude.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#ifdef _OPENMP
#include <omp.h>
#endif

/* Janela do plano complexo. Fixa em todos os experimentos: e o que garante que
 * aumentar a resolucao signifique "mais trabalho da mesma natureza", condicao
 * necessaria para a escalabilidade fraca fazer sentido. */
#define RE_MIN -2.0
#define RE_MAX  0.6
#define IM_MIN -1.3
#define IM_MAX  1.3

/* Relogio monotonico: nao anda para tras se o NTP ajustar a hora do sistema,
 * ao contrario de gettimeofday. Funciona nas duas versoes (omp_get_wtime nao
 * existe quando compilamos sem -fopenmp). */
static double agora_segundos(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec * 1e-9;
}

/*
 * Nucleo do calculo: itera z = z^2 + c e devolve em quantos passos o ponto
 * escapou do disco de raio 2, ou max_iter se nunca escapou.
 *
 * E AQUI que nasce o desbalanceamento de carga do problema: um pixel fora do
 * conjunto escapa em poucas iteracoes, enquanto um pixel dentro do conjunto
 * roda o laco max_iter vezes inteiras. O custo por pixel varia em ate tres
 * ordens de grandeza, e nao ha como saber de antemao qual pixel e caro.
 */
static inline int mandel_ponto(double cr, double ci, int max_iter)
{
    double zr = 0.0, zi = 0.0;
    int it = 0;

    /* Comparamos o modulo ao quadrado com 4.0 para evitar a raiz quadrada. */
    while (it < max_iter && zr * zr + zi * zi <= 4.0) {
        double zr_novo = zr * zr - zi * zi + cr;
        zi = 2.0 * zr * zi + ci;
        zr = zr_novo;
        it++;
    }
    return it;
}

/* Grava a imagem em PGM binario (P5), so para conferir visualmente que a
 * versao paralela produz a mesma figura da sequencial. */
static int grava_pgm(const char *caminho, const unsigned char *img,
                     int largura, int altura)
{
    FILE *f = fopen(caminho, "wb");
    if (!f) {
        perror("fopen");
        return -1;
    }
    fprintf(f, "P5\n%d %d\n255\n", largura, altura);
    fwrite(img, 1, (size_t)largura * altura, f);
    fclose(f);
    return 0;
}

static void uso(const char *prog)
{
    fprintf(stderr,
        "uso: %s [-w largura] [-a altura] [-i max_iter] [-t threads]\n"
        "        [-s static|dynamic|guided] [-c chunk] [-o saida.pgm]\n",
        prog);
}

int main(int argc, char **argv)
{
    int largura  = 1024;
    int altura   = 1024;
    int max_iter = 1000;
    int threads  = 0;          /* 0 = deixa o OpenMP decidir (OMP_NUM_THREADS) */
    int chunk    = 0;          /* 0 = tamanho de chunk padrao do OpenMP        */
    const char *nome_sched = "static";
    const char *saida_pgm  = NULL;
    int opt;

    while ((opt = getopt(argc, argv, "w:a:i:t:s:c:o:")) != -1) {
        switch (opt) {
        case 'w': largura    = atoi(optarg); break;
        case 'a': altura     = atoi(optarg); break;
        case 'i': max_iter   = atoi(optarg); break;
        case 't': threads    = atoi(optarg); break;
        case 's': nome_sched = optarg;       break;
        case 'c': chunk      = atoi(optarg); break;
        case 'o': saida_pgm  = optarg;       break;
        default: uso(argv[0]); return 1;
        }
    }

    if (largura <= 0 || altura <= 0 || max_iter <= 0) {
        uso(argv[0]);
        return 1;
    }

#ifdef _OPENMP
    if (threads > 0)
        omp_set_num_threads(threads);

    /* schedule(runtime) no pragma + omp_set_schedule aqui: permite comparar
     * static, dynamic e guided (e varios chunks) SEM recompilar o programa,
     * o que mantem o binario identico entre as medicoes de escalonador. */
    omp_sched_t tipo_sched = omp_sched_static;
    if (strcmp(nome_sched, "dynamic") == 0)      tipo_sched = omp_sched_dynamic;
    else if (strcmp(nome_sched, "guided") == 0)  tipo_sched = omp_sched_guided;
    else if (strcmp(nome_sched, "static") != 0) {
        fprintf(stderr, "schedule desconhecido: %s\n", nome_sched);
        return 1;
    }
    omp_set_schedule(tipo_sched, chunk);

    threads = omp_get_max_threads();
    const char *modo = "par";
#else
    threads = 1;
    const char *modo = "seq";
#endif

    unsigned char *img = malloc((size_t)largura * altura);
    if (!img) {
        fprintf(stderr, "memoria insuficiente para %dx%d\n", largura, altura);
        return 1;
    }

    /* Passo entre pixels vizinhos no plano complexo. Calculado uma vez fora do
     * laco: dentro dele seria trabalho redundante em cada iteracao. */
    const double passo_re = (RE_MAX - RE_MIN) / largura;
    const double passo_im = (IM_MAX - IM_MIN) / altura;

    long long checksum = 0;
    double t0 = agora_segundos();

    /*
     * A regiao paralela.
     *
     * - parallel for sobre as LINHAS: cada linha e uma tarefa independente,
     *   sem escrita compartilhada (cada thread escreve numa faixa propria de
     *   img), entao nao ha necessidade de critical nem de atomic no laco.
     * - schedule(runtime): o escalonador vem de omp_set_schedule, escolhido
     *   pela linha de comando. Static distribui as linhas em blocos fixos de
     *   antemao; dynamic entrega uma linha por vez conforme as threads ficam
     *   livres, o que corrige o desbalanceamento ao custo de sincronizacao.
     * - reduction(+:checksum): a soma das iteracoes e a unica variavel
     *   realmente compartilhada. A reducao da a cada thread uma copia privada
     *   e soma tudo no fim, evitando a condicao de corrida e o gargalo que um
     *   #pragma omp atomic no laco interno causaria.
     * - As variaveis declaradas DENTRO da regiao (x, cr, ci, it) sao privadas
     *   automaticamente, que e a forma mais segura de evitar compartilhamento
     *   acidental.
     */
#ifdef _OPENMP
    #pragma omp parallel for schedule(runtime) reduction(+:checksum)
#endif
    for (int y = 0; y < altura; y++) {
        double ci = IM_MIN + y * passo_im;
        for (int x = 0; x < largura; x++) {
            double cr = RE_MIN + x * passo_re;
            int it = mandel_ponto(cr, ci, max_iter);
            img[(size_t)y * largura + x] =
                (unsigned char)(255.0 * it / max_iter);
            checksum += it;
        }
    }

    double tempo = agora_segundos() - t0;

    if (saida_pgm)
        grava_pgm(saida_pgm, img, largura, altura);
    free(img);

    /* Linha CSV consumida por medir.sh:
     * modo;threads;schedule;chunk;largura;altura;max_iter;tempo;checksum */
    printf("%s;%d;%s;%d;%d;%d;%d;%.6f;%lld\n",
           modo, threads, nome_sched, chunk,
           largura, altura, max_iter, tempo, checksum);

    return 0;
}
