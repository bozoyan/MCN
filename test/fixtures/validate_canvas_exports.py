"""Validate actual export fixtures using the independent Draft 2020-12 engine.

Produce files with CANVAS_EXPORT_FIXTURE_DIR and canvas_export_test.dart, then:
uv run --with 'jsonschema[format-nongpl]' python test/fixtures/validate_canvas_exports.py <dir>
No application dependency is added.
"""
import copy
import json
import pathlib
import sys
from jsonschema import Draft202012Validator, FormatChecker

folder = pathlib.Path(sys.argv[1])
schema = json.loads((folder / 'canvas.schema.json').read_text())
Draft202012Validator.check_schema(schema)
assert 'date-time' in FormatChecker().checkers, 'Install jsonschema[format-nongpl] for RFC3339 checks'
validator = Draft202012Validator(schema, format_checker=FormatChecker())

def refs(value):
    if isinstance(value, dict):
        for key, child in value.items():
            if key == '$ref':
                assert child.startswith('#/'), child
            refs(child)
    elif isinstance(value, list):
        for child in value:
            refs(child)

refs(schema)
files = sorted(p for p in folder.glob('*.json') if p.name != 'canvas.schema.json')
assert files, 'No actual export fixtures supplied'
for file in files:
    validator.validate(json.loads(file.read_text()))
    print(f'VALID {file.name}')

sample = json.loads((folder / 'all_types.json').read_text())
mutations = 0

def rejected(changed):
    global mutations
    assert not validator.is_valid(changed), 'Invalid export unexpectedly accepted'
    mutations += 1

for field in sample:
    changed = copy.deepcopy(sample)
    del changed[field]
    rejected(changed)
changed = copy.deepcopy(sample)
changed['extra'] = True
rejected(changed)
for i, resource in enumerate(sample['resources']):
    if resource['detail_level'] != 'content':
        continue
    for field in resource['payload']:
        changed = copy.deepcopy(sample)
        del changed['resources'][i]['payload'][field]
        rejected(changed)
    changed = copy.deepcopy(sample)
    changed['resources'][i]['payload']['private_path'] = '/secret'
    rejected(changed)
    changed = copy.deepcopy(sample)
    changed['resources'][i]['type'] = 'unsupported'
    rejected(changed)
for field, value in [('format_version', 2), ('exported_at', 'yesterday')]:
    changed = copy.deepcopy(sample)
    changed[field] = value
    rejected(changed)
for field, value in [('width', 0), ('x', '12'), ('ref_type', 'unknown')]:
    changed = copy.deepcopy(sample)
    changed['nodes'][0][field] = value
    rejected(changed)
changed = copy.deepcopy(sample)
changed['edges'][0]['directed'] = not changed['edges'][0]['directed']
rejected(changed)
print(f'PASS {len(files)} valid fixtures; {mutations} malformed contracts rejected; all references offline')
