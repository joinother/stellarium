#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

const root = process.cwd();
const imageRoot = path.join(root, 'nebulae', 'default');
const textureFile = path.join(imageRoot, 'textures.json');
const catalogFile = path.join(imageRoot, 'catalog.txt');
const namesFile = path.join(imageRoot, 'names.dat');
const hapFile = path.join(root, 'build/libstellarium-harmonyos/entry/build/default/outputs/default/entry-default-signed.hap');
const outputFile = path.join(root, 'docs/harmonyos/DEEP-SKY-RESOURCE-INVENTORY.md');

function readText(file) {
  return fs.readFileSync(file, 'utf8');
}

function integer(value) {
  const number = Number.parseInt(value, 10);
  return Number.isFinite(number) ? number : 0;
}

function addIndex(index, key, value) {
  if (!key) return;
  if (!index.has(key)) index.set(key, []);
  index.get(key).push(value);
}

function catalogIndexes() {
  const index = new Map();
  const rows = readText(catalogFile).split(/\r?\n/).filter(line => line && !line.startsWith('#') && !line.startsWith('//'));
  for (const line of rows) {
    const fields = line.split('\t');
    if (fields.length < 45) continue;
    const object = {
      type: fields[5].trim() || 'DSO',
      id: fields[0].trim(),
      ra: fields[1].trim(),
      dec: fields[2].trim(),
      cross: []
    };
    const numeric = [
      ['NGC', 16], ['IC', 17], ['M', 18], ['C', 19], ['B', 20], ['Sh2', 21],
      ['VdB', 22], ['RCW', 23], ['LDN', 24], ['LBN', 25], ['Cr', 26], ['Mel', 27],
      ['PGC', 28], ['UGC', 29], ['Ced', 30], ['Arp', 31], ['VV', 32], ['PK', 33],
      ['PNG', 34], ['SNR G', 35], ['ACO', 36], ['HCG', 37], ['ESO', 38], ['VdBH', 39],
      ['DWB', 40], ['Tr', 41], ['St', 42], ['Ru', 43], ['VdB-Ha', 44]
    ];
    for (const [prefix, position] of numeric) {
      const value = fields[position].trim();
      if (value && value !== '0' && value !== '99') {
        const key = `${prefix}${value.replace(/\s+/g, '')}`.toUpperCase();
        object.cross.push(key);
        addIndex(index, key, object);
      }
    }
  }
  return index;
}

function nameIndex() {
  const index = new Map();
  for (const line of readText(namesFile).split(/\r?\n/)) {
    const match = line.match(/^([A-Za-z][A-Za-z0-9-]*)\s+(\S+)\s+_\("([^"]+)"/);
    if (!match) continue;
    const key = `${match[1]}${match[2]}`.replace(/\s+/g, '').toUpperCase();
    if (!index.has(key)) index.set(key, []);
    index.get(key).push(match[3]);
  }
  return index;
}

function candidates(file) {
  const stem = path.basename(file, '.png').toLowerCase();
  const result = [];
  const add = (prefix, value) => result.push(`${prefix}${value}`.toUpperCase());
  let match;
  if ((match = stem.match(/^m(\d+)/))) add('M', match[1]);
  if ((match = stem.match(/^n(\d+)/))) add('NGC', match[1]);
  if ((match = stem.match(/^ic(\d+)/))) add('IC', match[1]);
  if ((match = stem.match(/^sh2[-_ ]?(\d+)/))) add('SH2', match[1]);
  if ((match = stem.match(/^barnard[_ -]?(\d+)/))) add('B', match[1]);
  if ((match = stem.match(/^vdb[_ -]?(\d+)/))) add('VDB', match[1]);
  if ((match = stem.match(/^rcw[_ -]?(\d+)/))) add('RCW', match[1]);
  if ((match = stem.match(/^ldn[_ -]?(\d+)/))) add('LDN', match[1]);
  if ((match = stem.match(/^lbn[_ -]?(\d+)/))) add('LBN', match[1]);
  if ((match = stem.match(/^abell[_ -]?(\d+)/))) add('ACO', match[1]);
  if ((match = stem.match(/^u(\d+)/))) add('UGC', match[1]);
  if ((match = stem.match(/^arp[_ -]?(\d+)/))) add('ARP', match[1]);
  if ((match = stem.match(/^pgc[_ -]?(\d+)/))) add('PGC', match[1]);
  if ((match = stem.match(/^ced[_ -]?(\d+)/))) add('CED', match[1]);
  return result;
}

function typeLabel(type) {
  const value = type.toUpperCase();
  if (value.includes('QSO')) return '类星体';
  if (value.includes('SNR')) return '超新星遗迹';
  if (value === '*' || value.includes('STAR')) return '恒星/恒星区域';
  if (value.includes('GC') || value.includes('OC') || value.includes('CL')) return '星团';
  if (value.includes('GX') || value === 'G' || value.includes('AGX') || value.includes('RG') || value.includes('IG')) return '星系';
  if (value.includes('PN')) return '行星状星云';
  if (value.includes('HII') || value.includes('RN') || value.includes('DN') || value.includes('BN') || value.includes('EN') || value.includes('NEBULA')) return '发射/反射/暗星云';
  return '深空天体';
}

