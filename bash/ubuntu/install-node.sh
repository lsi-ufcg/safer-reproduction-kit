#!/bin/bash

# Install nvm  
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.2/install.sh | bash

\. "$HOME/.nvm/nvm.sh"

# Install NodeJS 22.16.0
nvm install 22.16.0

node -v
nvm current
npm -v
