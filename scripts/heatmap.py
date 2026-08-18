#!/usr/bin/env python3
"""GitHub 风格日历热力图 SVG 生成器（紧凑美观版）
用法: python3 heatmap.py data.json out.svg --year 2026 [--title "2026" --color purple --dark]
data.json: {"YYYY-MM-DD": count}
"""
import json, sys, argparse, calendar, datetime

# 5 阶色板（level 0-4），GitHub 官方风格
PALETTES = {
    'green':  ['#ebedf0', '#9be9a8', '#40c463', '#30a14e', '#216e39'],
    'purple': ['#ebedf0', '#d0bfff', '#b197fc', '#9775fa', '#845ef7'],
    'blue':   ['#ebedf0', '#a5d8ff', '#74c0fc', '#4dabf7', '#339af0'],
    'teal':   ['#ebedf0', '#96f2d7', '#63e6be', '#38d9a9', '#12b886'],
    'red':    ['#ebedf0', '#ffc9c9', '#ff8787', '#fa5252', '#e03131'],
    'github': ['#161b22', '#0e4429', '#006d32', '#26a641', '#39d353'],
}
DARK_PALETTES = {
    'green':  ['#161b22', '#0e4429', '#006d32', '#26a641', '#39d353'],
    'purple': ['#161b22', '#3b2e63', '#5f3dc4', '#845ef7', '#b197fc'],
    'blue':   ['#161b22', '#153e75', '#1c63d5', '#3291ff', '#6cb2ff'],
    'teal':   ['#161b22', '#0f3d33', '#0f7a5f', '#12b886', '#63e6be'],
}

CELL, GAP, R = 6, 2, 1.5         # 格子尺寸/间距/圆角（紧凑版，像 pin 卡片）
MONTHS = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec']
WEEKDAYS = ['', 'Mon', '', 'Wed', '', 'Fri', '']   # 周标签（周一/周三/周五）

def level_of(count, max_count):
    """5 阶分级：0 / 1 / 2 / 3 / 4+"""
    if count <= 0: return 0
    if count == 1: return 1
    if count == 2: return 2
    if count == 3: return 3
    return 4

def build(data, year, palette, title=None, show_legend=True):
    pal = palette
    bg = pal[0]
    # 布局
    first_day = datetime.date(year, 1, 1)
    start_weekday = first_day.weekday()  # 0=Mon
    # 第一格从 1 月 1 日所在周的周一开始
    grid_start = first_day - datetime.timedelta(days=start_weekday)
    # 最后一格 = 12 月 31 日所在周的周日
    last_day = datetime.date(year, 12, 31)
    end_weekday = last_day.weekday()
    grid_end = last_day + datetime.timedelta(days=6 - end_weekday)
    weeks = (grid_end - grid_start).days // 7 + 1
    cols = weeks

    W = 8 + cols * (CELL + GAP) + 8
    H = 22 + 7 * (CELL + GAP) + (14 if show_legend else 6)
    s = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">']
    s.append(f'<rect width="{W}" height="{H}" fill="{bg}"/>')

    # 标题
    if title:
        s.append(f'<text x="8" y="14" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,Helvetica,Arial,sans-serif" '
                 f'font-size="10" font-weight="600" fill="{pal[4]}">{title}</text>')

    # 月份标签
    month_pos = {}
    m = grid_start
    while m <= grid_end:
        if m.day <= 7 and m.month not in month_pos:
            col = (m - grid_start).days // 7
            month_pos[m.month] = col
        m += datetime.timedelta(days=7)
    for mon, col in month_pos.items():
        x = 8 + col * (CELL + GAP)
        s.append(f'<text x="{x}" y="23" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,Helvetica,Arial,sans-serif" '
                 f'font-size="7" fill="{pal[4]}" opacity="0.7">{MONTHS[mon-1]}</text>')

    # 周标签
    for i, label in enumerate(WEEKDAYS):
        if not label: continue
        y = 28 + i * (CELL + GAP) + CELL - 1
        s.append(f'<text x="3" y="{y}" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,Helvetica,Arial,sans-serif" '
                 f'font-size="6" fill="{pal[4]}" opacity="0.6" text-anchor="end">{label}</text>')

    # 格子
    day = grid_start
    for col in range(cols):
        for row in range(7):
            if day.year == year:
                count = data.get(day.isoformat(), 0)
                lv = level_of(count, 0)
                x = 8 + col * (CELL + GAP)
                y = 28 + row * (CELL + GAP)
                if lv > 0:
                    s.append(f'<rect x="{x}" y="{y}" width="{CELL}" height="{CELL}" rx="{R}" fill="{pal[lv]}">'
                             f'<title>{day.isoformat()} {count}次</title></rect>')
                else:
                    s.append(f'<rect x="{x}" y="{y}" width="{CELL}" height="{CELL}" rx="{R}" fill="{pal[0]}"/>')
            day += datetime.timedelta(days=1)

    # 图例
    if show_legend:
        lx = 8
        ly = 28 + 7 * (CELL + GAP) + 8
        s.append(f'<text x="{lx}" y="{ly+5}" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,Helvetica,Arial,sans-serif" '
                 f'font-size="6" fill="{pal[4]}" opacity="0.6">Less</text>')
        for i in range(5):
            s.append(f'<rect x="{lx+22+i*(CELL+2)}" y="{ly}" width="{CELL}" height="{CELL}" rx="{R}" fill="{pal[i]}"/>')
        s.append(f'<text x="{lx+22+5*(CELL+2)}" y="{ly+5}" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,Helvetica,Arial,sans-serif" '
                 f'font-size="6" fill="{pal[4]}" opacity="0.6">More</text>')

    s.append('</svg>')
    return '\n'.join(s)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('data_file')
    ap.add_argument('out_file')
    ap.add_argument('--year', type=int, required=True)
    ap.add_argument('--title', default=None)
    ap.add_argument('--color', default='green', choices=list(PALETTES))
    ap.add_argument('--dark', action='store_true')
    args = ap.parse_args()

    data = json.load(open(args.data_file))
    data = {k: int(v) for k, v in data.items()}
    pal = DARK_PALETTES.get(args.color) if args.dark else PALETTES.get(args.color)
    svg = build(data, args.year, pal, title=args.title or str(args.year))
    open(args.out_file, 'w').write(svg)
    print(f'✅ {args.out_file} ({len(svg)} bytes)')

if __name__ == '__main__':
    main()
