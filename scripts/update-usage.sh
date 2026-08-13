#!/bin/bash
# 自动更新 Denszh README 的 Token Usage by Model 区块
# 流程: 生成 USAGE 块 → 有变化则更新 README → push 分支 → PR → 自动合并
set -euo pipefail

# launchd 环境 PATH 不包含 homebrew，显式设置
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.bun/bin:/usr/bin:/bin:/usr/sbin:/sbin"

REPO="$HOME/imports/denszh-repo"
LOG="$HOME/.config/tokscale/readme-update.log"
TMP_JSON="$HOME/.config/tokscale/readme-models.json"
TMP_BLOCK="$HOME/.config/tokscale/readme-usage-block.txt"
CUR_BLOCK="$HOME/.config/tokscale/readme-current-block.txt"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }

log "=== 开始 ==="

cd "$REPO"
git pull --quiet 2>>"$LOG" || { log "git pull 失败"; exit 1; }

# 1. 生成最新模型统计 JSON
cd /tmp
if ! bunx tokscale@latest models --json --group-by model 2>/dev/null > "$TMP_JSON"; then
    log "生成 models JSON 失败"
    exit 1
fi

# 2. 生成 USAGE 块（环境变量传路径）
export TMP_JSON TMP_BLOCK REPO
python3 << 'PYEOF'
import json, os

d = json.load(open(os.environ['TMP_JSON']))
entries = d['entries']
total_t = d['totalInput']+d['totalOutput']+d['totalCacheRead']+d['totalCacheWrite']
total_msgs = d['totalMessages']
entries.sort(key=lambda e: -(e['input']+e['output']+e['cacheRead']+e['cacheWrite']))
top = [e for e in entries if e['input'] + e['output'] + e['cacheRead'] + e['cacheWrite'] >= 100_000_000]

def disp_w(s):
    return sum(2 if ord(c) > 0x2E80 else 1 for c in s)
def fmt_b(n):
    if n >= 1e9: return f"{n/1e9:.1f}B"
    if n >= 1e6: return f"{n/1e6:.1f}M"
    return f"{n/1e3:.0f}K"

lines = [f"all time · {fmt_b(total_t)} tokens · {total_msgs:,} messages", ""]
NAME_W = 30
for e in top:
    t = e['input']+e['output']+e['cacheRead']+e['cacheWrite']
    pct = t / total_t * 100
    filled = round(pct / 100 * 20)
    bar = '█' * filled + '░' * (20 - filled)
    name = e['model']
    pad = NAME_W - disp_w(name)
    lines.append(f"  {name}{' ' * pad}{bar}  {pct:4.0f}%  {fmt_b(t):>7}")

open(os.environ['TMP_BLOCK'], 'w').write('\n'.join(lines) + '\n')
PYEOF

# 3. 提取当前 README 的 USAGE 块
export CUR_BLOCK
python3 << 'PYEOF'
import re, os
readme = open(os.path.join(os.environ['REPO'], 'README.md')).read()
m = re.search(r'<!-- USAGE:START -->\n```console\n(.*?)\n```\n<!-- USAGE:END -->', readme, re.S)
open(os.environ['CUR_BLOCK'], 'w').write((m.group(1) + '\n') if m else '')
PYEOF

# 4. 无变化则退出
if diff -q "$TMP_BLOCK" "$CUR_BLOCK" >/dev/null 2>&1; then
    log "USAGE 块无变化，跳过"
    exit 0
fi

log "USAGE 块有变化，更新 README"

# 5. 更新 README（USAGE 块 + 图片 URL 版本参数防 camo 缓存）
python3 << 'PYEOF'
import re, os
from datetime import datetime
block = open(os.environ['TMP_BLOCK']).read().rstrip('\n')
readme = open(os.path.join(os.environ['REPO'], 'README.md')).read()
new_section = "<!-- USAGE:START -->\n```console\n" + block + "\n```\n<!-- USAGE:END -->"
readme = re.sub(r'<!-- USAGE:START -->.*?<!-- USAGE:END -->', new_section, readme, flags=re.S)
# 图片 URL 加时间戳版本参数：数据变化时 URL 变化 → GitHub camo 重新抓取，避免缓存 24h+ 旧图
v = datetime.now().strftime('%Y%m%d%H%M')
readme = re.sub(
    r'https://tokscale\.ai/api/embed/Denszh/svg\?[^)\s"]*',
    f'https://tokscale.ai/api/embed/Denszh/svg?template=graph&color=purple&graph=1&v={v}',
    readme, count=1)
open(os.path.join(os.environ['REPO'], 'README.md'), 'w').write(readme)
PYEOF

# 6. 提交 + PR + 自动合并
cd "$REPO"
BRANCH="update-usage-$(date +%Y%m%d-%H%M)"
git checkout -b "$BRANCH" >>"$LOG" 2>&1
git add README.md
git commit -m "docs: auto-update token usage by model" >>"$LOG" 2>&1
git push -u origin "$BRANCH" >>"$LOG" 2>&1
PR_URL=$(gh pr create --head "$BRANCH" --title "docs: auto-update token usage by model" --body "自动生成的按模型 token 统计更新" 2>>"$LOG")
log "创建 PR: $PR_URL"
gh pr merge --merge --delete-branch >>"$LOG" 2>&1
log "PR 已合并"
git checkout main >>"$LOG" 2>&1
git pull --quiet >>"$LOG" 2>&1

log "=== 完成 ==="
