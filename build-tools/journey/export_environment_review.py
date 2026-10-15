"""导出独立的展示层巡检页，不修改生产入口或导出预设。复用既有模板及导入缓存。"""
from pathlib import Path
import subprocess
import argparse
parser=argparse.ArgumentParser()
parser.add_argument("--fixture",default="environment_review")
args=parser.parse_args()
if args.fixture not in ["environment_review","polish_review"]:parser.error("unknown fixture")
ROOT=Path(__file__).resolve().parents[2]
STAGE=ROOT/'build-tools/cache'/args.fixture.replace('_','-')
STAGE.mkdir(parents=True,exist_ok=True)
for name in ['assets','scripts','scenes','.godot']:
 p=STAGE/name
 if not p.exists():p.symlink_to(ROOT/name,target_is_directory=True)
(STAGE/'environment_review.gd').write_bytes((ROOT/'tests/fixtures'/(args.fixture+'.gd')).read_bytes())
(STAGE/'environment_review.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://environment_review.gd" id="1"]\n[node name="Review" type="Node"]\nscript=ExtResource("1")\n')
(STAGE/'project.godot').write_text((ROOT/'project.godot').read_text().replace('res://scenes/journey_boot.tscn','res://environment_review.tscn'))
presets=(ROOT/'export_presets.cfg').read_text().replace('res://build-tools/cache/web_nothreads_release.zip',str(ROOT/'build-tools/cache/web_nothreads_release.zip'))
(STAGE/'export_presets.cfg').write_text(presets)
out=ROOT/'builds'/args.fixture.replace('_','-');out.mkdir(parents=True,exist_ok=True)
subprocess.run(['/Applications/Godot.app/Contents/MacOS/Godot','--headless','--path',str(STAGE),'--export-release','Web',str(out/'index.html')],check=True)
