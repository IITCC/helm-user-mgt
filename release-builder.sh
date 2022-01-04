#!/bin/bash

# Fail the script when a subsuquent command or pipe redirection fails
set -e
set -o pipefail

if [ "$#" -ne 3 ] || ! [ -d "$3" ]; then
  echo "Error: Invalid or insufficient arguements!" >&2
  echo "Usage: bash $0 <GITHUB_USERNAME> <GITHUB_TOKEN> <PRODUCT_REPO_DIR>" >&2
  exit 1
fi

# Check if jq and gh exists in the system
command -v jq >/dev/null 2>&1 || { echo >&2 "Error: $0 script requires 'jq' for JSON Processing.  Aborting as not found."; exit 1; }
command -v gh >/dev/null 2>&1 || { echo >&2 "Error: $0 script requires 'gh' to call GitHub APIs.  Aborting as not found."; exit 1; }

# Variables
GIT_USERNAME=$1
GIT_TOKEN=$2
WORK_DIR=$3
GIT_EMAIL="hasinthaindrajee@gmail.com"
CHART_YAML="${WORK_DIR}/Chart.yaml"

# Login to github cli with token.
echo "${GIT_TOKEN}" | gh auth login --with-token

# Read the tag version from the Chart.yaml
TAG_VERSION_TMP=$(grep 'version:' "${CHART_YAML}")
TAG_VERSION=${TAG_VERSION_TMP//*version: /}

echo "Tag version: ${TAG_VERSION}"

# Exporting variable current helm pack version
echo "::set-output name=CURRENT_TAG_VERSION::${TAG_VERSION}"

## Increment tag version to next tag version.
MAJOR=$(echo "${TAG_VERSION}" | cut -d. -f1)
MINOR=$(echo "${TAG_VERSION}" | cut -d. -f2)
PATCH=$(echo "${TAG_VERSION}" | cut -d. -f3)
PATCH=$((PATCH + 1))
NEW_TAG_VERSION=$MAJOR.$MINOR.$PATCH

echo "New release tag version: ${NEW_TAG_VERSION}"

# Set new release tag.
TAG="v${TAG_VERSION}"
TAG_NAME="helm-user-mgt-${TAG}"
echo "Release tag: ${TAG}"

# Release the tag.
gh release create --target main --title "${TAG_NAME}" -n "" "${TAG}";

git -C "${WORK_DIR}" config user.email "${GIT_EMAIL}"
git -C "${WORK_DIR}" config user.name "${GIT_USERNAME}"
git -C "${WORK_DIR}" pull

# Update the version in Chart.yaml
sed -i "s/version: ${TAG_VERSION}/version: ${NEW_TAG_VERSION}/" "${CHART_YAML}"
# Push new release version to Chart.yaml
git -C "${WORK_DIR}" add "${CHART_YAML}"
git -C "${WORK_DIR}" commit -m "Update Chart version to - v${NEW_TAG_VERSION}"
git -C "${WORK_DIR}" push

echo "Version updated in chart"

mkdir pipelines

# Clone the repo to push changes to dev branch.
git clone https://"${GIT_USERNAME}":"${GIT_TOKEN}"@github.com/IITCC/pipelines.git pipelines
git -C pipelines config user.email "${GIT_EMAIL}"
git -C pipelines config user.name "${GIT_USERNAME}"
git -C pipelines checkout dev

HELM_VERSION_LINE=$(grep -w 'HELM_VERSION' "${WORK_DIR}"/pipelines/user-mgt-fe/dev-setup-variables.yaml | sed 's/ *//')
sed -i 's|'"${HELM_VERSION_LINE}"'|HELM_VERSION: '"'${TAG}'"'|' "${WORK_DIR}"/pipelines/user-mgt-fe/dev-setup-variables.yaml

# Push new helm chart release version to dev-setup-variables.yaml.
git -C pipelines add "${WORK_DIR}"/pipelines/user-mgt-fe/dev-setup-variables.yaml
git -C pipelines commit -m "[Dev] Update user mgt FE helm chart version to - ${TAG}"
git -C pipelines push origin dev

echo "Release builder execution is completed."