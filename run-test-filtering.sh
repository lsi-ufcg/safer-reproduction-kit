#!/bin/bash
#
# Apaga as suites de teste que quebram a build ou falham em UM projeto, e
# registra num CSV quantos testes foram apagados de cada categoria (nativa,
# EvoSuite e Kex).
#
# Roda dentro do execucao_safer.sh: depois que ele monta a combinacao de testes
# em workstation/maven/<projeto>, e antes de chamar o Safer. O objetivo e o
# projeto chegar "verde" ao Safer, ja que ele usa o resultado dos testes para
# decidir se uma atualizacao de dependencia e segura.
#
# Para que verde aqui signifique verde no Safer, o filtro roda a mesma build que
# o Safer (mvn -B clean verify, no container do proprio Safer, com o JDK que ele
# escolheria), sobre o projeto ja preparado pelo bash/prepare-project.sh -- com
# as dependencias das suites geradas e o .mvn/maven.config que o Safer tambem vai
# usar. As suites sao apagadas nessa copia de trabalho; o dataset de origem nunca
# e alterado.
#
# Uso: ./run-test-filtering.sh [opcoes] <projeto>
# Veja ./run-test-filtering.sh --help

set -uo pipefail

ROOT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAFER_PATH="$ROOT_PATH/safer"
HELPERS_PATH="$ROOT_PATH/bash/test-filtering"
PREPARE_SCRIPT="$ROOT_PATH/bash/prepare-project.sh"

OUTPUT_CSV="$ROOT_PATH/results/v2/deleted-tests.csv"
DETAIL_CSV=""
PREPARE_CSV="$ROOT_PATH/results/v2/prepare-project.csv"
LOGS_DIR=""
RUN_ID=""
MAX_ITERATIONS=10
# O mesmo limite que o Safer usa por build (buildTimeoutSec, padrao 3600).
MVN_TIMEOUT=3600
KEEP_CONTAINER=false

usage() {
  cat <<'USAGE'
Uso: ./run-test-filtering.sh [opcoes] <projeto>

Filtra, no proprio lugar, as suites que falham no projeto informado -- que ja
deve estar no layout da combinacao que o Safer vai executar.

  -o, --output CSV          CSV de contagens (padrao: results/v2/deleted-tests.csv)
  -d, --detail CSV          CSV com um arquivo apagado por linha
                            (padrao: <output> com sufixo -detail)
      --prepare-csv CSV     CSV do bash/prepare-project.sh
                            (padrao: results/v2/prepare-project.csv)
      --id N                Id da execucao no pipeline, gravado nos CSVs
      --logs-dir DIR        Onde guardar os logs do Maven
                            (padrao: outputs/v2/<projeto>/test-filtering)
  -i, --max-iterations N    Rodadas de build (padrao: 10)
  -t, --timeout SEGUNDOS    Limite por rodada de Maven (padrao: 3600, o do Safer)
  -k, --keep-container      Nao remove o container ao final
  -h, --help                Mostra esta ajuda

Valores da coluna status:
  success             build verde com ao menos um teste executado
  no_tests_run        build verde sem nenhum teste executado
  build_error         a build quebra fora das suites (src/main, plugin, rede)
  timeout             uma rodada passou do limite de tempo
  killed              o Maven foi morto antes do limite (provavel falta de memoria)
  jdk_error           o JDK da imagem esta corrompido
  unresolved          as rodadas acabaram com suites ainda falhando
  no_tests            o projeto nao tem nenhuma suite
  not_maven           sem pom.xml
  java_version_error  nao foi possivel detectar a versao de Java
  container_error     o container nao subiu
  prepare_error       o bash/prepare-project.sh falhou
USAGE
}

PROJECT_PATH=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o|--output)          OUTPUT_CSV="$(readlink -m "$2")"; shift 2 ;;
    -d|--detail)          DETAIL_CSV="$(readlink -m "$2")"; shift 2 ;;
    --prepare-csv)        PREPARE_CSV="$(readlink -m "$2")"; shift 2 ;;
    --id)                 RUN_ID="$2"; shift 2 ;;
    --logs-dir)           LOGS_DIR="$(readlink -m "$2")"; shift 2 ;;
    -i|--max-iterations)  MAX_ITERATIONS="$2"; shift 2 ;;
    -t|--timeout)         MVN_TIMEOUT="$2"; shift 2 ;;
    -k|--keep-container)  KEEP_CONTAINER=true; shift ;;
    -h|--help)            usage; exit 0 ;;
    -*) echo "Opcao desconhecida: $1" >&2; usage >&2; exit 1 ;;
    *)  PROJECT_PATH="$(readlink -f "$1")"; shift ;;
  esac
