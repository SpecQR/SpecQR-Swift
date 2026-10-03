// Independent decoder verification. Requires Java 17+, Node 20+, and a release Swift build.
// Dependencies are test-only, SHA-256 pinned, and stored under ignored .build/.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const work = path.join(root, '.build/zxing-java');
fs.mkdirSync(work, { recursive: true });
function run(command, args, options = {}) {
  const out = spawnSync(command, args, { cwd: root, encoding: 'utf8', maxBuffer: 128 * 1024 * 1024, ...options });
  assert.equal(out.status, 0, `${command} ${args.join(' ')}\n${out.error ?? ''}\n${out.stderr}\n${out.stdout?.slice(0, 3000)}`);
  return out.stdout;
}
const binary = process.env.SPECQR_CLI ?? path.join(run('swift', ['build', '-c', 'release', '--show-bin-path']).trim(), 'specqr-cli');
const bin = path.dirname(path.resolve(binary));
assert.ok(fs.existsSync(binary), 'Run swift build -c release first.');
const jar = path.join(work, 'core-3.5.4.jar');
if (!fs.existsSync(jar)) run('curl', ['--fail', '--location', '--retry', '2',
  'https://repo.maven.apache.org/maven2/com/google/zxing/core/3.5.4/core-3.5.4.jar', '--output', jar]);
assert.equal(createHash('sha256').update(fs.readFileSync(jar)).digest('hex'),
  '71de5d89341b5fcf5dd89da7f44e84d825d0e084cdf3ec77c9abe26b0f0ceb13', 'ZXing artifact SHA-256');
const staticLibrary = path.join(bin, 'libSpecQR.a');
const objectDirectory = path.join(bin, 'SpecQR.build');
const linkInputs = fs.existsSync(staticLibrary) ? [staticLibrary] :
  fs.readdirSync(objectDirectory).filter(name => name.endsWith('.o')).map(name => path.join(objectDirectory, name));
const generator = path.join(work, 'generate-structured-append');
run('swiftc', ['-I', bin, '-I', path.join(bin, 'Modules'),
  path.join(root, 'Scripts/zxing-java/GenerateStructuredAppend.swift'), ...linkInputs, '-o', generator]);
const highLevel = run(generator, []).trim().split('\n').map(JSON.parse);
function swift(requests) {
  const lines = run(binary, ['--json-lines'], { input: requests.map(r => JSON.stringify(r)).join('\n') + '\n' })
    .trim().split('\n').map(JSON.parse);
  assert.equal(lines.length, requests.length);
  lines.forEach((value, index) => assert.equal(value.error, undefined, `Swift ${JSON.stringify(requests[index])}: ${value.error}`));
  return lines;
}
const b64 = bytes => Buffer.from(bytes).toString('base64');
const xor = bytes => [...bytes].reduce((a, b) => a ^ b, 0);
const tests = [];
const add = (id, request, expected) => tests.push({ id, request, expected });
for (const [ei, errorCorrectionLevel] of ['L', 'M', 'Q', 'H'].entries()) {
  for (let maskPattern = 0; maskPattern < 8; maskPattern++) {
    const options = { errorCorrectionLevel, maskPattern, version: 4 };
    add(`numeric-${ei}-${maskPattern}`, { text: '012345678901234567890123456789', options: { ...options, mode: 'numeric' } }, { text: '012345678901234567890123456789' });
    add(`alpha-${ei}-${maskPattern}`, { text: 'SPECQR / 12345 %', options: { ...options, mode: 'alphanumeric' } }, { text: 'SPECQR / 12345 %' });
    add(`kanji-${ei}-${maskPattern}`, { text: '漢字東京大阪日本語', options: { ...options, mode: 'kanji' } }, { text: '漢字東京大阪日本語' });
    const text = 'e\u0301🙂漢字 café';
    add(`eci-utf8-${ei}-${maskPattern}`, { text, options: { ...options, mode: 'byte', eci: 26 } }, { text, bytes: [...Buffer.from(text)], identifier: ']Q2' });
    const bytes = [0, 255, 128, 127, 13, 10, 29, 0, 254, 65];
    add(`binary-${ei}-${maskPattern}`, { bytes, options }, { bytes });
    add(`fnc1-alpha-${ei}-${maskPattern}`, { segments: [{ mode: 'fnc1' }, { mode: 'alphanumeric', text: '10LOT%21SER%%IAL' }], options }, { text: '10LOT\u001d21SER%IAL', identifier: ']Q3' });
    add(`fnc1-byte-${ei}-${maskPattern}`, { text: '10LOT\u001d21SER%IAL', options: { ...options, mode: 'byte', gs1: true } }, { text: '10LOT\u001d21SER%IAL', identifier: ']Q3' });
  }
}
// Known ECI assignments including the two-byte representation (170 = ASCII alias).
for (const [eci, bytes, text] of [[3, [99, 97, 102, 233], 'café'], [20, [138, 191, 142, 154], '漢字'], [170, [65, 83, 67, 73, 73], 'ASCII']]) {
  add(`eci-${eci}`, { segments: [{ mode: 'eci', assignmentNumber: eci }, { mode: 'byte', bytes }] }, { text, bytes, identifier: ']Q2' });
}
add('mixed-bytes', { segments: [{ mode: 'eci', assignmentNumber: 26 }, { mode: 'byte', text: 'café' }, { mode: 'numeric', text: '12345' }, { mode: 'byte', text: '🙂' }, { mode: 'kanji', text: '漢字' }] },
  { text: 'café12345🙂漢字', byteSegments: [b64(Buffer.from('café')), b64(Buffer.from('🙂'))], identifier: ']Q2' });
