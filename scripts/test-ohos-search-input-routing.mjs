import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'

// Text input focus routing now spans the search bar / location search
// components and the SkyInputController keyboard guard.
const root = path.resolve(new URL('..', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'))
const read = file => fs.readFileSync(path.join(root, file), 'utf8')
const input = read('harmonyos/ets-source/capability/SkyInputController.ets')
const page = read('harmonyos/ets-source/pages/MainWindowNativeNode.ets')
const searchBar = read('harmonyos/ets-source/panels/search/SearchBar.ets')
const locationSearch = read('harmonyos/ets-source/panels/location/LocationSearchPanel.ets')
const locationStore = read('harmonyos/ets-source/state/LocationStore.ets')

// While a text field is focused the sky keyboard handler must not consume keys.
assert.match(page, /@State private keyboardTextInputFocused: boolean = false/)
assert.match(input, /if \(this\.hooks\.keyboardTextInputFocused\(\)\) \{ return false \}/)
assert.match(page, /keyboardTextInputFocused: \(\): boolean => this\.keyboardTextInputFocused/)
assert.match(searchBar, /\.onFocus\(\(\) => \{ this\.onInputFocus\(\) \}\)/)
assert.match(searchBar, /\.onBlur\(\(\) => \{ this\.onInputBlur\(\) \}\)/)
assert.match(locationSearch, /\.onFocus\(\(\) => \{ this\.onInputFocus\(\) \}\)/)
assert.match(locationSearch, /\.onBlur\(\(\) => \{ this\.onInputBlur\(\) \}\)/)
assert.match(page, /this\.keyboardTextInputFocused = true/)
assert.match(page, /this\.keyboardTextInputFocused = false/)

// The location search scans a pre-normalized index in bounded time slices and
// throttles publishes.
assert.match(locationStore, /locationSearchScanTimer/)
assert.match(locationStore, /Date\.now\(\) - startedAt < LOCATION_SEARCH_CHUNK_MS/)
assert.match(locationStore, /locationSearchLastPublishMs/)

console.log('HarmonyOS search input routing and location search contract passed.')
