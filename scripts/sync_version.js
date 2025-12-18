#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

const rootDir = path.resolve(__dirname, '..');
const versionFile = path.join(rootDir, 'VERSION.txt');
const packageJsonFile = path.join(rootDir, 'package.json');

try {
  const version = fs.readFileSync(versionFile, 'utf8').trim();
  const packageJson = JSON.parse(fs.readFileSync(packageJsonFile, 'utf8'));

  if (packageJson.version !== version) {
    console.log(`Updating package.json version from ${packageJson.version} to ${version}`);
    packageJson.version = version;
    fs.writeFileSync(packageJsonFile, JSON.stringify(packageJson, null, 2) + '\n');
  } else {
    console.log('package.json version is already up to date.');
  }
} catch (error) {
  console.error('Error syncing version:', error);
  process.exit(1);
}
