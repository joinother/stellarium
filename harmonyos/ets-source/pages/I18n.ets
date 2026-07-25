// I18n.ets
// 统一国际化模块 —— 所有 UI 字符串和 C++ 返回数据的翻译都在这一个文件里管理。
//
// 设计原则：
//   1. 选定语言后，所有文本都用该语言显示，不混杂其他语言
//   2. 缺失翻译时回退到英语（不会显示错误语言）
//   3. 语言切换是响应式的：通过 AppStorage('i18nLang') 触发 UI 重渲染
//   4. C++ 核心返回的英文数据（天体类型、卫星分组等）在此层翻译
//
// 支持的语言：en, zh_CN, zh_TW, ja, ko, fr, de, es, ru, pt, it, nl, pl, tr, ar, hi, th, vi, id, uk, sv
// 完整翻译：en, zh_CN, ja, ko, fr, de, es, ru（8种）
// 其他语言回退到英语。

// 语言代码类型
export type LangCode = 'en' | 'zh_CN' | 'zh_TW' | 'ja' | 'ko' | 'fr' | 'de' | 'es' | 'ru' | 'pt' | 'it' | 'nl' | 'pl' | 'tr' | 'ar' | 'hi' | 'th' | 'vi' | 'id' | 'uk' | 'sv'

// 支持的语言列表（用于设置面板显示）
// ── 恒星翻译表（供外部直接引用的快捷列表）──
export const BRIGHT_STARS: string[] = ['Sirius', 'Canopus', 'Arcturus', 'Vega', 'Rigel', 'Betelgeuse', 'Polaris']

export const SUPPORTED_LANGUAGES: string[] = [
  'en', 'zh_CN', 'zh_TW', 'ja', 'ko', 'fr', 'de', 'es', 'ru',
  'pt', 'it', 'nl', 'pl', 'tr', 'ar', 'hi', 'th', 'vi', 'id', 'uk', 'sv'
]

// 语言显示名称（始终用本地文字显示）
export const LANGUAGE_DISPLAY: Record<string, string> = {
  'en': 'English', 'zh_CN': '中文', 'zh_TW': '繁體中文',
  'ja': '日本語', 'ko': '한국어', 'fr': 'Français', 'de': 'Deutsch',
  'es': 'Español', 'ru': 'Русский', 'pt': 'Português', 'it': 'Italiano',
  'nl': 'Nederlands', 'pl': 'Polski', 'tr': 'Türkçe', 'ar': 'العربية',
  'hi': 'हिन्दी', 'th': 'ไทย', 'vi': 'Tiếng Việt', 'id': 'Indonesia',
  'uk': 'Українська', 'sv': 'Svenska'
}


// 天体类型翻译表（C++ getTypeStr 返回的英文 → 各语言）
const OBJECT_TYPES: Record<string, Record<string, string>> = {
  'Artificial satellite': { 'en': 'Artificial satellite', 'zh_CN': '人造卫星', 'ja': '人工衛星', 'ko': '인공위성', 'fr': 'Satellite artificiel', 'de': 'Künstlicher Satellit', 'es': 'Satélite artificial', 'ru': 'Искусственный спутник' },
  'Asterism': { 'en': 'Asterism', 'zh_CN': '星组', 'ja': '星群', 'ko': '성군', 'fr': 'Astérisme', 'de': 'Asterismus', 'es': 'Asterismo', 'ru': 'Астеризм' },
  'Asteroid': { 'en': 'Asteroid', 'zh_CN': '小行星', 'ja': '小惑星', 'ko': '소행성', 'fr': 'Astéroïde', 'de': 'Asteroid', 'es': 'Asteroide', 'ru': 'Астероид' },
  'Binary star': { 'en': 'Binary star', 'zh_CN': '双星', 'ja': '連星', 'ko': '쌍성', 'fr': 'Étoile binaire', 'de': ' Doppelsternsystem', 'es': 'Estrella binaria', 'ru': 'Двойная система' },
  'Bright nebula': { 'en': 'Bright nebula', 'zh_CN': '亮星云', 'ja': '輝線星雲', 'ko': '밝은성운', 'fr': 'Nébuleuse brillante', 'de': 'Heller Nebel', 'es': 'Nebulosa brillante', 'ru': 'Яркая туманность' },
  'Cluster': { 'en': 'Cluster', 'zh_CN': '星团', 'ja': '星団', 'ko': '성단', 'fr': 'Amas', 'de': 'Sternhaufen', 'es': 'Cúmulo', 'ru': 'Скопление' },
  'Comet': { 'en': 'Comet', 'zh_CN': '彗星', 'ja': '彗星', 'ko': '혜성', 'fr': 'Comète', 'de': 'Komet', 'es': 'Cometa', 'ru': 'Комета' },
  'Constellation': { 'en': 'Constellation', 'zh_CN': '星座', 'ja': '星座', 'ko': '별자리', 'fr': 'Constellation', 'de': 'Sternbild', 'es': 'Constelación', 'ru': 'Созвездие' },
  'Core not ready': { 'en': 'Core not ready', 'zh_CN': '核心未就绪', 'ja': 'コア未準備', 'ko': '코어 미준비', 'fr': 'Noyau non prêt', 'de': 'Kern nicht bereit', 'es': 'Núcleo no listo', 'ru': 'Ядро не готово' },
  'Dark Nebula': { 'en': 'Dark nebula', 'zh_CN': '暗星云', 'ja': '暗黒星雲', 'ko': '암흑성운', 'fr': 'Nébuleuse sombre', 'de': 'Dunkler Nebel', 'es': 'Nebulosa oscura', 'ru': 'Тёмная туманность' },
  'Deep-sky object': { 'en': 'Deep-sky object', 'zh_CN': '深空天体', 'ja': '深空天体', 'ko': '심우주천체', 'fr': 'Objet du ciel profond', 'de': 'Deep-Sky-Objekt', 'es': 'Objeto de cielo profundo', 'ru': 'Объект дальнего космоса' },
  'Double star': { 'en': 'Double star', 'zh_CN': '双星', 'ja': '二重星', 'ko': '쌍성', 'fr': 'Étoile double', 'de': 'Doppelstern', 'es': 'Estrella doble', 'ru': 'Двойная звезда' },
  'Galaxy': { 'en': 'Galaxy', 'zh_CN': '星系', 'ja': '銀河', 'ko': '은하', 'fr': 'Galaxie', 'de': 'Galaxie', 'es': 'Galaxia', 'ru': 'Галактика' },
  'Globular cluster': { 'en': 'Globular cluster', 'zh_CN': '球状星团', 'ja': '球状星団', 'ko': '구상성단', 'fr': 'Amas globulaire', 'de': 'Kugelsternhaufen', 'es': 'Cúmulo globular', 'ru': 'Шаровое скопление' },
  'Interplanetary probe': { 'en': 'Interplanetary probe', 'zh_CN': '行星际探测器', 'ja': '惑星間探査機', 'ko': '행성간 탐사선', 'fr': 'Sonde interplanétaire', 'de': 'Interplanetare Sonde', 'es': 'Sonda interplanetaria', 'ru': 'Межпланетная станция' },
  'Interstellar object': { 'en': 'Interstellar object', 'zh_CN': '星际天体', 'ja': '星間天体', 'ko': '성간 천체', 'fr': 'Objet interstellaire', 'de': 'Interstellares Objekt', 'es': 'Objeto interestelar', 'ru': 'Межзвёздный объект' },
  'Meteor shower': { 'en': 'Meteor shower', 'zh_CN': '流星雨', 'ja': '流星群', 'ko': '유성우', 'fr': 'Pluie de météores', 'de': 'Meteorschauer', 'es': 'Lluvia de meteoros', 'ru': 'Метеорный поток' },
  'Minor planet': { 'en': 'Minor planet', 'zh_CN': '小行星', 'ja': '小惑星', 'ko': '소행성', 'fr': 'Petite planète', 'de': 'Kleiner Planet', 'es': 'Planeta menor', 'ru': 'Малая планета' },
  'Molecular cloud': { 'en': 'Molecular cloud', 'zh_CN': '分子云', 'ja': '分子雲', 'ko': '분자구름', 'fr': 'Nuage moléculaire', 'de': 'Molekülwolke', 'es': 'Nube molecular', 'ru': 'Молекулярное облако' },
  'Moon': { 'en': 'Moon', 'zh_CN': '月球', 'ja': '月', 'ko': '달', 'fr': 'Lune', 'de': 'Mond', 'es': 'Luna', 'ru': 'Луна' },
  'Nebula': { 'en': 'Nebula', 'zh_CN': '星云', 'ja': '星雲', 'ko': '성운', 'fr': 'Nébuleuse', 'de': 'Nebel', 'es': 'Nebulosa', 'ru': 'Туманность' },
  'No match': { 'en': 'No match', 'zh_CN': '无匹配结果', 'ja': '該当なし', 'ko': '일치 없음', 'fr': 'Aucune correspondance', 'de': 'Kein Treffer', 'es': 'Sin coincidencia', 'ru': 'Нет совпадения' },
  'No selection': { 'en': 'No selection', 'zh_CN': '未选择', 'ja': '未選択', 'ko': '미선택', 'fr': 'Aucune sélection', 'de': 'Nicht ausgewählt', 'es': 'Sin selección', 'ru': 'Не выбрано' },
  'Not found': { 'en': 'Not found', 'zh_CN': '未找到', 'ja': '見つかりません', 'ko': '찾을 수 없음', 'fr': 'Introuvable', 'de': 'Nicht gefunden', 'es': 'No encontrado', 'ru': 'Не найдено' },
  'Object': { 'en': 'Object', 'zh_CN': '天体', 'ja': '天体', 'ko': '천체', 'fr': 'Objet', 'de': 'Objekt', 'es': 'Objeto', 'ru': 'Объект' },
  'Observatory': { 'en': 'Observatory', 'zh_CN': '天文台', 'ja': '天文台', 'ko': '천문대', 'fr': 'Observatoire', 'de': 'Sternwarte', 'es': 'Observatorio', 'ru': 'Обсерватория' },
  'Open cluster': { 'en': 'Open cluster', 'zh_CN': '疏散星团', 'ja': '散開星団', 'ko': '산개성단', 'fr': 'Amas ouvert', 'de': 'Offener Sternhaufen', 'es': 'Cúmulo abierto', 'ru': 'Рассеянное скопление' },
  'Planet': { 'en': 'Planet', 'zh_CN': '行星', 'ja': '惑星', 'ko': '행성', 'fr': 'Planète', 'de': 'Planet', 'es': 'Planeta', 'ru': 'Планета' },
  'Planetary nebula': { 'en': 'Planetary nebula', 'zh_CN': '行星状星云', 'ja': '惑星状星雲', 'ko': '행성상성운', 'fr': 'Nébuleuse planétaire', 'de': 'Planetarischer Nebel', 'es': 'Nebulosa planetaria', 'ru': 'Планетарная туманность' },
  'Pulsar': { 'en': 'Pulsar', 'zh_CN': '脉冲星', 'ja': 'パルサー', 'ko': '펄서', 'fr': 'Pulsar', 'de': 'Pulsar', 'es': 'Púlsar', 'ru': 'Пульсар' },
  'Quasar': { 'en': 'Quasar', 'zh_CN': '类星体', 'ja': 'クエーサー', 'ko': '퀘이사', 'fr': 'Quasar', 'de': 'Quasar', 'es': 'Cuásar', 'ru': 'Квазар' },
  'Rocket body': { 'en': 'Rocket body', 'zh_CN': '火箭残骸', 'ja': 'ロケット残骸', 'ko': '로켓 잔해', 'fr': 'Corps de fusée', 'de': 'Raketenkörper', 'es': 'Cuerpo de cohete', 'ru': 'Ракетный корпус' },
  'Satellite': { 'en': 'Satellite', 'zh_CN': '人造卫星', 'ja': '人工衛星', 'ko': '인공위성', 'fr': 'Satellite', 'de': 'Satellit', 'es': 'Satélite', 'ru': 'Спутник' },
  'Star': { 'en': 'Star', 'zh_CN': '恒星', 'ja': '恒星', 'ko': '항성', 'fr': 'Étoile', 'de': 'Stern', 'es': 'Estrella', 'ru': 'Звезда' },
  'Star cluster': { 'en': 'Star cluster', 'zh_CN': '星团', 'ja': '星団', 'ko': '성단', 'fr': 'Amas stellaire', 'de': 'Sternhaufen', 'es': 'Cúmulo estelar', 'ru': 'Звёздное скопление' },
  'Sun': { 'en': 'Sun', 'zh_CN': '太阳', 'ja': '太陽', 'ko': '태양', 'fr': 'Soleil', 'de': 'Sonne', 'es': 'Sol', 'ru': 'Солнце' },
  'Supernova': { 'en': 'Supernova', 'zh_CN': '超新星', 'ja': '超新星', 'ko': '초신성', 'fr': 'Supernova', 'de': 'Supernova', 'es': 'Supernova', 'ru': 'Сверхновая' },
  'Supernova remnant': { 'en': 'Supernova remnant', 'zh_CN': '超新星遗迹', 'ja': '超新星残骸', 'ko': '초신성잔해', 'fr': 'Reste de supernova', 'de': 'Supernovaüberrest', 'es': 'Resto de supernova', 'ru': 'Остаток сверхновой' },
  'Variable Star': { 'en': 'Variable star', 'zh_CN': '变星', 'ja': '変光星', 'ko': '변광성', 'fr': 'Étoile variable', 'de': 'Veränderlicher Stern', 'es': 'Estrella variable', 'ru': 'Переменная звезда' },
  'Variable star': { 'en': 'Variable star', 'zh_CN': '变星', 'ja': '変光星', 'ko': '변광성', 'fr': 'Étoile variable', 'de': 'Veränderlicher Stern', 'es': 'Estrella variable', 'ru': 'Переменная звезда' },
}

