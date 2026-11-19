#!/bin/bash

unzip safer.zip

cd safer
# npm ci instala exatamente as versoes do package-lock.json, sem reescreve-lo:
# com o npm install, o lock alterado deixava o repositorio do Safer modificado,
# e todo run.json saia com "dirty": true.
npm ci
cd ..

git config --global user.email "safer.bot2025@gmail.com"
git config --global user.name "safer-bot"