done

if [ -z "$PROJECT_PATH" ] || [ ! -d "$PROJECT_PATH" ]; then
  echo "Informe o diretorio do projeto." >&2
  usage >&2
  exit 1
fi

PROJECT_NAME="$(basename "$PROJECT_PATH")"
[ -n "$DETAIL_CSV" ] || DETAIL_CSV="${OUTPUT_CSV%.csv}-detail.csv"
[ -n "$LOGS_DIR" ] || LOGS_DIR="$ROOT_PATH/outputs/v2/$PROJECT_NAME/test-filtering"

WORK_DIR="$ROOT_PATH/.test-filtering"
CSV_LOCK="$WORK_DIR/csv.lock"
IMAGE_LOCK="$WORK_DIR/image.lock"
MANIFEST="$LOGS_DIR/test-manifest.tsv"
POM_BACKUP="$LOGS_DIR/pom.xml.prepared"

mkdir -p "$WORK_DIR" "$(dirname "$OUTPUT_CSV")" "$(dirname "$DETAIL_CSV")"
touch "$CSV_LOCK" "$IMAGE_LOCK"

# Logs de uma execucao anterior com mais rodadas ficariam misturados com os novos.
rm -rf "$LOGS_DIR"
mkdir -p "$LOGS_DIR"

pretty_print() {
  local DEFAULT="\e[0m" RED="\e[1;31m" YELLOW="\e[1;33m" BLUE="\e[1;34m" GREEN="\e[1;92m"
  local color_uppercase="${1^^}"
  echo -e "${!color_uppercase}${2}${DEFAULT}"
}

# ---------------------------------------------------------------------------
# Manifesto
# ---------------------------------------------------------------------------

