# GitHub Search

This script was used to collect the list of 35187 open-source Maven projects we used in our experiment

## Install dependencies

`npm i`

## Github Search

It receives Github Token as input and outputs `./output.csv`

### How to run

Create `.env` file  
`touch .env`

Add your token in .env file  
`GITHUB_TOKEN=<your_token>`

Run script  
`npm run script`

## Sort Results

It receives `./output.csv` as input and outputs `sorted_output.csv`

### How to run

Run script  
`npm run sort-results`
