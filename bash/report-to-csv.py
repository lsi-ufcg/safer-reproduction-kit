#!/usr/bin/env python3
"""Converte uma execucao do Safer novo numa linha do dataset do experimento.

O Safer antigo imprimia uma linha depois de "CSV:" no stdout; o novo grava os
resultados numa pasta por execucao (a da linha "Safer run dir:"). Este script le
essa pasta e escreve a linha com as mesmas colunas de antes, para que os
notebooks continuem funcionando, mais cinco colunas no fim:

  Unknown vulnerabilities (Before/After)  vulnerabilidades sem severidade; o
                                          Safer novo as conta com peso zero
  Rate (Before/After)                     a metrica que o Safer novo usa para
                                          decidir: soma de (nota CVSS x peso)
  Tests Executed                          se a build do baseline rodou os testes.
                                          O Safer os desliga sozinho quando nao
                                          sobra nenhum @Test (por exemplo, quando
                                          o filtro apagou todas as suites), mesmo
                                          com projectTests=true no config

As colunas antigas mantem o significado, com estas diferencas de origem:
  - Tests: o executions.projectTests do config, como no Safer antigo.
  - Improved: a mesma formula do run-experiment.sh antigo (low*1 + medium*2 +
    high*3 + critical*5, depois menor que antes), sobre as contagens do Safer novo.
  - Number of vulnerabilities / por severidade: o Safer novo conta IDs distintos
    (aliases juntados) na arvore de runtime inteira.
  - Number of dependencies with vulnerabilities: artefatos da arvore de runtime
    (trees/baseline.txt e trees/final.txt) com ao menos um ID no osv/ids.json.

Uso:
  report-to-csv.py --run-dir DIR --output CSV --id N [--project NOME]
                   [--execution-time S] [--artifacts COMMIT]

--project e o nome gravado em Project Name (padrao: o do report.json). O
execucao_safer.sh retoma a execucao comparando essa coluna com o nome da pasta
do projeto, por isso o run-experiment.sh passa o nome da pasta.

Saida: 0 com a linha gravada; 2 quando a execucao nao terminou com sucesso
(sem report.json, ou run.json com status diferente de ok) -- nesse caso nada e
gravado; 1 em erro de uso ou de leitura.
"""

import argparse
import csv
import fcntl
import json
import os
import re
import sys

HEADER = [
    'id',
    'Project Name',
    'Number of dependencies with vulnerabilities (Before)',
    'Number of dependencies with vulnerabilities (After)',
    'Number of vulnerabilities (Before)',
    'Number of vulnerabilities (After)',
    'Low vulnerabilities (Before)',
    'Low vulnerabilities (After)',
    'Medium vulnerabilities (Before)',
    'Medium vulnerabilities (After)',
    'High vulnerabilities (Before)',
    'High vulnerabilities (After)',
    'Critical vulnerabilities (Before)',
    'Critical vulnerabilities (After)',
    'Build Tool',
    'Tests',
    'Project Type',
    'Execution Time (s)',
    'Artifacts',
    'Improved',
    'Unknown vulnerabilities (Before)',
    'Unknown vulnerabilities (After)',
    'Rate (Before)',
    'Rate (After)',
    'Tests Executed',
]

# Pesos fixos do run-experiment.sh antigo, para o Improved manter o significado.
OLD_WEIGHTS = {'low': 1, 'medium': 2, 'high': 3, 'critical': 5}


class NotSuccessful(Exception):
    pass


def load_json(path):
    with open(path, encoding='utf-8') as f:
        return json.load(f)


def read_run(run_dir):
    run_path = os.path.join(run_dir, 'run.json')
    report_path = os.path.join(run_dir, 'report.json')
    if not os.path.isfile(run_path):
        raise NotSuccessful('sem run.json em %s' % run_dir)
    run = load_json(run_path)
    if run.get('status') != 'ok':
        raise NotSuccessful('execucao com status %s: %s' % (run.get('status'), run.get('error', '')))
    if not os.path.isfile(report_path):
        raise NotSuccessful('sem report.json em %s' % run_dir)
    return run, load_json(report_path)


