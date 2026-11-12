// Para cada dependencia avaliada pelo Safer, calcula a distancia (em versoes
// publicadas) entre a versao atual e a adotada, e entre a adotada e a mais
// recente.
//
// A lista de versoes vem do evento "candidates" de cada execucao: as versoes
// mais novas que a atual, inclusive as que o Safer descarta (pre-releases,
// versoes com data, outros "sabores"), como a lista do Sonatype que o script
// antigo lia do dependencies-versions.txt. O get-dependencies-versions.sh deixa
// de ser necessario.
import path from 'path';

import { candidateLists, dependencyOutcomes, findRunDir, newerVersions, parseArgs, readCsv, readEvents, readRun, semVerChange, writeCsv } from '../../lib/safer-run';

const USAGE = `Uso: tsx src/script.ts <dataset.csv> [-o saida.csv] [--outputs DIR]

  <dataset.csv>   dataset gravado pelo bash/report-to-csv.py
  -o, --output    padrao: version-changes-<nome do dataset>, na mesma pasta
  --outputs       pasta das saidas do Safer (padrao: <kit>/outputs/v2)`;

const HEADER = ['projectName', 'tests', 'javaVersion', 'dependency', 'oldVersion', 'newVersion', 'mostRecentVersion', 'oldVersionOffset', 'mostRecentVersionOffset', 'semVerChange', 'id'];

const args = parseArgs(process.argv.slice(2), USAGE);
const output = args.output ?? path.join(path.dirname(args.input), `version-changes-${path.basename(args.input)}`);
const { rows } = readCsv(args.input);
const out: Record<string, unknown>[] = [];

for (const row of rows) {
  const project = row['Project Name'];
  const runDir = findRunDir(args.outputs, project, row['id']);
  console.log(`=================== [${row['id']}] ${project}`);
  if (!runDir) {
    console.error(`Erro: pasta da execucao nao encontrada em ${path.join(args.outputs, project)}`);
    continue;
  }

  const javaVersion = readRun(runDir).tools?.java ?? '-';
  const events = readEvents(runDir);
  const lists = candidateLists(events);

  for (const o of dependencyOutcomes(events)) {
    const list = lists.get(o.dep);
    if (!list) {
      console.error(`Erro: sem lista de versoes para ${o.dep}`);
      continue;
    }
    const versions = [o.oldVersion, ...newerVersions(list)];
    const index = versions.indexOf(o.newVersion);
    if (index < 0) {
      console.error(`Erro: ${o.dep} ${o.newVersion} nao esta na lista de versoes`);
      continue;
    }
    const changed = index !== 0;
    const record = {
      projectName: project,
      tests: row['Tests'],
      javaVersion,
      dependency: o.dep,
      oldVersion: o.oldVersion,
      newVersion: o.newVersion,
      mostRecentVersion: versions[versions.length - 1],
      oldVersionOffset: index,
      mostRecentVersionOffset: versions.length - index - 1,
      semVerChange: changed ? semVerChange(o.oldVersion, o.newVersion) : 'not changed',
      id: row['id'],
    };
    console.log(record);
    out.push(record);
  }
}

writeCsv(output, HEADER, out);
console.log(`CSV written to ${output}`);
