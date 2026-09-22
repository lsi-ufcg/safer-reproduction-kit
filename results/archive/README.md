# Resultados superados

Arquivos de execuções anteriores, mantidos apenas como registro. **Nenhum deles deve ser
usado na análise**: todos vêm de execuções com algum defeito conhecido, descrito abaixo.

Os resultados válidos ficam em `results/`, nomeados por combinação:
`dataset_<combinacao>.csv` e `deleted-tests_<combinacao>.csv`.

## Filtragem global (15 a 18 de setembro de 2026)

| Arquivo | O que é |
| --- | --- |
| `deleted-tests.old-2026-09-15.csv` (+ `-detail`) | Primeira filtragem global |
| `deleted-tests.bak-2026-09-17.csv` | Cópia feita antes de refiltrar os projetos com JDK corrompido |
| `deleted-tests.global-2026-09-18.csv` (+ `-detail`) | Filtragem global final |
| `refilter-jdk-error.csv` | Lista dos 146 projetos a refiltrar por corrupção da imagem `java-setup-11` |

Essas execuções filtravam o dataset de origem uma única vez, com as três categorias de
teste juntas, antes do pipeline. Dois problemas invalidam os números:

1.  **A filtragem não valia para a combinação executada.** Uma suíte que passa com as três
    categorias juntas pode falhar quando só duas rodam -- e vice-versa. No `88250_solo`, com
    as suítes EvoSuite presentes o TestNG não executou nenhum teste; sem elas, 30 falharam.
2.  **Projetos marcados como `success` sem teste nenhum executado.** O critério de sucesso
    não verificava se algum teste havia rodado.

## Execuções do pipeline

| Arquivo | O que é |
| --- | --- |
| `dataset_native_kex.pre-filtro-2026-09-18.csv`, `logs.pre-filtro-2026-09-18.txt` | Execuções anteriores à filtragem dentro do pipeline |
| `dataset_native_kex.colisao-2026-09-18.csv`, `logs.colisao-2026-09-18.txt`, `deleted-tests_native_kex.colisao-2026-09-18.csv` (+ `-detail`) | Execução com três instâncias simultâneas |

Na execução com colisão, cada instância apagava o `workstation/maven` e os containers das
outras, então o Safer falhava com `No such container` mesmo com os testes verdes. O
`execucao_safer.sh` passou a aceitar uma instância por vez.
