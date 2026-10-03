import { writeFileSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';

// Usage: node Scripts/generate-structured-append-fixtures.mjs /path/to/SpecQR-JS
// Reference: SpecQR 3.0.0-rc.2, commit 15ad15e5c770ea0e39072f8f88b2733018f02ffd.
const upstream = path.resolve(process.argv[2] ?? '../upstream');
const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const packageInfo = JSON.parse(readFileSync(path.join(upstream, 'package.json'), 'utf8'));
if (packageInfo.version !== '3.0.0-rc.2') throw new Error('Expected SpecQR JS 3.0.0-rc.2');
const expectedCommit = '15ad15e5c770ea0e39072f8f88b2733018f02ffd';
const commit = execFileSync('git', ['-C', upstream, 'rev-parse', 'HEAD'], { encoding: 'utf8' }).trim();
if (commit !== expectedCommit) throw new Error(`Expected upstream commit ${expectedCommit}, got ${commit}`);
execFileSync('git', ['-C', upstream, 'diff', '--quiet', 'HEAD', '--', 'src', 'fixtures', 'package.json']);
const { generateStructuredAppend, generateSegmentsStructuredAppend } = await import(pathToFileURL(path.join(upstream, 'src/index.js')));
const cases=[];
function add(id,type,payload,options={}){cases.push({id,type,...(type==='text'?{text:payload}:type==='binary'?{bytes:payload}:{segments:payload}),options});}
add('alpha-v1-l-mask0','text','A'.repeat(31),{version:1,errorCorrectionLevel:'L',maskPattern:0,mode:'alphanumeric'});
add('numeric-v1-m','text','0123456789'.repeat(12),{version:1,errorCorrectionLevel:'M',maskPattern:3,mode:'numeric'});
add('kanji-v1-q','text','漢字茗荷'.repeat(8),{version:1,errorCorrectionLevel:'Q',maskPattern:4,mode:'kanji'});
add('unicode-scalars','text','é🙂漢e\u0301'.repeat(8),{version:2,errorCorrectionLevel:'M',maskPattern:5,mode:'byte'});
for(const optimizeSegments of [true,false]) add('auto-mixed-'+optimizeSegments,'text','1234567890123456789abc漢字HELLO WORLD'.repeat(4),{version:2,errorCorrectionLevel:'M',optimizeSegments});
for(const [i,errorCorrectionLevel] of ['L','M','Q','H'].entries()) add('binary-v1-'+errorCorrectionLevel,'binary',Array.from({length:60},(_,i)=>i*7%256),{version:1,errorCorrectionLevel,maskPattern:i});
add('auto-version-binary-max3','binary',Array.from({length:500},(_,i)=>i%256),{minVersion:1,maxVersion:10,maxSymbols:3,errorCorrectionLevel:'M',maskPattern:6});
add('auto-version-text-max4','text','1234567890abc漢字'.repeat(35),{minVersion:2,maxVersion:12,maxSymbols:4,errorCorrectionLevel:'Q',maskPattern:7});
add('version10-band','binary',Array.from({length:500},(_,i)=>(i*13)%256),{version:10,errorCorrectionLevel:'L',maskPattern:0});
add('version27-band','binary',Array.from({length:1600},(_,i)=>(i*29)%256),{version:27,errorCorrectionLevel:'M',maskPattern:2});
for(const fixture of JSON.parse(readFileSync(path.join(upstream, 'fixtures/structured-append-segments.json'),'utf8')))add(fixture.id,'manual',fixture.segments,fixture.options);
add('manual-unicode-scalars','manual',[{mode:'byte',data:'🙂ée\u0301'.repeat(12)}],{version:1,errorCorrectionLevel:'L',maskPattern:3});
add('manual-adjacent-byte-preserve','manual',[{mode:'byte',data:'abcdefghijk'},{mode:'byte',data:'ABCDEFGHIJK'},{mode:'byte',data:[1,2,3,4,5,6,7,8]}],{version:1,errorCorrectionLevel:'L',maskPattern:4});
add('manual-auto-minimum','manual',[{mode:'alphanumeric',data:'A'.repeat(45)},{mode:'numeric',data:'1234567890'.repeat(10)},{mode:'byte',data:'é'.repeat(45)}],{maxSymbols:4,errorCorrectionLevel:'M',maskPattern:1});
add('manual-binary16','manual',[{mode:'byte',data:Array.from({length:240},(_,i)=>i)}],{version:1,errorCorrectionLevel:'L',maxSymbols:16,maskPattern:0});
add('text-scalar-not-grapheme','text','e\u0301'.repeat(25),{version:1,errorCorrectionLevel:'L',mode:'byte',maskPattern:1});
for(const f of cases){let options={...f.options,output:'matrix',diagnostics:f.type==='manual'?{splitUnits:'full'}:true};let r=f.type==='manual'?generateSegmentsStructuredAppend(f.segments,options):generateStructuredAppend(f.type==='binary'?Uint8Array.from(f.bytes):f.text,options);f.expected={total:r.total,parity:r.parity,inputLength:r.inputLength,byteLength:r.byteLength,diagnostics:r.diagnostics,matrices:r.symbols.map(s=>s.matrix.map(r=>r.map(b=>b?'1':'0').join('')))};}
writeFileSync(path.join(root, 'Tests/SpecQRTests/Fixtures/structured-append-differential.json'),JSON.stringify({upstreamCommit:'15ad15e5c770ea0e39072f8f88b2733018f02ffd',upstreamVersion:'3.0.0-rc.2',cases},null,2)+'\n');
console.log(cases.length, 'fixtures generated');
