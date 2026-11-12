#!/usr/bin/env python3
"""Ferramentas de pom.xml e de saida do Maven para o prepare-project.sh.

O pom.xml e editado como texto, e nao reescrito por um parser XML: o
ElementTree descarta comentarios, troca aspas e prefixos de namespace, e o pom
sairia diferente do original em linhas que nada tem a ver com a injecao. Aqui,
o arquivo so ganha os blocos <dependency> injetados.

Subcomandos:
  missing <pom>                 Lista (groupId:artifactId) das dependencias de
                                teste que faltam no <dependencies> do projeto.
  inject <pom> <vintage>        Injeta as que faltam, com escopo test, e lista
                                as injetadas.
  set-vintage <pom> <versao>    Troca a versao do junit-vintage-engine declarado
                                no <dependencies> do projeto.
  tree <arquivo>                Le a saida de `mvn dependency:list -DoutputFile`
                                e imprime g:a:v ordenado, sem repeticao.
  platform <arquivo>            Imprime a versao do JUnit Platform resolvida.
"""

import re
import sys
import xml.etree.ElementTree as ET

EVOSUITE_VERSION = '1.1.0'
JUNIT_VERSION = '4.13.2'

#O vintage recebe a versao na chamada, porque depois ela e alinhada com o JUnit Platform do projeto.
REQUIRED = [
    ('org.evosuite', 'evosuite-standalone-runtime', EVOSUITE_VERSION),
    ('junit', 'junit', JUNIT_VERSION),
    ('org.junit.vintage', 'junit-vintage-engine', None),
]

MASKED_SECTIONS = [
    r'<!--.*?-->',
    r'<dependencyManagement\s*>.*?</dependencyManagement\s*>',
    r'<profiles\s*>.*?</profiles\s*>',
    r'<build\s*>.*?</build\s*>',
    r'<reporting\s*>.*?</reporting\s*>',
]

DEPENDENCY = re.compile(r'<dependency>.*?</dependency>', re.S)


def read(path):
    with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
        return f.read()


def write(path, text):
    with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
        f.write(text)


def mask(text):
    """Apaga (com espacos, mantendo as posicoes) o que nao e do projeto."""
    for pattern in MASKED_SECTIONS:
        text = re.sub(pattern, lambda m: ' ' * len(m.group(0)), text, flags=re.S)
    return text


def tag(text, name):
    m = re.search(r'<%s>\s*([^<]*?)\s*</%s>' % (re.escape(name), re.escape(name)), text)
    return m.group(1) if m else None


def project_dependencies(text):
    """(inicio, fim) do conteudo do <dependencies> do projeto, ou None."""
    masked = mask(text)
    opens = [m.end() for m in re.finditer(r'<dependencies\s*>', masked)]
    if not opens:
        return None
    if len(opens) > 1:
        raise SystemExit('pom.xml com mais de um <dependencies> no nivel do projeto')
    close = re.compile(r'</dependencies\s*>').search(masked, opens[0])
    if close is None:
        raise SystemExit('pom.xml com <dependencies> sem fechamento')
    return opens[0], close.start()


def declared(text):
    """[(groupId, artifactId, (inicio, fim))] declarados no <dependencies> do projeto."""
    span = project_dependencies(text)
    if span is None:
        return []
    masked = mask(text)
    result = []
    for m in DEPENDENCY.finditer(masked, span[0], span[1]):
        own = re.sub(r'<exclusions>.*?</exclusions>', '', m.group(0), flags=re.S)
        result.append((tag(own, 'groupId') or '', tag(own, 'artifactId') or '', (m.start(), m.end())))
    return result


def missing(text):
    present = {(g, a) for g, a, _ in declared(text)}
    return [(g, a, v) for g, a, v in REQUIRED if (g, a) not in present]


def line_indent(text, position):
    start = text.rfind('\n', 0, position) + 1
    return re.match(r'[ \t]*', text[start:]).group(0)


def indent_unit(text):
    """Recuo de um nivel, deduzido do primeiro filho de <project>."""
    m = re.search(r'\n([ \t]+)<modelVersion>', text)
    return m.group(1) if m else '    '