// Exhaust every legal Structured Append (index,total) combination: 135 headers.
for (let total = 2; total <= 16; total++) for (let index = 1; index <= total; index++) {
  const bytes = [0, index, total, 255, 128];
  const parity = (total * 17 + index * 31) & 255;
  add(`sa-${index}-${total}`, { bytes, options: { version: 2, maskPattern: index % 8,
    errorCorrectionLevel: ['L', 'M', 'Q', 'H'][total % 4], structuredAppend: { index, total, parity } } },
    { bytes, sequence: (index - 1) * 16 + total - 1, parity });
}
// Safe high-level GS1 text preserves both percent and actual U+001D separators.
for (const text of ['10ABC%DEF', '10ABC%%DEF', '10ABC%DEF\u001d21SER%%IAL', '10ABC\u001d21SERIAL']) {
  for (const optimizeSegments of [true, false]) {
    add(`high-gs1-${tests.length}`, { text, options: { gs1: true, optimizeSegments } }, { text, identifier: ']Q3' });
  }
}
const generated = swift(tests.map(test => test.request));
const pngs = swift(tests.map(test => ({ ...test.request, command: 'render', format: 'png', render: { scale: 3 } })));
const inputs = [], checks = [];
function enqueue(kind, input, expectation, context) {
  inputs.push(`${kind}\t${input}`); checks.push({ expectation, context });
}
function addSymbol(id, symbol, png, expected) {
  const expectation = { sequence: null, parity: null, identifier: ']Q1', ...expected,
    rawBytes: b64(symbol.dataCodewords), ecc: symbol.ecc ?? symbol.errorCorrectionLevel };
  enqueue('matrix', symbol.matrix.join(','), expectation, `${id} matrix`);
  const pngPath = path.join(work, `${id}.png`);
  fs.writeFileSync(pngPath, Buffer.from(png, 'base64'));
  enqueue('png', pngPath, expectation, `${id} PNG detection`);
}
tests.forEach((test, index) => addSymbol(test.id, generated[index], pngs[index].output.split(',')[1], test.expected));
const groupChecks = [];
for (const group of highLevel) {
  const sourceBytes = group.bytes ?? [...Buffer.from(group.text)];
  assert.equal(group.parity, xor(sourceBytes), `${group.id} parity`);
  assert.equal(group.symbols.length, group.total);
  if (group.id === 'high-sixteen-symbols') assert.equal(group.total, 16);
  const indices = [];
  group.symbols.forEach((symbol, index) => {
    indices.push(checks.length);
    addSymbol(`${group.id}-${index + 1}`, symbol, symbol.pngBase64,
      { sequence: index * 16 + group.total - 1, parity: group.parity });
  });
  groupChecks.push({ group, indices, sourceBytes });
}
// Version 1 bottom-right modules at y=20,16,12 are in three distinct data codewords.
const damageRequests = ['L', 'M', 'Q', 'H'].flatMap(errorCorrectionLevel => Array.from({ length: 8 }, (_, maskPattern) =>
  ({ text: 'ECC', options: { version: 1, errorCorrectionLevel, maskPattern, mode: 'byte' } })));
