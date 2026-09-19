#!/usr/bin/env node
//
// Lua syntax check.
//   node tools/luacheck.js                 # checks Scripts/**/*.lua
//   node tools/luacheck.js path/to/one.lua
//
// Needs luaparse. It is not vendored, so install it wherever is convenient:
//   npm install --save-dev luaparse       (in this repo)
//   npm install -g luaparse
//
// This is a PARSE check only. It catches typos and unbalanced blocks; it says
// nothing about whether a UFunction call has the right arity, which is the
// failure mode that actually crashes this game. For that, read the headers in
// <Palworld>/Mods/NativeMods/UE4SS/CXXHeaderDump/.

const fs = require('fs');
const path = require('path');

let luaparse;
try {
  luaparse = require('luaparse');
} catch {
  try {
    // Fall back to a global install, whose path is not on NODE_PATH by default.
    const root = require('child_process')
      .execSync('npm root -g', { encoding: 'utf8' })
      .trim();
    luaparse = require(path.join(root, 'luaparse'));
  } catch {
    console.error('luaparse not found. Run:  npm install --no-save luaparse');
    process.exit(2);
  }
}

// RECURSIVE. The runtime lives in Scripts/lp/, and a flat readdir silently
// skipped all of it -- reporting OK on three files while nine went unchecked,
// which is worse than not running at all.
function luaFilesUnder(dir) {
  const found = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) found.push(...luaFilesUnder(full));
    else if (entry.name.endsWith('.lua')) found.push(full);
  }
  return found.sort();
}

let files = process.argv.slice(2);
const scripts = path.join(__dirname, '..', 'Scripts');
if (files.length === 0) files = luaFilesUnder(scripts);

let failed = 0;
for (const file of files) {
  const name = path.relative(scripts, file).split(path.sep).join('/');
  try {
    luaparse.parse(fs.readFileSync(file, 'utf8'), { luaVersion: '5.3' });
    console.log('OK   ' + name);
  } catch (err) {
    failed++;
    console.log('FAIL ' + name + ' -> ' + err.message);
  }
}
process.exit(failed ? 1 : 0);