function dimensions() {
  const result = new Map();
  const files = fs.readdirSync(imageRoot).filter(file => file.endsWith('.png')).map(file => path.join(imageRoot, file));
  const output = execFileSync('sips', ['-g', 'pixelWidth', '-g', 'pixelHeight', ...files], { encoding: 'utf8' });
  const lines = output.split(/\r?\n/);
  for (let index = 0; index < lines.length; index += 1) {
    const fileMatch = lines[index].match(/\/([^/]+\.png)$/);
    const widthMatch = lines[index + 1]?.match(/pixelWidth:\s*(\d+)/);
    const heightMatch = lines[index + 2]?.match(/pixelHeight:\s*(\d+)/);
    if (fileMatch && widthMatch && heightMatch) {
      result.set(fileMatch[1], { width: integer(widthMatch[1]), height: integer(heightMatch[1]) });
    }
  }
  return result;
}

function quality(size) {
  if (size.width >= 1024 && size.height >= 1024) return '高清（1024 及以上）';
  if (size.width >= 512 && size.height >= 512) return '中高（512）';
  return '低分辨率（256/128）';
}

function main() {
  const textureText = readText(textureFile);
  const images = [...textureText.matchAll(/"imageUrl"\s*:\s*"([^"]+)"/g)].map(match => match[1]).sort();
  const catalog = catalogIndexes();
  const names = nameIndex();
  const sizes = dimensions();
  const hapListing = fs.existsSync(hapFile) ? execFileSync('unzip', ['-l', hapFile], { encoding: 'utf8' }) : '';
  const rows = images.map(file => {
    const keys = candidates(file);
    const objects = keys.flatMap(key => catalog.get(key) || []);
    const uniqueObjects = [...new Map(objects.map(object => [object.id, object])).values()];
    const object = uniqueObjects[0];
    // Image filenames often use a Messier alias while names.dat stores the
    // common name under the object's NGC/IC alias. Include every cross-name
    // attached to the matched catalogue row so M31/M42/M51 are not reported
    // as unnamed merely because their image filename uses "M".
    const objectNames = (object?.cross || keys).flatMap(key => names.get(key) || []);
    const size = sizes.get(file) || { width: 0, height: 0 };
    const inHap = hapListing.includes(`/nebulae/default/${file}`);
    return {
      file,
      size: `${size.width}×${size.height}`,
      quality: quality(size),
      designation: keys.join('、') || '专名/组合图',
      type: object ? typeLabel(object.type) : '专名/组合图',
      catalogType: object?.type || '未匹配',
      names: [...new Set(objectNames)].slice(0, 3).join('；') || '目录未提供通用名',
      inHap: inHap ? '是' : '否'
    };
  });
  const counts = rows.reduce((map, row) => map.set(row.quality, (map.get(row.quality) || 0) + 1), new Map());
  const high = rows.filter(row => row.quality === '高清（1024 及以上）');
  const lines = [
    '# 深空图像资源核对清单',
    '',
    `生成时间：${new Date().toISOString()}`, 
    `源码目录：\`nebulae/default\``,
    `图像总数：${rows.length} 张 PNG；纹理索引引用：${images.length} 张；当前 HAP 收录：${rows.filter(row => row.inHap).length} 张。`,
    '',
    '## 分辨率统计',
    '',
    '|级别|数量|定义|',
    '|---|---:|---|',
    `|高清|${counts.get('高清（1024 及以上）') || 0}|宽高均不低于 1024|`,
    `|中高|${counts.get('中高（512）') || 0}|宽高均为 512|`,
    `|低分辨率|${counts.get('低分辨率（256/128）') || 0}|主要为 256 或 128|`,
    '',
    '## 高清资源（1024 及以上）',
    '',
    '|文件|分辨率|对应目录编号|类型|目录类型|通用名|HAP|',
    '|---|---:|---|---|---|---|---|',
    ...high.map(row => `|\`${row.file}\`|${row.size}|${row.designation}|${row.type}|${row.catalogType}|${row.names}|${row.inHap}|`),
    '',
    '## 全部深空图像',
    '',
    '|文件|分辨率|级别|对应目录编号|类型|目录类型|通用名|HAP|',
    '|---|---:|---|---|---|---|---|---|',
    ...rows.map(row => `|\`${row.file}\`|${row.size}|${row.quality}|${row.designation}|${row.type}|${row.catalogType}|${row.names}|${row.inHap}|`),
    '',
    '说明：文件名来自开源 Stellarium 深空纹理集合；“对应目录编号”按文件名与 `catalog.txt` 的交叉编号推断，无法唯一匹配的组合图保留为“专名/组合图”。类型是目录中的原始类型映射，不代表图片一定是该天体的高清实拍原图。'
  ];
  fs.writeFileSync(outputFile, `${lines.join('\n')}\n`);
  console.log(`已生成 ${outputFile}`);
  console.log(`图像 ${rows.length}，高清 ${high.length}，HAP ${rows.filter(row => row.inHap).length}`);
}

main();