// 行星名称翻译表
const PLANET_NAMES: Record<string, Record<string, string>> = {
  'Earth': { 'en': 'Earth', 'zh_CN': '地球', 'ja': '地球', 'ko': '지구', 'fr': 'Terre', 'de': 'Erde', 'es': 'Tierra', 'ru': 'Земля' },
  'Jupiter': { 'en': 'Jupiter', 'zh_CN': '木星', 'ja': '木星', 'ko': '목성', 'fr': 'Jupiter', 'de': 'Jupiter', 'es': 'Júpiter', 'ru': 'Юпитер' },
  'Mars': { 'en': 'Mars', 'zh_CN': '火星', 'ja': '火星', 'ko': '화성', 'fr': 'Mars', 'de': 'Mars', 'es': 'Marte', 'ru': 'Марс' },
  'Mercury': { 'en': 'Mercury', 'zh_CN': '水星', 'ja': '水星', 'ko': '수성', 'fr': 'Mercure', 'de': 'Merkur', 'es': 'Mercurio', 'ru': 'Меркурий' },
  'Moon': { 'en': 'Moon', 'zh_CN': '月球', 'ja': '月', 'ko': '달', 'fr': 'Lune', 'de': 'Mond', 'es': 'Luna', 'ru': 'Луна' },
  'Neptune': { 'en': 'Neptune', 'zh_CN': '海王星', 'ja': '海王星', 'ko': '해왕성', 'fr': 'Neptune', 'de': 'Neptun', 'es': 'Neptuno', 'ru': 'Нептун' },
  'Pluto': { 'en': 'Pluto', 'zh_CN': '冥王星', 'ja': '冥王星', 'ko': '명왕성', 'fr': 'Pluton', 'de': 'Pluto', 'es': 'Plutón', 'ru': 'Плутон' },
  'Saturn': { 'en': 'Saturn', 'zh_CN': '土星', 'ja': '土星', 'ko': '토성', 'fr': 'Saturne', 'de': 'Saturn', 'es': 'Saturno', 'ru': 'Сатурн' },
  'Sun': { 'en': 'Sun', 'zh_CN': '太阳', 'ja': '太陽', 'ko': '태양', 'fr': 'Soleil', 'de': 'Sonne', 'es': 'Sol', 'ru': 'Солнце' },
  'Uranus': { 'en': 'Uranus', 'zh_CN': '天王星', 'ja': '天王星', 'ko': '천왕성', 'fr': 'Uranus', 'de': 'Uranus', 'es': 'Urano', 'ru': 'Уран' },
  'Venus': { 'en': 'Venus', 'zh_CN': '金星', 'ja': '金星', 'ko': '금성', 'fr': 'Vénus', 'de': 'Venus', 'es': 'Venus', 'ru': 'Венера' },
}

