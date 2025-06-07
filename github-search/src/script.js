import fetch from 'node-fetch';
import pLimit from 'p-limit';
import dotenv from 'dotenv';
import fs from 'fs';
dotenv.config();

const TOKEN = process.env.GITHUB_TOKEN;
if (!TOKEN) {
  console.error('Please set GITHUB_TOKEN in your .env file');
  process.exit(1);
}

const HEADERS = {
  Accept: 'application/vnd.github+json',
  Authorization: `Bearer ${TOKEN}`,
};

const SEARCH_API = 'https://api.github.com/search/repositories';
const MAX_PAGES = 1;
const PER_PAGE = 100;
const SEARCH_QUERY = 'language:Java stars:>=5';
const CONCURRENT_TREE_REQUESTS = 1; // to avoid spamming API
const SEARCH_RATE_LIMIT_PER_MINUTE = 30; // max search requests/min

// Simple delay function
const delay = ms => new Promise(res => setTimeout(res, ms));

// Function to respect search API rate limits (30 req/min)
async function rateLimitedSearchFetch(url) {
  // You could add a smarter token bucket or leaky bucket here.
  // For now, just wait 2100ms between calls (~28.5 req/min)
  await delay(2100);
  return fetch(url, { headers: HEADERS });
}

async function fetchReposPage(page) {
  const url = `${SEARCH_API}?q=${encodeURIComponent(SEARCH_QUERY)}&sort=stars&order=desc&per_page=${PER_PAGE}&page=${page}`;
  const response = await rateLimitedSearchFetch(url);
  if (!response.ok) {
    throw new Error(`Search API error: ${response.status} ${response.statusText}`);
  }
  const data = await response.json();
  return data.items || [];
}

async function checkPomInRoot(owner, repo, branch) {
  const treeUrl = `https://api.github.com/repos/${owner}/${repo}/git/trees/${branch}`;
  const response = await fetch(treeUrl, { headers: HEADERS });
  if (!response.ok) {
    // Some repos may have weird branches or permissions, ignore errors
    console.warn(`Failed to fetch tree for ${owner}/${repo}: ${response.status}`);
    return false;
  }
  const data = await response.json();
  if (!data.tree) return false;
  return data.tree.some(item => item.path === 'pom.xml' && item.type === 'blob');
}

async function main() {
  console.log('Starting repo search and filtering...');

  const limit = pLimit(CONCURRENT_TREE_REQUESTS);
  const reposWithPom = [];

  for (let page = 1; page <= MAX_PAGES; page++) {
    console.log(`Fetching page ${page} of repos...`);
    let repos;
    try {
      repos = await fetchReposPage(page);
    } catch (err) {
      console.error('Error fetching repos:', err);
      break;
    }
    if (repos.length === 0) {
      console.log('No more repos found.');
      break;
    }

    // Check pom.xml presence with concurrency limit
    const checkPromises = repos.map(repo => 
      limit(async () => {
        const hasPom = await checkPomInRoot(repo.owner.login, repo.name, repo.default_branch);
        if (hasPom) {
          console.log(`✔ ${repo.full_name} stars: ${repo.stargazers_count}`);
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

  console.log(`\nFound ${reposWithPom.length} repositories with pom.xml in root matching criteria.`);
  console.log('Results:', reposWithPom);
  const result = reposWithPom.map(repo => repo.url).join("\n");
  fs.writeFileSync("output.txt", result);
}

main().catch(err => {
  console.error('Fatal error:', err);
});