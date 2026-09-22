#!/usr/bin/env python3
"""Le o log do Maven e os relatorios do Surefire de uma execucao e lista os
arquivos de teste que precisam ser apagados.

Tres fontes de problema sao consideradas:

  compile_error  o javac reclamou do arquivo, entao o projeto nem chega a rodar
  test_failure   o Surefire registrou <failure> na classe
  test_error     o Surefire registrou <error> na classe (inclui initializationError)
  crash          a VM forkada morreu levando a classe junto

Toda suite EvoSuite apagada leva junto o seu *_ESTest_scaffolding.java, que so
existe para servir aquela suite. O scaffolding sai com o motivo "scaffolding" e
nao entra na contagem de testes apagados.

Uso: collect-failing-tests.py <project_path> <maven_log> <manifest>
Saida: TSV com relpath na copia de trabalho, categoria, motivo e caminho de
origem no projeto real (onde a suite de fato mora e deve ser apagada).
Codigo 2: houve falha que nao pode ser atribuida a nenhum arquivo do manifesto,
sinalizando ao chamador que apagar suites nao vai resolver a build.
"""

import os
import re
import sys
import xml.etree.ElementTree as ET

TEST_ROOT = 'src/test/java/'

# [ERROR] /app/src/test/java/com/foo/Bar_ESTest.java:[42,17] cannot find symbol
COMPILE_ERROR = re.compile(r'^\[ERROR\]\s+(/[^\s:\[\]]+\.java):\[\d+')

# Bloco "Crashed tests:" que o Surefire imprime quando a VM forkada morre.
CRASH_HEADER = re.compile(r'^\[ERROR\]\s+Crashed tests:\s*$')
CRASHED_CLASS = re.compile(r'^\[ERROR\]\s+([A-Za-z_$][\w.$]*)\s*$')


def load_manifest(manifest_path):
    """relpath -> (categoria, origem), montado quando as suites foram posicionadas."""
    entries = {}
    with open(manifest_path, encoding='utf-8') as manifest:
        for line in manifest:
            line = line.rstrip('\n')
            if not line:
                continue
            fields = line.split('\t')
            relpath, category = fields[0], fields[1]
            entries[relpath] = (category, fields[2] if len(fields) > 2 else relpath)
    return entries


PACKAGE = re.compile(r'^\s*package\s+([\w.]+)\s*;', re.MULTILINE)


def class_index(project_path, categories):
    """Nome qualificado da classe -> relpath, para casar com o Surefire.

    O nome sai do package declarado no arquivo, e nao do caminho: no layout do
    pipeline o Kex fica em src/test/java/kex-tests/tests/<pacote>/, e o caminho
    daria "kex-tests.tests.<pacote>.X" em vez do "<pacote>.X" que o Surefire
    reporta.
    """
    index = {}
    for relpath in categories:
        simple_name = os.path.basename(relpath)[:-len('.java')]
        try:
            with open(os.path.join(project_path, relpath), encoding='utf-8', errors='replace') as source:
                match = PACKAGE.search(source.read())
        except OSError:
            continue
        index[match.group(1) + '.' + simple_name if match else simple_name] = relpath
    return index


def to_relpath(absolute, project_path):
    """Converte o caminho impresso pelo Maven em caminho relativo ao projeto.

    O Maven roda dentro do container, entao os caminhos vem sob /app. O prefixo
    do host tambem e aceito para o caso de a build ter rodado fora do Docker.
    """
    for prefix in ('/app/', project_path.rstrip('/') + '/'):
        if absolute.startswith(prefix):
            return absolute[len(prefix):]

    marker = absolute.find(TEST_ROOT)
    return absolute[marker:] if marker != -1 else None


def compile_errors(log_path, project_path, categories):
    found = []
    unmapped = 0

    with open(log_path, encoding='utf-8', errors='replace') as log:
        for line in log:
            match = COMPILE_ERROR.match(line.rstrip('\n'))
            if not match:
                continue

            relpath = to_relpath(match.group(1), project_path)
            if relpath in categories:
                found.append((relpath, 'compile_error'))
            else:
                # Erro em src/main ou em arquivo fora do manifesto: apagar suite
                # nao resolve, entao so contabiliza para o chamador desistir.
                unmapped += 1

    return found, unmapped