const damaged = swift(damageRequests);
damaged.forEach((symbol, index) => {
  const matrix = symbol.matrix.map(row => row.split(''));
  for (const y of [20, 16, 12]) matrix[y][20] = matrix[y][20] === '1' ? '0' : '1';
  enqueue('matrix', matrix.map(row => row.join('')).join(','),
    { text: 'ECC', rawBytes: b64(symbol.dataCodewords), ecc: symbol.errorCorrectionLevel,
      sequence: null, parity: null, identifier: ']Q1', errorsCorrected: 3 }, `three-codeword-damage-${index}`);
});
enqueue('matrix', Array(21).fill('0'.repeat(21)).join(','), { error: true }, 'invalid-all-white-matrix');
const list = path.join(work, 'inputs.tsv');
fs.writeFileSync(list, inputs.join('\n') + '\n');
const output = run('java', ['-Djava.awt.headless=true', '--class-path', jar,
  path.join(root, 'Scripts/zxing-java/DecodeSymbols.java'), list]);
const decoded = output.trim().split('\n').map(JSON.parse);
assert.equal(decoded.length, checks.length);
for (const [index, record] of decoded.entries()) {
  const { expectation: exp, context } = checks[index];
  assert.equal(record.ordinal, index);
  if (exp.error) { assert.ok(record.error, context); continue; }
  assert.equal(record.error, undefined, `${context}: ${record.error}`);
  if (exp.text !== undefined) assert.equal(Buffer.from(record.textBase64, 'base64').toString('utf8'), exp.text, `${context} text`);
  if (exp.bytes) assert.deepEqual([...Buffer.concat(record.byteSegments.map(s => Buffer.from(s, 'base64')))], exp.bytes, `${context} bytes`);
  if (exp.byteSegments) assert.deepEqual(record.byteSegments, exp.byteSegments, `${context} byte-segment boundaries`);
  assert.equal(record.rawBytesBase64, exp.rawBytes, `${context} complete corrected data codewords`);
  assert.equal(record.sequence, exp.sequence, `${context} sequence`);
  assert.equal(record.parity, exp.parity, `${context} parity`);
  assert.equal(record.ecc, exp.ecc, `${context} ECC`);
  assert.equal(record.symbologyIdentifier, exp.identifier, `${context} symbology`);
  if (exp.errorsCorrected !== undefined) assert.equal(record.errorsCorrected, exp.errorsCorrected, `${context} corrected errors`);
}
for (const { group, indices, sourceBytes } of groupChecks) {
  for (const offset of [0, 1]) {
    // Simulate out-of-order scanning, reconstruct only from decoded metadata.
    const parts = indices.map(index => decoded[index + offset]).reverse().sort((a, b) => (a.sequence >> 4) - (b.sequence >> 4));
    if (group.bytes) {
      const bytes = Buffer.concat(parts.flatMap(part => part.byteSegments.map(s => Buffer.from(s, 'base64'))));
      assert.deepEqual([...bytes], sourceBytes, `${group.id} reassembled bytes`);
      assert.equal(xor(bytes), parts[0].parity, `${group.id} decoder-derived parity`);
    } else {
      const text = parts.map(part => Buffer.from(part.textBase64, 'base64').toString('utf8')).join('');
      assert.equal(text, group.text, `${group.id} reassembled text`);
      assert.equal(xor(Buffer.from(text)), parts[0].parity, `${group.id} decoder-derived parity`);
    }
  }
}
const report = {
  decoder: 'ZXing Java core 3.5.4',
  swiftCLISHA256: createHash('sha256').update(fs.readFileSync(binary)).digest('hex'),
  decoderSHA256: createHash('sha256').update(fs.readFileSync(jar)).digest('hex'),
  java: run('java', ['--version']).split('\n')[0],
  lowLevelSymbols: tests.length, structuredAppendHeaders: 135,
  highLevelSets: highLevel.length, highLevelSymbols: highLevel.reduce((sum, group) => sum + group.total, 0),
  pngDetectionDecodes: checks.filter(check => check.context.endsWith('PNG detection')).length,
  matrixDecodes: checks.filter(check => check.context.endsWith('matrix')).length - 1,
  damagedSymbolsCorrected: damaged.length, errorsPerDamagedSymbol: 3,
  invalidSymbolsRejected: 1, assertionsPassed: true,
  limitations: [
    'ZXing Java 3.5.4 does not consume the FNC1-second application indicator; that mode is not claimed as Java-decoder verified.',
    'Arbitrary ECI assignments are not universally supported by decoders. Tested assignments: 3, 20, 26, 170.',
    'Synthetic PNG detection and controlled data-module damage are not physical-camera, print, or general damage-tolerance tests.'
  ]
};
fs.writeFileSync(path.join(work, 'decoded.jsonl'), output);
fs.writeFileSync(path.join(work, 'report.json'), JSON.stringify(report, null, 2) + '\n');
console.log(JSON.stringify(report, null, 2));
