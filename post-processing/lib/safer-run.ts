// Leitura das execucoes do Safer novo para o pos-processamento.
//
// O Safer antigo imprimia as versoes no stdout ("Version: X [NEW] [OLD]") e o
// pos-processamento as extraia com expressoes regulares. O novo grava cada
// decisao como um evento JSON em decisions.jsonl, dentro da pasta da execucao
// que o bash/run-experiment.sh move para outputs/v2/<projeto>/safer-run (e que o
// execucao_safer.sh move para outputs/v2/<projeto>/execution_<n>/safer-run).
//
// A ordem das versoes e a do proprio Safer (compareVersions), importada do
// codigo dele -- o mesmo que o kit faz em bash/test-filtering/safer-java-version.ts.
import fs from 'fs';
import path from 'path';

import { compareVersions } from '../../safer/src/core/versions';

export { compareVersions };

export const KIT_ROOT = path.resolve(__dirname, '..', '..');

// ---------------------------------------------------------------------------
// CSV (RFC 4180, o formato que o csv.writer do report-to-csv.py grava)
// ---------------------------------------------------------------------------

export type CsvTable = { header: string[]; rows: Record<string, string>[] };

export function parseCsv(text: string): string[][] {
  const records: string[][] = [];
  let record: string[] = [];
  let field = '';
  let quoted = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (quoted) {
      if (c === '"' && text[i + 1] === '"') {
        field += '"';
        i++;
      } else if (c === '"') quoted = false;
      else field += c;
    } else if (c === '"') quoted = true;
    else if (c === ',') {
      record.push(field);
      field = '';
    } else if (c === '\n' || c === '\r') {
      if (c === '\r' && text[i + 1] === '\n') i++;
      record.push(field);
      records.push(record);
      record = [];
      field = '';
    } else field += c;
  }
  if (field !== '' || record.length) {
    record.push(field);
    records.push(record);
  }
  return records.filter(r => !(r.length === 1 && r[0] === ''));
}

export function readCsv(file: string): CsvTable {
  const [header, ...records] = parseCsv(fs.readFileSync(file, 'utf8'));
  if (!header) throw new Error(`${file} esta vazio`);
  return { header, rows: records.map(r => Object.fromEntries(header.map((h, i) => [h, r[i] ?? '']))) };
}

const csvField = (value: unknown): string => {
  const s = String(value ?? '');
  return /[",\r\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
};

export function writeCsv(file: string, header: string[], rows: Record<string, unknown>[]): void {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const lines = [header, ...rows.map(r => header.map(h => r[h]))].map(r => r.map(csvField).join(','));
  fs.writeFileSync(file, `${lines.join('\n')}\n`);
}

// ---------------------------------------------------------------------------
// Pasta da execucao
// ---------------------------------------------------------------------------

function safeRunDirs(dir: string, depth = 0): string[] {
  if (!fs.existsSync(dir) || depth > 2) return [];
  const found: string[] = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (!entry.isDirectory()) continue;
    const full = path.join(dir, entry.name);
    if (entry.name === 'safer-run') found.push(full);
    else found.push(...safeRunDirs(full, depth + 1));
  }
  return found;
}

/**
 * Pasta da execucao de uma linha do dataset: a que tem kit.json com o mesmo id
 * em outputs/<projeto>/[execution_<n>/]safer-run. Sem kit.json, aceita a unica
 * pasta que houver.
 */
export function findRunDir(outputsDir: string, project: string, id: string): string | null {
  const dirs = safeRunDirs(path.join(outputsDir, project));
  const byId = dirs.filter(d => {
    try {
      return String(JSON.parse(fs.readFileSync(path.join(d, 'kit.json'), 'utf8')).id) === id;
    } catch {
      return false;
    }
  });
  if (byId.length === 1) return byId[0];
  if (byId.length === 0 && dirs.length === 1 && !fs.existsSync(path.join(dirs[0], 'kit.json'))) return dirs[0];
  return null;
}

// ---------------------------------------------------------------------------
// Eventos
// ---------------------------------------------------------------------------

type Member = { dep: string; from: string; to?: string };
export type DecisionEvent = {
  type: string;
  dep?: string;
  version?: string;
  from?: string;
  reason?: string;
  data?: Record<string, unknown>;
  members?: Member[];
};

export type CandidateList = {
  current: string;
  candidates: string[];
  currentFound: boolean;
  olderCount: number;
  dropped: { prerelease: string[]; dateStyle: string[]; flavor: string[] };
};

export type DependencyOutcome = {
  dep: string; // group:artifact
  oldVersion: string;
  newVersion: string;
  outcome: 'adopted' | 'kept';
};

export function readEvents(runDir: string): DecisionEvent[] {
  return fs
    .readFileSync(path.join(runDir, 'decisions.jsonl'), 'utf8')
    .split('\n')
    .filter(Boolean)
    .map(line => JSON.parse(line));
}