// 卫星分组翻译表（C++ getGroupIdList 返回的分组 ID → 各语言）
const SAT_GROUPS: Record<string, Record<string, string>> = {
  'amateur': { 'en': 'Amateur', 'zh_CN': '业余', 'ja': 'アマチュア', 'ko': '아마추어', 'fr': 'Amateur', 'de': 'Amateur', 'es': 'Aficionado', 'ru': 'Любительские' },
  'communications': { 'en': 'Communications', 'zh_CN': '通信', 'ja': '通信', 'ko': '통신', 'fr': 'Communications', 'de': 'Kommunikation', 'es': 'Comunicaciones', 'ru': 'Связь' },
  'debris': { 'en': 'Debris', 'zh_CN': '碎片', 'ja': 'デブリ', 'ko': '파편', 'fr': 'Débris', 'de': 'Trümmer', 'es': 'Escombros', 'ru': 'Мусор' },
  'education': { 'en': 'Education', 'zh_CN': '教育', 'ja': '教育', 'ko': '교육', 'fr': 'Éducation', 'de': 'Bildung', 'es': 'Educación', 'ru': 'Образование' },
  'engineering': { 'en': 'Engineering', 'zh_CN': '工程', 'ja': '工学', 'ko': '공학', 'fr': 'Ingénierie', 'de': 'Ingenieurwesen', 'es': 'Ingeniería', 'ru': 'Инженерные' },
  'geodetic': { 'en': 'Geodetic', 'zh_CN': '测地', 'ja': '測地', 'ko': '측지', 'fr': 'Géodésique', 'de': 'Geodätisch', 'es': 'Geodésico', 'ru': 'Геодезические' },
  'globalstar': { 'en': 'Globalstar', 'zh_CN': '全球星', 'ja': 'グローバルスター', 'ko': '글로벌스타', 'fr': 'Globalstar', 'de': 'Globalstar', 'es': 'Globalstar', 'ru': 'Globalstar' },
  'intelsat': { 'en': 'Intelsat', 'zh_CN': '国际通信卫星', 'ja': 'インテルサット', 'ko': '인텔샛', 'fr': 'Intelsat', 'de': 'Intelsat', 'es': 'Intelsat', 'ru': 'Интелсат' },
  'iridium': { 'en': 'Iridium', 'zh_CN': '铱星', 'ja': 'イリジウム', 'ko': '이리듐', 'fr': 'Iridium', 'de': 'Iridium', 'es': 'Iridium', 'ru': 'Иридиум' },
  'military': { 'en': 'Military', 'zh_CN': '军事', 'ja': '軍事', 'ko': '군사', 'fr': 'Militaire', 'de': 'Militär', 'es': 'Militar', 'ru': 'Военные' },
  'navigation': { 'en': 'Navigation', 'zh_CN': '导航', 'ja': '航法', 'ko': '항법', 'fr': 'Navigation', 'de': 'Navigation', 'es': 'Navegación', 'ru': 'Навигационные' },
  'radar': { 'en': 'Radar', 'zh_CN': '雷达', 'ja': 'レーダー', 'ko': '레이더', 'fr': 'Radar', 'de': 'Radar', 'es': 'Radar', 'ru': 'Радар' },
  'scientific': { 'en': 'Scientific', 'zh_CN': '科学', 'ja': '科学', 'ko': '과학', 'fr': 'Scientifique', 'de': 'Wissenschaft', 'es': 'Científico', 'ru': 'Научные' },
  'ses': { 'en': 'SES', 'zh_CN': 'SES', 'ja': 'SES', 'ko': 'SES', 'fr': 'SES', 'de': 'SES', 'es': 'SES', 'ru': 'SES' },
  'starlink': { 'en': 'Starlink', 'zh_CN': '星链', 'ja': 'スターリンク', 'ko': '스타링크', 'fr': 'Starlink', 'de': 'Starlink', 'es': 'Starlink', 'ru': ' Старлинк' },
  'stations': { 'en': 'Space Stations', 'zh_CN': '空间站', 'ja': '宇宙ステーション', 'ko': '우주정거장', 'fr': 'Stations spatiales', 'de': 'Raumstationen', 'es': 'Estaciones espaciales', 'ru': 'Космические станции' },
  'tdrss': { 'en': 'TDRSS', 'zh_CN': '跟踪与数据中继卫星', 'ja': 'TDRSS', 'ko': 'TDRSS', 'fr': 'TDRSS', 'de': 'TDRSS', 'es': 'TDRSS', 'ru': 'TDRSS' },
  'tv': { 'en': 'TV', 'zh_CN': '电视', 'ja': 'テレビ', 'ko': 'TV', 'fr': 'TV', 'de': 'TV', 'es': 'TV', 'ru': 'ТВ' },
  'visual': { 'en': 'Visual', 'zh_CN': '可视', 'ja': '可視', 'ko': '가시', 'fr': 'Visuel', 'de': 'Visuell', 'es': 'Visual', 'ru': 'Видимые' },
  'weather': { 'en': 'Weather', 'zh_CN': '气象', 'ja': '気象', 'ko': '기상', 'fr': 'Météo', 'de': 'Wetter', 'es': 'Meteorología', 'ru': 'Метеорологические' },
  'beidou': { 'en': 'BeiDou', 'zh_CN': '北斗', 'ja': '北斗', 'ko': '베이더우', 'fr': 'BeiDou', 'de': 'BeiDou', 'es': 'BeiDou', 'ru': 'Бэйдоу' },
  'cosmos': { 'en': 'Cosmos', 'zh_CN': '宇宙', 'ja': 'コスモス', 'ko': '코스모스', 'fr': 'Cosmos', 'de': 'Kosmos', 'es': 'Cosmos', 'ru': 'Космос' },
  'earth resources': { 'en': 'Earth Resources', 'zh_CN': '地球资源', 'ja': '地球観測', 'ko': '지구 자원', 'fr': 'Ressources terrestres', 'de': 'Erdressourcen', 'es': 'Recursos terrestres', 'ru': 'Ресурсы Земли' },
  'galileo': { 'en': 'Galileo', 'zh_CN': '伽利略', 'ja': 'ガリレオ', 'ko': '갈릴레오', 'fr': 'Galileo', 'de': 'Galileo', 'es': 'Galileo', 'ru': 'Галилео' },
  'geo': { 'en': 'GEO', 'zh_CN': '地球同步轨道', 'ja': '静止軌道', 'ko': '정지궤도', 'fr': 'GEO', 'de': 'GEO', 'es': 'GEO', 'ru': 'ГЕО' },
  'geostationary': { 'en': 'Geostationary', 'zh_CN': '地球静止轨道', 'ja': '静止軌道', 'ko': '정지궤도', 'fr': 'Géostationnaire', 'de': 'Geostationär', 'es': 'Geoestacionario', 'ru': 'Геостационарные' },
  'glo-ops': { 'en': 'GLO-OPS', 'zh_CN': '格洛纳斯运营', 'ja': 'GLONASS運用', 'ko': 'GLONASS 운영', 'fr': 'GLO-OPS', 'de': 'GLO-OPS', 'es': 'GLO-OPS', 'ru': 'ГЛОНАСС-ОПС' },
  'glonass': { 'en': 'GLONASS', 'zh_CN': '格洛纳斯', 'ja': 'GLONASS', 'ko': 'GLONASS', 'fr': 'GLONASS', 'de': 'GLONASS', 'es': 'GLONASS', 'ru': 'ГЛОНАСС' },
  'gnss': { 'en': 'GNSS', 'zh_CN': '全球导航卫星系统', 'ja': '測位衛星', 'ko': '위성항법시스템', 'fr': 'GNSS', 'de': 'GNSS', 'es': 'GNSS', 'ru': 'ГНСС' },
  'gonets': { 'en': 'Gonets', 'zh_CN': '戈涅斯', 'ja': 'ゴネツ', 'ko': '고네츠', 'fr': 'Gonets', 'de': 'Gonets', 'es': 'Gonets', 'ru': 'Гонец' },
  'gps': { 'en': 'GPS', 'zh_CN': 'GPS', 'ja': 'GPS', 'ko': 'GPS', 'fr': 'GPS', 'de': 'GPS', 'es': 'GPS', 'ru': 'GPS' },
  'gps-ops': { 'en': 'GPS-OPS', 'zh_CN': 'GPS运营', 'ja': 'GPS運用', 'ko': 'GPS 운영', 'fr': 'GPS-OPS', 'de': 'GPS-OPS', 'es': 'GPS-OPS', 'ru': 'GPS-ОПС' },
  'iridium-next': { 'en': 'Iridium NEXT', 'zh_CN': '铱星NEXT', 'ja': 'Iridium-NEXT', 'ko': 'Iridium-NEXT', 'fr': 'Iridium-NEXT', 'de': 'Iridium-NEXT', 'es': 'Iridium-NEXT', 'ru': 'Иридиум-NEXT' },
  'irnss': { 'en': 'IRNSS', 'zh_CN': '印度区域导航', 'ja': 'インド区域航法', 'ko': '인도 지역항법', 'fr': 'IRNSS', 'de': 'IRNSS', 'es': 'IRNSS', 'ru': 'IRNSS' },
  'last-30-days': { 'en': 'Last 30 Days', 'zh_CN': '近30天', 'ja': '過去30日間', 'ko': '최근 30일', 'fr': '30 derniers jours', 'de': 'Letzte 30 Tage', 'es': 'Últimos 30 días', 'ru': 'За 30 дней' },
  'leo': { 'en': 'LEO', 'zh_CN': '低轨卫星', 'ja': '低軌道', 'ko': '저궤도', 'fr': 'LEO', 'de': 'LEO', 'es': 'LEO', 'ru': 'НСО' },
  'meo': { 'en': 'MEO', 'zh_CN': '中轨卫星', 'ja': '中軌道', 'ko': '중궤도', 'fr': 'MEO', 'de': 'MEO', 'es': 'MEO', 'ru': 'СПО' },
  'resource': { 'en': 'Resource', 'zh_CN': '资源', 'ja': '資源', 'ko': '자원', 'fr': 'Ressource', 'de': 'Ressource', 'es': 'Recurso', 'ru': 'Ресурс' },
  'space-station': { 'en': 'Space Station', 'zh_CN': '空间站', 'ja': '宇宙ステーション', 'ko': '우주정거장', 'fr': 'Station spatiale', 'de': 'Raumstation', 'es': 'Estación espacial', 'ru': 'Космическая станция' },
  'tracking': { 'en': 'Tracking', 'zh_CN': '跟踪', 'ja': '追跡', 'ko': '추적', 'fr': 'Suivi', 'de': 'Verfolgung', 'es': 'Seguimiento', 'ru': 'Слежение' },
}

// 插件名称翻译表
// 恒星名称翻译表（搜索面板快捷按钮用）
const STAR_NAMES: Record<string, Record<string, string>> = {
  'Achernar': { 'en': 'Achernar', 'zh_CN': '水委一', 'ja': 'アケルナル', 'ko': '아케르나르', 'fr': 'Achernar', 'de': 'Achernar', 'es': 'Achernar', 'ru': 'Ахернар' },
  'Aldebaran': { 'en': 'Aldebaran', 'zh_CN': '毕宿五', 'ja': 'アルデバラン', 'ko': '알데바란', 'fr': 'Aldébaran', 'de': 'Aldebaran', 'es': 'Aldebarán', 'ru': 'Альдебаран' },
  'Altair': { 'en': 'Altair', 'zh_CN': '牛郎星', 'ja': 'アルタイル', 'ko': '알타이르', 'fr': 'Altaïr', 'de': 'Altair', 'es': 'Altair', 'ru': 'Альтаир' },
  'Antares': { 'en': 'Antares', 'zh_CN': '心宿二', 'ja': 'アンタレス', 'ko': '안타레스', 'fr': 'Antarès', 'de': 'Antares', 'es': 'Antares', 'ru': 'Антарес' },
  'Arcturus': { 'en': 'Arcturus', 'zh_CN': '大角星', 'ja': 'アークトゥルス', 'ko': '아크투루스', 'fr': 'Arcturus', 'de': 'Arcturus', 'es': 'Arcturus', 'ru': 'Арктур' },
  'Betelgeuse': { 'en': 'Betelgeuse', 'zh_CN': '参宿四', 'ja': 'ベテルギウス', 'ko': '베텔기우스', 'fr': 'Bételgeuse', 'de': 'Beteigeuze', 'es': 'Betelgeuse', 'ru': 'Бетельгейзе' },
  'Canopus': { 'en': 'Canopus', 'zh_CN': '老人星', 'ja': 'カノプス', 'ko': '카노푸스', 'fr': 'Canope', 'de': 'Canopus', 'es': 'Canopus', 'ru': 'Канопус' },
  'Capella': { 'en': 'Capella', 'zh_CN': '五车二', 'ja': 'カペラ', 'ko': '카펠라', 'fr': 'Capella', 'de': 'Capella', 'es': 'Capella', 'ru': 'Капелла' },
  'Deneb': { 'en': 'Deneb', 'zh_CN': '天津四', 'ja': 'デネブ', 'ko': '데네브', 'fr': 'Deneb', 'de': 'Deneb', 'es': 'Deneb', 'ru': 'Денеб' },
  'Fomalhaut': { 'en': 'Fomalhaut', 'zh_CN': '北落师门', 'ja': 'フォマルハウト', 'ko': '포말하우트', 'fr': 'Fomalhaut', 'de': 'Fomalhaut', 'es': 'Fomalhaut', 'ru': 'Фомальгаут' },
  'Polaris': { 'en': 'Polaris', 'zh_CN': '北极星', 'ja': 'ポラリス', 'ko': '폴라리스', 'fr': 'Polaris', 'de': 'Polaris', 'es': 'Polaris', 'ru': 'Полярная звезда' },
  'Pollux': { 'en': 'Pollux', 'zh_CN': '北河三', 'ja': 'ポルックス', 'ko': '폴룩스', 'fr': 'Pollux', 'de': 'Pollux', 'es': 'Pólux', 'ru': 'Поллукс' },
  'Procyon': { 'en': 'Procyon', 'zh_CN': '南河三', 'ja': 'プロキオン', 'ko': '프로키온', 'fr': 'Procyon', 'de': 'Prokyon', 'es': 'Próción', 'ru': 'Прохион' },
  'Regulus': { 'en': 'Regulus', 'zh_CN': '轩辕十四', 'ja': 'レグルス', 'ko': '레굴루스', 'fr': 'Régulus', 'de': 'Regulus', 'es': 'Regulo', 'ru': 'Регул' },
  'Rigel': { 'en': 'Rigel', 'zh_CN': '参宿七', 'ja': 'リゲル', 'ko': '리겔', 'fr': 'Rigel', 'de': 'Rigel', 'es': 'Rigel', 'ru': 'Ригель' },
  'Sirius': { 'en': 'Sirius', 'zh_CN': '天狼星', 'ja': 'シリウス', 'ko': '시리우스', 'fr': 'Sirius', 'de': 'Sirius', 'es': 'Sirio', 'ru': 'Сириус' },
  'Spica': { 'en': 'Spica', 'zh_CN': '角宿一', 'ja': 'スピカ', 'ko': '스피카', 'fr': 'Spica', 'de': 'Spica', 'es': 'Espiga', 'ru': 'Спика' },
  'Vega': { 'en': 'Vega', 'zh_CN': '织女星', 'ja': 'ベガ', 'ko': '베가', 'fr': 'Véga', 'de': 'Wega', 'es': 'Vega', 'ru': 'Вега' },
}

