#!/usr/bin/env node
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');
const readline = require('readline');

const isWindows = os.platform() === 'win32';
const scriptPath = isWindows ? path.join('scripts', 'install.ps1') : path.join('scripts', 'install.sh');
const fullPath = path.join(__dirname, '..', scriptPath);

if (!fs.existsSync(fullPath)) {
  console.error(`Installation script not found: ${fullPath}`);
  process.exit(1);
}

function runInstall(useSudo) {
  try {
    const cmd = useSudo ? `sudo bash "${fullPath}"` : `bash "${fullPath}"`;
    execSync(cmd, { stdio: 'inherit' });
    console.log('✓ Installation completed successfully');
    process.exit(0);
  } catch (error) {
    console.error('✗ Installation failed:', error.message);
    process.exit(1);
  }
}

if (isWindows) {
  try {
    execSync(`powershell -ExecutionPolicy Bypass -File "${fullPath}"`, {
      stdio: 'inherit',
      shell: true
    });
    console.log('✓ Installation completed successfully');
  } catch (error) {
    console.error('✗ Installation failed:', error.message);
    process.exit(1);
  }
} else {
  const isRoot = process.getuid && process.getuid() === 0;

  if (isRoot) {
    console.log('Running installation with root privileges...');
    runInstall(false);
  } else {
    console.log('Installation requires root privileges for system-wide components...');
    // Check if interactive
    if (!process.stdin.isTTY) {
      console.log('Non-interactive environment detected. Skipping system-wide installation steps requiring sudo.');
      process.exit(0);
    }

    const rl = readline.createInterface({
      input: process.stdin,
      output: process.stdout
    });

    console.log('\nThis package includes optional system-wide components (shell completion, helper scripts).');
    console.log('Installing them requires root privileges (sudo).');
    
    rl.question('Do you want to install these components? [y/N] ', (answer) => {
      rl.close();
      if (answer.toLowerCase() === 'y' || answer.toLowerCase() === 'yes') {
        runInstall(true);
      } else {
        console.log('Skipping system-wide installation.');
        process.exit(0);
      }
    });
  }
}
