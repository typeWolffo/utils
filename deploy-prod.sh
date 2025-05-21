deploy-prod() {
    local GREEN='\033[0;32m'
    local YELLOW='\033[1;33m'
    local RED='\033[0;31m'
    local BLUE='\033[0;34m'
    local NC='\033[0m'

    echo "${YELLOW}Starting deployment process to PRODUCTION environment...${NC}"

    echo "${GREEN}Switching to production branch and pulling latest changes...${NC}"
    git checkout production
    git pull

    echo "${GREEN}Getting information about the latest tag...${NC}"
    local LATEST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
    echo "Latest tag: ${YELLOW}$LATEST_TAG${NC}"

    local NEW_TAG
    if [[ $LATEST_TAG =~ v([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
        local MAJOR="${match[1]}"
        local MINOR="${match[2]}"
        local PATCH="${match[3]}"

        PATCH=$((PATCH + 1))

        NEW_TAG="v$MAJOR.$MINOR.$PATCH"
    else
        echo "${RED}Failed to parse tag. Using v0.0.1 as the new tag.${NC}"
        NEW_TAG="v0.0.1"
    fi

    echo "${BLUE}Suggested new version: ${YELLOW}$NEW_TAG${NC}"
    echo "${BLUE}Is this version correct? (y/n)${NC}"
    read ANSWER

    if [[ $ANSWER != "y" && $ANSWER != "Y" ]]; then
        echo "${BLUE}Please enter the new version (format: vX.X.X):${NC}"
        read USER_VERSION

        if [[ $USER_VERSION =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            NEW_TAG="$USER_VERSION"
            echo "${GREEN}Using version: ${YELLOW}$NEW_TAG${NC}"
        else
            echo "${RED}Invalid version format. Using the suggested version: ${YELLOW}$NEW_TAG${NC}"
        fi
    fi

    echo "${GREEN}Creating new tag: ${YELLOW}$NEW_TAG${NC}"
    git tag $NEW_TAG

    echo "${GREEN}Pushing tags to remote, which will trigger deploy action in GitHub Actions...${NC}"
    git push --tags

    echo "${YELLOW}Deployment to PRODUCTION environment completed successfully!${NC}"
    echo "${YELLOW}Tag: $NEW_TAG${NC}"
}

alias dprod='deploy-prod'
