import fs from "fs";
import path from "path";
import csv from "csv-parser";
import { stringify } from "csv-stringify/sync";
import { fileURLToPath } from "url";
import { dirname } from "path";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const inputFile = path.join(__dirname, "../../../results/dataset.csv");
const outputFile = path.join(
    __dirname,
    "../dataset-version-changes.csv"
);

const dataset = [];

const SEMANTIC_VERSION_REGEX =
    /(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?/;
const JAVA_VERSION_REGEX = /Required Java version: (\d+)/;

fs.createReadStream(inputFile)
    .pipe(csv())
    .on("data", (data) => {
        dataset.push(data);
    })
    .on("end", () => {
        dataset.forEach((result) => {
            const projectName = result["Project Name"];
            const tests = result["Tests"];
            const stdoutPath = `../../outputs/${projectName}/stdout.txt`;
            const dependenciesVersionsPath = `../../outputs/${projectName}/dependencies-versions.txt`;

            let stdout;
            try {
                stdout = fs.readFileSync(stdoutPath, {
                    encoding: "utf-8",
                });
            } catch (err) {
                console.error("Error: Could not read stdout" + err);
                return;
            }

            let dependenciesVersions;
            try {
                dependenciesVersions = fs.readFileSync(
                    dependenciesVersionsPath,
                    {
                        encoding: "utf-8",
                    }
                );
            } catch (err) {
                console.error(
                    "Error: Could not read dependencies-versions" + err
                );
                return;
            }
            const javaVersionMatch = stdout.match(JAVA_VERSION_REGEX);
            const javaVersion = javaVersionMatch[1];
            console.log(`=================== ${result["Project Name"]}`);
            console.log(`Java Version: ${javaVersion}\n`);

            const dependenciesNewerVersionsMatch = dependenciesVersions.match(
                /========= DEPENDENCIES NEWER VERSIONS ==========\n\n(\[[\s\S]+\}\n\])\n/
            );
            if (!dependenciesNewerVersionsMatch) {
                console.error("Error: Could not match newer versions object");
                return;
            }
            const dependenciesNewerVersions = eval(
                dependenciesNewerVersionsMatch[1]
            );

            const dependenciesMatch = stdout.matchAll(
                /- (.+):(?= \d.+\])([\s\S\n]+?)\n\n/g
            );

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

            const inlineResults = [];
            for (const dependency of dependenciesMatch) {
                const versionChangesMatch = dependency[0].matchAll(
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
                versionsData = filterMatchedPairs(versionsData);
                const dependencyName = dependency[1];
                if (versionsData.length === 0) {
                    console.error(
                        `Error: Could not retrieve the changes of the dependency: ${dependencyName}`
                    );
                    continue;
                }
                const dependencyObject = dependenciesNewerVersions.find(
                    (d) =>
                        dependencyName ===
                        `${d.dependency.group}:${d.dependency.name}`
                );
                if (!dependencyObject) {
                    console.error(
                        `Error: Could not retrive this dependency from dependencies object: ${dependencyName}`
                    );
                    continue;
                }
                const newVersion = versionsData[0].version;
                const oldVersion = versionsData[1].version;
                const newVersionIndex =
                    dependencyObject.newerVersions.findIndex(
                        (version) => version === newVersion
                    );
                const oldVersionOffset =
                    newVersionIndex !== -1 ? newVersionIndex : 0;
                const mostRecentVersionOffset =
                    dependencyObject.newerVersions.length - newVersionIndex - 1;
                const mostRecentVersion =
                    dependencyObject.newerVersions[
                        dependencyObject.newerVersions.length - 1
                    ];
                const changed = oldVersionOffset !== 0;
                const semVerChange = changed ? resolveSemVerChange(
                    oldVersion,
                    newVersion
                ) : "not changed";
                const result = {
                    projectName,
                    tests,
                    javaVersion,
                    dependency: dependencyName,
                    oldVersion,
                    newVersion,
                    mostRecentVersion,
                    oldVersionOffset,
                    mostRecentVersionOffset,
                    semVerChange,
                };
                console.log(result);
                console.log(dependencyObject.newerVersions);
                inlineResults.push(Object.values(result).join());
            }
            if (inlineResults.length > 0) {
                fs.appendFileSync(outputFile, `${inlineResults.join("\n")}\n`);
            }
        });
    });

const resolveSemVerChange = (v1, v2) => {
    const isV1Semantic = SEMANTIC_VERSION_REGEX.test(v1);
    const isV2Semantic = SEMANTIC_VERSION_REGEX.test(v2);

    if (!isV1Semantic || !isV2Semantic) {
        return "not semantic version";
    }

    const matchv1 = v1.match(SEMANTIC_VERSION_REGEX);
    const matchv2 = v2.match(SEMANTIC_VERSION_REGEX);

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

    if (v1Major && v2Major && Number(v1Major) !== Number(v2Major)) {
        return "major";
    }
    if (v1Minor && v2Minor && Number(v1Minor) !== Number(v2Minor)) {
        return "minor";
    }
    if (v1Patch && v2Patch && Number(v1Patch) !== Number(v2Patch)) {
        return "patch";
    }
    if (v1Prerelease && v2Prerelease && v1Prerelease !== v2Prerelease) {
        return "prerelease";
    }
    if (
        v1Buildmetadata &&
        v2Buildmetadata &&
        v1Buildmetadata !== v2Buildmetadata
    ) {
        return "buildmetadata";
    }
    return "-";
};
