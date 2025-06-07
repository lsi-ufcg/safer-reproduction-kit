import fetch from "node-fetch";
import pLimit from "p-limit";
import dotenv from "dotenv";
import fs from "fs";
dotenv.config();

const TOKEN = process.env.GITHUB_TOKEN;
if (!TOKEN) {
    console.error("Please set GITHUB_TOKEN in your .env file");
    process.exit(1);
}

const HEADERS = {
    Accept: "application/vnd.github+json",
    Authorization: `Bearer ${TOKEN}`,
};

const FIRST_PAGE = 8;
const LAST_PAGE = 10;
const PER_PAGE = 100;
const CONCURRENT_TREE_REQUESTS = 10;

const delay = (ms) => new Promise((res) => setTimeout(res, ms));

async function rateLimitedSearchFetch(url) {
    await delay(2100);
    return fetch(url, { headers: HEADERS });
}

async function fetchRepositories(page) {
    const url = `https://api.github.com/search/repositories?q=${encodeURIComponent(
        "language:Java stars:>=5"
    )}&sort=stars&order=desc&per_page=${PER_PAGE}&page=${page}`;
    const response = await rateLimitedSearchFetch(url);
    if (!response.ok) {
        throw new Error(
            `Search API error: ${response.status} ${response.statusText}`
        );
    }
    const data = await response.json();
    return data.items || [];
}

async function checkPomInRoot(owner, repo, branch) {
    const treeUrl = `https://api.github.com/repos/${owner}/${repo}/git/trees/${branch}`;
    try {
        const response = await fetch(treeUrl, { headers: HEADERS });
        if (!response.ok) {
            console.warn(
                `Failed to fetch tree for ${owner}/${repo}: ${response.status}`
            );
            return false;
        }
        const data = await response.json();
        if (!data.tree) return false;
        return data.tree.some(
            (item) => item.path === "pom.xml" && item.type === "blob"
        );
    } catch (err) {
        console.warn(
            `Failed to fetch tree for ${owner}/${repo}: ${response.status}`
        );
        return false;
    }
}

async function main() {
    console.log("Starting repo search and filtering...");

    const limit = pLimit(CONCURRENT_TREE_REQUESTS);
    const reposWithPom = [];

    for (let page = FIRST_PAGE; page <= LAST_PAGE; page++) {
        console.log(`Fetching page ${page} of repos...`);
        let repos;
        try {
            repos = await fetchRepositories(page);
        } catch (err) {
            console.error("Error fetching repos:", err);
            break;
        }
        if (repos.length === 0) {
            console.log("No more repos found.");
            break;
        }

        const checkPromises = repos.map((repo) =>
            limit(async () => {
                const hasPom = await checkPomInRoot(
                    repo.owner.login,
                    repo.name,
                    repo.default_branch
                );
                if (hasPom) {
                    console.log(
                        `✔ ${repo.full_name} stars: ${repo.stargazers_count}`
                    );
                    reposWithPom.push({
                        full_name: repo.full_name,
                        stars: repo.stargazers_count,
                        url: repo.html_url,
                    });
                }
            })
        );

        await Promise.all(checkPromises);
    }

    console.log(
        `\nFound ${reposWithPom.length} repositories with pom.xml in root matching criteria.`
    );
    console.log("Results:", reposWithPom);
    const result = reposWithPom.map((repo) => repo.url).join("\n");
    fs.writeFileSync("output.txt", result);
}

main().catch((err) => {
    console.error("Fatal error:", err);
});