# Registra cada .java de teste com a sua categoria, deduzida do layout que o
# execucao_safer.sh monta: o Kex entra como src/test/java/kex-tests/, e o
# EvoSuite entra como src/test/java/evosuite-tests/ ou, quando nao havia
# src/test/java, como o proprio src/test/java -- por isso tambem pelo nome
# *_ESTest, que o EvoSuite sempre usa.
#
# Formato: <caminho no projeto> TAB <categoria> TAB <caminho no projeto>
build_manifest() {
  : > "$MANIFEST"

  while IFS= read -r file; do
    local relative="${file#$PROJECT_PATH/}" category=native

    case "$relative" in
      */kex-tests/*)                                  category=kex ;;
      */evosuite-tests/*|*_ESTest.java|*_ESTest_scaffolding.java) category=evosuite ;;
    esac

    printf '%s\t%s\t%s\n' "$relative" "$category" "$relative" >> "$MANIFEST"
  done < <(find "$PROJECT_PATH" -type d \( -name target -o -name .git \) -prune -o \
             -type f -name '*.java' -path '*/src/test/java/*' -print)
}

count_category() {
  awk -F'\t' -v category="$1" '$2 == category { total++ } END { print total + 0 }' "$MANIFEST"
}

# ---------------------------------------------------------------------------
# Container, preparo e build
# ---------------------------------------------------------------------------

# Nome proprio: o Safer usa java-container-safer-<pid> e, ao subir, remove os
# que sobraram de execucoes mortas (so os terminados em numero), entao este
# nunca colide com o dele.
container_name() {
  echo "java-container-safer-filter-$PROJECT_NAME"
}

# A mesma funcao do Safer, sobre o pom.xml (veja safer-java-version.ts).
detect_java_version() {
  ( cd "$SAFER_PATH/src" && ../node_modules/.bin/tsx \
      "$HELPERS_PATH/safer-java-version.ts" "$PROJECT_PATH" 2>>"$LOGS_DIR/container.log" ) | tail -1
}

start_container() {
  local java_version="$1" attempt

  docker rm -f "$(container_name)" >/dev/null 2>&1

  # A construcao da imagem e serializada porque projetos em paralelo
  # compartilham a tag java-setup:<versao>. O contexto do build fica no
  # diretorio de trabalho, quase vazio, para o buildx nao enviar o repositorio
  # inteiro. O init-java-container.sh tambem sobe (ou reaproveita) o Nexus.
  (
    cd "$WORK_DIR" || exit 1
    flock 9
    "$SAFER_PATH/src/runners/java/init-java-container.sh" \
      "$java_version" "$PROJECT_PATH" "$SAFER_PATH" "$(container_name)"
  ) 9>"$IMAGE_LOCK" || return 1

  # O container sobe em segundo plano; como o Safer, espera o docker exec responder.
  for attempt in $(seq 60); do
    docker exec "$(container_name)" true >/dev/null 2>&1 && return 0
    sleep 1
  done
  echo "container $(container_name) nao respondeu em 60s"
  return 1
}

# Subir o container depende da rede (a imagem baixa o JDK e o Maven). Uma
# oscilacao derrubava o projeto inteiro como container_error, sem nenhuma
# filtragem -- por isso a segunda tentativa.
start_container_with_retry() {
  local java_version="$1" attempt

  for attempt in 1 2; do
    if start_container "$java_version" >> "$LOGS_DIR/container.log" 2>&1; then
      return 0
    fi

    if [ "$attempt" -eq 1 ]; then
      pretty_print yellow "  [filtro] falha ao subir o container; repetindo em 20s"
      sleep 20
    fi
  done

  return 1
}

stop_container() {
  $KEEP_CONTAINER && return 0
  docker rm -f "$(container_name)" >/dev/null 2>&1
  return 0
}

# Sem container (antes de ele subir, ou quando nao sobe), o preparo ainda grava
# o .mvn/maven.config, que o Safer tambem le; so a injecao exige o container.
prepare_project() {
  local container_args=()
  [ -n "${1:-}" ] && container_args=(--container "$1")
  "$PREPARE_SCRIPT" "${container_args[@]}" -o "$PREPARE_CSV" --id "$RUN_ID" \
    --logs-dir "$LOGS_DIR/prepare" "$PROJECT_PATH"
}

# O javac quebrando ao verificar as PROPRIAS classes nao e erro do projeto: e a
# imagem java-setup:<versao> corrompida em disco.
jdk_is_broken() {
  grep -qE 'java\.lang\.VerifyError|compiler message file broken' "$1"
}

# O mesmo comando do Safer (MavenTool.build com os testes ligados). O timeout de
# dentro do container mata a JVM; o de fora, um minuto depois, e so uma garantia
# para o cliente do docker. Devolve 124 quando o limite estoura; 137 antes do
# limite e outro SIGKILL (provavel falta de memoria, o container tem 4 GB).
run_build() {
  local log_path="$1" started status
  started=$(date +%s)

  timeout -s KILL "$((MVN_TIMEOUT + 60))" \
    docker exec "$(container_name)" timeout -s KILL "$MVN_TIMEOUT" \
      mvn -B clean verify -Ddependency-check.skip=true \
    > "$log_path" 2>&1
  status=$?

  if [ "$status" -eq 124 ] || { [ "$status" -eq 137 ] && [ "$(( $(date +%s) - started ))" -ge "$((MVN_TIMEOUT - 5))" ]; }; then
    docker exec "$(container_name)" sh -c 'pkill -9 -f maven; pkill -9 java' >/dev/null 2>&1
    return 124
  fi

  return "$status"
}

# ---------------------------------------------------------------------------
# Saida
# ---------------------------------------------------------------------------

append_row() {
  ( flock 9
    [ -s "$1" ] || echo "$2" > "$1"
    echo "$3" >> "$1"
  ) 9>"$CSV_LOCK"
}

COUNTS_HEADER="id,project,native_deleted,evosuite_deleted,kex_deleted,total_deleted,native_total,evosuite_total,kex_total,tests_executed,iterations,status"
DETAIL_HEADER="id,project,category,reason,iteration,file"

# ---------------------------------------------------------------------------
# Execucao
# ---------------------------------------------------------------------------

native_deleted=0 evosuite_deleted=0 kex_deleted=0 total_deleted=0
tests_executed=0 iteration=0 status="unresolved"

# Sempre passa por aqui: o container e removido (o Safer sobe o dele), o pom.xml
# volta ao estado preparado -- com as dependencias injetadas, que o Safer
# precisa para compilar as suites geradas -- e a linha vai para o CSV.
finish() {
  stop_container
  [ -f "$POM_BACKUP" ] && cp "$POM_BACKUP" "$PROJECT_PATH/pom.xml"

  case "$status" in
    success) pretty_print green "  [filtro] OK apos $iteration rodada(s), $tests_executed testes executados -- apagados: native=$native_deleted evosuite=$evosuite_deleted kex=$kex_deleted" ;;
    *)       pretty_print red   "  [filtro] $status apos $iteration rodada(s), $tests_executed testes executados -- apagados: native=$native_deleted evosuite=$evosuite_deleted kex=$kex_deleted" ;;
  esac

  append_row "$OUTPUT_CSV" "$COUNTS_HEADER" \
    "$RUN_ID,$PROJECT_NAME,$native_deleted,$evosuite_deleted,$kex_deleted,$total_deleted,${native_total:-0},${evosuite_total:-0},${kex_total:-0},$tests_executed,$iteration,$status"
  exit 0
}

# Saidas antes de o container subir: o preparo sem container ainda grava o
# maven.config (e falha, sem efeito, se houver dependencia a injetar).
finish_without_container() {
  status="$1"
  prepare_project || true
  finish
}

pretty_print blue "  [filtro] $PROJECT_NAME"

if [ ! -f "$PROJECT_PATH/pom.xml" ]; then
  status="not_maven"
  finish
fi

build_manifest
native_total=$(count_category native)
evosuite_total=$(count_category evosuite)
kex_total=$(count_category kex)
echo "  [filtro] suites: native=$native_total evosuite=$evosuite_total kex=$kex_total"

if [ "$((native_total + evosuite_total + kex_total))" -eq 0 ]; then
  finish_without_container "no_tests"
fi

java_version=$(detect_java_version)
if [ -z "$java_version" ]; then
  finish_without_container "java_version_error"
fi
echo "  [filtro] Java $java_version"

if ! start_container_with_retry "$java_version"; then
  finish_without_container "container_error"
fi

if ! prepare_project "$(container_name)"; then
  status="prepare_error"
  finish
fi

# O backup vem depois do preparo: e esse pom, com as dependencias das suites
# geradas, que o Safer vai receber. A build nao mexe no pom; o backup so garante
# que nada do filtro chegue ao Safer.
cp "$PROJECT_PATH/pom.xml" "$POM_BACKUP"

jdk_retries=0
while [ "$iteration" -lt "$MAX_ITERATIONS" ]; do
  iteration=$((iteration + 1))
  maven_log="$LOGS_DIR/maven-iteration-$iteration.log"

  run_build "$maven_log"
  maven_status=$?
  tests_executed=$(python3 "$HELPERS_PATH/count-executed-tests.py" "$PROJECT_PATH")

  failures=$(python3 "$HELPERS_PATH/collect-failing-tests.py" "$PROJECT_PATH" "$maven_log" "$MANIFEST")

  if [ -z "$failures" ] && [ "$maven_status" -ne 0 ] && jdk_is_broken "$maven_log"; then
    if [ "$jdk_retries" -lt 1 ]; then
      jdk_retries=$((jdk_retries + 1))
      pretty_print yellow "  [filtro] JDK do container corrompido; recriando o container e repetindo"
      stop_container
      start_container "$java_version" >> "$LOGS_DIR/container.log" 2>&1
      continue
    fi
    status="jdk_error"
    break
  fi

  if [ -z "$failures" ]; then
    if [ "$maven_status" -eq 0 ] && [ "$tests_executed" -gt 0 ]; then
      status="success"
    elif [ "$maven_status" -eq 0 ]; then
      # Verde sem nenhum teste executado nao valida nada: o motor de testes pode
      # ter falhado na descoberta e engolido o erro.
      status="no_tests_run"
    elif [ "$maven_status" -eq 124 ]; then
      status="timeout"
    elif [ "$maven_status" -eq 137 ]; then
      status="killed"
    else
      # Quebrou fora das suites (src/main, plugin, rede): apagar teste nao ajuda.
      status="build_error"
    fi
    break
  fi

  deleted_now=0
  while IFS=$'\t' read -r relative category reason origin; do
    [ -n "$relative" ] || continue
    rm -f "$PROJECT_PATH/$origin" || continue
    deleted_now=$((deleted_now + 1))

    append_row "$DETAIL_CSV" "$DETAIL_HEADER" "$RUN_ID,$PROJECT_NAME,$category,$reason,$iteration,$origin"

    # Scaffolding do EvoSuite so existe para servir a suite que ja saiu,
    # entao acompanha a exclusao sem contar como teste apagado.
    [ "$reason" = "scaffolding" ] && continue

    case "$category" in
      native)   native_deleted=$((native_deleted + 1)) ;;
      evosuite) evosuite_deleted=$((evosuite_deleted + 1)) ;;
      kex)      kex_deleted=$((kex_deleted + 1)) ;;
    esac
    total_deleted=$((total_deleted + 1))
  done <<< "$failures"

  echo "  [filtro] rodada $iteration: $deleted_now arquivo(s) apagado(s)"

  if [ "$deleted_now" -eq 0 ]; then
    status="build_error"
    break
  fi
done

finish
