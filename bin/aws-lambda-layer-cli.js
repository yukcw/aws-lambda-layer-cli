#!/usr/bin/env node

'use strict';

const { spawnSync } = require('child_process');
const fs = require('fs');
const path = require('path');

function which(cmd) {
  const isWin = process.platform === 'win32';
  const exts = isWin ? (process.env.PATHEXT || '.EXE;.CMD;.BAT;.COM').split(';') : [''];
  const paths = (process.env.PATH || '').split(path.delimiter);

  for (const p of paths) {
    if (!p) continue;
    for (const ext of exts) {
      const full = path.join(p, isWin ? cmd + ext.toLowerCase() : cmd);
      if (fs.existsSync(full)) return full;
      // Also check original case on Windows
      const full2 = path.join(p, cmd + ext);
      if (fs.existsSync(full2)) return full2;
    }
  }
  return null;
}

function shQuote(s) {
  // Single-quote for bash -lc
  return `'${String(s).replace(/'/g, `'\\''`)}'`;
}

function windowsPathToWsl(p) {
  // C:\Users\me\x -> /mnt/c/Users/me/x
  const m = /^([a-zA-Z]):\\(.*)$/.exec(p);
  if (!m) return null;
  return `/mnt/${m[1].toLowerCase()}/${m[2].replace(/\\/g, '/')}`;
}

function cygpathConvert(mode, p) {
  const cygpath = which('cygpath');
  if (!cygpath) return null;
  const res = spawnSync(cygpath, [mode, p], { encoding: 'utf8' });
  if (res.status !== 0) return null;
  return (res.stdout || '').trim();
}

function run(cmd, args) {
  const res = spawnSync(cmd, args, { stdio: 'inherit' });
  process.exit(res.status ?? 1);
}

const args = process.argv.slice(2);

if (args[0] === 'completion') {
  if (args.includes('--help') || args.includes('-h')) {
    console.log('Usage: aws-lambda-layer-cli completion [options]');
    console.log('');
    console.log('Options:');
    console.log('  --zsh     Output zsh completion script');
    console.log('  --bash    Output bash completion script');
    console.log('');
    console.log('Examples:');
    console.log('  # Load completion in current shell');
    console.log('  source <(aws-lambda-layer-cli completion)');
    console.log('');
    console.log('  # Add to .zshrc');
    console.log('  aws-lambda-layer-cli completion >> ~/.zshrc');
    process.exit(0);
  }

  const completionDir = path.resolve(__dirname, '..', 'completion');
  let shell = 'bash';

  // Detect shell or use flag
  if (args.includes('--zsh') || (process.env.SHELL && process.env.SHELL.includes('zsh'))) {
    shell = 'zsh';
  }
  if (args.includes('--bash')) {
    shell = 'bash';
  }

  if (shell === 'zsh') {
    const file = path.join(completionDir, 'aws-lambda-layer-completion.zsh');
    if (fs.existsSync(file)) {
      let content = fs.readFileSync(file, 'utf8');
      // Remove the auto-execution line if present, to make it safe for sourcing
      content = content.replace(/_aws-lambda-layer-cli "\$@"\s*$/, '');
      console.log(content);
      console.log('\n# Register completion');
      console.log('if type compdef &>/dev/null; then');
      console.log('  compdef _aws-lambda-layer-cli aws-lambda-layer-cli');
      console.log('fi');
    } else {
      console.error('Completion script not found for zsh');
      process.exit(1);
    }
  } else {
    // bash
    const file = path.join(completionDir, 'aws-lambda-layer-completion.bash');
    if (fs.existsSync(file)) {
      console.log(fs.readFileSync(file, 'utf8'));
    } else {
      console.error('Completion script not found for bash');
      process.exit(1);
    }
  }
  process.exit(0);
}

if (args[0] === 'uninstall') {
  const uninstallScript = path.resolve(__dirname, '..', 'scripts', 'uninstall.js');
  if (fs.existsSync(uninstallScript)) {
    require(uninstallScript);
    // The script will handle exit
  } else {
    console.error('Uninstall script not found');
    process.exit(1);
  }
  return;
}

const bashScript = path.resolve(__dirname, '..', 'scripts', 'aws-lambda-layer-cli');

if (!fs.existsSync(bashScript)) {
  console.error('Error: packaged bash script not found:', bashScript);
  process.exit(1);
}

// POSIX platforms
if (process.platform !== 'win32') {
  run('bash', [bashScript, ...args]);
}

// Windows platforms:
// - Prefer Git Bash / MSYS / Cygwin: convert to POSIX path using cygpath -u
// - Else attempt WSL: convert to /mnt/<drive>/... and run via wsl.exe
// - Else give a clear message

const posixPath = cygpathConvert('-u', bashScript);
if (posixPath) {
  run('bash', [posixPath, ...args]);
}

const wsl = which('wsl.exe') || which('wsl');
if (wsl) {
  const wslPath = windowsPathToWsl(bashScript);
  if (!wslPath) {
    console.error('Error: unable to convert path for WSL:', bashScript);
    process.exit(1);
  }

  const cmd = `bash ${shQuote(wslPath)} ${args.map(shQuote).join(' ')}`.trim();
  run(wsl, ['bash', '-lc', cmd]);
}

console.error('Error: no compatible bash found on Windows.');
console.error('Install and run this tool inside WSL, or install Git Bash and ensure `bash`/`cygpath` are on PATH.');
process.exit(1);
