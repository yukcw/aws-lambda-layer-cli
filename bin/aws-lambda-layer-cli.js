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
  const hasZsh = args.includes('--zsh');
  const hasBash = args.includes('--bash');
  
  if (args.includes('--help') || args.includes('-h') || (!hasZsh && !hasBash)) {
    const GREEN = '\x1b[0;32m';
    const YELLOW = '\x1b[0;33m';
    const BLUE = '\x1b[0;34m';
    const MAGENTA = '\x1b[0;35m';
    const NC = '\x1b[0m';
    const UNDERLINE = '\x1b[4m';

    console.log(`${BLUE}Usage:${NC}`);
    console.log(`  aws-lambda-layer-cli ${GREEN}completion${NC} [options]`);
    console.log('');
    console.log(`${BLUE}Options:${NC}`);
    console.log(`  ${YELLOW}--zsh${NC}     Output zsh completion script`);
    console.log(`  ${YELLOW}--bash${NC}    Output bash completion script`);
    console.log('');
    console.log(`${MAGENTA}${UNDERLINE}Examples:${NC}`);
    console.log('  # Load completion in current shell');
    console.log(`  source <(aws-lambda-layer-cli ${GREEN}completion${NC} ${YELLOW}--bash${NC})`);
    console.log('');
    console.log('  # Add to .zshrc');
    console.log(`  aws-lambda-layer-cli ${GREEN}completion${NC} ${YELLOW}--zsh${NC} >> ~/.zshrc`);
    process.exit(0);
  }

  const completionDir = path.resolve(__dirname, '..', 'completion');
  let shell = '';

  if (hasZsh) {
    shell = 'zsh';
  } else if (hasBash) {
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
  if (args.includes('--help') || args.includes('-h')) {
    const GREEN = '\x1b[0;32m';
    const BLUE = '\x1b[0;34m';
    const NC = '\x1b[0m';
    
    console.log(`${BLUE}Usage:${NC}`);
    console.log(`  aws-lambda-layer-cli ${GREEN}uninstall${NC}`);
    console.log('');
    console.log(`${BLUE}Description:${NC}`);
    console.log('  Uninstalls the AWS Lambda Layer CLI tool and removes all associated files.');
    console.log('  This includes:');
    console.log('  - The CLI executable and symlinks');
    console.log('  - The installation directory');
    console.log('  - Shell completion scripts');
    process.exit(0);
  }

  const uninstallScript = path.resolve(__dirname, '..', 'scripts', 'uninstall.js');
  if (fs.existsSync(uninstallScript)) {
    run(process.execPath, [uninstallScript, ...args.slice(1)]);
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
