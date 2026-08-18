#!/bin/bash
# 更新 README Sports & Fitness 区块（高驰 COROS 数据）
# 依赖: coros-mcp (npm i -g coros-mcp) + 已登录 (~/.coros-mcp-skill-gateway-ts/token.json)
# 用法: ./scripts/update-sports.sh [--push]
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
README="$REPO_DIR/README.md"
YEAR="$(date +%Y)"
TODAY="$(date +%Y%m%d)"
WEEK_START="$(date -v-7d +%Y%m%d 2>/dev/null || date -d '7 days ago' +%Y%m%d)"

# 1. 拉取数据
FIT="$(coros-mcp call-tool --tool queryFitnessAssessmentOverview 2>/dev/null || true)"
REC="$(coros-mcp call-tool --tool queryRecoveryStatus 2>/dev/null || true)"
YEAR_DATA="$(coros-mcp call-tool --tool querySportRecords --arguments-json "{\"startDate\":\"${YEAR}0101\",\"endDate\":\"${YEAR}1231\",\"limit\":500}" 2>/dev/null || true)"
WEEK_DATA="$(coros-mcp call-tool --tool querySportRecords --arguments-json "{\"startDate\":\"${WEEK_START}\",\"endDate\":\"${TODAY}\",\"limit\":100}" 2>/dev/null || true)"

# 2. 解析生成区块
BLOCK="$(FIT="$FIT" REC="$REC" YEAR_DATA="$YEAR_DATA" WEEK_DATA="$WEEK_DATA" YEAR="$YEAR" python3 << 'PYEOF'
import json, re, os
from collections import defaultdict

def get_text(raw):
    try:
        d = json.loads(raw)
        return json.loads(d['content'][0]['text'])
    except Exception:
        return ''

MERGE = {
    'Pool Swim': '🏊 游泳', 'Open Water Swim': '🏊 游泳',
    'Outdoor Run': '🏃 跑步', 'Indoor Run': '🏃 跑步',
    'Strength': '💪 力量', 'Cycling': '🚴 骑行', 'Triathlon': '🏊 铁三',
    'Hike': '🥾 徒步', 'Jump Rope': '🤸 跳绳', 'Floor Climb': '🧗 爬楼',
    'Gym Cardio': '🏋️ 有氧',
}

def parse_records(txt):
    records, cur = [], None
    for line in txt.split('\n'):
        m = re.match(r'^(\d+)\. (.+?) — (\d{4}-\d{2}-\d{2})', line)
        if m:
            cur = {'type': m.group(2).strip(), 'date': m.group(3)}
            records.append(cur)
        elif cur and 'Duration:' in line:
            dm = re.search(r'([\d.]+) km', line)
            cur['km'] = float(dm.group(1)) if dm else 0.0
            tm = re.search(r'Duration: (\d+):(\d{2}):(\d{2})', line)
            if tm:
                cur['min'] = int(tm.group(1))*60 + int(tm.group(2)) + int(tm.group(3))/60
            else:
                tm2 = re.search(r'Duration: (\d+):(\d{2})', line)
                cur['min'] = int(tm2.group(1)) + int(tm2.group(2))/60 if tm2 else 0
    return records

def agg_by(recs):
    a = defaultdict(lambda: {'count': 0, 'km': 0.0, 'min': 0.0})
    for r in recs:
        k = MERGE.get(r['type'], r['type'])
        x = a[k]
        x['count'] += 1
        x['km'] += r.get('km', 0)
        x['min'] += r.get('min', 0)
    return a

def fmt_parts(agg):
    parts = []
    for label, x in sorted(agg.items(), key=lambda kv: -kv[1]['count']):
        km = f" {x['km']:.0f}km" if x['km'] >= 1 else ""
        parts.append(f"{label} {x['count']} 次{km}")
    return ' · '.join(parts)

def fmt_dur(minutes):
    m = int(round(minutes))
    if m >= 60:
        return f"{m//60}h{m%60:02d}m"
    return f"{m}m"

fit = get_text(os.environ['FIT'])
rec = get_text(os.environ['REC'])
year_txt = get_text(os.environ['YEAR_DATA'])
week_txt = get_text(os.environ['WEEK_DATA'])

vo2 = re.search(r'VO2max: (\d+)', fit).group(1) if fit else '?'
t5k = re.search(r'5 km Prediction: (.+)', fit).group(1).strip() if fit else '?'
thalf = re.search(r'Half Marathon Prediction: (.+)', fit).group(1).strip() if fit else '?'
tfull = re.search(r'^Marathon Prediction: (.+)', fit, re.M).group(1).strip() if fit else '?'
rec_pct = re.search(r'Recovery: (\d+)%', rec).group(1) if rec else '?'

