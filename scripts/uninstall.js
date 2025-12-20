#!/usr/bin/env node
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');

try {
  const isWindows = os.platform() === 'win32';
  const scriptPath = isWindows ? path.join('scripts', 'uninstall.ps1') : path.join('scripts', 'uninstall.sh');
  const fullPath = path.join(__dirname, '..', scriptPath);

  if (!fs.existsSync(fullPath)) {
    console.error(`Uninstallation script not found: ${fullPath}`);
    process.exit(1);
  }

  if (isWindows) {
    // Run PowerShell script with proper execution policy
    execSync(`powershell -ExecutionPolicy Bypass -File "${fullPath}"`, {
      stdio: 'inherit',
      shell: true
    });
  } else {
    // Check if we are root
    const isRoot = process.getuid && process.getuid() === 0;
    
    if (!isRoot) {
      console.log('This script requires root privileges to uninstall from /usr/local/lib.');
      console.log('Requesting sudo permissions...');
      // Run with sudo directly from node
      execSync(`sudo bash "${fullPath}"`, {
        stdio: 'inherit'
      });
    } else {
      // Already root, just run it
      execSync(`bash "${fullPath}"`, {
        stdio: 'inherit'
      });
    }
  }
  
  console.log('✓ Uninstallation completed successfully');
} catch (error) {
  console.error('✗ Uninstallation failed:', error.message);
  process.exit(1);
}
