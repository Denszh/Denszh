#!/bin/bash
# 更新 README Sports & Fitness 区块（高驰 COROS 数据）
# 依赖: coros-mcp (npm i -g coros-mcp, 已登录) + Python3 (heatmap.py 生成热力图)
# 用法: ./scripts/update-sports.sh [--push]
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
README="$REPO_DIR/README.md"
ASSETS="$REPO_DIR/assets"
HEATMAP="$REPO_DIR/scripts/heatmap.py"
TODAY="$(date +%Y%m%d)"
CUR_YEAR="$(date +%Y)"
FIRST_YEAR=2022   # 有记录的第一年

# 1. 拉取运动数据（2024 ~ 当前年）
mkdir -p /tmp/sports-data
for y in $(seq "$FIRST_YEAR" "$CUR_YEAR"); do
  coros-mcp call-tool --tool querySportRecords --arguments-json "{\"startDate\":\"${y}0101\",\"endDate\":\"${y}1231\",\"limit\":500}" 2>/dev/null \
    > "/tmp/sports-data/$y.json" || true
done
# 睡眠近 7 天
WEEK_START="$(date -v-7d +%Y%m%d 2>/dev/null || date -d '7 days ago' +%Y%m%d)"
coros-mcp call-tool --tool querySleepData --arguments-json "{\"startDate\":\"${WEEK_START}\",\"endDate\":\"${TODAY}\"}" 2>/dev/null > /tmp/sports-data/sleep.json || true

# 2. 生成热力图（只最近一年，heatmap.py 自绘 GitHub 风格）
y="$CUR_YEAR"
python3 - "$y" /tmp/sports-data << 'PYEOF' || true
import json, sys, re
year = sys.argv[1]
data_dir = sys.argv[2]
try:
    d = json.load(open(f'{data_dir}/{year}.json'))
    txt = json.loads(d['content'][0]['text'])
    counts = {}
    for line in txt.split('\n'):
        m = re.match(r'^(\d+)\. .+? — (\d{4}-\d{2}-\d{2})', line)
        if m: counts[m.group(2)] = counts.get(m.group(2), 0) + 1
    json.dump(counts, open(f'{data_dir}/count-{year}.json','w'))
    print(f'  ✅ {year} heatmap data: {len(counts)} days')
except Exception as e:
    print(f'  ⚠️ {year} 热力图数据失败: {e}')
PYEOF
  N_DAYS=$(python3 -c "import json;print(len(json.load(open('/tmp/sports-data/count-$y.json'))))" 2>/dev/null || echo 0)
  python3 "$HEATMAP" "/tmp/sports-data/count-$y.json" "$ASSETS/training-$y.svg" \
    --year "$y" --title "$y · $N_DAYS days" --color green \
    && echo "  ✅ 热力图已生成 assets/training-$y.svg"

# 3. 生成 SPORTS 区块
SPORTS_BLOCK="$(python3 - "$FIRST_YEAR" "$CUR_YEAR" /tmp/sports-data << 'PYEOF'
import json, re, os, sys
from collections import defaultdict

first_year, cur_year, data_dir = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]

MERGE = {
    'Pool Swim':'🏊 Swimming','Open Water Swim':'🏊 Swimming',
    'Outdoor Run':'🏃 Running','Indoor Run':'🏃 Running','Trail Run':'🏃 Running','Track Run':'🏃 Running',
    'Strength':'💪 Strength','Cycling':'🚴 Cycling','Triathlon':'🏊 Triathlon',
    'Hike':'🥾 Hiking','Jump Rope':'🤸 Jump Rope','Floor Climb':'🧗 Stairs','Gym Cardio':'🏋️ Cardio',
    'Walk':'🚶 Walking','GPS Cardio':'🗺️ Outdoor Cardio','Rowing':'🚣 Rowing',
}

def load_json(name):
    try:
        d = json.load(open(f'{data_dir}/{name}'))
        return json.loads(d['content'][0]['text'])
    except Exception:
        return ''

def parse_records(txt):
    recs, cur = [], None
    for line in txt.split('\n'):
        m = re.match(r'^(\d+)\. (.+?) — (\d{4}-\d{2}-\d{2})', line)
        if m:
            cur = {'type': m.group(2).strip(), 'date': m.group(3)}
            recs.append(cur)
        elif cur and 'Duration:' in line:
            dm = re.search(r'([\d.]+) km', line)
            cur['km'] = float(dm.group(1)) if dm else 0.0
            tm = re.search(r'Duration: (\d+):(\d{2}):(\d{2})', line)
            if tm: cur['min'] = int(tm.group(1))*60+int(tm.group(2))+int(tm.group(3))/60
            else:
                tm2 = re.search(r'Duration: (\d+):(\d{2})', line)
                cur['min'] = int(tm2.group(1))+int(tm2.group(2))/60 if tm2 else 0
    return recs

def fmt_dur(m):
    m = int(round(m))
    return f"{m//60}h{m%60:02d}m" if m >= 60 else f"{m}m"

# All Time 聚合（first_year ~ cur_year）
all_agg = defaultdict(lambda: {'n':0,'km':0.0,'h':0.0})
all_recs = []
for y in range(first_year, cur_year + 1):
    recs = parse_records(load_json(f'{y}.json'))
    all_recs.extend(recs)
    for r in recs:
        k = MERGE.get(r['type'], r['type'])
        a = all_agg[k]; a['n'] += 1; a['km'] += r.get('km',0); a['h'] += r.get('min',0)/60

