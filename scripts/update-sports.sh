#!/bin/bash
# 更新 README Sports & Fitness 区块（高驰 COROS 数据）
# 依赖: coros-mcp (npm i -g coros-mcp, 已登录) + GitHubPoster (自动安装到 ~/.venvs/github-poster)
# 用法: ./scripts/update-sports.sh [--push]
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
README="$REPO_DIR/README.md"
ASSETS="$REPO_DIR/assets"
TODAY="$(date +%Y%m%d)"
CUR_YEAR="$(date +%Y)"
FIRST_YEAR=2024   # 有记录的第一年
GP_VENV="${GP_VENV:-$HOME/.venvs/github-poster}"

# GitHubPoster 懒安装
if [ ! -x "$GP_VENV/bin/github_poster" ]; then
  echo "⚙️ 安装 GitHubPoster..."
  python3.11 -m venv "$GP_VENV"
  "$GP_VENV/bin/pip" install -q 'github_poster[all]'
fi

# 1. 拉取运动数据（2024 ~ 当前年）
mkdir -p /tmp/sports-data
for y in $(seq "$FIRST_YEAR" "$CUR_YEAR"); do
  coros-mcp call-tool --tool querySportRecords --arguments-json "{\"startDate\":\"${y}0101\",\"endDate\":\"${y}1231\",\"limit\":500}" 2>/dev/null \
    > "/tmp/sports-data/$y.json" || true
done
# 睡眠近 7 天
WEEK_START="$(date -v-7d +%Y%m%d 2>/dev/null || date -d '7 days ago' +%Y%m%d)"
coros-mcp call-tool --tool querySleepData --arguments-json "{\"startDate\":\"${WEEK_START}\",\"endDate\":\"${TODAY}\"}" 2>/dev/null > /tmp/sports-data/sleep.json || true
coros-mcp call-tool --tool queryFitnessAssessmentOverview 2>/dev/null > /tmp/sports-data/fit.json || true

# 2. 生成热力图（2026 运动次数）
python3 - "$CUR_YEAR" /tmp/sports-data << 'PYEOF'
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
    print(f'  ✅ {year} 热力图数据: {len(counts)} 天')
except Exception as e:
    print(f'  ⚠️ 热力图数据失败: {e}')
PYEOF
"$GP_VENV/bin/github_poster" json \
  --json_file "/tmp/sports-data/count-${CUR_YEAR}.json" \
  --year "$CUR_YEAR" --me "Denszh 💪 Training" \
  --background-color "#0d1117" --without-type-name >/dev/null 2>&1 || true
SVG_SRC="$(dirname "$("$GP_VENV/bin/github_poster" --help >/dev/null 2>&1; echo)")/OUT_FOLDER/json.svg"
[ -f /private/tmp/OUT_FOLDER/json.svg ] && SVG_SRC=/private/tmp/OUT_FOLDER/json.svg
[ -f "$SVG_SRC" ] && cp "$SVG_SRC" "$ASSETS/training-${CUR_YEAR}.svg" && echo "  ✅ 热力图已生成 assets/training-${CUR_YEAR}.svg"

# 3. 生成 SPORTS 区块
SPORTS_BLOCK="$(python3 - "$FIRST_YEAR" "$CUR_YEAR" /tmp/sports-data << 'PYEOF'
import json, re, os, sys
from collections import defaultdict

first_year, cur_year, data_dir = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]

MERGE = {
    'Pool Swim':'🏊 游泳','Open Water Swim':'🏊 游泳',
    'Outdoor Run':'🏃 跑步','Indoor Run':'🏃 跑步','Trail Run':'🏃 越野跑',
    'Strength':'💪 力量','Cycling':'🚴 骑行','Triathlon':'🏊 铁三',
    'Hike':'🥾 徒步','Jump Rope':'🤸 跳绳','Floor Climb':'🧗 爬楼','Gym Cardio':'🏋️ 有氧',
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

# 年度统计
year_lines = []
all_recs = []
for y in range(cur_year, first_year - 1, -1):
    recs = parse_records(load_json(f'{y}.json'))
    all_recs.extend(recs)
    agg = defaultdict(lambda: {'n':0,'km':0.0,'h':0.0})
    for r in recs:
        k = MERGE.get(r['type'], r['type'])
        a = agg[k]; a['n'] += 1; a['km'] += r.get('km',0); a['h'] += r.get('min',0)/60
    if not agg: continue
    parts = []
    for k, a in sorted(agg.items(), key=lambda x: -x[1]['n']):
        s = f"{k} {a['n']}次"
        if a['km'] >= 1: s += f" {a['km']:.0f}km"
        if a['h'] >= 1: s += f" {a['h']:.0f}h"
        parts.append(s)
    year_lines.append(f"- {y}: {' · '.join(parts)}")
year_block = '\n'.join(year_lines)

# 最近 5 次
recent = sorted(all_recs, key=lambda r: r['date'], reverse=True)[:5]
recent_parts = []
for r in recent:
    label = MERGE.get(r['type'], r['type'])
    d = r['date'].split('-')
    km = f" {r.get('km',0):.2f}km" if r.get('km',0) >= 1 else ""
    recent_parts.append(f"{d[1]}-{d[2]} {label}{km} {fmt_dur(r.get('min',0))}")
recent_line = ' · '.join(recent_parts) if recent_parts else '无记录'

# 睡眠近 7 天
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
    sleep_parts = []
    for s in sleeps:
        d = s['date'].split('-')
        flag = ' ⚠️' if s.get('score', 100) < 70 else ''
        sleep_parts.append(f"{d[1]}-{d[2]} 😴{s['score']} {s.get('dur','')}{flag}")
    sleep_line = ' · '.join(sleep_parts)
    d1, d2 = sleeps[0]['date'].split('-'), sleeps[-1]['date'].split('-')
    sleep_hdr = f"**本周睡眠** ({d1[1]}/{d1[2]}–{d2[1]}/{d2[2]}):"
else:
    sleep_hdr, sleep_line = '**本周睡眠**:', '无数据'

# 体能
fit = load_json('fit.json')
vo2 = re.search(r'VO2max: (\d+)', fit).group(1) if fit else '?'
t5k = re.search(r'5 km Prediction: (.+)', fit).group(1).strip() if fit else '?'
thalf = re.search(r'Half Marathon Prediction: (.+)', fit).group(1).strip() if fit else '?'
tfull = re.search(r'^Marathon Prediction: (.+)', fit, re.M).group(1).strip() if fit else '?'

block = f"""<!--SPORTS:START-->
## 🏃 Sports & Fitness

🏅 VO2max {vo2} · ⏱ 5K {t5k} · 半马 {thalf} · 全马 {tfull}

**年度训练**:
{year_block}

![{cur_year} 训练热力图](https://raw.githubusercontent.com/Denszh/Denszh/main/assets/training-{cur_year}.svg)

**最近 5 次**: {recent_line}

{sleep_hdr}
{sleep_line}

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