year_recs = parse_records(year_txt)
ya = agg_by(year_recs)
tot_n = sum(x['count'] for x in ya.values())
tot_km = sum(x['km'] for x in ya.values())
tot_h = sum(x['min'] for x in ya.values()) / 60

# 最近 5 次明细（按日期倒序）
recent = sorted(year_recs, key=lambda r: r['date'], reverse=True)[:5]
recent_parts = []
for r in recent:
    label = MERGE.get(r['type'], r['type'])
    d = r['date'].split('-')
    dd = f"{d[1]}-{d[2]}"
    km = f" {r.get('km', 0):.2f}km" if r.get('km', 0) >= 1 else ""
    recent_parts.append(f"{dd} {label}{km} {fmt_dur(r.get('min', 0))}")
recent_line = ' · '.join(recent_parts) if recent_parts else '无记录'

# 月度聚合（倒序，最近月在前）
by_month = defaultdict(lambda: defaultdict(lambda: {'count': 0, 'km': 0.0, 'min': 0.0}))
for r in year_recs:
    ym = r['date'][:7]
    k = MERGE.get(r['type'], r['type'])
    x = by_month[ym][k]
    x['count'] += 1
    x['km'] += r.get('km', 0)
    x['min'] += r.get('min', 0)
month_lines = []
for ym in sorted(by_month.keys(), reverse=True):
    parts = []
    for label, x in sorted(by_month[ym].items(), key=lambda kv: -kv[1]['count']):
        km = f" {x['km']:.0f}km" if x['km'] >= 1 else ""
        parts.append(f"{label} {x['count']}{km}")
    month_lines.append(f"{ym[5:]}月: {' · '.join(parts)}")
month_block = '\n'.join(f"- {ml}" for ml in month_lines)

week_recs = parse_records(week_txt)
week_recs.sort(key=lambda r: r['date'])
wa = agg_by(week_recs)
wp = []
for label, x in sorted(wa.items(), key=lambda kv: -kv[1]['count']):
    tm = int(round(x['min']))
    wp.append(f"{label} {x['count']} 次 {tm//60}h{tm%60:02d}m" if tm >= 60 else f"{label} {x['count']} 次 {tm}m")
week_sum = ' · '.join(wp) if wp else '无运动'
if week_recs:
    d1, d2 = week_recs[0]['date'].split('-'), week_recs[-1]['date'].split('-')
    week_days = f"{d1[1]}/{d1[2]}–{d2[1]}/{d2[2]}"
else:
    week_days = ''

year_label = '**2026 至今**' if os.environ['YEAR'] == '2026' else f"**{os.environ['YEAR']} 至今**"
year_line = f"{year_label}: {fmt_parts(ya)}（{tot_n} 次 · {tot_km:.0f} km · {tot_h:.0f} h）" if year_recs else f"{year_label}: 无记录"
week_line = f"**本周 ({week_days})**: {week_sum}" if week_days else ''

block = f"""<!--SPORTS:START-->
## 🏃 Sports & Fitness

🏅 VO2max {vo2} · 恢复 {rec_pct}% · ⏱ 5K {t5k} · 半马 {thalf} · 全马 {tfull}

**最近 5 次**: {recent_line}

{year_line}

**月度统计**:
{month_block}

<!--SPORTS:END-->"""
print(block)
PYEOF
)"

# 3. 替换 README
python3 - "$README" "$BLOCK" << 'PYEOF'
import sys
readme = open(sys.argv[1]).read()
block = sys.argv[2]
start = readme.find('<!--SPORTS:START-->')
end = readme.find('<!--SPORTS:END-->')
if start == -1 or end == -1:
    print('⚠️ 未找到 SPORTS 标记，跳过'); sys.exit(0)
readme = readme[:start] + block + readme[end + len('<!--SPORTS:END-->'):]
open(sys.argv[1], 'w').write(readme)
print('✅ README Sports 区块已更新')
PYEOF

# 4. 提交（可选）
if [ "${1:-}" = "--push" ]; then
  cd "$REPO_DIR"
  git add README.md
  git commit -m "docs: update sports section ($(date +%m-%d))" -q || true
  git push -q origin HEAD 2>/dev/null || true
  echo "已提交推送"
fi