# All Time 柱状图（tokscale bar 风格）
ITEMS = [
    ('🏃 Running', all_agg['🏃 Running']['km'], 'km'),
    ('🚴 Cycling', all_agg['🚴 Cycling']['km'], 'km'),
    ('🏊 Swimming', all_agg['🏊 Swimming']['km'], 'km'),
    ('💪 Strength', all_agg['💪 Strength']['h'], 'h'),
]
_mx = max(v for _, v, _ in ITEMS) or 1
bar_lines = []
for name, v, unit in ITEMS:
    pct = v / _mx * 100
    filled = round(pct / 5)
    bar = '█' * filled + '░' * (20 - filled)
    val_str = f"{v:,.0f}{unit}"
    bar_lines.append(f"{name:<12}{val_str:>8} {bar} {pct:5.0f}%")
bar_block = '\n'.join(bar_lines)

# 热力图（只最近一年）
import datetime as _dt
_cache_v = _dt.datetime.now().strftime('%Y%m%d%H%M')
heatmap_lines = f"![{cur_year}](https://raw.githubusercontent.com/Denszh/Denszh/main/assets/training-{cur_year}.svg?v={_cache_v})"

# 最近一周运动（7 天内，bar 图）
_week_ago = (_dt.date.today() - _dt.timedelta(days=7)).isoformat()
week_recs = sorted([r for r in all_recs if r['date'] >= _week_ago], key=lambda r: r['date'], reverse=True)
_week_hdr = f"**This Week's Workouts** ({(_dt.date.today()-_dt.timedelta(days=6)).strftime('%m/%d')}–{_dt.date.today().strftime('%m/%d')}):"
if week_recs:
    _mx_dur = max(r.get('min', 0) for r in week_recs) or 1
    week_bar = []
    for r in week_recs:
        label = MERGE.get(r['type'], r['type'])
        d = r['date'].split('-')
        dur = r.get('min', 0)
        pct = dur / _mx_dur * 100
        filled = round(pct / 5)
        bar = '█' * filled + '░' * (20 - filled)
        km = f" {r.get('km',0):.2f}km" if r.get('km',0) >= 1 else ""
        week_bar.append(f"{d[1]}-{d[2]} {label:<9}{fmt_dur(dur):>7} {bar} {pct:5.0f}%{km}")
    week_block = '\n'.join(week_bar)
else:
    week_block = 'No workouts'

# 本周睡眠
sleep_txt = load_json('sleep.json')
sleeps = []
cur = None
for line in sleep_txt.split('\n'):
    m = re.match(r'^(\d{4}-\d{2}-\d{2})$', line.strip())
    if m: cur = m.group(1); sleeps.append({'date': cur}); continue
    if cur:
        sm = re.search(r'Sleep Score: (\d+)', line)
        if sm: sleeps[-1]['score'] = int(sm.group(1))
        tm = re.search(r'Main Sleep: (\d+)h (\d+)min', line)
        if tm: sleeps[-1]['dur'] = f"{tm.group(1)}h{tm.group(2)}m"
sleeps = [s for s in sleeps if 'score' in s]
if sleeps:
    sleep_bar = []
    for s in sleeps:
        d = s['date'].split('-')
        score = s.get('score', 0)
        filled = round(score / 5)
        bar = '█' * filled + '░' * (20 - filled)
        flag = ' ⚠️' if score < 70 else ''
        sleep_bar.append(f"{d[1]}-{d[2]} 😴{score:>3} {s.get('dur',''):>7} {bar} {score:5.0f}%{flag}")
    sleep_block = '\n'.join(sleep_bar)
    d1, d2 = sleeps[0]['date'].split('-'), sleeps[-1]['date'].split('-')
    sleep_hdr = f"**This Week's Sleep** ({d1[1]}/{d1[2]}–{d2[1]}/{d2[2]}):"
else:
    sleep_hdr, sleep_block = "**This Week's Sleep**:", 'No data'

block = f"""<!--SPORTS:START-->
## 🏃 Sports & Fitness

**All Time ({first_year}–{cur_year})**:
```
{bar_block}
```

![{cur_year} Training Heatmap](https://raw.githubusercontent.com/Denszh/Denszh/main/assets/training-{cur_year}.svg?v={_cache_v})

{_week_hdr}
```
{week_block}
```

{sleep_hdr}
```
{sleep_block}
```

<!--SPORTS:END-->"""
print(block)
PYEOF
)"

# 4. 替换 README
python3 - "$README" "$SPORTS_BLOCK" << 'PYEOF'
import sys
readme = open(sys.argv[1]).read()
block = sys.argv[2]
start = readme.find('<!--SPORTS:START-->')
end = readme.find('<!--SPORTS:END-->')
if start == -1 or end == -1:
    print('⚠️ 未找到 SPORTS 标记'); sys.exit(0)
readme = readme[:start] + block + readme[end + len('<!--SPORTS:END-->'):]
open(sys.argv[1], 'w').write(readme)
print('✅ README Sports 区块已更新')
PYEOF

# 5. 提交（可选）
if [ "${1:-}" = "--push" ]; then
  cd "$REPO_DIR"
  git add README.md assets/training-*.svg
  git commit -m "docs: update sports section ($(date +%m-%d))" -q || true
  git push -q origin HEAD 2>/dev/null || true
  echo "已提交推送"
fi
