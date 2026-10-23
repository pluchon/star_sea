"""转换用户提供的个人游玩音乐，保留来源与两遍响度分析结果。"""
from pathlib import Path
import argparse
import json
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'game/audio/music'
GROUPS = {
    'dawn_day': ['蓝天', '树林晨光', '清晨露水', '溪流', '松树', '初春之梦', '漫游', '湖面', '波光'],
    'dawn_dusk': ['夕阳下的回忆', '晚风', '风和落叶'],
    'night': ['静谧之夜', '满天繁星', '黑夜', '星空下的畅谈'],
    'rain': ['雷雨', '雾霭'], 'cave': ['洞穴'], 'space': ['巡航', '倒影'], 'ending': ['倒影'],
}
# 自动选取的候选区间，听感仍由第一版试玩确认，不声称已经试听。
EXCERPTS = {'echo_daily': ('初春之梦', 32, 20), 'echo_faith': ('洞穴', 20, 18),
            'echo_departure': ('夕阳下的回忆', 16, 21), 'echo_watcher': ('静谧之夜', 24, 18),
            'echo_ending': ('满天繁星', 40, 25)}


def run(args):
    return subprocess.run(args, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def convert(name, source, start=0, duration=None):
    destination = OUTPUT / (name + '.ogg')
    command = ['ffmpeg', '-hide_banner', '-nostdin', '-y', '-ss', str(start), '-i', str(source)]
    if duration is not None:
        command += ['-t', str(duration)]
    prefix = f'afade=t=in:d=1,afade=t=out:st={duration - 3}:d=3,' if duration else ''
    result = run(command + ['-af', prefix + 'loudnorm=I=-23:TP=-1.5:LRA=11:print_format=json', '-f', 'null', '-'])
    analysis = json.loads(re.findall(r'\{[^{}]+\}', result.stderr.decode('utf-8', errors='replace'))[-1])
    measured = ':'.join(f'{key}={analysis[value]}' for key, value in
                        [('measured_I', 'input_i'), ('measured_LRA', 'input_lra'),
                         ('measured_TP', 'input_tp'), ('measured_thresh', 'input_thresh'), ('offset', 'target_offset')])
    run(command + ['-af', prefix + 'loudnorm=I=-23:TP=-1.5:LRA=11:linear=true:' + measured,
                   '-ar', '44100', '-ac', '2', '-c:a', 'libvorbis', '-q:a', '6', str(destination)])
    return {'file': destination.name, 'source': source.name, 'start_s': start,
            'end_s': start + duration if duration else '整曲', 'analysis': analysis, 'bytes': destination.stat().st_size}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--only', help='仅重新转换一个输出名称，不含扩展名')
    args = parser.parse_args()
    if not shutil.which('ffmpeg'):
        raise SystemExit('缺少 ffmpeg，音乐转换不能继续。')
    OUTPUT.mkdir(parents=True, exist_ok=True)
    jobs = [(f'{group}_{i}', source, 0, None) for group, sources in GROUPS.items() for i, source in enumerate(sources, 1)]
    jobs += [(name, *values) for name, values in EXCERPTS.items()]
    records = []
    for name, source, start, duration in jobs:
        if not args.only or name == args.only:
            records.append(convert(name, ROOT / 'refer/音乐' / (source + '.m4a'), start, duration))
            print(name, '已转换', flush=True)
    rows = ['# 音乐来源与用途限制', '', '原始文件由用户提供，保存在 refer/音乐/。用户确认仅供个人游玩，不商用、不公开分发；这些曲目不属于项目原创或 CC0 素材。原始 m4a 不进入游戏包。', '',
            '采用 ffmpeg 两遍 loudnorm，目标 -23 LUFS、真峰值 -1.5 dBTP，Ogg Vorbis 立体声 44.1 kHz、质量 6。', '',
            '回声区间为实现阶段选择的候选段，尚未完成听感确认，第一版记录保留该项。', '', '| 输出文件 | 原始文件 | 区间 |', '| --- | --- | --- |']
    for name, source, start, duration in jobs:
        rows.append(f'| {name}.ogg | {source}.m4a | {start}–{start + duration} 秒 |' if duration else f'| {name}.ogg | {source}.m4a | 整曲 |')
    rows += ['', 'fallback/dawn_theme.wav 为项目原创加法合成音乐，来源为 tools/Generate-Music.py；仅在 dawn_day 无曲目时使用。', '']
    (OUTPUT / '来源.md').write_text('\n'.join(rows), encoding='utf-8')
    report = ROOT / 'test-output/audio/music-conversion.json'
    report.parent.mkdir(parents=True, exist_ok=True)
    report.write_text(json.dumps(records, ensure_ascii=False, indent=2), encoding='utf-8')
    print('本次转换', len(records), '文件，共', sum(r['bytes'] for r in records), '字节。')
