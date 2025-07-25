#!/bin/bash

pretty_print() {
  local DEFAULT="\e[0m"
  local RED="\e[1;31m"
  local YELLOW="\e[1;33m"
  local BLUE="\e[1;34m"
  local GREEN="\e[1;92m"

  local color_uppercase="${1^^}"
  local message="$2"
  echo -e "${!color_uppercase}${message}${DEFAULT}"
}

base_path=$(pwd)
dataset=results/artifacts-dataset.csv

mkdir -p workstation/maven
log_file="$base_path/results/artifacts.log"
echo "========== SAFER BATCH STARTED: $(date) ==========" >>"$log_file"

# Read the Dataset
tail -n +2 $dataset | while IFS=',' read -r c1 project_name c3 c4 vulnerabilities_before vulnerabilities_after c7 c8 c9 c10 c11 c12 c13 c14 c15 c16 c17 c18 commit improved c21; do
  {
    sleep 20
    echo -e "\n==============================="
    echo "Project: $project_name"
    echo "Timestamp: $(date)"
    echo "==============================="

    echo "Creating github artifacts for $project_name"
    project_root_path=$base_path/workstation/maven/$project_name

    cd $base_path/workstation/maven
    IFS='_' read -ra repo <<<"$project_name"
    upstream="${repo[0]}/${repo[1]}"

    # Fork repository
    if ! gh repo fork $upstream --clone=false --fork-name=$project_name; then
      echo "ERROR: Failed to fork repository."
      continue
    fi

    echo "Waiting for fork to be available..."
    while ! gh repo view "safer-bot/$project_name" >/dev/null 2>&1; do
      sleep 2
    done

    if ! git clone --depth=1 "git@github.com:safer-bot/$project_name.git"; then
      echo "ERROR: Failed to clone repository."
      continue
    fi

    cd "$project_name" || continue
    git remote add upstream git@github.com:$upstream.git
    gh repo set-default $upstream

    main_branch=$(git rev-parse --abbrev-ref HEAD)
    git checkout safer-result 2>/dev/null || git checkout -b safer-result

    # Copy updated pom.xml
    updated_pom="$base_path/outputs/$project_name/pom.xml"
    if ! cp "$updated_pom" "$project_root_path/pom.xml"; then
      echo "ERROR: pom.xml not found. Skipping..."
      continue
    fi

    git add pom.xml
    git config user.name "safer-bot"
    git config user.email "safer.bot2025@gmail.com"
    if ! git commit -m "add new pom.xml updated by Safer"; then
      echo "INFO: No changes detected in pom.xml. Skipping..."
      continue
    fi

    git push --force -u origin safer-result

    safer_report_path=$base_path/outputs/$project_name/stdout.txt
    if [ ! -f "$safer_report_path" ]; then
      echo "ERROR: Safer report not found. Skipping PR and issue creation."
      continue
    fi

    safer_results=$(grep -A7 "Number of dependencies with vulnerabilities:" "$safer_report_path")
    safer_report_log_gist=$(gh gist create "$safer_report_path" --public --desc "Safer report log")
    if [ $? -ne 0 ]; then
      echo "ERROR: Failed to create Gist for safer report."
      continue
    fi

    # Create PR
    git checkout safer-result
    pr_url=$(gh pr create --head safer-bot:safer-result \
      --title "Updated pom.xml by Safer" \
      --base $main_branch \
      --body "$(
        cat <<EOF
This PR was automatically created by Safer, an open-source tool that updates vulnerable dependencies with compatible and more secure versions.

Analyzed commit: $commit
File updated: pom.xml
Vulnerabilities reduced: $vulnerabilities_before -> $vulnerabilities_after

Let us know if you have questions.

Thanks,
Safer Bot
EOF
      )")

    if [ $? -ne 0 ]; then
      echo "ERROR: PR creation failed."
      continue
    fi
    echo "SUCCESS: Pull Request created: $pr_url"

    # Create Issue
    issue_link=$(
      gh issue create \
        --title "Safer - Compatible Updates to Fix Vulnerable Dependencies" \
        --body "$(
          cat <<EOF
Hi there 👋,
I'm [Safer Bot](https://gitlab.com/lsi-ufcg/vulnerabilidades/safer)!
Safer is an open-source tool that automatically updates vulnerable dependencies to more secure and compatible versions. Our goal is to help maintainers keep their projects secure without breaking changes.
We ran Safer on your project at commit $commit and identified dependency updates that reduce vulnerabilities while preserving stability. Safer uses a compatibility-aware heuristic to select the most appropriate versions for each dependency.

Safer Report Summary:

$safer_results

View the full Safer report [here]($safer_report_log_gist).

I'm excited to contribute to the open source community with my tool and would be happy to assist with any questions or feedback.
Feel free to reply to this issue and I'll respond as soon as possible.

Thanks,
Safer Bot
EOF
        )"
    )

    if [ $? -eq 0 ]; then
      issue_number=$(basename "$issue_link")
      echo "SUCCESS: Issue created: $issue_link"
      comment=$(gh pr comment "$pr_url" --body "See details in issue #$issue_number")
      echo "SUCCESS: Issue comment created: $comment"
    else
      echo "WARNING: PR created, but issue creation failed."
    fi
    cd "$base_path" || exit
  } >>"$log_file" 2>&1
done

echo -e "\n========== SAFER BATCH ENDED: $(date) ==========" >>"$log_file"
