import argparse
import json
from pathlib import Path
import re
import subprocess
import time


ROOT = Path(__file__).resolve().parents[1]
HDC = '/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--device', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    report = {'checks': []}

    def command(name, payload='', allow_error=False):
        result = subprocess.run(['node', str(ROOT / 'scripts/stellarium-cli.mjs'), '--device', args.device,
                                 '--command', name, '--payload', payload, '--json'],
                                capture_output=True, text=True, timeout=60)
        value = json.loads(result.stdout)
        if result.returncode and not allow_error:
            raise RuntimeError(result.stdout + result.stderr)
        return value

    def state(**expected):
        for attempt in range(30):
            value = command('getSearchBrowserState', allow_error=True)
            if value.get('ok') and all(value.get(key) == item for key, item in expected.items()):
                return value
            time.sleep(0.25)
        raise AssertionError('state not reached: ' + str(expected) + ': ' + str(value))

    def hdc(*values):
        return subprocess.check_output([HDC, '-t', args.device, *map(str, values)], text=True, timeout=50)

    def layout():
        remote = '/data/local/tmp/search-browser-layout.json'
        local = args.output.parent / 'search-browser-layout.json'
        hdc('shell', 'uitest', 'dumpLayout', '-p', remote)
        hdc('file', 'recv', remote, local)
        nodes = [json.loads(local.read_text())]
        bounds, texts = {}, []
        while nodes:
            node = nodes.pop()
            attributes = node.get('attributes', {})
            if attributes.get('id'):
                bounds[attributes['id']] = [int(value) for value in re.findall(r'-?\d+', attributes['bounds'])]
            if attributes.get('text'):
                texts.append(attributes['text'])
            nodes.extend(node.get('children', []))
        return bounds, texts

    def screenshot(name):
        remote = '/data/local/tmp/search-browser.jpeg'
        hdc('shell', 'snapshot_display', '-f', remote)
        hdc('file', 'recv', remote, args.output.parent / ('search-browser-' + name + '.jpeg'))

    def layout_with(identifier):
        for attempt in range(8):
            bounds, texts = layout()
            if identifier in bounds:
                return bounds, texts
            time.sleep(0.5)
        raise AssertionError('rendered control not found: ' + identifier)

    def check(label, condition):
        report['checks'].append({'label': label, 'passed': bool(condition)})
        assert condition, label

    initial = None
    try:
        command('setSearchBrowserPage', 'browse')
        initial = state(page='browse')
        time.sleep(1)
        bounds, texts = layout_with('search-category-picker')
        check('one category entry and one filter entry', 'search-category-picker' in bounds and 'search-filter-picker' in bounds)
        check('no extension block or duplicate filter', '扩展目录' not in texts and '+ 筛选' not in texts and texts.count('筛选') == 1)
        screenshot('home')
        command('setSearchBrowserPage', 'categories')
        categories = state(page='categories')['categories']
        check('core categories retained', all(code in [item['code'] for item in categories]
                                            for code in ['planet', 'moon', 'star', 'nebula', 'satellite']))
        modules = [item.get('moduleId') or item['code'] for item in categories]
        check('no duplicate module IDs', len(modules) == len(set(modules)))
        extensions = [item for item in categories if item['code'].startswith('module:')]
        check('extensions remain in unified list', len(extensions) > 0)
        report['categories'] = categories
        bounds, texts = layout_with('search-category-planet')
        category_header_top = bounds['search-browser-back'][1] - bounds['search-browser-scroll'][1]
        rows = sorted([bounds['search-category-' + item['code']] for item in categories
                       if 'search-category-' + item['code'] in bounds], key=lambda rect: rect[1])
        check('visible rows do not overlap', len(rows) >= 2 and all(rows[index][3] < rows[index + 1][1]
                                                                  for index in range(len(rows) - 1)))
        screenshot('categories')
        left, top, right, bottom = bounds['search-browser-back']
        hdc('shell', 'uitest', 'uiInput', 'click', (left + right) // 2, (top + bottom) // 2)
        state(page='browse')
        check('real back returns to browser', True)
        command('setSearchBrowserPage', 'categories')
        state(page='categories')
        bounds, texts = layout_with('search-category-planet')
        left, top, right, bottom = bounds['search-category-planet']
        hdc('shell', 'uitest', 'uiInput', 'click', (left + right) // 2, (top + bottom) // 2)
        state(page='browse', category='planet')
        check('real row click returns to results', True)
        command('setSearchBrowserPage', 'categories')
        state(page='categories')
        for attempt in range(12):
            bounds, texts = layout()
            if any('search-category-' + item['code'] in bounds for item in extensions):
                break
            left, top, right, bottom = bounds['search-browser-scroll']
            hdc('shell', 'uitest', 'uiInput', 'swipe', (left + right) // 2, bottom - 45,
                (left + right) // 2, top + 80, 500)
            time.sleep(0.4)
        check('extension rows reachable by vertical scrolling', any('search-category-' + item['code'] in bounds for item in extensions))
        check('scrolling does not accidentally select a row', state()['page'] == 'categories')
        screenshot('extensions')
        command('setSearchBrowserFilter', 'visibility|above')
        state(page='browse', visibility='above')
        selected = extensions[0]
        command('selectSearchCategory', selected['code'])
        state(page='browse', category=selected['code'], moduleId=selected['moduleId'], visibility='above')
        check('extension selection preserves filters', True)
        command('selectSearchCategory', 'satellite')
        state(page='browse', category='satellite', moduleId='Satellites')
        check('satellite remains selectable', True)
        command('setSearchBrowserPage', 'root')
        state(page='root')
        time.sleep(0.6)
        bounds, texts = layout_with('search-browser-back')
        filter_header_top = bounds['search-browser-back'][1] - bounds['search-browser-scroll'][1]
        check('short filter page remains top aligned', abs(filter_header_top - category_header_top) <= 6)
        check('filter page does not duplicate category list', not any(key.startswith('search-category-') for key in bounds))
        screenshot('filters')
        check('invalid category rejected', command('selectSearchCategory', 'nonexistent', True).get('ok') is False)
        check('invalid filter rejected', command('setSearchBrowserFilter', 'visibility|invalid', True).get('ok') is False)
    finally:
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
        if initial is not None:
            command('setSearchBrowserFilter', 'visibility|' + initial['visibility'])
            command('setSearchBrowserFilter', 'instrument|' + initial['instrument'])
            command('selectSearchCategory', initial['category'])
            state(page='browse', category=initial['category'])
    print(json.dumps({'passed': len(report['checks']), 'output': str(args.output)}))


if __name__ == '__main__':
    main()
