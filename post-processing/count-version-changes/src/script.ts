// Acrescenta ao dataset, por linha, a versao de Java e a contagem das mudancas
// de versao que o Safer aplicou, por tipo (semver).
//
// Mantem todas as colunas do dataset de entrada, inclusive as que o
// report-to-csv.py acrescentou, e poe as novas no fim.
import { DependencyOutcome, dependencyOutcomes, findRunDir, parseArgs, readCsv, readEvents, readRun, semVerChange, writeCsv } from '../../lib/safer-run';
import path from 'path';

const USAGE = `Uso: tsx src/script.ts <dataset.csv> [-o saida.csv] [--outputs DIR]

  <dataset.csv>   dataset gravado pelo bash/report-to-csv.py
  -o, --output    padrao: final-<nome do dataset>, na mesma pasta
  --outputs       pasta das saidas do Safer (padrao: <kit>/outputs/v2)`;

const COLUMNS = ['javaVersion', 'countMajor', 'countMinor', 'countPatch', 'countPrerelease', 'countBuildmetadata', 'countNoChange', 'countOther'] as const;

/**
 * countNoChange: dependencias que o Safer avaliou e manteve na mesma versao.
 * countOther: mudancas que nao cabem nas cinco categorias (versao fora do
 * formato X.Y.Z, ou diferenca so no 4o numero/qualificador). O script antigo
 * as descartava sem contar; com esta coluna, a soma das contagens e o total de
 * dependencias avaliadas.
 */
function count(outcomes: DependencyOutcome[]): Record<string, number> {
  const c = { countMajor: 0, countMinor: 0, countPatch: 0, countPrerelease: 0, countBuildmetadata: 0, countNoChange: 0, countOther: 0 };
  for (const o of outcomes) {
    if (o.oldVersion === o.newVersion) {
      c.countNoChange++;
      continue;
    }
    const change = semVerChange(o.oldVersion, o.newVersion);
    switch (change) {
      case 'major': c.countMajor++; break;
      case 'minor': c.countMinor++; break;
      case 'patch': c.countPatch++; break;
      case 'prerelease': c.countPrerelease++; break;
      case 'buildmetadata': c.countBuildmetadata++; break;
      default: c.countOther++;
    }
  }
  return c;
}

const args = parseArgs(process.argv.slice(2), USAGE);
const output = args.output ?? path.join(path.dirname(args.input), `final-${path.basename(args.input)}`);
const { header, rows } = readCsv(args.input);

const result = rows.map(row => {
  const project = row['Project Name'];
  const runDir = findRunDir(args.outputs, project, row['id']);
  console.log(`=================== [${row['id']}] ${project}`);
  if (!runDir) {
    console.error(`Erro: pasta da execucao nao encontrada em ${path.join(args.outputs, project)}`);
    return { ...row, ...Object.fromEntries(COLUMNS.map(c => [c, '-'])) };
  }

  const javaVersion = readRun(runDir).tools?.java ?? '-';
  const outcomes = dependencyOutcomes(readEvents(runDir));
  for (const o of outcomes) {
    const change = o.oldVersion === o.newVersion ? 'no change' : semVerChange(o.oldVersion, o.newVersion);
    console.log(`${o.dep}: ${o.oldVersion} -> ${o.newVersion} (${change})`);
  }
  const counts = count(outcomes);
  console.log(`Java Version: ${javaVersion}; ${JSON.stringify(counts)}\n`);
  return { ...row, javaVersion, ...counts };
});

writeCsv(output, [...header.filter(h => !(COLUMNS as readonly string[]).includes(h)), ...COLUMNS], result);
console.log(`CSV written to ${output}`);
