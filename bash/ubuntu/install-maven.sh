#!/bin/bash

curl -s "https://get.sdkman.io" | bash
source "~/.sdkman/bin/sdkman-init.sh"
sdk install java 11.0.27-amzn
sudo apt install maven -y