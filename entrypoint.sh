#!/bin/bash
# If any commands fail (exit code other than 0) entire script exits
set -e

# Check for required environment variables and make sure they are setup
: ${PROJECT_TYPE?"PROJECT_TYPE Missing"} # theme|plugin
: ${WPE_INSTALL?"WPE_INSTALL Missing"}   # subdomain for wpengine install (Legacy single environment setup)
: ${REPO_NAME?"REPO_NAME Missing"}       # repo name (Typically the folder name of the project)

CI_BRANCH={GITHUB_REF##*/}

SSH_PATH="$HOME/.ssh"
WPENGINE_HOST="git.wpengine.com"
KNOWN_HOSTS_PATH="$SSH_PATH/known_hosts"
WPENGINE_SSH_KEY_PRIVATE_PATH="$SSH_PATH/wpengine_key"
WPENGINE_SSH_KEY_PUBLIC_PATH="$SSH_PATH/wpengine_key.pub"

mkdir "$SSH_PATH"

ssh-keyscan -t rsa "$WPENGINE_HOST" >> "$KNOWN_HOSTS_PATH"

echo "$WPENGINE_SSH_KEY_PRIVATE" > "$WPENGINE_SSH_KEY_PRIVATE_PATH"
echo "$WPENGINE_SSH_KEY_PUBLIC" > "$WPENGINE_SSH_KEY_PUBLIC_PATH"

chmod 700 "$SSH_PATH"
chmod 644 "$KNOWN_HOSTS_PATH"
chmod 600 "$WPENGINE_SSH_KEY_PRIVATE_PATH"
chmod 644 "$WPENGINE_SSH_KEY_PUBLIC_PATH"

git config --global core.sshCommand "ssh -i $WPENGINE_SSH_KEY_PRIVATE_PATH -o UserKnownHostsFile=$KNOWN_HOSTS_PATH"

# Set repo based on current branch, by default master=production, develop=staging
# @todo support custom branches

# This is considered legacy wpengine setup and should be deprecated. We'll keep this workflow in place for backwards compatibility.
target_wpe_install=${WPE_INSTALL}

if [[ "$CI_BRANCH" == "master" && -n "$WPE_INSTALL" ]]
then
    repo=production
else
    if [[ "$CI_BRANCH" == "develop" && -n "$WPE_INSTALL" ]]
    then
        repo=staging
    fi
fi

# In WP Engine's multi-environment setup, we'll target each instance based on branch with variables to designate them individually.
if [[ "$CI_BRANCH" == "master" && -n "$WPE_INSTALL_PROD" ]]
then
    target_wpe_install=${WPE_INSTALL_PROD}
    repo=production
fi

if [[ "$CI_BRANCH" == "staging" && -n "$WPE_INSTALL_STAGE" ]]
then
    target_wpe_install=${WPE_INSTALL_STAGE}
    repo=production
fi

if [[ "$CI_BRANCH" == "develop" && -n "$WPE_INSTALL_DEV" ]]
then
    target_wpe_install=${WPE_INSTALL_DEV}
    repo=production
fi

repo=production

echo -e  "Install: ${WPE_INSTALL_PROD} or ${WPE_INSTALL}"
echo -e  "Repo: ${repo}"

# Begin from the clone directory
# this directory is the default your git project is checked out into by Codeship.
cd clone

# Get official list of files/folders that are not meant to be on production if $EXCLUDE_LIST is not set.
if [[ -z "${EXCLUDE_LIST}" ]]; then
    wget https://raw.githubusercontent.com/linchpin/wpengine-codeship-continuous-deployment/master/exclude-list.txt
else
    # @todo validate proper url?
    wget ${EXCLUDE_LIST}
fi

# Loop over list of files/folders and remove them from deployment
ITEMS=`cat exclude-list.txt`
for ITEM in $ITEMS; do
    if [[ "$ITEM" == *.* ]]
    then
        find . -depth -name "$ITEM" -type f -exec rm "{}" \;
    else
        find . -depth -name "$ITEM" -type d -exec rm -rf "{}" \;
    fi
done

# Remove exclude-list file
rm exclude-list.txt

# go back home
cd ..

# Clone the WPEngine files to the deployment directory
# if we are not force pushing our changes
if [[ "$CI_MESSAGE" != *#force* ]]
then
    force=''
    git clone git@git.wpengine.com:${repo}/${target_wpe_install}.git ./deployment
else
    force='-f'
fi

# If there was a problem cloning, exit
if [ "$?" != "0" ] ; then
    echo "Unable to clone ${repo}"
    kill -SIGINT $$
fi

# check to see if we have a deployment folder, if so change directory to it. If not make the directory an initialize a git repo
if [ ! -d ./deployment ]; then
    mkdir ./deployment
    cd ./deployment
    git init
else
    cd ./deployment
fi

# Move the gitignore file to the deployments folder
wget --output-document=.gitignore https://raw.githubusercontent.com/linchpin/wpengine-codeship-continuous-deployment/master/gitignore-template.txt

# Delete plugin/theme if it exists, and move cleaned version into deployment folder
rm -rf ./wp-content/${PROJECT_TYPE}s/${REPO_NAME}

# Check to see if the wp-content directory exists, if not create it
if [ ! -d ./wp-content ];
then
    mkdir ./wp-content
fi

# Check to see if the plugins directory exists, if not create it
if [ ! -d ./wp-content/plugins ];
then
    mkdir ./wp-content/plugins
fi

# Check to see if the themes directory exists, if not create it
if [ ! -d ./wp-content/themes ];
then
    mkdir ./wp-content/themes
fi

# Move files into the deployment folder
rsync -a ../clone/* ./wp-content/${PROJECT_TYPE}s/${REPO_NAME}

# Stage, commit, and push to wpengine repo
git remote add ${repo} git@git.wpengine.com:${repo}/${target_wpe_install}.git

git add --all
git commit -am "Deployment to ${target_wpe_install} $repo by $CI_COMMITTER_NAME from $CI_NAME"

git push ${force} ${repo} master