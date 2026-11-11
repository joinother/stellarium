export function calendarText(language: string, chinese: string, english: string): string {
  return language.toLowerCase().startsWith('zh') ? chinese : english
}

export function calendarMonthTitle(language: string, year: number, month: number): string {
  return calendarText(language, `${year} 年 ${month} 月`, `${year}-${String(month).padStart(2, '0')}`)
}

export function calendarWeekdays(language: string): string[] {
  return language.toLowerCase().startsWith('zh') ? ['日', '一', '二', '三', '四', '五', '六'] :
    ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa']
}

export function calendarSolarTermTitle(language: string, index: number): string {
  const chinese: string[] = ['小寒', '大寒', '立春', '雨水', '惊蛰', '春分', '清明', '谷雨',
    '立夏', '小满', '芒种', '夏至', '小暑', '大暑', '立秋', '处暑', '白露', '秋分', '寒露', '霜降', '立冬', '小雪', '大雪', '冬至']
  const english: string[] = ['Minor Cold', 'Major Cold', 'Start of Spring', 'Rain Water', 'Awakening of Insects',
    'March equinox', 'Clear and Bright', 'Grain Rain', 'Start of Summer', 'Grain Full', 'Grain in Ear', 'June solstice',
    'Minor Heat', 'Major Heat', 'Start of Autumn', 'End of Heat', 'White Dew', 'September equinox', 'Cold Dew',
    'Frost Descent', 'Start of Winter', 'Minor Snow', 'Major Snow', 'December solstice']
  return index >= 0 && index < 24 ? calendarText(language, chinese[index], english[index]) : ''
}

export function calendarMoonPhaseTitle(language: string, index: number): string {
  const chinese: string[] = ['新月', '上弦', '满月', '下弦']
  const english: string[] = ['New moon', 'First quarter', 'Full moon', 'Last quarter']
  return index >= 0 && index < 4 ? calendarText(language, chinese[index], english[index]) : ''
}
