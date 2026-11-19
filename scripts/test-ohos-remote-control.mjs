import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const read = p => readFileSync(new URL(p, import.meta.url), 'utf8');

const requestHandler = read('../plugins/RemoteControl/src/RequestHandler.cpp');
const requestHandlerHeader = read('../plugins/RemoteControl/src/RequestHandler.hpp');
const apiController = read('../plugins/RemoteControl/src/APIController.cpp');
const remoteControl = read('../plugins/RemoteControl/src/RemoteControl.cpp');
const httpRequest = read('../plugins/RemoteControl/src/qtwebapp/httpserver/httprequest.cpp');
const remoteQrc = read('../plugins/RemoteControl/RemoteControl.qrc');
const consoleHtml = read('../plugins/RemoteControl/resources/ohos_console.html');
const mainView = read('../src/StelMainView.cpp');
const settingsPanel = read('../harmonyos/ets-source/panels/panels/SettingsPanel.ets');
const hostPage = read('../harmonyos/ets-source/pages/MainWindowNativeNode.ets');

test('RequestHandler enforces constant-time multi-format auth and JSON 401 on /api/*', () => {
  assert.match(requestHandlerHeader, /QMutex authMutex;/);
  assert.match(requestHandler, /constantTimeEquals\(/);
  assert.match(requestHandler, /qstrnicmp\(authHeader\.constData\(\), "Basic ", 6\)/);
  assert.match(requestHandler, /qstrnicmp\(authHeader\.constData\(\), "Bearer ", 7\)/);
  assert.match(requestHandler, /request\.getHeader\("X-API-Key"\)/);
  assert.match(requestHandler, /request\.getHeader\("X-Stellarium-Token"\)/);
  assert.match(requestHandler, /response\.setStatus\(401,"Not Authorized"\)/);
  assert.match(requestHandler, /\\"error\\":\\"unauthorized\\"/);
  assert.match(requestHandler, /Access-Control-Allow-Headers.*Authorization.*X-API-Key/);
});

test('RemoteControl refuses non-loopback start without password and supports live restart', () => {
  assert.match(remoteControl, /if \(!isLoopback && \(!usePassword \|\| password\.trimmed\(\)\.isEmpty\(\)\)\)/);
  assert.match(remoteControl, /bool RemoteControl::restartServer\(\)/);
  assert.match(remoteControl, /lastError =/);
});

test('Embedded Web Console fallback and /api/info discovery exist and contain no external CDNs', () => {
  assert.match(remoteQrc, /resources\/ohos_console\.html/);
  assert.match(requestHandler, /:\/RemoteControl\/resources\/ohos_console\.html/);
  assert.match(apiController, /serviceString == "info"/);
  assert.match(apiController, /GET \/api\/main\/status/);
  assert.match(consoleHtml, /\/api\/main\/status/);
  assert.match(consoleHtml, /\/api\/main\/focus/);
  assert.match(consoleHtml, /\/api\/stelaction\/do/);
  assert.match(consoleHtml, /\/api\/info/);
  assert.doesNotMatch(consoleHtml, /https?:\/\//i, 'embedded web console must remain 100% offline');
});

test('StelMainView bridge auto-generates strong token, handles CORS, live restart, and error reporting', () => {
  const start = mainView.indexOf('if (commandName == "setRemoteControl" || commandName == "getRemoteControlState")');
  const end = mainView.indexOf('if (commandName == "loadPlugin")', start);
  assert.ok(start > 0 && end > start);
  const block = mainView.slice(start, end);
  assert.match(block, /QRandomGenerator::system\(\)/);
  assert.match(block, /loadPlugin\(QStringLiteral\("RemoteControl"\)\)/);
  assert.match(block, /remote->restartServer\(\)/);
  assert.match(block, /result\["password"\] = remote->getPassword\(\)/);
  assert.match(block, /result\["enableCors"\] = remote->getFlagEnableCors\(\)/);
  assert.match(block, /result\["apiInfoUrl"\]/);
  assert.match(block, /if \(enable && !okState\)/);
});

test('HarmonyOS SettingsPanel and host page wire password, regenerate, copy, CORS, and state sync', () => {
  assert.match(settingsPanel, /remoteControlPassword/);
  assert.match(settingsPanel, /remoteControlCors/);
  assert.match(settingsPanel, /换新密钥/);
  assert.match(settingsPanel, /复制地址/);
  assert.match(settingsPanel, /复制 curl/);
  assert.match(settingsPanel, /允许跨域调用/);
  assert.match(settingsPanel, /if \(value !== this\.remoteControlEnabled\)/);
  assert.match(settingsPanel, /if \(value !== this\.remoteControlCors\)/);
  assert.match(hostPage, /syncRemoteControlState\(\)/);
  assert.match(hostPage, /if \(panel === 'settings'\) \{\s*this\.syncRemoteControlState\(\)/);
  assert.match(hostPage, /callLongRunningInteractive\(\s*'getRemoteControlState'/);
  assert.match(hostPage, /callLongRunningInteractive\(\s*'setRemoteControl'/);
  assert.match(hostPage, /copyTextToClipboard\(/);
});

test('HttpRequest normalizes HTTP header names case-insensitively per RFC 9110', () => {
  assert.match(httpRequest, /currentHeader=newData\.left\(colon\)\.trimmed\(\)\.toLower\(\);/);
  assert.match(httpRequest, /return headers\.value\(name\.toLower\(\)\);/);
  assert.match(httpRequest, /return headers\.values\(name\.toLower\(\)\);/);
  assert.match(httpRequest, /getHeader\("content-length"\)/);
  assert.match(httpRequest, /getHeader\("content-type"\)/);
  assert.doesNotMatch(httpRequest, /headers\.value\("Content-Type"\)/);
});