def baseline_build(run_dir):
    """Texto da build do baseline bem-sucedido, ex.: 'build ok (tests on, 3m12s)'."""
    with open(os.path.join(run_dir, 'decisions.jsonl'), encoding='utf-8') as f:
        for line in f:
            event = json.loads(line)
            data = event.get('data') or {}
            if event.get('type') == 'baseline' and data.get('ok') and 'build' in data:
                return data['build']
    raise ValueError('evento baseline nao encontrado em decisions.jsonl')


def tests_executed(build):
    m = re.search(r'\(tests (on|off)\b', build)
    return bool(m) and m.group(1) == 'on'


def vulnerable_dependencies(run_dir, tree_name, ids):
    path = os.path.join(run_dir, 'trees', '%s.txt' % tree_name)
    count = 0
    with open(path, encoding='utf-8') as f:
        for line in f:
            gav = line.strip()
            if not gav:
                continue
            if gav not in ids:
                raise ValueError('%s, de trees/%s.txt, nao esta no osv/ids.json' % (gav, tree_name))
            if ids[gav]:
                count += 1
    return count


def old_score(by_severity):
    return sum(by_severity.get(level, 0) * weight for level, weight in OLD_WEIGHTS.items())


def number(value):
    return ('%d' % value) if float(value).is_integer() else repr(float(value))


def build_row(args):
    run, report = read_run(args.run_dir)
    ids = load_json(os.path.join(args.run_dir, 'osv', 'ids.json'))
    before, after = report['before'], report['after']
    bs, as_ = before['bySeverity'], after['bySeverity']

    improved = old_score(as_) < old_score(bs)
    return [
        args.id,
        args.project or report['project'],
        vulnerable_dependencies(args.run_dir, 'baseline', ids),
        vulnerable_dependencies(args.run_dir, 'final', ids),
        before['distinct'],
        after['distinct'],
        bs['low'], as_['low'],
        bs['medium'], as_['medium'],
        bs['high'], as_['high'],
        bs['critical'], as_['critical'],
        'maven',
        'true' if run['config']['projectTests'] else 'false',
        'open source',
        args.execution_time,
        args.artifacts,
        'improvement' if improved else 'no improvement',
        bs.get('unknown', 0), as_.get('unknown', 0),
        number(before['rate']), number(after['rate']),
        'true' if tests_executed(baseline_build(args.run_dir)) else 'false',
    ]


def append(output, row):
    directory = os.path.dirname(os.path.abspath(output))
    os.makedirs(directory, exist_ok=True)
    with open(output, 'a+', encoding='utf-8', newline='') as f:
        # Projetos em paralelo (run-experiments.sh) gravam no mesmo arquivo.
        fcntl.flock(f, fcntl.LOCK_EX)
        f.seek(0)
        first = f.readline().rstrip('\r\n')
        if first and next(csv.reader([first])) != HEADER:
            raise SystemExit(
                'erro: %s tem outro cabecalho (talvez seja um dataset do Safer antigo); '
                'use outro arquivo para nao misturar formatos' % output)
        writer = csv.writer(f, lineterminator='\n')
        if not first:
            writer.writerow(HEADER)
        writer.writerow(row)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--run-dir', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--id', required=True)
    parser.add_argument('--project', default='')
    parser.add_argument('--execution-time', default='')
    parser.add_argument('--artifacts', default='')
    args = parser.parse_args()

    try:
        row = build_row(args)
    except NotSuccessful as error:
        print('report-to-csv: %s' % error, file=sys.stderr)
        return 2
    except (OSError, ValueError, KeyError) as error:
        print('report-to-csv: falha ao ler %s: %s' % (args.run_dir, error), file=sys.stderr)
        return 1

    append(args.output, row)
    print(','.join(str(v) for v in row))
    return 0


if __name__ == '__main__':
    sys.exit(main())