const PLUGIN_NAMES: Record<string, Record<string, string>> = {
  'Angle Measure': { 'en': 'Angle Measure', 'zh_CN': '角度测量', 'ja': '角度測定', 'ko': '각도 측정', 'fr': 'Mesure d\'angle', 'de': 'Winkelmessung', 'es': 'Medida de ángulo', 'ru': 'Измерение углов' },
  'ArchaeoLines': { 'en': 'ArchaeoLines', 'zh_CN': '考古线', 'ja': 'アーケオライン', 'ko': '고고학 선', 'fr': 'Lignes archéologiques', 'de': 'Archäo-Linien', 'es': 'Líneas arqueológicas', 'ru': 'Археолинии' },
  'Calendars': { 'en': 'Calendars', 'zh_CN': '历法', 'ja': '暦', 'ko': '달력', 'fr': 'Calendriers', 'de': 'Kalender', 'es': 'Calendarios', 'ru': 'Календари' },
  'Equation of Time': { 'en': 'Equation of Time', 'zh_CN': '时差方程', 'ja': '均時差', 'ko': '시차 방정식', 'fr': 'Équation du temps', 'de': 'Zeitgleichung', 'es': 'Ecuación del tiempo', 'ru': 'Уравнение времени' },
  'Exoplanets': { 'en': 'Exoplanets', 'zh_CN': '系外行星', 'ja': '系外惑星', 'ko': '계외행성', 'fr': 'Exoplanètes', 'de': 'Exoplaneten', 'es': 'Exoplanetas', 'ru': 'Экзопланеты' },
  'Lens distortion estimator': { 'en': 'Lens distortion estimator', 'zh_CN': '镜头畸变估算', 'ja': 'レンズ歪み推定', 'ko': '렌즈 왜곡 추정', 'fr': 'Estimateur de distorsion', 'de': 'Linsenverzerrung', 'es': 'Estimador de distorsión', 'ru': 'Оценка искажения линзы' },
  'Meteor Showers': { 'en': 'Meteor Showers', 'zh_CN': '流星雨', 'ja': '流星群', 'ko': '유성우', 'fr': 'Pluies de météores', 'de': 'Meteorschauer', 'es': 'Lluvias de meteoros', 'ru': 'Метеорные потоки' },
  'Novae': { 'en': 'Novae', 'zh_CN': '新星', 'ja': '新星', 'ko': '신성', 'fr': 'Novae', 'de': 'Novae', 'es': 'Novae', 'ru': 'Новые' },
  'Observability': { 'en': 'Observability', 'zh_CN': '可观测性', 'ja': '観測可能性', 'ko': '관측가능성', 'fr': 'Observabilité', 'de': 'Beobachtbarkeit', 'es': 'Observabilidad', 'ru': 'Наблюдаемость' },
  'Pulsars': { 'en': 'Pulsars', 'zh_CN': '脉冲星', 'ja': 'パルサー', 'ko': '펄서', 'fr': 'Pulsars', 'de': 'Pulsare', 'es': 'Púlsares', 'ru': 'Пульсары' },
  'Quasars': { 'en': 'Quasars', 'zh_CN': '类星体', 'ja': 'クエーサー', 'ko': '퀘이사', 'fr': 'Quasars', 'de': 'Quasare', 'es': 'Cuásares', 'ru': 'Квазары' },
  'Remote Control': { 'en': 'Remote Control', 'zh_CN': '远程控制', 'ja': 'リモートコントロール', 'ko': '원격 제어', 'fr': 'Contrôle à distance', 'de': 'Fernsteuerung', 'es': 'Control remoto', 'ru': 'Удалённое управление' },
  'Satellites': { 'en': 'Satellites', 'zh_CN': '卫星', 'ja': '衛星', 'ko': '위성', 'fr': 'Satellites', 'de': 'Satelliten', 'es': 'Satélites', 'ru': 'Спутники' },
  'Screenshots': { 'en': 'Screenshots', 'zh_CN': '截图', 'ja': 'スクリーンショット', 'ko': '스크린샷', 'fr': 'Captures d\'écran', 'de': 'Screenshots', 'es': 'Capturas de pantalla', 'ru': 'Снимки экрана' },
  'Sky Cultures': { 'en': 'Sky Cultures', 'zh_CN': '星空文化', 'ja': '星空文化', 'ko': '별자리 문화', 'fr': 'Cultures célestes', 'de': 'Sternkulturen', 'es': 'Culturas celestes', 'ru': 'Звёздные культуры' },
  'Solar System Editor': { 'en': 'Solar System Editor', 'zh_CN': '太阳系编辑器', 'ja': '太陽系エディタ', 'ko': '태양계 편집기', 'fr': 'Éditeur du système solaire', 'de': 'Sonnensystem-Editor', 'es': 'Editor del sistema solar', 'ru': 'Редактор Солнечной системы' },
  'Supernovae': { 'en': 'Supernovae', 'zh_CN': '超新星', 'ja': '超新星', 'ko': '초신성', 'fr': 'Supernovae', 'de': 'Supernovae', 'es': 'Supernovas', 'ru': 'Сверхновые' },
  'Text User Interface': { 'en': 'Text User Interface', 'zh_CN': '文本用户界面', 'ja': 'テキストUI', 'ko': '텍스트 UI', 'fr': 'Interface texte', 'de': 'Text-Benutzeroberfläche', 'es': 'Interfaz de texto', 'ru': 'Текстовый интерфейс' },
  'Time Zone': { 'en': 'Time Zone', 'zh_CN': '时区', 'ja': 'タイムゾーン', 'ko': '시간대', 'fr': 'Fuseau horaire', 'de': 'Zeitzone', 'es': 'Zona horaria', 'ru': 'Часовой пояс' },
  'Voculars': { 'en': 'Voculars', 'zh_CN': '声码器', 'ja': 'ボキュラーズ', 'ko': '보큘러스', 'fr': 'Voculars', 'de': 'Voculars', 'es': 'Voculars', 'ru': 'Вокуляры' },
}