def crashed_classes(log_path, classes):
    found = []
    inside_block = False

    with open(log_path, encoding='utf-8', errors='replace') as log:
        for line in log:
            line = line.rstrip('\n')

            if CRASH_HEADER.match(line):
                inside_block = True
                continue

            if not inside_block:
                continue

            match = CRASHED_CLASS.match(line)
            if not match:
                inside_block = False
                continue

            relpath = classes.get(match.group(1))
            if relpath:
                found.append((relpath, 'crash'))

    return found


def surefire_reports(project_path):
    for current, directories, files in os.walk(project_path):
        directories[:] = [d for d in directories if d != '.git']
        if os.path.basename(current) != 'surefire-reports':
            continue
        for name in files:
            if name.startswith('TEST-') and name.endswith('.xml'):
                yield os.path.join(current, name)


def failing_suites(project_path, classes):
    """Classes com falha nos relatorios do Surefire.

    A falha e atribuida pelo classname de cada testcase, e nao pelo nome da
    suite: com TestNG o Surefire grava um unico TEST-TestSuite.xml, com
    name="TestSuite", e a classe de verdade so aparece no testcase. O nome da
    suite fica como alternativa para erros que o Surefire registra so no nivel
    da suite, como o initializationError.
    """
    reasons = {}
    unmapped = set()

    def record(class_name, reason):
        class_name = (class_name or '').split('$')[0]
        relpath = classes.get(class_name)
        if not relpath:
            unmapped.add(class_name)
            return
        # Um erro prevalece sobre uma falha de assercao na mesma classe.
        if reasons.get(relpath) != 'test_error':
            reasons[relpath] = reason

    for report in surefire_reports(project_path):
        try:
            root = ET.parse(report).getroot()
        except ET.ParseError:
            # Relatorio truncado costuma significar que a VM morreu no meio da
            # classe; o bloco "Crashed tests:" do log cobre esse caso.
            continue

        suites = [root] if root.tag == 'testsuite' else root.iter('testsuite')

        for suite in suites:
            found_in_cases = False

            for case in suite.iter('testcase'):
                if case.find('error') is not None:
                    reason = 'test_error'
                elif case.find('failure') is not None:
                    reason = 'test_failure'
                else:
                    continue
                found_in_cases = True
                record(case.get('classname') or suite.get('name'), reason)

            if not found_in_cases and (int(suite.get('errors', 0) or 0)
                                       or int(suite.get('failures', 0) or 0)):
                record(suite.get('name'), 'test_error')

    return list(reasons.items()), len(unmapped)


def with_scaffolding(selected, categories):
    """Acrescenta o scaffolding EvoSuite de cada suite marcada para exclusao."""
    extra = []
    for relpath, _ in selected:
        if not relpath.endswith('_ESTest.java'):
            continue
        scaffolding = relpath[:-len('.java')] + '_scaffolding.java'
        if scaffolding in categories:
            extra.append((scaffolding, 'scaffolding'))
    return extra


def main():
    project_path, log_path, manifest_path = sys.argv[1:4]

    categories = load_manifest(manifest_path)
    classes = class_index(project_path, categories)

    from_compiler, unmapped_compiler = compile_errors(log_path, project_path, categories)
    from_surefire, unmapped_surefire = failing_suites(project_path, classes)

    selected = from_compiler + from_surefire + crashed_classes(log_path, classes)
    selected += with_scaffolding(selected, categories)

    emitted = set()
    for relpath, reason in selected:
        if relpath in emitted:
            continue
        emitted.add(relpath)
        category, origin = categories[relpath]
        print('%s\t%s\t%s\t%s' % (relpath, category, reason, origin))

    if unmapped_compiler or unmapped_surefire:
        sys.exit(2)


if __name__ == '__main__':
    main()
