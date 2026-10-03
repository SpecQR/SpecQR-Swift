// Development-only reproducibility tool. The Swift library has no Node dependency.
// Regenerates static mapping data from the platform's WHATWG Shift_JIS decoder,
// matching SpecQR's first-mapping behavior. Does not import any QR implementation.
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const decoder = new TextDecoder('shift_jis', { fatal: true });
const mapping = new Map();
for (let lead = 0x81; lead <= 0xeb; lead++) {
  if (lead > 0x9f && lead < 0xe0) continue;
  for (let trail = 0x40; trail <= 0xfc; trail++) {
    if (trail === 0x7f) continue;
    try {
      const text = decoder.decode(Uint8Array.of(lead, trail));
      const characters = Array.from(text);
      if (characters.length !== 1 || text === '\ufffd') continue;
      const scalar = text.codePointAt(0);
      if (scalar > 0xffff) throw new Error('Update the storage format for supplementary scalars');
      if (!mapping.has(scalar)) mapping.set(scalar, (lead << 8) | trail);
    } catch (error) {
      if (!(error instanceof TypeError)) throw error;
    }
  }
}
const packed = [...mapping].flatMap(([scalar, code]) => [scalar >> 8, scalar & 255, code >> 8, code & 255]);
const base64 = Buffer.from(packed).toString('base64');
const path = fileURLToPath(new URL('../Sources/SpecQR/Encoding/KanjiMap.swift', import.meta.url));
const source = readFileSync(path, 'utf8');
const pattern = /Data\(\s*base64Encoded:\s*"([A-Za-z0-9+/=]+)"/;
const match = source.match(pattern);
if (!match) throw new Error('Embedded mapping initializer not found');
if (match[1] === base64) console.log(`Mapping unchanged (${mapping.size} scalars).`);
else {
  writeFileSync(path, source.replace(match[1], base64));
  console.log(`Regenerated ${mapping.size} mappings.`);
}