// 地景名称翻译表
const LANDSCAPE_NAMES: Record<string, Record<string, string>> = {
  'Armintxe Cave': { 'en': 'Armintxe Cave', 'zh_CN': '阿明特谢洞穴', 'ja': 'アルミントシェ洞窟', 'ko': '아르민트셰 동굴', 'fr': 'Grotte d\'Armintxe', 'de': 'Armintxe-Höhle', 'es': 'Cueva de Armintxe', 'ru': 'Пещера Арминтше' },
  'Forest': { 'en': 'Forest', 'zh_CN': '森林', 'ja': '森', 'ko': '숲', 'fr': 'Forêt', 'de': 'Wald', 'es': 'Bosque', 'ru': 'Лес' },
  'Garching': { 'en': 'Garching', 'zh_CN': '加兴', 'ja': 'ガルヒング', 'ko': '가르힝', 'fr': 'Garching', 'de': 'Garching', 'es': 'Garching', 'ru': 'Гархинг' },
  'Geneva': { 'en': 'Geneva', 'zh_CN': '日内瓦', 'ja': 'ジュネーブ', 'ko': '제네바', 'fr': 'Genève', 'de': 'Genf', 'es': 'Ginebra', 'ru': 'Женева' },
  'Grossmugl': { 'en': 'Grossmugl', 'zh_CN': '格罗斯穆格尔', 'ja': 'グロースムーグル', 'ko': '그로스무글', 'fr': 'Grossmugl', 'de': 'Großmugl', 'es': 'Grossmugl', 'ru': 'Гроссмугль' },
  'Guereins': { 'en': 'Guereins', 'zh_CN': '盖兰', 'ja': 'ゲラン', 'ko': '게랭', 'fr': 'Guéreins', 'de': 'Guéreins', 'es': 'Guereins', 'ru': 'Геррен' },
  'Guereins 0 0': { 'en': 'Guereins 0 0', 'zh_CN': '盖兰 0 0', 'ja': 'ゲラン 0 0', 'ko': '게랭 0 0', 'fr': 'Guéreins 0 0', 'de': 'Guéreins 0 0', 'es': 'Guereins 0 0', 'ru': 'Геррен 0 0' },
  'Hurricane': { 'en': 'Hurricane', 'zh_CN': '飓风', 'ja': 'ハリケーン', 'ko': '허리케인', 'fr': 'Ouragan', 'de': 'Hurrikan', 'es': 'Huracán', 'ru': 'Ураган' },
  'Jupiter': { 'en': 'Jupiter', 'zh_CN': '木星', 'ja': '木星', 'ko': '목성', 'fr': 'Jupiter', 'de': 'Jupiter', 'es': 'Júpiter', 'ru': 'Юпитер' },
  'Mars': { 'en': 'Mars', 'zh_CN': '火星', 'ja': '火星', 'ko': '화성', 'fr': 'Mars', 'de': 'Mars', 'es': 'Marte', 'ru': 'Марс' },
  'Moon': { 'en': 'Moon', 'zh_CN': '月球', 'ja': '月', 'ko': '달', 'fr': 'Lune', 'de': 'Mond', 'es': 'Luna', 'ru': 'Луна' },
  'Ocean': { 'en': 'Ocean', 'zh_CN': '海洋', 'ja': '海洋', 'ko': '해양', 'fr': 'Océan', 'de': 'Ozean', 'es': 'Océano', 'ru': 'Океан' },
  'Tree': { 'en': 'Tree', 'zh_CN': '树林', 'ja': '木', 'ko': '나무', 'fr': 'Arbre', 'de': 'Baum', 'es': 'Árbol', 'ru': 'Дерево' },
  'Zero': { 'en': 'Zero', 'zh_CN': '零点', 'ja': 'ゼロ', 'ko': '제로', 'fr': 'Zéro', 'de': 'Null', 'es': 'Cero', 'ru': 'Ноль' },
}

// 陀螺仪灵敏度翻译表
const SENSITIVITY: Record<string, Record<string, string>> = {
  'Fast': { 'en': 'Fast', 'zh_CN': '快速', 'ja': '高速', 'ko': '빠름', 'fr': 'Rapide', 'de': 'Schnell', 'es': 'Rápido', 'ru': 'Быстрая' },
  'Slow': { 'en': 'Slow', 'zh_CN': '慢速', 'ja': '低速', 'ko': '느림', 'fr': 'Lent', 'de': 'Langsam', 'es': 'Lento', 'ru': 'Медленная' },
  'Standard': { 'en': 'Standard', 'zh_CN': '标准', 'ja': '標準', 'ko': '표준', 'fr': 'Standard', 'de': 'Standard', 'es': 'Estándar', 'ru': 'Стандартная' },
}

// 追踪状态翻译表
const TRACK_STATUS: Record<string, Record<string, string>> = {
  'Off': { 'en': 'Off', 'zh_CN': '关闭', 'ja': 'オフ', 'ko': '꺼짐', 'fr': 'Désactivé', 'de': 'Aus', 'es': 'Desactivado', 'ru': 'Выкл' },
  'On': { 'en': 'On', 'zh_CN': '开启', 'ja': 'オン', 'ko': '켜짐', 'fr': 'Activé', 'de': 'Ein', 'es': 'Activado', 'ru': 'Вкл' },
}

// 选中状态翻译表
const SELECTED_STATUS: Record<string, Record<string, string>> = {
  'Core not ready': { 'en': 'Core not ready', 'zh_CN': '核心未就绪', 'ja': 'コア未準備', 'ko': '코어 미준비', 'fr': 'Noyau non prêt', 'de': 'Kern nicht bereit', 'es': 'Núcleo no listo', 'ru': 'Ядро не готово' },
  'No match': { 'en': 'No match', 'zh_CN': '无匹配结果', 'ja': '該当なし', 'ko': '일치 없음', 'fr': 'Aucune correspondance', 'de': 'Kein Treffer', 'es': 'Sin coincidencia', 'ru': 'Нет совпадения' },
  'No selection': { 'en': 'No selection', 'zh_CN': '未选择', 'ja': '未選択', 'ko': '미선택', 'fr': 'Aucune sélection', 'de': 'Nicht ausgewählt', 'es': 'Sin selección', 'ru': 'Не выбрано' },
  'Not found': { 'en': 'Not found', 'zh_CN': '未找到', 'ja': '見つかりません', 'ko': '찾을 수 없음', 'fr': 'Introuvable', 'de': 'Nicht gefunden', 'es': 'No encontrado', 'ru': 'Не найдено' },
  'Selected': { 'en': 'Selected', 'zh_CN': '已选中', 'ja': '選択中', 'ko': '선택됨', 'fr': 'Sélectionné', 'de': 'Ausgewählt', 'es': 'Seleccionado', 'ru': 'Выбрано' },
  'Try English name': { 'en': 'Try English name', 'zh_CN': '尝试英文名称', 'ja': '英語名で試行', 'ko': '영어명으로 시도', 'fr': 'Essayez le nom anglais', 'de': 'Englischen Namen versuchen', 'es': 'Pruebe nombre en inglés', 'ru': 'Попробуйте английское название' },
}

// 富文本短语翻译表（用于天体描述文本的本地化替换）
const RICH_PHRASES: Record<string, Record<string, string>> = {
  'binary star': { 'en': 'binary star', 'zh_CN': '双星', 'ja': '連星', 'ko': '쌍성', 'fr': 'étoile binaire', 'de': 'Doppelsternsystem', 'es': 'estrella binaria', 'ru': 'двойная звезда' },
  'cluster': { 'en': 'cluster', 'zh_CN': '星团', 'ja': '星団', 'ko': '성단', 'fr': 'amas', 'de': 'Sternhaufen', 'es': 'cúmulo', 'ru': 'скопление' },
  'double star': { 'en': 'double star', 'zh_CN': '双星', 'ja': '二重星', 'ko': '쌍성', 'fr': 'étoile double', 'de': 'Doppelstern', 'es': 'estrella doble', 'ru': 'двойная звезда' },
  'eclipsing binary system': { 'en': 'eclipsing binary system', 'zh_CN': '食双星系统', 'ja': '食連星系', 'ko': '식쌍성계', 'fr': 'système binaire à éclipses', 'de': 'bedeckungsveränderliches System', 'es': 'sistema binario eclipsante', 'ru': 'затменная двойная система' },
  'elliptical galaxy': { 'en': 'elliptical galaxy', 'zh_CN': '椭圆星系', 'ja': '楕円銀河', 'ko': '타원은하', 'fr': 'galaxie elliptique', 'de': 'Elliptische Galaxie', 'es': 'galaxia elíptica', 'ru': 'эллиптическая галактика' },
  'emission nebula': { 'en': 'emission nebula', 'zh_CN': '发射星云', 'ja': '輝線星雲', 'ko': '발산성운', 'fr': 'nébuleuse en émission', 'de': 'Emissionsnebel', 'es': 'nebulosa de emisión', 'ru': 'эмиссионная туманность' },
  'galaxy': { 'en': 'galaxy', 'zh_CN': '星系', 'ja': '銀河', 'ko': '은하', 'fr': 'galaxie', 'de': 'Galaxie', 'es': 'galaxia', 'ru': 'галактика' },
  'globular cluster': { 'en': 'globular cluster', 'zh_CN': '球状星团', 'ja': '球状星団', 'ko': '구상성단', 'fr': 'amas globulaire', 'de': 'Kugelsternhaufen', 'es': 'cúmulo globular', 'ru': 'шаровое скопление' },
  'nebula': { 'en': 'nebula', 'zh_CN': '星云', 'ja': '星雲', 'ko': '성운', 'fr': 'nébuleuse', 'de': 'Nebel', 'es': 'nebulosa', 'ru': 'туманность' },
  'open cluster': { 'en': 'open cluster', 'zh_CN': '疏散星团', 'ja': '散開星団', 'ko': '산개성단', 'fr': 'amas ouvert', 'de': 'offener Sternhaufen', 'es': 'cúmulo abierto', 'ru': 'рассеянное скопление' },
  'planetary nebula': { 'en': 'planetary nebula', 'zh_CN': '行星状星云', 'ja': '惑星状星雲', 'ko': '행성상성운', 'fr': 'nébuleuse planétaire', 'de': 'planetarischer Nebel', 'es': 'nebulosa planetaria', 'ru': 'планетарная туманность' },
  'reflection nebula': { 'en': 'reflection nebula', 'zh_CN': '反射星云', 'ja': '反射星雲', 'ko': '반사성운', 'fr': 'nébuleuse par réflexion', 'de': 'Reflexionsnebel', 'es': 'nebulosa de reflexión', 'ru': 'отражательная туманность' },
  'spiral galaxy': { 'en': 'spiral galaxy', 'zh_CN': '螺旋星系', 'ja': '渦巻銀河', 'ko': '나선은하', 'fr': 'galaxie spirale', 'de': 'Spiralgalaxie', 'es': 'galaxia espiral', 'ru': 'спиральная галактика' },
  'supernova remnant': { 'en': 'supernova remnant', 'zh_CN': '超新星遗迹', 'ja': '超新星残骸', 'ko': '초신성잔해', 'fr': 'reste de supernova', 'de': 'Supernovaüberrest', 'es': 'resto de supernova', 'ru': 'остаток сверхновой' },
  'variable star': { 'en': 'variable star', 'zh_CN': '变星', 'ja': '変光星', 'ko': '변광성', 'fr': 'étoile variable', 'de': 'veränderlicher Stern', 'es': 'estrella variable', 'ru': 'переменная звезда' },
}

