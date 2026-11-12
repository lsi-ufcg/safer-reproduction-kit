#!/bin/bash
#
# Prepara UM projeto, ja no layout da combinacao de testes, para o filtro e para
# o Safer. Assume o que o run-maven-build.sh do Safer antigo fazia; o Safer novo
# nao sabe nada de EvoSuite nem de Kex.
#
#   1. Instala o evosuite-standalone-runtime 1.1.0 (libs/) no repositorio Maven
#      que o container do Safer monta. Essa versao nao esta no Maven Central.
#   2. Injeta no pom.xml, com escopo test, as dependencias que as suites geradas
#      precisam: evosuite-standalone-runtime, junit e junit-vintage-engine. So
#      quando ha evosuite-tests ou kex-tests, e so as que o projeto nao declara.
#   3. Alinha o junit-vintage-engine com o JUnit Platform que o projeto resolve.
#   4. Compara a arvore de runtime antes e depois da injecao. O Safer pontua so
#      essa arvore e ignora as dependencias de teste, mas uma declaracao direta
#      com escopo test pode tirar da arvore uma dependencia que chegava por
#      transitividade (o Maven fica com o escopo da declaracao direta). Cada
#      projeto ganha uma linha no CSV, e uma diferenca fica registrada nela.
#   5. Acrescenta ao .mvn/maven.config as flags que o comando antigo passava na
#      linha de comando, sem apagar o que ja existir.
#
# Os passos 3 e 4 rodam o Maven dentro de um container ja em execucao, com o
# projeto montado em /app -- o mesmo que o filtro sobe com o init-java-container.sh
# do Safer, com o JDK que o Safer vai usar. Assim a arvore comparada aqui e a que
# o Safer vai pontuar. O container so e exigido quando ha dependencia a injetar;
# sem ele, o script ainda grava o .mvn/maven.config.
#
# Uso: bash/prepare-project.sh [opcoes] [--container NOME] <projeto>
# Veja bash/prepare-project.sh --help

set -uo pipefail

ROOT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POM_TOOLS="$ROOT_PATH/bash/prepare/pom_tools.py"

EVOSUITE_JAR="$ROOT_PATH/libs/evosuite-standalone-runtime-1.1.0.jar"
EVOSUITE_SHA256="5419394affc8ccc681a7421ef546755df125ed535ef2da3e1a48d6e4c9ec985e"
# O mesmo cache que o init-java-container.sh do Safer monta em /tmp/.m2
# (o Maven do container usa user.home=/tmp).
M2_REPOSITORY="$HOME/.cache/safer/m2/repository"
EVOSUITE_REPO_DIR="$M2_REPOSITORY/org/evosuite/evosuite-standalone-runtime/1.1.0"

DEFAULT_VINTAGE="5.10.0"
# Mesmo limite que o Safer usa para dependency:list (RESOLVE_TIMEOUT_SEC).
RESOLVE_TIMEOUT=600

MAVEN_CONFIG_FLAGS=(
  "-Dtest=*Test,*Tests,*TestCase,*_init_*,*_equals_*,*Utils*,*_*"
  "-DfailIfNoTests=true"
  "-DskipTests=false"
  "-Dmaven.test.skip=false"
  "-Dgit.buildhook.skip=true"
)

OUTPUT_CSV="$ROOT_PATH/results/v2/prepare-project.csv"
LOGS_DIR=""
RUN_ID=""
CONTAINER=""