def render(deps, vintage, indent, unit, newline):
    lines = [indent + '<!-- adicionadas pelo prepare-project.sh do kit de reproducao -->']
    for group, artifact, version in deps:
        lines += [
            indent + '<dependency>',
            indent + unit + '<groupId>%s</groupId>' % group,
            indent + unit + '<artifactId>%s</artifactId>' % artifact,
            indent + unit + '<version>%s</version>' % (version or vintage),
            indent + unit + '<scope>test</scope>',
            indent + '</dependency>',
        ]
    return newline.join(lines)


def check_well_formed(original, edited):
    try:
        ET.fromstring(original.encode('utf-8', 'surrogateescape'))
    except ET.ParseError:
        return
    try:
        ET.fromstring(edited.encode('utf-8', 'surrogateescape'))
    except ET.ParseError as error:
        raise SystemExit('a injecao deixaria o pom.xml invalido: %s' % error)


def inject(path, vintage):
    text = read(path)
    deps = missing(text)
    if not deps:
        return []

    empty = re.search(r'<dependencies\s*/>', mask(text))
    if empty:
        text = text[:empty.start()] + '<dependencies></dependencies>' + text[empty.end():]

    newline = '\r\n' if '\r\n' in text else '\n'
    unit = indent_unit(text)
    span = project_dependencies(text)

    if span is not None:
        existing = declared(text)
        close_indent = line_indent(text, span[1])
        indent = line_indent(text, existing[0][2][0]) if existing else close_indent + unit
        # Entra logo antes da linha do </dependencies>, depois do ultimo bloco.
        # Se o </dependencies> divide a linha com outra coisa, entra colado nele,
        # para nunca cair dentro do ultimo <dependency>.
        insert_at = text.rfind('\n', span[0], span[1])
        if insert_at >= 0 and not text[insert_at:span[1]].strip():
            block = newline + render(deps, vintage, indent, unit, newline)
        else:
            insert_at = span[1]
            block = newline + render(deps, vintage, indent, unit, newline) + newline + close_indent
        edited = text[:insert_at] + block + text[insert_at:]
    else:
        masked = mask(text)
        close = masked.rfind('</project>')
        if close < 0:
            raise SystemExit('pom.xml sem </project>')
        insert_at = text.rfind('\n', 0, close) + 1
        block = (unit + '<dependencies>' + newline
                 + render(deps, vintage, unit + unit, unit, newline) + newline
                 + unit + '</dependencies>' + newline)
        edited = text[:insert_at] + block + text[insert_at:]

    check_well_formed(text, edited)
    write(path, edited)
    return deps


def set_vintage(path, version):
    text = read(path)
    masked = mask(text)
    for group, artifact, (start, end) in declared(text):
        if (group, artifact) == ('org.junit.vintage', 'junit-vintage-engine'):
            found = re.compile(r'<version>\s*([^<]*?)\s*</version>').search(masked, start, end)
            if found is None:
                raise SystemExit('junit-vintage-engine declarado sem <version>')
            write(path, text[:found.start(1)] + version + text[found.end(1):])
            return
    raise SystemExit('junit-vintage-engine nao declarado no <dependencies> do projeto')


def parse_dependency_list(path):
    """Mesmo formato que o Safer le: group:artifact:type[:classifier]:version:scope [-- module ...]."""
    result = []
    with open(path, encoding='utf-8', errors='replace') as f:
        for raw in f:
            line = re.sub(r'\s+--\s+module.*$', '', raw).strip()
            parts = line.split(':')
            if len(parts) not in (5, 6) or not re.match(r'^[\w.-]+$', parts[0]):
                continue
            result.append((parts[0], parts[1], parts[-2], parts[-1]))
    return result


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    command, path = sys.argv[1], sys.argv[2]

    if command == 'missing':
        for group, artifact, _ in missing(read(path)):
            print('%s:%s' % (group, artifact))
    elif command == 'inject':
        for group, artifact, _ in inject(path, sys.argv[3]):
            print('%s:%s' % (group, artifact))
    elif command == 'set-vintage':
        set_vintage(path, sys.argv[3])
    elif command == 'tree':
        for gav in sorted({'%s:%s:%s' % (g, a, v) for g, a, v, _ in parse_dependency_list(path)}):
            print(gav)
    elif command == 'platform':
        versions = {a: v for g, a, v, _ in parse_dependency_list(path) if g == 'org.junit.platform'}
        version = versions.get('junit-platform-engine') or versions.get('junit-platform-commons')
        if version:
            print(version)
    else:
        raise SystemExit(__doc__)


if __name__ == '__main__':
    main()
