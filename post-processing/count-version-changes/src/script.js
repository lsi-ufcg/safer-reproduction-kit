import fs from "fs";
import path from "path";
import csv from "csv-parser";
import { stringify } from "csv-stringify/sync";
import { fileURLToPath } from "url";
import { dirname } from "path";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const inputFile = path.join(__dirname, "../../../results/dataset.csv");
const outputFile = path.join(__dirname, "../../../results/final-dataset.csv");

const results = [];

const SEMANTIC_VERSION_REGEX =
    /(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?/;
const JAVA_VERSION_REGEX = /Required Java version: (\d+)/;

fs.createReadStream(inputFile)
    .pipe(csv())
    .on("data", (data) => {
        results.push(data);
    })
    .on("end", () => {
        const parsedResults = results.map((result) => {
            const projectName = result["Project Name"];
            const stdoutPath = `../../outputs/${projectName}/stdout.txt`;

            let stdout;
            console.log(`=================== ${result["Project Name"]}`);
            try {
                stdout = fs.readFileSync(stdoutPath, {
                    encoding: "utf-8",
                });
            } catch (err) {
                console.err("Error: Could not read stdout" + err);
                return {
                    ...result,
                    javaVersion: "-",
                    countMajor: "-",
                    countMinor: "-",
                    countPatch: "-",
                    countPrerelease: "-",
                    countBuildmetadata: "-",
                };
            }
            const javaVersionMatch = stdout.match(JAVA_VERSION_REGEX);
            const javaVersion = javaVersionMatch[1];

            const versionChangesMatch = stdout.matchAll(
                /Version: ([^\s]+) ([\[\]A-Z ]+),/g
            );
            let versionsData = [];
            for (const match of versionChangesMatch) {
                const version = match[1];
                const newOrOld = match[2];
                if (newOrOld === "[NEW] [OLD]") {
                    versionsData.push({
                        version,
                        newOrOld: "[NEW]",
                    });
                    versionsData.push({
                        version,
                        newOrOld: "[OLD]",
                    });
                } else {
                    versionsData.push({
                        version,
                        newOrOld,
                    });
                }
            }

            function filterMatchedPairs(data) {
                const queue = [];
                const output = [];

                for (const entry of data) {
                    if (entry.newOrOld === "[NEW]") {
                        queue.push(entry);
                    } else if (entry.newOrOld === "[OLD]") {
                        if (queue.length > 1) {
                            queue.shift(); // Remove unmatched NEW (the first one)
                        }

                        if (queue.length === 1) {
                            const matchedNew = queue.shift();
                            output.push(matchedNew, entry);
                        }
                        // Else: unmatched OLD — skip it
                    }
                }

                return output;
            }

            versionsData = filterMatchedPairs(versionsData);

            console.log(`Java Version: ${javaVersion}\n`);
            if (versionsData.length % 2 == 1) {
                console.error(
                    "Error: Odd numbers of matches. Something is wrong.\n"
                );
                return {
                    ...result,
                    javaVersion,
                    countMajor: "-",
                    countMinor: "-",
                    countPatch: "-",
                    countPrerelease: "-",
                    countBuildmetadata: "-",
                };
            } else {
                let countMajor = 0;
                let countMinor = 0;
                let countPatch = 0;
                let countPrerelease = 0;
                let countBuildmetadata = 0;
                for (let i = 0; i < versionsData.length; i += 2) {
                    const v1 = versionsData[i];
                    const v2 = versionsData[i + 1];
                    console.log("Dependency");
                    console.log(`Version 1: ${v1.version}`);
                    console.log(`Version 2: ${v2.version}`);

                    const isV1Semantic = SEMANTIC_VERSION_REGEX.test(
                        v1.version
                    );
                    const isV2Semantic = SEMANTIC_VERSION_REGEX.test(
                        v2.version
                    );

                    if (!isV1Semantic || !isV2Semantic) {
                        console.log("Versions are not semantic. Skipping\n");
                        continue;
                    }

                    const matchv1 = v1.version.match(SEMANTIC_VERSION_REGEX);
                    const matchv2 = v2.version.match(SEMANTIC_VERSION_REGEX);

                    const v1Major = matchv1[1];
                    const v1Minor = matchv1[2];
                    const v1Patch = matchv1[3];
                    const v1Prerelease = matchv1[4];
                    const v1Buildmetadata = matchv1[5];

                    const v2Major = matchv2[1];
                    const v2Minor = matchv2[2];
                    const v2Patch = matchv2[3];
                    const v2Prerelease = matchv2[4];
                    const v2Buildmetadata = matchv2[5];

                    if (
                        v1Major &&
                        v2Major &&
                        Number(v1Major) !== Number(v2Major)
                    ) {
                        console.log("Major change\n");
                        countMajor++;
                        continue;
                    }
                    if (
                        v1Minor &&
                        v2Minor &&
                        Number(v1Minor) !== Number(v2Minor)
                    ) {
                        console.log("Minor change\n");
                        countMinor++;
                        continue;
                    }
                    if (
                        v1Patch &&
                        v2Patch &&
                        Number(v1Patch) !== Number(v2Patch)
                    ) {
                        console.log("Patch change\n");
                        countPatch++;
                        continue;
                    }
                    if (
                        v1Prerelease &&
                        v2Prerelease &&
                        v1Prerelease !== v2Prerelease
                    ) {
                        console.log("Prerelease change\n");
                        countPrerelease++;
                        continue;
                    }
                    if (
                        v1Buildmetadata &&
                        v2Buildmetadata &&
                        v1Buildmetadata !== v2Buildmetadata
                    ) {
                        console.log("Buildmetadata change\n");
                        countBuildmetadata++;
                        continue;
                    }
                }
                return {
                    ...result,
                    javaVersion,
                    countMajor,
                    countMinor,
                    countPatch,
                    countPrerelease,
                    countBuildmetadata,
                };
            }
        });

        const output = stringify(parsedResults, {
            header: true,
            columns: [
                "id",
                "Project Name",
                "Number of dependencies with vulnerabilities (Before)",
                "Number of dependencies with vulnerabilities (After)",
                "Number of vulnerabilities (Before)",
                "Number of vulnerabilities (After)",
                "Low vulnerabilities (Before)",
                "Low vulnerabilities (After)",
                "Medium vulnerabilities (Before)",
                "Medium vulnerabilities (After)",
                "High vulnerabilities (Before)",
                "High vulnerabilities (After)",
                "Critical vulnerabilities (Before)",
                "Critical vulnerabilities (After)",
                "Build Tool",
                "Tests",
                "Project Type",
                "Execution Time (s)",
                "Artifacts",
                "Improved",
                "javaVersion",
                "countMajor",
                "countMinor",
                "countPatch",
                "countPrerelease",
                "countBuildmetadata",
            ],
        });

        fs.writeFileSync(outputFile, output);
        console.log(`Sorted CSV written to ${outputFile}`);
    });