export function readRun(runDir: string): Record<string, any> {
  return JSON.parse(fs.readFileSync(path.join(runDir, 'run.json'), 'utf8'));
}

/**
 * Uma entrada por dependencia direta que o Safer avaliou: as adotadas (versao
 * nova) e as mantidas (mesma versao). Grupos (dependencias que sobem juntas)
 * viram uma entrada por membro. As "skipped" ficam de fora: o Safer nao as
 * avalia (versao gerenciada pelo parent/BOM, ou escopo test/provided -- o que
 * inclui as dependencias de teste que o kit injeta).
 */
export function dependencyOutcomes(events: DecisionEvent[]): DependencyOutcome[] {
  const out: DependencyOutcome[] = [];
  for (const e of events) {
    if (e.type !== 'adopted' && e.type !== 'kept') continue;
    if (e.members?.length) {
      for (const m of e.members) {
        const newVersion = e.type === 'adopted' ? m.to ?? m.from : m.from;
        out.push({ dep: m.dep, oldVersion: m.from, newVersion, outcome: newVersion === m.from ? 'kept' : e.type });
      }
    } else if (e.type === 'adopted') {
      out.push({ dep: e.dep!, oldVersion: e.from!, newVersion: e.version!, outcome: 'adopted' });
    } else {
      out.push({ dep: e.dep!, oldVersion: e.version!, newVersion: e.version!, outcome: 'kept' });
    }
  }
  return out;
}

/** Lista de versoes de cada dependencia (evento candidates), por group:artifact. */
export function candidateLists(events: DecisionEvent[]): Map<string, CandidateList> {
  const lists = new Map<string, CandidateList>();
  for (const e of events) {
    if (e.type !== 'candidates' || !e.data) continue;
    if (e.members?.length) {
      const members = (e.data.members ?? {}) as Record<string, CandidateList>;
      for (const [dep, list] of Object.entries(members)) lists.set(dep, list);
    } else {
      lists.set(e.dep!, e.data as unknown as CandidateList);
    }
  }
  return lists;
}

/**
 * Todas as versoes publicadas mais novas que a atual, em ordem crescente --
 * inclusive as que o Safer descarta (pre-releases, versoes com data, outros
 * "sabores"), como a lista do Sonatype que o pos-processamento antigo usava.
 */
export function newerVersions(list: CandidateList): string[] {
  const all = [...list.candidates, ...list.dropped.prerelease, ...list.dropped.dateStyle, ...list.dropped.flavor];
  return [...new Set(all)].sort(compareVersions);
}

// ---------------------------------------------------------------------------
// Semver (mesma classificacao do pos-processamento antigo)
// ---------------------------------------------------------------------------

// A mesma expressao do script antigo, sem ancora: "2.9.10.8" casa como 2.9.10.
const SEMANTIC_VERSION_REGEX =
  /(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?/;

export type SemVerChange = 'major' | 'minor' | 'patch' | 'prerelease' | 'buildmetadata' | 'not semantic version' | '-';

/**
 * Tipo de mudanca entre duas versoes diferentes, na mesma ordem de testes do
 * script antigo. "not semantic version": alguma das duas nao tem a forma X.Y.Z;
 * "-": tem, mas a diferenca nao cai em nenhuma categoria (ex.: 2.9.10 -> 2.9.10.8,
 * ou 1.0.0-RC1 -> 1.0.0). O script antigo descartava esses dois casos sem contar.
 */
export function semVerChange(oldVersion: string, newVersion: string): SemVerChange {
  const a = oldVersion.match(SEMANTIC_VERSION_REGEX);
  const b = newVersion.match(SEMANTIC_VERSION_REGEX);
  if (!a || !b) return 'not semantic version';
  if (Number(a[1]) !== Number(b[1])) return 'major';
  if (Number(a[2]) !== Number(b[2])) return 'minor';
  if (Number(a[3]) !== Number(b[3])) return 'patch';
  if (a[4] && b[4] && a[4] !== b[4]) return 'prerelease';
  if (a[5] && b[5] && a[5] !== b[5]) return 'buildmetadata';
  return '-';
}

// ---------------------------------------------------------------------------
// Argumentos
// ---------------------------------------------------------------------------

export function parseArgs(argv: string[], usage: string): { input: string; output?: string; outputs: string } {
  const args: { input?: string; output?: string; outputs: string } = { outputs: path.join(KIT_ROOT, 'outputs', 'v2') };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '-o' || a === '--output') args.output = path.resolve(argv[++i]);
    else if (a === '--outputs') args.outputs = path.resolve(argv[++i]);
    else if (a === '-h' || a === '--help') {
      console.log(usage);
      process.exit(0);
    } else if (!a.startsWith('-') && !args.input) args.input = path.resolve(a);
    else {
      console.error(usage);
      process.exit(1);
    }
  }
  if (!args.input) {
    console.error(usage);
    process.exit(1);
  }
  return args as { input: string; output?: string; outputs: string };
}