// UI 字符串翻译表（硬编码的 UI 文本 → 各语言）
const UI_STRINGS: Record<string, Record<string, string>> = {
  'btn_start_recording': { 'en': 'Start Recording', 'zh_CN': '开始录制', 'ja': '録画開始', 'ko': '녹화 시작', 'fr': 'Commencer l\'enregistrement', 'de': 'Aufnahme starten', 'es': 'Iniciar grabación', 'ru': 'Начать запись' },
  'btn_stop_recording': { 'en': 'Stop Recording', 'zh_CN': '停止录制', 'ja': '録画停止', 'ko': '녹화 중지', 'fr': 'Arrêter l\'enregistrement', 'de': 'Aufnahme stoppen', 'es': 'Detener grabación', 'ru': 'Остановить запись' },
  'msg_apply_failed': { 'en': 'Apply failed', 'zh_CN': '应用失败', 'ja': '適用失敗', 'ko': '적용 실패', 'fr': 'Échec de l\'application', 'de': 'Anwendung fehlgeschlagen', 'es': 'Error al aplicar', 'ru': 'Ошибка применения' },
  'msg_azimuth': { 'en': 'Az', 'zh_CN': '方位角', 'ja': '方位角', 'ko': '방위각', 'fr': 'Az', 'de': 'Az', 'es': 'Az', 'ru': 'Аз' },
  'msg_bookmark_deleted': { 'en': 'Bookmark deleted', 'zh_CN': '已删除书签', 'ja': 'ブックマーク削除済み', 'ko': '북마크 삭제됨', 'fr': 'Signet supprimé', 'de': 'Lesezeichen gelöscht', 'es': 'Marcador eliminado', 'ru': 'Закладка удалена' },
  'msg_bookmark_saved': { 'en': 'Bookmark saved', 'zh_CN': '已保存书签', 'ja': 'ブックマーク保存済み', 'ko': '북마크 저장됨', 'fr': 'Signet enregistré', 'de': 'Lesezeichen gespeichert', 'es': 'Marcador guardado', 'ru': 'Закладка сохранена' },
  'msg_catalog_downloading': { 'en': 'Catalog is downloading', 'zh_CN': '已有星表正在下载', 'ja': '星表ダウンロード中', 'ko': '성표 다운로드 중', 'fr': 'Catalogue en cours de téléchargement', 'de': 'Katalog wird heruntergeladen', 'es': 'Catálogo descargándose', 'ru': 'Каталог загружается' },
  'msg_catalog_msg': { 'en': 'Catalog', 'zh_CN': '星表', 'ja': '星表', 'ko': '성표', 'fr': 'Catalogue', 'de': 'Katalog', 'es': 'Catálogo', 'ru': 'Каталог' },
  'msg_config_exported': { 'en': 'Config exported', 'zh_CN': '已导出配置', 'ja': '設定エクスポート済み', 'ko': '설정 내보내기 완료', 'fr': 'Configuration exportée', 'de': 'Konfiguration exportiert', 'es': 'Configuración exportada', 'ru': 'Конфигурация экспортирована' },
  'msg_config_imported': { 'en': 'Config imported', 'zh_CN': '已导入配置', 'ja': '設定インポート済み', 'ko': '설정 가져오기 완료', 'fr': 'Configuration importée', 'de': 'Konfiguration importiert', 'es': 'Configuración importada', 'ru': 'Конфигурация импортирована' },
  'msg_exported': { 'en': 'Exported', 'zh_CN': '已导出', 'ja': 'エクスポート済み', 'ko': '내보내기 완료', 'fr': 'Exporté', 'de': 'Exportiert', 'es': 'Exportado', 'ru': 'Экспортировано' },
  'msg_import_failed': { 'en': 'Import failed', 'zh_CN': '导入失败', 'ja': 'インポート失敗', 'ko': '가져오기 실패', 'fr': 'Échec de l\'import', 'de': 'Import fehlgeschlagen', 'es': 'Error al importar', 'ru': 'Ошибка импорта' },
  'msg_jumped': { 'en': 'Jumped', 'zh_CN': '已跳转', 'ja': '移動完了', 'ko': '이동 완료', 'fr': 'Sauté', 'de': 'Gesprungen', 'es': 'Saltado', 'ru': 'Переход выполнен' },
  'msg_jumped_to': { 'en': 'Jumped to', 'zh_CN': '已跳至', 'ja': '移動先', 'ko': '이동됨', 'fr': 'Sauté à', 'de': 'Gesprungen zu', 'es': 'Saltado a', 'ru': 'Переход к' },
  'msg_loaded': { 'en': 'loaded', 'zh_CN': '已加载', 'ja': '読込済み', 'ko': '로드됨', 'fr': 'chargé', 'de': 'geladen', 'es': 'cargado', 'ru': 'загружено' },
  'msg_locking': { 'en': 'locking', 'zh_CN': '锁定', 'ja': 'ロック', 'ko': '잠금', 'fr': 'verrouillage', 'de': 'Sperren', 'es': 'bloqueo', 'ru': 'фиксация' },
  'msg_moment': { 'en': 'moment', 'zh_CN': '时刻', 'ja': '時刻', 'ko': '시각', 'fr': 'moment', 'de': 'Zeitpunkt', 'es': 'momento', 'ru': 'момент' },
  'msg_music_off': { 'en': 'Music: Muted', 'zh_CN': '音乐：静音', 'ja': '音楽：ミュート', 'ko': '음악: 음소거', 'fr': 'Musique : Mutée', 'de': 'Musik: Stumm', 'es': 'Música: Silenciada', 'ru': 'Музыка: Выкл' },
  'msg_music_on': { 'en': 'Music: On ♪', 'zh_CN': '音乐：开 ♪', 'ja': '音楽：オン ♪', 'ko': '음악: 켜짐 ♪', 'fr': 'Musique : Activée ♪', 'de': 'Musik: An ♪', 'es': 'Música: Activada ♪', 'ru': 'Музыка: Вкл ♪' },
  'msg_no_object_tts': { 'en': 'No object selected', 'zh_CN': '未选中天体', 'ja': '天体未選択', 'ko': '천체 미선택', 'fr': 'Aucun objet sélectionné', 'de': 'Kein Objekt ausgewählt', 'es': 'Ningún objeto seleccionado', 'ru': 'Объект не выбран' },
  'msg_no_selection_tts': { 'en': 'No object selected, cannot generate speech text', 'zh_CN': '未选中天体，无法生成朗读文本', 'ja': '天体未選択、音声テキスト生成不可', 'ko': '천체 미선택, 음성 텍스트 생성 불가', 'fr': 'Aucun objet sélectionné', 'de': 'Kein Objekt ausgewählt', 'es': 'Sin objeto seleccionado', 'ru': 'Объект не выбран' },
  'msg_not_enabled': { 'en': 'Not enabled', 'zh_CN': '未启用', 'ja': '未使用', 'ko': '미사용', 'fr': 'Non activé', 'de': 'Nicht aktiviert', 'es': 'No activado', 'ru': 'Не включено' },
  'msg_not_found_alt': { 'en': 'not found', 'zh_CN': '未找到', 'ja': '見つかりません', 'ko': '찾을 수 없음', 'fr': 'introuvable', 'de': 'nicht gefunden', 'es': 'no encontrado', 'ru': 'не найдено' },
  'msg_not_selected': { 'en': 'not selected', 'zh_CN': '未选中', 'ja': '未選択', 'ko': '미선택', 'fr': 'non sélectionné', 'de': 'nicht ausgewählt', 'es': 'no seleccionado', 'ru': 'не выбрано' },
  'msg_paused': { 'en': 'Paused', 'zh_CN': '已暂停', 'ja': '一時停止中', 'ko': '일시정지됨', 'fr': 'En pause', 'de': 'Pausiert', 'es': 'Pausado', 'ru': 'Пауза' },
  'msg_planet_switched': { 'en': 'Switched observing planet', 'zh_CN': '已切换观测星球', 'ja': '観測惑星切替済み', 'ko': '관측 행성 전환됨', 'fr': 'Planète d\'observation changée', 'de': 'Beobachtungsplanet gewechselt', 'es': 'Planeta de observación cambiado', 'ru': 'Планета наблюдения переключена' },
  'msg_pointed_to': { 'en': 'Pointed to Alt', 'zh_CN': '已指向 高度角', 'ja': '指向済み 高度', 'ko': '포인팅됨 고도', 'fr': 'Pointé vers Alt', 'de': 'Gezeigt auf Höhe', 'es': 'Apuntado a Alt', 'ru': 'Наведено на высоту' },
  'msg_pointing': { 'en': 'Pointing', 'zh_CN': '指向中…', 'ja': '指向中…', 'ko': '포인팅 중…', 'fr': 'Pointage en cours…', 'de': 'Zeige…', 'es': 'Apuntando…', 'ru': 'Наведение…' },
  'msg_pointing_stopped': { 'en': 'Pointing stopped, locking center star', 'zh_CN': '已停止指向，正在锁定中心星…', 'ja': '指向停止、中心星ロック中…', 'ko': '포인팅 중지, 중앙성 잠금 중…', 'fr': 'Pointage arrêté, verrouillage de l\'étoile centrale…', 'de': 'Zeigen gestoppt, zentralen Stern sperren…', 'es': 'Apuntado detenido, bloqueando estrella central…', 'ru': 'Наведение остановлено, фиксация центральной звезды…' },
  'msg_recording_deleted': { 'en': 'Recording deleted', 'zh_CN': '已删除录制', 'ja': '録画削除済み', 'ko': '녹화 삭제됨', 'fr': 'Enregistrement supprimé', 'de': 'Aufnahme gelöscht', 'es': 'Grabación eliminada', 'ru': 'Запись удалена' },
  'msg_recording_empty': { 'en': 'Stopped (no operations to save)', 'zh_CN': '已停止（没有可保存的操作）', 'ja': '停止（保存する操作なし）', 'ko': '중지됨 (저장할 조작 없음)', 'fr': 'Arrêté (rien à sauvegarder)', 'de': 'Gestoppt (nichts zu speichern)', 'es': 'Detenido (nada que guardar)', 'ru': 'Остановлено (нет данных для сохранения)' },
  'msg_recording_failed': { 'en': 'Recording failed', 'zh_CN': '停止录制失败', 'ja': '録画停止失敗', 'ko': '녹화 중지 실패', 'fr': 'Échec de l\'arrêt', 'de': 'Aufnahmestopp fehlgeschlagen', 'es': 'Error al detener', 'ru': 'Ошибка остановки записи' },
  'msg_recording_saved': { 'en': 'Saved', 'zh_CN': '已保存', 'ja': '保存済み', 'ko': '저장됨', 'fr': 'Enregistré', 'de': 'Gespeichert', 'es': 'Guardado', 'ru': 'Сохранено' },
  'msg_recording_started': { 'en': 'Recording started', 'zh_CN': '开始录制：接下来的操作会被记录', 'ja': '録画開始：これ以降の操作が記録されます', 'ko': '녹화 시작: 이후 조작이 기록됩니다', 'fr': 'Enregistrement commencé', 'de': 'Aufnahme gestartet', 'es': 'Grabación iniciada', 'ru': 'Запись начата' },
  'msg_recording_stopped': { 'en': 'Stopped, can save', 'zh_CN': '已停止，可保存', 'ja': '停止、保存可能', 'ko': '중지됨, 저장 가능', 'fr': 'Arrêté, peut sauvegarder', 'de': 'Gestoppt, kann gespeichert werden', 'es': 'Detenido, puede guardar', 'ru': 'Остановлено, можно сохранить' },
  'msg_refreshed': { 'en': 'Refreshed', 'zh_CN': '已刷新今晚天象 · 点击卡片可跳转', 'ja': '今夜の天文現象を更新 · カードでジャンプ', 'ko': '금일 천문 현상 갱신됨 · 카드로 이동', 'fr': 'Actualisé · cliquez sur la carte pour sauter', 'de': 'Aktualisiert · Karte klicken zum Springen', 'es': 'Actualizado · clic en tarjeta para saltar', 'ru': 'Обновлено · нажмите карту для перехода' },
  'msg_satellites_count': { 'en': 'satellites', 'zh_CN': '颗', 'ja': '個', 'ko': '개', 'fr': 'satellites', 'de': 'Satelliten', 'es': 'satélites', 'ru': 'спутников' },
  'msg_save_failed': { 'en': 'Save failed', 'zh_CN': '保存失败', 'ja': '保存失敗', 'ko': '저장 실패', 'fr': 'Échec de la sauvegarde', 'de': 'Speichern fehlgeschlagen', 'es': 'Error al guardar', 'ru': 'Ошибка сохранения' },
  'msg_selected': { 'en': 'selected', 'zh_CN': '选中', 'ja': '選択', 'ko': '선택', 'fr': 'sélectionné', 'de': 'ausgewählt', 'es': 'seleccionado', 'ru': 'выбрано' },
  'msg_sky_next_frame': { 'en': '(sky will turn and select center star next frame)', 'zh_CN': '（星图下一帧转过去并选中中心星）', 'ja': '（次フレームで中心星を選択）', 'ko': '(다음 프레임에서 중앙성 선택)', 'fr': '(le ciel tournera au prochain frame)', 'de': '(Himmel dreht sich im nächsten Frame)', 'es': '(el cielo girará en el siguiente frame)', 'ru': '(небо повернётся в следующем кадре)' },
  'msg_start_download': { 'en': 'Start downloading', 'zh_CN': '开始下载', 'ja': 'ダウンロード開始', 'ko': '다운로드 시작', 'fr': 'Début du téléchargement', 'de': 'Download gestartet', 'es': 'Iniciar descarga', 'ru': 'Начало загрузки' },
  'msg_start_recording_failed': { 'en': 'Start recording failed', 'zh_CN': '开始录制失败', 'ja': '録画開始失敗', 'ko': '녹화 시작 실패', 'fr': 'Échec du démarrage', 'de': 'Aufnahmestart fehlgeschlagen', 'es': 'Error al iniciar', 'ru': 'Ошибка запуска записи' },
  'msg_start_tracking': { 'en': 'Start pointing (track)', 'zh_CN': '开始指向(跟踪)', 'ja': '指向開始(追跡)', 'ko': '포인팅 시작(추적)', 'fr': 'Commencer le pointage (suivi)', 'de': 'Zeigen starten (Nachverfolgen)', 'es': 'Iniciar apuntado (seguimiento)', 'ru': 'Начать наведение (слежение)' },
  'msg_transit_forecast': { 'en': '(transit forecast needs more data)', 'zh_CN': '（过境预报需更多数据）', 'ja': '（通過予報にはより多くのデータが必要）', 'ko': '(통과 예보는 더 많은 데이터 필요)', 'fr': '(prévision de transit nécessite plus de données)', 'de': '(Transitvorhersage benötigt mehr Daten)', 'es': '(previsión de tránsito necesita más datos)', 'ru': '(прогноз транзита требует больше данных)' },
  'msg_tts_generated': { 'en': 'Speech text generated (TTS not available in current SDK)', 'zh_CN': '已生成朗读文本（当前 SDK 未集成语音合成）', 'ja': '音声テキスト生成済み（現在のSDKには音声合成なし）', 'ko': '음성 텍스트 생성됨 (현재 SDK에 음성 합성 없음)', 'fr': 'Texte vocal généré (TTS non disponible)', 'de': 'Sprachtext generiert (TTS nicht verfügbar)', 'es': 'Texto de voz generado (TTS no disponible)', 'ru': 'Текст речи сгенерирован (TTS недоступен)' },
  'msg_unknown': { 'en': 'Unknown', 'zh_CN': '未知', 'ja': '不明', 'ko': '알 수 없음', 'fr': 'Inconnu', 'de': 'Unbekannt', 'es': 'Desconocido', 'ru': 'Неизвестно' },
  'msg_hidden': { 'en': 'Hidden', 'zh_CN': '已隐藏', 'ja': '非表示', 'ko': '숨김', 'fr': 'Masqué', 'de': 'Ausgeblendet', 'es': 'Oculto', 'ru': 'Скрыто' },
  'msg_shown': { 'en': 'Shown', 'zh_CN': '已显示', 'ja': '表示', 'ko': '표시', 'fr': 'Affiché', 'de': 'Angezeigt', 'es': 'Mostrado', 'ru': 'Отображено' },
  'msg_unknown_error': { 'en': 'Unknown error', 'zh_CN': '未知错误', 'ja': '不明なエラー', 'ko': '알 수 없는 오류', 'fr': 'Erreur inconnue', 'de': 'Unbekannter Fehler', 'es': 'Error desconocido', 'ru': 'Неизвестная ошибка' },
  'msg_updated': { 'en': 'Updated', 'zh_CN': '已更新', 'ja': '更新済み', 'ko': '갱신됨', 'fr': 'Mis à jour', 'de': 'Aktualisiert', 'es': 'Actualizado', 'ru': 'Обновлено' },
  'msg_video_recording_started': { 'en': 'Started video frame sequence', 'zh_CN': '开始录制视频帧序列', 'ja': '動画フレーム録画開始', 'ko': '비디오 프레임 녹화 시작', 'fr': 'Séquence vidéo commencée', 'de': 'Video-Sequenz gestartet', 'es': 'Secuencia de video iniciada', 'ru': 'Начата запись видеопоследовательности' },
  'msg_video_recording_stopped': { 'en': 'Stopped, frames saved', 'zh_CN': '已停止，共帧已保存', 'ja': '停止、フレーム保存済み', 'ko': '중지됨, 프레임 저장됨', 'fr': 'Arrêté, images sauvegardées', 'de': 'Gestoppt, Frames gespeichert', 'es': 'Detenido, fotogramas guardados', 'ru': 'Остановлено, кадры сохранены' },
  'nav_meteor_showers': { 'en': 'Meteor Showers', 'zh_CN': '流星雨', 'ja': '流星群', 'ko': '유성우', 'fr': 'Pluies de météores', 'de': 'Meteorschauer', 'es': 'Lluvias de meteoros', 'ru': 'Метеорные потоки' },
  'nav_satellites': { 'en': 'Satellites', 'zh_CN': '卫星', 'ja': '衛星', 'ko': '위성', 'fr': 'Satellites', 'de': 'Satelliten', 'es': 'Satélites', 'ru': 'Спутники' },
  'ui_constellation': { 'en': 'Constellation', 'zh_CN': '星座', 'ja': '星座', 'ko': '별자리', 'fr': 'Constellation', 'de': 'Sternbild', 'es': 'Constelación', 'ru': 'Созвездие' },
  'ui_distance': { 'en': 'Distance', 'zh_CN': '距离', 'ja': '距離', 'ko': '거리', 'fr': 'Distance', 'de': 'Entfernung', 'es': 'Distancia', 'ru': 'Расстояние' },
  'ui_elongation': { 'en': 'Elongation', 'zh_CN': '距角', 'ja': '離角', 'ko': '이각', 'fr': 'Élongation', 'de': 'Elongation', 'es': 'Elongación', 'ru': 'Элонгация' },
  'ui_equatorial_coord': { 'en': 'Equatorial Coord', 'zh_CN': '赤道坐标', 'ja': '赤道座標', 'ko': '적도좌표', 'fr': 'Coord. équatoriales', 'de': 'Äquatorialkoord.', 'es': 'Coord. ecuatoriales', 'ru': 'Экв. коорд.' },
  'ui_fov': { 'en': 'FOV', 'zh_CN': '视场', 'ja': '視野', 'ko': '시야', 'fr': 'Champ', 'de': 'FoV', 'es': 'Campo', 'ru': 'Поле' },
  'ui_horizontal_coord': { 'en': 'Horizontal Coord', 'zh_CN': '地平坐标', 'ja': '地平座標', 'ko': '지평좌표', 'fr': 'Coord. horizontales', 'de': 'HorizontalKoord.', 'es': 'Coord. horizontales', 'ru': 'Гориз. коорд.' },
  'ui_magnitude': { 'en': 'Magnitude', 'zh_CN': '星等', 'ja': '等級', 'ko': '등급', 'fr': 'Magnitude', 'de': 'Magnitude', 'es': 'Magnitud', 'ru': 'Звёздная величина' },
  'ui_phase': { 'en': 'Phase', 'zh_CN': '相位', 'ja': '位相', 'ko': '위상', 'fr': 'Phase', 'de': 'Phase', 'es': 'Fase', 'ru': 'Фаза' },
  'ui_rise_transit_set': { 'en': 'Rise/Transit/Set', 'zh_CN': '升起/中天/落下', 'ja': '昇/南中/没', 'ko': '승출/남중/몰', 'fr': 'Lever/Transit/Coucher', 'de': 'Aufgang/Kulmine/Untergang', 'es': 'Orto/Tránsito/Ocaso', 'ru': 'Восх/Кульм/Заход' },
  'ui_size': { 'en': 'Size', 'zh_CN': '大小', 'ja': '大きさ', 'ko': '크기', 'fr': 'Taille', 'de': 'Größe', 'es': 'Tamaño', 'ru': 'Размер' },
  'msg_bookmark_save_failed': { 'en': 'Failed to save bookmark', 'zh_CN': '保存书签失败', 'ja': 'ブックマーク保存失敗', 'ko': '북마크 저장 실패', 'fr': 'Échec sauvegarde signet', 'de': 'Lesezeichen speichern fehlgeschlagen', 'es': 'Error al guardar marcador', 'ru': 'Ошибка сохранения закладки' },
  'msg_command_sent': { 'en': 'Command sent', 'zh_CN': '指令已发送', 'ja': 'コマンド送信済み', 'ko': '명령 전송됨', 'fr': 'Commande envoyée', 'de': 'Befehl gesendet', 'es': 'Comando enviado', 'ru': 'Команда отправлена' },
  'msg_delete_failed': { 'en': 'Delete failed', 'zh_CN': '删除失败', 'ja': '削除失敗', 'ko': '삭제 실패', 'fr': 'Échec de la suppression', 'de': 'Löschen fehlgeschlagen', 'es': 'Error al eliminar', 'ru': 'Ошибка удаления' },
  'msg_download_failed': { 'en': 'Download failed to start', 'zh_CN': '下载启动失败', 'ja': 'ダウンロード開始失敗', 'ko': '다운로드 시작 실패', 'fr': 'Échec du démarrage du téléchargement', 'de': 'Download konnte nicht gestartet werden', 'es': 'Error al iniciar descarga', 'ru': 'Ошибка запуска загрузки' },
  'msg_fetch_failed': { 'en': 'Fetch failed', 'zh_CN': '获取失败', 'ja': '取得失敗', 'ko': '가져오기 실패', 'fr': 'Échec de récupération', 'de': 'Abruf fehlgeschlagen', 'es': 'Error al obtener', 'ru': 'Ошибка получения' },
  'msg_language_switched': { 'en': 'Language', 'zh_CN': '星图语言', 'ja': '星図の言語', 'ko': '성도 언어', 'fr': 'Langue du ciel', 'de': 'Sprache', 'es': 'Idioma del cielo', 'ru': 'Язык карты' },
  'msg_navigated': { 'en': 'Navigated', 'zh_CN': '已跳转', 'ja': '移動済み', 'ko': '이동됨', 'fr': 'Navigué', 'de': 'Navigiert', 'es': 'Navegado', 'ru': 'Переход выполнен' },
  'msg_navigating': { 'en': 'Navigating...', 'zh_CN': '跳转中…', 'ja': '移動中…', 'ko': '이동 중…', 'fr': 'Navigation...', 'de': 'Navigiert...', 'es': 'Navegando...', 'ru': 'Переход...' },
  'msg_navigation_failed': { 'en': 'Navigation failed', 'zh_CN': '跳转失败', 'ja': '移動失敗', 'ko': '이동 실패', 'fr': 'Échec de la navigation', 'de': 'Navigation fehlgeschlagen', 'es': 'Error de navegación', 'ru': 'Ошибка перехода' },
  'msg_no_selection_for_tts': { 'en': 'No object selected, cannot generate speech text', 'zh_CN': '未选中天体，无法生成朗读文本', 'ja': '天体未選択、音声テキストを生成できません', 'ko': '선택된 천체 없음, 음성 텍스트를 생성할 수 없습니다', 'fr': 'Aucun objet sélectionné, impossible de générer le texte vocal', 'de': 'Kein Objekt ausgewählt, Sprachtext kann nicht generiert werden', 'es': 'Sin objeto seleccionado, no se puede generar texto de voz', 'ru': 'Объект не выбран, невозможно создать текст речи' },
  'msg_paste_config_first': { 'en': 'Please paste config.ini content first', 'zh_CN': '请先粘贴 config.ini 内容', 'ja': '先にconfig.iniの内容を貼り付けてください', 'ko': '먼저 config.ini 내용을 붙여넣으세요', 'fr': 'Veuillez d’abord coller le contenu de config.ini', 'de': 'Bitte zuerst config.ini Inhalt einfügen', 'es': 'Primero pegue el contenido de config.ini', 'ru': 'Сначала вставьте содержимое config.ini' },
  'msg_watch_pointing_started': { 'en': 'Watch pointing started', 'zh_CN': '手表指向开始', 'ja': '時計のポイント開始', 'ko': '시계 포인팅 시작', 'fr': 'Pointage de la montre commencé', 'de': 'Uhr-Zeigen gestartet', 'es': 'Apuntado de reloj iniciado', 'ru': 'Наведение с часов начато' },
}


