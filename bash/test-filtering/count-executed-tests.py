#!/usr/bin/env python3
"""Conta quantos testes o Surefire de fato executou num projeto.

Le os relatorios XML (TEST-*.xml) em vez do log, porque o formato do log muda
entre versoes do Surefire -- o 2.12.4, por exemplo, nao prefixa as linhas com
[INFO]. Uma build verde com zero testes nao validou nada: o motor de testes pode
ter falhado na descoberta e engolido o erro.

Uso: count-executed-tests.py <project_path>
"""

import os
import sys
import xml.etree.ElementTree as ET


def main():
    total = 0
    for current, directories, files in os.walk(sys.argv[1]):
        directories[:] = [d for d in directories if d != '.git']
        if os.path.basename(current) != 'surefire-reports':
            continue
        for name in files:
            if not (name.startswith('TEST-') and name.endswith('.xml')):
                continue
            try:
                total += sum(1 for _ in ET.parse(os.path.join(current, name)).getroot().iter('testcase'))
            except ET.ParseError:
                continue
    print(total)


if __name__ == '__main__':
    main()
