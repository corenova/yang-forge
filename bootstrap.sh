#!/bin/sh

npm install js-yaml
node_modules/.bin/js-yaml package.yaml > package.json