usage() {
  cat <<'USAGE'
Uso: bash/prepare-project.sh [opcoes] [--container NOME] <projeto>

Prepara, no proprio lugar, o projeto informado -- que ja deve estar no layout
da combinacao que o Safer vai executar.

  -c, --container NOME   Container em execucao com o projeto montado em /app
                         (o filtro sobe com o init-java-container.sh). Exigido
                         quando ha suites geradas e dependencia a injetar
  -o, --output CSV       Uma linha por projeto (padrao: results/v2/prepare-project.csv)
      --id N             Id da execucao no pipeline, gravado no CSV
      --logs-dir DIR     Onde guardar logs e arvores
                         (padrao: outputs/v2/<projeto>/prepare)
  -h, --help             Mostra esta ajuda

Saida: 0 quando o projeto ficou preparado (mesmo que a arvore tenha mudado ou
nao tenha podido ser comparada: isso vai para a coluna tree do CSV); 1 quando
nao foi possivel preparar.

Valores da coluna tree:
  same                   a arvore de runtime nao mudou com a injecao
  changed                mudou; as colunas added/removed dizem como
  error                  nao foi possivel resolver uma das arvores (veja os logs)
  not_injected           nada foi injetado (sem suites geradas, ou o projeto ja
                         declarava tudo), entao nao ha o que comparar
USAGE
}

PROJECT_PATH=""
while [ $# -gt 0 ]; do
  case "$1" in
    -c|--container) CONTAINER="$2"; shift 2 ;;
    -o|--output)    OUTPUT_CSV="$(readlink -m "$2")"; shift 2 ;;
    --id)           RUN_ID="$2"; shift 2 ;;
    --logs-dir)     LOGS_DIR="$(readlink -m "$2")"; shift 2 ;;
    -h|--help)      usage; exit 0 ;;
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
POM="$PROJECT_PATH/pom.xml"
[ -n "$LOGS_DIR" ] || LOGS_DIR="$ROOT_PATH/outputs/v2/$PROJECT_NAME/prepare"

rm -rf "$LOGS_DIR"
mkdir -p "$LOGS_DIR" "$(dirname "$OUTPUT_CSV")"

pretty_print() {
  local DEFAULT="\e[0m" RED="\e[1;31m" YELLOW="\e[1;33m" BLUE="\e[1;34m" GREEN="\e[1;92m"
  local color_uppercase="${1^^}"
  echo -e "${!color_uppercase}${2}${DEFAULT}"
}

fail() {
  pretty_print red "  [preparo] $1" >&2
  exit 1
}

# ---------------------------------------------------------------------------
# 1. EvoSuite no repositorio Maven
# ---------------------------------------------------------------------------

# O jar traz embutido o pom original, que herda de org.evosuite:evosuite:1.1.0,
# um parent que nunca foi publicado. O jar e shaded e nao tem dependencia
# transitiva, entao um pom minimo resolve sem efeito colateral.
EVOSUITE_POM="<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<project xmlns=\"http://maven.apache.org/POM/4.0.0\">
  <modelVersion>4.0.0</modelVersion>
  <groupId>org.evosuite</groupId>
  <artifactId>evosuite-standalone-runtime</artifactId>
  <version>1.1.0</version>
  <packaging>jar</packaging>
</project>"

