#!/usr/bin/env node
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');

try {
  const isWindows = os.platform() === 'win32';
  const scriptPath = isWindows ? path.join('scripts', 'install.ps1') : path.join('scripts', 'install.sh');
  const fullPath = path.join(__dirname, '..', scriptPath);

  if (!fs.existsSync(fullPath)) {
    console.error(`Installation script not found: ${fullPath}`);
    process.exit(1);
  }

  if (isWindows) {
    // Run PowerShell script with proper execution policy
    execSync(`powershell -ExecutionPolicy Bypass -File "${fullPath}"`, {
      stdio: 'inherit',
      shell: true
    });
  } else {
    // Run bash script
    execSync(`bash "${fullPath}"`, {
      stdio: 'inherit'
    });
  }
  
  console.log('✓ Installation completed successfully');
} catch (error) {
  console.error('✗ Installation failed:', error.message);
  process.exit(1);
}
