import fs from "fs";
import path from "path";
import csv from "csv-parser";
import { stringify } from "csv-stringify/sync";
import { fileURLToPath } from "url";
import { dirname } from "path";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const inputFile = path.join(__dirname, "../output.csv");
const outputFile = path.join(__dirname, "../sorted_output.csv");

const results = [];

fs.createReadStream(inputFile)
    .pipe(csv())
    .on("data", (data) => {
        data.stars = Number(data.stars);
        results.push(data);
    })
    .on("end", () => {
        results.sort((a, b) => b.stars + b.commits - (a.stars + a.commits));

        const output = stringify(results, {
            header: true,
            columns: ["full_name", "url", "stars", "commits"],
        });

        fs.writeFileSync(outputFile, output);
        console.log(`Sorted CSV written to ${outputFile}`);
    });
