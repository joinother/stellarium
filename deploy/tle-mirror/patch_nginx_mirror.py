#!/usr/bin/env python3
"""把 /v1/ 镜像路由挂到 skyinstrument.cn 的 server 块里（幂等，带备份）。

用法：python3 patch_nginx_mirror.py
"""
import re
import shutil
import sys
import time

CONF = '/etc/skyinstrument-website/nginx.conf'
MARK = 'location ^~ /v1/'
SNIPPET = '''        # 星象仪在线数据镜像（/srv/tle-mirror 由 tle-mirror.timer 每 3 小时刷新）
        location ^~ /v1/ {
            alias /srv/tle-mirror/v1/;
            default_type application/octet-stream;
            add_header Cache-Control "public, max-age=1800" always;
            add_header Access-Control-Allow-Origin "*" always;
        }

'''

text = open(CONF, encoding='utf-8').read()
if MARK in text:
    print('already patched')
    sys.exit(0)

apex = text.find('server_name skyinstrument.cn;')
if apex < 0:
    print('FAIL: apex server block not found')
    sys.exit(2)

anchor = text.find('location ~ /\\.', apex)
if anchor < 0:
    print('FAIL: anchor (location ~ /\\.) not found in apex block')
    sys.exit(3)

backup = CONF + '.bak-' + time.strftime('%Y%m%d%H%M%S')
shutil.copy2(CONF, backup)

patched = text[:anchor] + SNIPPET + text[anchor:]
open(CONF, 'w', encoding='utf-8').write(patched)
print('backup:', backup)
print('patched: inserted /v1/ alias into apex block at line',
      patched[:anchor].count('\n') + 1)