// ═══════════════════════════════════════════════════════════════
// I18n 主类
// ═══════════════════════════════════════════════════════════════

export class I18n {
  private static lang: LangCode = 'en'

  // 设置当前语言（同时通知 AppStorage 触发 UI 重渲染）
  static setLanguage(lang: LangCode): void {
    I18n.lang = lang
    AppStorage.setOrCreate('i18nLang', lang)
  }

  // 获取当前语言
  static getLanguage(): LangCode {
    return I18n.lang
  }

  // 从 Stellarium 语言代码转换（C++ 侧用的代码可能不同）
  static fromStellariumCode(code: string): LangCode {
    const map: Record<string, LangCode> = {
      'en': 'en', 'en_US': 'en',
      'zh_CN': 'zh_CN', 'zh': 'zh_CN',
      'zh_TW': 'zh_TW', 'zh_HK': 'zh_TW',
      'ja': 'ja', 'ja_JP': 'ja',
      'ko': 'ko', 'ko_KR': 'ko',
      'fr': 'fr', 'fr_FR': 'fr',
      'de': 'de', 'de_DE': 'de',
      'es': 'es', 'es_ES': 'es',
      'ru': 'ru', 'ru_RU': 'ru',
      'pt': 'pt', 'pt_BR': 'pt',
      'it': 'it', 'it_IT': 'it',
      'nl': 'nl', 'nl_NL': 'nl',
      'pl': 'pl', 'pl_PL': 'pl',
      'tr': 'tr', 'tr_TR': 'tr',
      'ar': 'ar', 'ar_SA': 'ar',
      'hi': 'hi', 'hi_IN': 'hi',
      'th': 'th', 'th_TH': 'th',
      'vi': 'vi', 'vi_VN': 'vi',
      'id': 'id', 'id_ID': 'id',
      'uk': 'uk', 'uk_UA': 'uk',
      'sv': 'sv', 'sv_SE': 'sv',
    }
    return map[code] ?? 'en'
  }

