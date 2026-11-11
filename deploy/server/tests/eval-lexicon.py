# -*- coding: utf-8 -*-
"""词库召回/误报评测：用固定样本集衡量，改动词库后跑一遍即可对比。"""
from importlib.machinery import SourceFileLoader

m = SourceFileLoader('ca', '/usr/local/sbin/skyinstrument-content-audit').load_module()
lex = m.load_lexicon()
words = set(x for v in lex.values() for x in v)

BAD = [
    ('博彩平台首存送100', '赌博'), ('澳门线上赌场', '赌场'), ('博 彩 平台', '空格变体'),
    ('博*彩 首存', '符号变体'), ('博採平台', '繁体'), ('代办证件 一条龙', '办证'),
    ('无抵押贷款 当天放款', '贷款'), ('冰毒 麻黄素 出售', '毒品'), ('气枪 铅弹 免邮', '枪支'),
    ('加微信领福利', '导流'), ('全网最准的占星软件', '极限词'), ('色情直播 一对一', '色情'),
    ('裸聊 一对一', '裸聊'), ('网上兼职刷单', '刷单'), ('办假证', '假证'),
    ('澳门赌场官网', '赌场'), ('棋牌平台 首存送', '棋牌'), ('刷单返利 日结', '刷单'),
    ('杀猪盘 带单老师', '杀猪盘'), ('代开发票 点数低', '发票'),
]
GOOD = [
    ('本工具采用最新的星表数据，支持离线使用。', '说明'),
    ('我们不会上传您的观测记录。', '隐私'),
    ('卫星过境提醒可设置提前 1 分钟。', '功能'),
    ('开源项目遵循 GPL v2 许可。', '许可'),
    ('观测前请校准时间与坐标。', '指导'),
    ('请在设置中开启通知权限。', '功能'),
    ('星象仪支持导入 TLE 文件。', '功能'),
    ('这个颜色情况需要确认。', '易误伤'),
]

def hit_raw(t):
    return [w for w in words if w in t]

def hit_norm(t):
    n = m.normalize(t)
    out = []
    for w in words:
        nw = m.normalized_word(w)
        if len(nw) >= 2 and nw in n:
            out.append(w)
    return out

raw_ok = norm_ok = 0
print('=== 违规样本 ===')
print('%-24s %-10s %-10s' % ('样本', '原始匹配', '含变体'))
for t, label in BAD:
    r = hit_raw(t)
    n = r or hit_norm(t)
    raw_ok += bool(r)
    norm_ok += bool(n)
    print('%-24s %-10s %-10s %s' % (label, '✅' if r else '—', '✅' if n else '❌',
                                    (r or n)[:2]))
print('\n召回：原始 %d/%d，含变体 %d/%d' % (raw_ok, len(BAD), norm_ok, len(BAD)))

raw_fp = norm_fp = 0
print('\n=== 正常样本 ===')
for t, label in GOOD:
    r = hit_raw(t)
    n = hit_norm(t)
    raw_fp += bool(r)
    norm_fp += bool(n and not r)
    note = '误报:%s' % r[:2] if r else ('变体误报:%s' % n[:2] if n else '')
    print('%-24s %s' % (label, note or '✅'))
print('\n误报：原始 %d/%d，含变体新增 %d' % (raw_fp, len(GOOD), norm_fp))
