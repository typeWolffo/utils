deploy-stg() {
    local GREEN='\033[0;32m'
    local YELLOW='\033[1;33m'
    local NC='\033[0m'

    echo "${YELLOW}Starting deployment process to STAGING environment...${NC}"

    echo "${GREEN}Switching to main branch and pulling latest changes...${NC}"
    git checkout main
    git pull

    echo "${GREEN}Switching to production branch...${NC}"
    git checkout production

    echo "${GREEN}Pulling latest changes from production branch...${NC}"
    git pull

    echo "${GREEN}Merging main branch into production (--ff-only)...${NC}"
    git merge main --ff-only

    echo "${GREEN}Pushing changes to remote, which will trigger deploy action in GitHub Actions...${NC}"
    git push

    echo "${YELLOW}Deployment to STAGING environment completed successfully!${NC}"
}

alias dstg='deploy-stg'
