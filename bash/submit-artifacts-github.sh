#!/bin/bash

project_path=$1
safer_report_path=$2
vulnerabilities_before=$3
vulnerabilities_after=$4

current_path=$(pwd)
cd $project_path
commit=$(git rev-parse HEAD)

safer_results=$(grep -A7 "Number of dependencies with vulnerabilities:" $safer_report_path)

safer_report_log_gist=$(gh gist create $safer_report_path --public --desc "Safer report log")

issue_link=$(
  gh issue create \
    --title "Safer - Compatible Updates to Fix Vulnerable Dependencies" \
    --body "$(cat <<EOF
Hi there 👋,
I'm [Safer Bot](https://gitlab.com/lsi-ufcg/vulnerabilidades/safer)!
Safer is an open-source tool that automatically updates vulnerable dependencies to more secure and compatible versions. Our goal is to help maintainers keep their projects secure without breaking changes.
We ran Safer on your project at commit $commit and identified dependency updates that reduce vulnerabilities while preserving stability. Safer uses a compatibility-aware heuristic to select the most appropriate versions for each dependency.

Safer Report Summary: 

$safer_results

View the full Safer report [here]($safer_report_log_gist).

I'm excited to contribute to the open source community using our tool and would be happy to assist with any questions or feedback.
Feel free to reply to this issue and I'll respond as soon as possible.

Thanks,
Safer Bot
EOF
)"
)
echo $issue_link $commit
issue_number=$(basename $issue_link)
main_branch=$(git rev-parse --abbrev-ref HEAD)
git checkout safer-result > /dev/null 2>&1

gh pr create --title "Updated pom.xml by Safer" \
  --body "$(cat <<EOF
This PR was automatically created by Safer, an open-source tool that updates vulnerable dependencies with compatible and more secure versions.

Analyzed commit: $commit
File updated: pom.xml
Vulnerabilities reduced: $vulnerabilities_before -> $vulnerabilities_after
See details in issue #$issue_number

Let us know if you have questions.

Thanks,
Safer Bot
EOF
)" \
  --base $main_branch
  >&2

cd $current_path