  // 转换为 Stellarium 语言代码（发给 C++ setLanguage 命令）
  static toStellariumCode(): string {
    return I18n.lang
  }

  // 通用翻译函数
  static t(key: string): string {
    const entry = UI_STRINGS[key]
    if (!entry) return key
    return entry[I18n.lang] ?? entry['en'] ?? key
  }

  // 天体类型翻译（C++ 返回的英文类型名）
  static objectType(en: string): string {
    const entry = OBJECT_TYPES[en]
    if (!entry) return en
    return entry[I18n.lang] ?? entry['en'] ?? en
  }

  // 行星名称翻译
  static planetName(en: string): string {
    const entry = PLANET_NAMES[en]
    if (!entry) return en
    return entry[I18n.lang] ?? entry['en'] ?? en
  }

  // 卫星分组翻译
  static satGroup(en: string): string {
    const entry = SAT_GROUPS[en]
    if (!entry) return en
    return entry[I18n.lang] ?? entry['en'] ?? en
  }

  // 插件名称翻译
  static pluginName(en: string): string {
    const entry = PLUGIN_NAMES[en]
    if (!entry) return en
    return entry[I18n.lang] ?? entry['en'] ?? en
  }

  // 地景名称翻译
  static landscapeName(en: string): string {
    const entry = LANDSCAPE_NAMES[en]
    if (!entry) return en
    return entry[I18n.lang] ?? entry['en'] ?? en
  }

  // 灵敏度翻译
  static sensitivity(en: string): string {
    const entry = SENSITIVITY[en]
    if (!entry) return en
    return entry[I18n.lang] ?? entry['en'] ?? en
  }

  // 追踪状态翻译
  static trackStatus(en: string): string {
    const entry = TRACK_STATUS[en]
    if (!entry) return en
    return entry[I18n.lang] ?? entry['en'] ?? en
  }

  // 选中状态翻译
  static selectedStatus(en: string): string {
    const entry = SELECTED_STATUS[en]
    if (!entry) return en
    return entry[I18n.lang] ?? entry['en'] ?? en
  }

  // 恒星名称翻译
  static starName(en: string): string {
    const entry = STAR_NAMES[en]
    if (!entry) return en
    return entry[I18n.lang] ?? entry['en'] ?? en
  }

  // 富文本翻译（替换英文短语为当前语言）
  static richText(text: string): string {
    if (!text || text.length === 0) return ''
    let out: string = text
    // 按短语长度降序排列，避免短短语先替换导致长短语无法匹配
    const keys = Object.keys(RICH_PHRASES).sort((a, b) => b.length - a.length)
    for (const en of keys) {
      const entry = RICH_PHRASES[en]
      const translated = entry[I18n.lang] ?? entry['en'] ?? en
      if (translated !== en) {
        out = out.replace(new RegExp(en, 'gi'), translated)
      }
    }
    return out
  }
}
