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

const SEARCH_API = "https://api.github.com/search/repositories";
const MAX_PAGES = 10; // GitHub search API max = 1000 results
const PER_PAGE = 100;
const CONCURRENT_REQUESTS = 10;

const delay = (ms) => new Promise((res) => setTimeout(res, ms));

async function rateLimitedSearchFetch(url) {
    await delay(2100);
    return fetch(url, { headers: HEADERS });
}

async function fetchReposPage(query, page) {
    const url = `${SEARCH_API}?q=${encodeURIComponent(
        query
    )}&sort=stars&order=desc&per_page=${PER_PAGE}&page=${page}`;
    console.log(url);
    const response = await rateLimitedSearchFetch(url);
    if (!response.ok) {
        console.error(
            `Search API error: ${response.status} ${response.statusText}`
        );
    }
    const data = await response.json();
    return data.items || [];
}

async function getCommitCount(owner, repo, branch) {
    const commitsUrl = `https://api.github.com/repos/${owner}/${repo}/commits?per_page=1&sha=${branch}`;
    try {
        const response = await fetch(commitsUrl, { headers: HEADERS });
        if (!response.ok) {
            console.warn(`Failed to get commits for ${owner}/${repo}`);
            return 0;
        }
    
        const linkHeader = response.headers.get("link");
        if (!linkHeader) return 1;
    
        const match = linkHeader.match(/&page=(\d+)>; rel="last"/);
        if (match) {
            return parseInt(match[1], 10);
        }
    
        return 1;
    } catch(err) {
        console.warn(`Failed to fetch tree for ${owner}/${repo}`);
        return false;
    }
}

async function checkPomInRoot(owner, repo, branch) {
    const treeUrl = `https://api.github.com/repos/${owner}/${repo}/git/trees/${branch}`;
    try {
        const response = await fetch(treeUrl, { headers: HEADERS });
        if (!response.ok) {
            console.warn(
                `Failed to fetch tree for ${owner}/${repo}: ${response.status}`
            );
            if (response.status === 403) {
                console.log("Waiting for 20 minutes...");
                await delay(20 * 60 * 1000);
                console.log("20 minutes has passed!");
            }
            return false;
        }
        const data = await response.json();
        if (!data.tree) return false;
        return data.tree.some(
            (item) => item.path === "pom.xml" && item.type === "blob"
        );
    } catch (err) {
        console.warn(`Failed to fetch tree for ${owner}/${repo}`);
        return false;
    }
}

function* generateMonthRanges(startYear = 2018) {
    const now = new Date();
    for (let year = startYear; year <= now.getFullYear(); year++) {
        const endMonth = year === now.getFullYear() ? now.getMonth() + 1 : 12;
        for (let month = 1; month <= endMonth; month++) {
            const start = `${year}-${String(month).padStart(2, "0")}-01`;
            const endDate = new Date(year, month, 0).getDate(); // last day of the month
            const end = `${year}-${String(month).padStart(2, "0")}-${endDate}`;
            yield { start, end };
        }
    }
}

async function main() {
    console.log("Starting repo search and filtering by month...");

    const limit = pLimit(CONCURRENT_REQUESTS);
    let reposWithPom = [];

    for (const { start, end } of generateMonthRanges(2015)) {
        console.log(`\n🔍 Searching from ${start} to ${end}`);
        const searchQuery = `language:Java stars:>=5 created:${start}..${end}`;
        for (let page = 1; page < MAX_PAGES; page++) {
            console.log(`Fetching page ${page} for ${start}..${end}`);
            let repos;
            try {
                repos = await fetchReposPage(searchQuery, page);
            } catch (err) {
                console.error("Error fetching repos:", err);
                break;
            }
            if (repos.length === 0) {
                console.log("No more repos in this range.");
                break;
            }

            const checkPromises = repos.map((repo) =>
                limit(async () => {
                    const commitCount = await getCommitCount(
                        repo.owner.login,
                        repo.name,
                        repo.default_branch
                    );

                    const hasPom = await checkPomInRoot(
                        repo.owner.login,
                        repo.name,
                        repo.default_branch
                    );

                    if (hasPom) {
                        console.log(
                            `✔ ${repo.full_name} stars: ${repo.stargazers_count}, commits: ${commitCount}`
                        );
                        reposWithPom.push({
                            full_name: repo.full_name,
                            stars: repo.stargazers_count,
                            commits: commitCount,
                            url: repo.html_url,
                        });
                    }
                })
            );

            await Promise.all(checkPromises);
        }

        console.log(
            `\n🎉 Found ${reposWithPom.length} repositories with pom.xml from ${start} to ${end}.`
        );

        const result = reposWithPom.map((repo) => `${repo.full_name},${repo.url},${repo.stars},${repo.commits}`).join("\n");
        fs.appendFileSync("output.txt", result + "\n");

        reposWithPom = []; // Reset for next month
    }
}

main().catch((err) => {
    console.error("Fatal error:", err);
});
