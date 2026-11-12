import fs from 'fs';
import path from 'path';

import { detectJavaVersion } from '../../safer/src/runners/maven/pom-edit';

console.log(detectJavaVersion(fs.readFileSync(path.join(process.argv[2], 'pom.xml'), 'utf8')));
