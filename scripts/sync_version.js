#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

const rootDir = path.resolve(__dirname, '..');
const versionFile = path.join(rootDir, 'VERSION.txt');
const packageJsonFile = path.join(rootDir, 'package.json');

// Files that need version updates
const scriptFiles = [
  path.join(rootDir, 'scripts', 'aws-lambda-layer-cli'),
  path.join(rootDir, 'aws_lambda_layer_cli', 'assets', 'aws-lambda-layer-cli'),
  path.join(rootDir, 'scripts', 'install.ps1')
];

try {
  const version = fs.readFileSync(versionFile, 'utf8').trim();
  let updated = false;

  // Update package.json
  const packageJson = JSON.parse(fs.readFileSync(packageJsonFile, 'utf8'));
  if (packageJson.version !== version) {
    console.log(`Updating package.json version from ${packageJson.version} to ${version}`);
    packageJson.version = version;
    fs.writeFileSync(packageJsonFile, JSON.stringify(packageJson, null, 2) + '\n');
    updated = true;
  }

  // Update bash scripts
  scriptFiles.forEach(file => {
    if (fs.existsSync(file)) {
      let content = fs.readFileSync(file, 'utf8');
      let originalContent = content;
      
      // Update version in bash scripts
      content = content.replace(/local version="[^"]+"/g, `local version="${version}"`);
      content = content.replace(/echo "v[0-9]+\.[0-9]+\.[0-9]+"/g, `echo "v${version}"`);
      
      // Update version in PowerShell script
      content = content.replace(/\$Version = "[^"]+"/g, `$Version = "${version}"`);
      
      if (content !== originalContent) {
        fs.writeFileSync(file, content);
        console.log(`Updated version in ${path.relative(rootDir, file)}`);
        updated = true;
      }
    }
  });

  if (!updated) {
    console.log('All versions are already up to date.');
  }
} catch (error) {
  console.error('Error syncing version:', error);
  process.exit(1);
}