# Copia em vez de install:install-file: dispensa Maven no host e container. Sem
# _remote.repositories, o Maven trata o artefato como instalado localmente e o
# aceita de qualquer repositorio, inclusive pelo mirror do Nexus. Marcas de uma
# tentativa de download anterior (*.lastUpdated) sao removidas pelo mesmo motivo.
install_evosuite() {
  [ -f "$EVOSUITE_JAR" ] || fail "jar do EvoSuite nao encontrado: $EVOSUITE_JAR"
  local actual
  actual=$(sha256sum "$EVOSUITE_JAR" | cut -d' ' -f1)
  [ "$actual" = "$EVOSUITE_SHA256" ] || fail "sha256 inesperado em $EVOSUITE_JAR (esperado o evosuite-standalone-runtime 1.1.0)"

  mkdir -p "$EVOSUITE_REPO_DIR" || fail "nao foi possivel criar $EVOSUITE_REPO_DIR"
  local jar="$EVOSUITE_REPO_DIR/evosuite-standalone-runtime-1.1.0.jar"
  local pom="$EVOSUITE_REPO_DIR/evosuite-standalone-runtime-1.1.0.pom"

  # Escrita atomica (temporario + mv): projetos em paralelo podem chegar aqui juntos.
  if [ ! -f "$jar" ] || [ "$(sha256sum "$jar" | cut -d' ' -f1)" != "$EVOSUITE_SHA256" ]; then
    cp "$EVOSUITE_JAR" "$jar.tmp.$$" && mv -f "$jar.tmp.$$" "$jar" || fail "falha ao copiar o jar para $EVOSUITE_REPO_DIR"
  fi
  if [ ! -f "$pom" ] || [ "$(cat "$pom")" != "$EVOSUITE_POM" ]; then
    printf '%s\n' "$EVOSUITE_POM" > "$pom.tmp.$$" && mv -f "$pom.tmp.$$" "$pom" || fail "falha ao gravar o pom em $EVOSUITE_REPO_DIR"
  fi
  rm -f "$EVOSUITE_REPO_DIR"/*.lastUpdated "$EVOSUITE_REPO_DIR/_remote.repositories" "$EVOSUITE_REPO_DIR/resolver-status.properties"
}

# ---------------------------------------------------------------------------
# Maven no container
# ---------------------------------------------------------------------------

# Roda `mvn dependency:list` como o Safer roda (-B -q -f pom.xml, saida num
# arquivo relativo a raiz) e deixa a saida em $LOGS_DIR/<rotulo>.list.
dependency_list() {
  local label="$1"; shift
  local out=".prepare-$$-$label.txt"
  local log="$LOGS_DIR/mvn-$label.log"

  docker exec "$CONTAINER" timeout -s KILL "$RESOLVE_TIMEOUT" \
    mvn -B -q -f pom.xml dependency:list "$@" "-DoutputFile=$out" > "$log" 2>&1
  local status=$?

  if [ "$status" -eq 0 ] && [ -f "$PROJECT_PATH/$out" ]; then
    mv -f "$PROJECT_PATH/$out" "$LOGS_DIR/$label.list"
  else
    status=1
  fi
  # Num multi-modulo, cada modulo grava o proprio arquivo.
  find "$PROJECT_PATH" -name "$out" -type f -delete 2>/dev/null
  return $status
}

runtime_tree() {
  local label="$1"
  dependency_list "$label" -DincludeScope=runtime || return 1
  python3 "$POM_TOOLS" tree "$LOGS_DIR/$label.list" > "$LOGS_DIR/$label.txt"
}

# O jupiter e o vintage sao publicados juntos: o Platform 1.X.Y corresponde ao
# vintage 5.X.Y (a partir do JUnit 6, as versoes sao iguais). Muitos projetos
# gerenciam o Platform numa versao antiga (o spring-boot-starter-test 2.1 fixa
# 1.3.2), e o vintage 5.10.0 rebaixado para esse Platform quebra na descoberta
# com "NoClassDefFoundError: org/junit/platform/commons/util/LruCache" -- e com
# -DfailIfNoTests=true a build falha. A versao gerenciada so aparece depois que
# o vintage entra no pom, por isso a consulta vem depois da injecao.
align_vintage() {
  dependency_list all-scopes || return 1
  local platform
  platform=$(python3 "$POM_TOOLS" platform "$LOGS_DIR/all-scopes.list")
  [ -n "$platform" ] || return 1

  case "$platform" in
    1.*) vintage="5.${platform#1.}" ;;
    *)   vintage="$platform" ;;
  esac

  if [ "$vintage" != "$DEFAULT_VINTAGE" ]; then
    python3 "$POM_TOOLS" set-vintage "$POM" "$vintage" || return 1
    echo "  [preparo] junit-vintage-engine alinhado em $vintage (JUnit Platform $platform)"
  fi
}

# ---------------------------------------------------------------------------
# 5. .mvn/maven.config
# ---------------------------------------------------------------------------

# O Maven 3.9 le uma opcao por linha. As flags entram no fim, para prevalecer
# sobre as do projeto; as que ja estao la nao sao repetidas. O Safer continua
# podendo desligar os testes: o -DskipTests que ele passa na linha de comando
# prevalece sobre o maven.config.
write_maven_config() {
  local config="$PROJECT_PATH/.mvn/maven.config" flag
  mkdir -p "$PROJECT_PATH/.mvn" || return 1
  touch "$config" || return 1
  [ -s "$config" ] && [ -n "$(tail -c1 "$config")" ] && echo >> "$config"

  for flag in "${MAVEN_CONFIG_FLAGS[@]}"; do
    grep -qxF -- "$flag" "$config" || echo "$flag" >> "$config"
  done
}

# ---------------------------------------------------------------------------
# Saida
# ---------------------------------------------------------------------------

CSV_HEADER="id,project,injected,vintage,tree,added,removed"
injected="" vintage="" tree="not_injected" added="" removed=""

append_row() {
  ( flock 9
    [ -s "$OUTPUT_CSV" ] || echo "$CSV_HEADER" >> "$OUTPUT_CSV"
    echo "$RUN_ID,$PROJECT_NAME,$injected,$vintage,$tree,$added,$removed" >> "$OUTPUT_CSV"
  ) 9>>"$OUTPUT_CSV"
}

# ---------------------------------------------------------------------------
# Execucao
# ---------------------------------------------------------------------------

pretty_print blue "  [preparo] $PROJECT_NAME"

[ -f "$POM" ] || fail "pom.xml nao encontrado em $PROJECT_PATH"

has_generated_tests=false
if [ -d "$PROJECT_PATH/src/test/java" ] && \
   find "$PROJECT_PATH/src/test/java" -type d \( -name evosuite-tests -o -name kex-tests \) -print -quit | grep -q .; then
  has_generated_tests=true
fi

if $has_generated_tests; then
  missing=$(python3 "$POM_TOOLS" missing "$POM") || fail "nao foi possivel ler o pom.xml"

  if [ -n "$missing" ]; then
    [ -n "$CONTAINER" ] || fail "ha dependencias a injetar; informe o container com --container"
    docker exec "$CONTAINER" true >/dev/null 2>&1 || fail "container $CONTAINER nao esta em execucao"
    install_evosuite
    cp "$POM" "$LOGS_DIR/pom.xml.orig"

    tree_ok=true
    runtime_tree runtime-before || tree_ok=false

    injected_list=$(python3 "$POM_TOOLS" inject "$POM" "$DEFAULT_VINTAGE") || fail "falha ao injetar as dependencias no pom.xml"
    injected=$(echo "$injected_list" | paste -sd';')
    echo "  [preparo] injetadas: ${injected//;/, }"

    if echo "$injected_list" | grep -qx 'org.junit.vintage:junit-vintage-engine'; then
      vintage="$DEFAULT_VINTAGE"
      if ! align_vintage; then
        pretty_print yellow "  [preparo] nao foi possivel alinhar o junit-vintage-engine; fica o $DEFAULT_VINTAGE (veja $LOGS_DIR/mvn-all-scopes.log)"
      fi
    fi

    $tree_ok && { runtime_tree runtime-after || tree_ok=false; }

    if ! $tree_ok; then
      tree="error"
      pretty_print yellow "  [preparo] nao foi possivel comparar a arvore de runtime (veja os logs em $LOGS_DIR)"
    elif cmp -s "$LOGS_DIR/runtime-before.txt" "$LOGS_DIR/runtime-after.txt"; then
      tree="same"
    else
      tree="changed"
      # LC_ALL=C: o pom_tools.py ordena por codigo de caractere, como o locale C.
      added=$(LC_ALL=C comm -13 "$LOGS_DIR/runtime-before.txt" "$LOGS_DIR/runtime-after.txt" | paste -sd';')
      removed=$(LC_ALL=C comm -23 "$LOGS_DIR/runtime-before.txt" "$LOGS_DIR/runtime-after.txt" | paste -sd';')
      pretty_print yellow "  [preparo] a injecao mudou a arvore de runtime: +[${added//;/, }] -[${removed//;/, }]"
    fi
  fi
fi

write_maven_config || fail "falha ao gravar $PROJECT_PATH/.mvn/maven.config"

append_row
pretty_print green "  [preparo] OK (arvore: $tree)"
exit 0
