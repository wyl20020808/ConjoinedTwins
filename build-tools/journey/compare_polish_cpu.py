"""对同一密集布局比较本轮查询优化，复用当前导入缓存，不修改工作区源码。"""
from pathlib import Path
import argparse
import json
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument('--engine', default='/Applications/Godot.app/Contents/MacOS/Godot')
parser.add_argument('--base', default='3ee7185')
args = parser.parse_args()
stage = ROOT / 'build-tools/cache/polish-reference'
stage.mkdir(parents=True, exist_ok=True)
shutil.copytree(ROOT/'scripts', stage/'scripts', dirs_exist_ok=True)
(stage/'tests').mkdir(exist_ok=True)
shutil.copy2(ROOT/'tests/journey_polish_performance.gd', stage/'tests/journey_polish_performance.gd')
shutil.copy2(ROOT/'project.godot', stage/'project.godot')
for name in ['assets', '.godot', 'scenes']:
    if not (stage/name).exists():
        (stage/name).symlink_to(ROOT/name, target_is_directory=True)
source = stage/'scripts/journey_run.gd'
text = source.read_text()
baseline = subprocess.check_output(['git', 'show', args.base+':scripts/journey_run.gd'], cwd=ROOT, text=True)
for name in ['ground_gaps', 'surface_at', 'indexed_terrain']:
    pattern = r'func '+name+r'\(.*?(?=\nfunc |\n#|\Z)'
    original = re.search(pattern, baseline, re.S)
    if not original:
        raise RuntimeError('Missing baseline function: '+name)
    text, count = re.subn(pattern, lambda _: original.group(), text, flags=re.S)
    if count != 1:
        raise RuntimeError('Unexpected replacement count: '+name)
for name in ['indexed_solids', 'sweeper_rope_hits']:
    text, count = re.subn(r'\nfunc '+name+r'\(.*?(?=\nfunc |\n#|\Z)', '', text, flags=re.S)
    if count != 1:
        raise RuntimeError('Missing optimized override: '+name)
source.write_text(text)
output = ROOT/'build-tools/journey/evidence/polish'
output.mkdir(parents=True, exist_ok=True)
report = {'baseline': args.base, 'samples_per_chapter': 180, 'warmup_steps': 30}
for name, project in [('reference', stage), ('optimized', ROOT)]:
    result = subprocess.run([args.engine, '--headless', '--path', str(project), '--script', 'tests/journey_polish_performance.gd'], capture_output=True, text=True)
    log = result.stdout+result.stderr
    (output/('cpu-'+name+'-final.log')).write_text(log)
    if result.returncode or 'ERROR:' in log:
        raise RuntimeError(log)
    line = next(line for line in log.splitlines() if line.startswith('POLISH_CPU '))
    report[name] = json.loads(line.removeprefix('POLISH_CPU '))
    print(name, report[name], flush=True)
(output/'cpu-comparison.json').write_text(json.dumps(report, indent=2)+'\n')
