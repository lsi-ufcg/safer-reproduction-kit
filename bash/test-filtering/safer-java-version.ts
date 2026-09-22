// Imprime a versao de Java que o Safer usaria para o projeto informado.
//
// Usa as proprias funcoes do Safer em vez de reimplementar a deteccao: o filtro
// precisa subir o container com o mesmo JDK que o Safer vai usar depois, senao
// um teste pode passar num JDK e falhar no outro. O Safer calcula a versao sobre
// o POM efetivo, e nao sobre o pom.xml bruto -- e assim que ele enxerga, por
// exemplo, o maven.compiler.source herdado do spring-boot-starter-parent.
//
// Uso (a partir de safer/src, como o run-experiment.sh roda o Safer):
//   tsx ../../bash/test-filtering/safer-java-version.ts <projeto>
import { MavenAdapter } from '../../safer/src/runners/maven/maven-adapter';

(async () => {
  // Mesmo comando de MavenAdapter.getFromMvn.
  const pomString = (await MavenAdapter._execMvnCommand(
    "mvn help:effective-pom | awk '/<project /{flag=1} flag; /<\\/project>/{if(flag){flag=0; exit}}'",
    process.argv[2]
  )).trim();
  console.log(await MavenAdapter._getJavaVersion(pomString));
})();
