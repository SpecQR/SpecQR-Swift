#!/usr/bin/env python3
"""Independent FNC1-second semantic checks using SHA-256-pinned ZXing-C++ wheels.

Python 3.10+ with pip is required. Test dependencies and reports stay under .build/.
Neither NumPy nor Pillow is needed: the decoder consumes a built-in memoryview.
"""
import hashlib
import importlib
import importlib.metadata
import json
import os
from pathlib import Path
import string
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / '.build' / 'zxing-cpp'
WORK.mkdir(parents=True, exist_ok=True)
REQUIREMENTS = ROOT / 'Scripts' / 'zxing-java' / 'zxing-cpp-requirements.txt'
requirement_hash = hashlib.sha256(REQUIREMENTS.read_bytes()).hexdigest()
receipt = WORK / '.verified-requirements-sha256'
if not receipt.exists() or receipt.read_text().strip() != requirement_hash:
    subprocess.run([sys.executable, '-m', 'pip', 'install', '--target', str(WORK),
                    '--upgrade', '--only-binary=:all:', '--no-deps', '--require-hashes',
                    '--requirement', str(REQUIREMENTS)], check=True)
    receipt.write_text(requirement_hash + '\n')
sys.path.insert(0, str(WORK))
zxingcpp = importlib.import_module('zxingcpp')
assert importlib.metadata.version('zxing-cpp') == '3.1.1'
BINARY = os.environ.get('SPECQR_CLI')
if not BINARY:
    directory = subprocess.check_output(['swift', 'build', '-c', 'release', '--show-bin-path'], cwd=ROOT, text=True).strip()
    BINARY = str(Path(directory) / 'specqr-cli')
assert Path(BINARY).exists(), 'Run swift build -c release first.'


def swift(requests):
    process = subprocess.run([BINARY, '--json-lines'],
                             input='\n'.join(map(json.dumps, requests)) + '\n',
                             capture_output=True, text=True, check=True)
    results = [json.loads(line) for line in process.stdout.splitlines()]
    assert len(results) == len(requests)
    for request, result in zip(requests, results):
        assert 'error' not in result, (request, result)
    return results


def decode(matrix):
    # Quiet zone + nearest-neighbor expansion only. No SpecQR decoder or JS oracle.
    width = len(matrix) + 8
    pixels = bytearray([255]) * (width * width)
    for y, row in enumerate(matrix):
        for x, value in enumerate(row):
            pixels[(y + 4) * width + x + 4] = 0 if value == '1' else 255
    scaled = bytearray()
    for y in range(width):
        row = bytearray(value for value in pixels[y * width:(y + 1) * width] for _ in range(3))
        scaled.extend(row * 3)
    view = memoryview(scaled).cast('B', shape=(width * 3, width * 3))
    result = zxingcpp.read_barcode(view, text_mode=zxingcpp.TextMode.Plain)
    assert result is not None and result.valid, 'ZXing-C++ did not decode the symbol'
    return result


cases = []
indicators = [f'{value:02}' for value in range(100)] + list(string.ascii_uppercase + string.ascii_lowercase)
for ordinal, indicator in enumerate(indicators):
    options = {'version': 3, 'errorCorrectionLevel': ['L', 'M', 'Q', 'H'][ordinal % 4], 'maskPattern': ordinal % 8}
    alpha = {'mode': 'alphanumeric', 'text': 'ABC%123%%XYZ'}
    binary = {'mode': 'byte', 'bytes': [0, 255, 128, 29, 37, 65, 0]}
    for data in [alpha, binary]:
        for route in ['manual', 'options']:
            expected_bytes = indicator.encode() + (b'ABC\x1d123%XYZ' if data['mode'] == 'alphanumeric' else bytes(data['bytes']))
            if route == 'manual':
                request = {'segments': [{'mode': 'fnc1-second', 'applicationIndicator': indicator}, data], 'options': options}
            else:
                request = {key: value for key, value in data.items() if key != 'mode'}
                request['options'] = {**options, 'mode': 'auto' if data['mode'] == 'alphanumeric' else 'byte', 'fnc1Second': indicator}
                if data['mode'] == 'alphanumeric':
                    expected_bytes = indicator.encode() + data['text'].encode()
            cases.append((request, expected_bytes, f'{indicator}-{data["mode"]}-{route}'))

results = swift([case[0] for case in cases])
for (request, expected_bytes, name), generated in zip(cases, results):
    decoded = decode(generated['matrix'])
    # ZXing-C++ prepends the decoded application indicator to the data bytes.
    assert decoded.bytes == expected_bytes, (name, decoded.bytes, expected_bytes)
    assert decoded.symbology_identifier == ']Q5', (name, decoded.symbology_identifier)
    assert decoded.ec_level == request['options']['errorCorrectionLevel'], name
    assert decoded.extra['DataMask'] == request['options']['maskPattern'], name
    assert decoded.extra['Version'] == str(request['options']['version']), name

# High-level text APIs preserve literal percent. Explicit low-level FNC1 controls
# above retain the standard alphanumeric single-percent/doubled-percent meaning.
percent_cases = []
for text in ['10ABC%DEF', '10ABC%%DEF', '10ABC%DEF\x1d21SER%%IAL', '10ABC\x1d21SERIAL']:
    for optimize in [True, False]:
        for mode in ['auto', 'byte']:
            for controls, prefix, identifier in [({'gs1': True}, b'', ']Q3'),
                                                   ({'fnc1Second': 'A'}, b'A', ']Q5')]:
                request = {'text': text, 'options': {**controls, 'mode': mode, 'optimizeSegments': optimize}}
                percent_cases.append((request, prefix + text.encode(), identifier))
for (request, expected_bytes, identifier), generated in zip(percent_cases, swift([case[0] for case in percent_cases])):
    decoded = decode(generated['matrix'])
    assert decoded.bytes == expected_bytes, (request, decoded.bytes, expected_bytes)
    assert decoded.symbology_identifier == identifier


report = {
    'decoder': 'ZXing-C++ 3.1.1',
    'swiftCLISHA256': hashlib.sha256(Path(BINARY).read_bytes()).hexdigest(),
    'requirementsSHA256': requirement_hash,
    'python': sys.version.split()[0],
    'applicationIndicators': len(indicators),
    'fnc1SecondSymbols': len(cases),
    'fnc1SecondRoutes': ['manual segments', 'options'],
    'fnc1SecondModes': ['low-level alphanumeric with GS and escaped percent', 'high-level literal-percent text', 'binary byte payload'],
    'highLevelPercentAndSeparatorCases': len(percent_cases),
    'assertionsPassed': True,
    'limitations': [
        'ZXing-C++ returns the FNC1-second application indicator as a prefix of decoded data.',
        'Explicit low-level FNC1 alphanumeric segments retain the standard single-percent separator and doubled-percent literal semantics; high-level text APIs preserve input percent bytes.',
        'Synthetic matrix rasterization is not physical-camera or print validation.',
    ],
}
(WORK / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report, indent=2))
