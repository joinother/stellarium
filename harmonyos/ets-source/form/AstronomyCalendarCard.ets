import {
  CalendarGridCell,
  CalendarMonthGridPlan,
  CalendarMonthHighlight,
  buildAstronomyMonthGrid,
  clampCalendarMonthOffset,
  moonPhaseNameFromAge,
  parseRemindedEventIds,
  routePlanetForCard
} from './AstronomyCardData'
import {
  StarfieldLayer,
  eventAccentColor,
  orbResource,
  phaseMaskResource
} from './WidgetVisuals'
import { WIDGET_RADIUS_BADGE, WIDGET_RADIUS_PILL, WIDGET_RADIUS_ROW } from './WidgetTokens'

const calendarCardStorage: LocalStorage = new LocalStorage()
const WEEKDAY_HEADERS: string[] = ['日', '一', '二', '三', '四', '五', '六']

@Entry(calendarCardStorage)
@Component
struct AstronomyCalendarCard {
  @LocalStorageProp('observerPlanet') observerPlanet: string = 'Earth'
  @LocalStorageProp('observerPlanetName') observerPlanetName: string = '地球'
  @LocalStorageProp('moonPhase') moonPhase: string = '盈凸月'
  @LocalStorageProp('moonIllumination') moonIllumination: string = '68'
  @LocalStorageProp('moonAge') moonAge: string = '10.0'
  @LocalStorageProp('upcomingEventsJson') upcomingEventsJson: string = '[]'
  @LocalStorageProp('calendarMonthOffset') calendarMonthOffsetRaw: string = '0'
  @LocalStorageProp('remindedEventIds') remindedEventIds: string = '[]'
  @LocalStorageProp('reminderToast') reminderToast: string = ''
  @LocalStorageProp('skyHexTop') skyHexTop: string = '#070D1D'
  @LocalStorageProp('skyHexHorizon') skyHexHorizon: string = '#152442'
  @LocalStorageProp('cardThemeStyle') cardThemeStyle: string = 'sky'
  @LocalStorageProp('cardOverflowMode') cardOverflowMode: string = 'auto'

  @State cardHeight: number = 320

  private isTall(): boolean {
    return this.cardHeight >= 230
  }

  private monthOffset(): number {
    return clampCalendarMonthOffset(Number(this.calendarMonthOffsetRaw))
  }

  private plan(): CalendarMonthGridPlan {
    return buildAstronomyMonthGrid(
      Date.now(),
      this.monthOffset(),
      this.upcomingEventsJson,
      this.observerPlanet
    )
  }

  private rowIndices(rowCount: number): number[] {
    return rowCount <= 5 ? [0, 1, 2, 3, 4] : [0, 1, 2, 3, 4, 5]
  }

  private rowCells(cells: CalendarGridCell[], rowIdx: number): CalendarGridCell[] {
    const start = rowIdx * 7
    return cells.slice(start, start + 7)
  }

  private cellDotColor(cell: CalendarGridCell): string {
    if (cell.eventKind === 'eclipse') return '#FF8A65'
    if (cell.eventKind === 'meteor') return '#64B5F6'
    if (cell.eventKind === 'planet') return '#FFB74D'
    if (cell.eventKind === 'solar') return '#81C784'
    if (cell.eventKind === 'satellite') return '#4DD0E1'
    if (cell.phaseMilestone === '望') return '#FFE082'
    if (cell.phaseMilestone.length > 0) return '#C8DEFA'
    return ''
  }

  private highlightBadgeColor(kind: string): string {
    if (kind === 'eclipse') return '#FF8A65'
    if (kind === 'meteor') return '#64B5F6'
    if (kind === 'planet') return '#FFB74D'
    if (kind === 'solar') return '#81C784'
    if (kind === 'moon') return '#FFE082'
    return eventAccentColor(kind)
  }

  private stepMonth(delta: number): void {
    postCardAction(this, {
      action: 'message',
      abilityName: 'SkyInstrumentFormAbility',
      params: {
        message: 'stepCalendarMonth',
        formName: 'astronomy_calendar_card',
        deltaMonths: delta
      }
    })
  }

  private resetMonth(): void {
    postCardAction(this, {
      action: 'message',
      abilityName: 'SkyInstrumentFormAbility',
      params: {
        message: 'resetCalendarMonth',
        formName: 'astronomy_calendar_card'
      }
    })
  }

  private cyclePlanet(): void {
    postCardAction(this, {
      action: 'message',
      abilityName: 'SkyInstrumentFormAbility',
      params: {
        message: 'cyclePlanet',
        formName: 'astronomy_calendar_card',
        currentPlanet: this.observerPlanet
      }
    })
  }

  private highlightReminderId(hl: CalendarMonthHighlight): string {
    return hl.eventId.length > 0 ? hl.eventId : ('cal-hl-' + hl.key)
  }

  private isHighlightReminded(hl: CalendarMonthHighlight): boolean {
    const id = this.highlightReminderId(hl)
    return parseRemindedEventIds(this.remindedEventIds).includes(id)
  }

  private toggleHighlightReminder(hl: CalendarMonthHighlight): void {
    const atMs = Math.round((hl.jd - 2440587.5) * 86400000)
    postCardAction(this, {
      action: 'message',
      abilityName: 'SkyInstrumentFormAbility',
      params: {
        message: 'toggleEventReminder',
        formName: 'astronomy_calendar_card',
        eventId: this.highlightReminderId(hl),
        title: hl.title,
        kind: hl.kind,
        target: hl.target,
        at: atMs,
        jd: hl.jd,
        observerPlanet: routePlanetForCard(this.observerPlanet)
      }
    })
  }

  private openCalendarAt(jd: number, target: string, eventId: string): void {
    postCardAction(this, {
      action: 'router',
      abilityName: 'QAbility',
      params: {
        panel: 'calendar',
        observerPlanet: routePlanetForCard(this.observerPlanet),
        jd: Number.isFinite(jd) && jd > 0 ? jd : 0,
        target: target,
        eventId: eventId
      }
    })
  }

  private triggerOverflowOrOpen(): void {
    if (this.cardOverflowMode === 'off') {
      this.openCalendarAt(0, '', '')
      return
    }
    postCardAction(this, {
      action: 'message',
      abilityName: 'SkyInstrumentFormAbility',
      params: {
        message: 'requestOverflow',
        formName: 'astronomy_calendar_card'
      }
    })
  }

  private todayPhaseSummary(): string {
    const illumNum = Math.round(Number(this.moonIllumination))
    const ageNum = Number(this.moonAge)
    const phaseName = this.moonPhase.length > 0 ? this.moonPhase : moonPhaseNameFromAge(Number.isFinite(ageNum) ? ageNum : 10)
    if (Number.isFinite(illumNum) && illumNum >= 0 && illumNum <= 100) {
      return phaseName + ' ' + String(illumNum) + '%'
    }
    return phaseName
  }

  @Builder
  private buildMiniMoonDisc(illumination: number, age: number, size: number) {
    Stack({ alignContent: Alignment.Center }) {
      Image(orbResource('moon'))
        .width(size)
        .height(size)
        .borderRadius(size / 2)
        .objectFit(ImageFit.Cover)
      Image(phaseMaskResource(illumination, age))
        .width(size)
        .height(size)
        .borderRadius(size / 2)
        .objectFit(ImageFit.Cover)
    }
    .width(size)
    .height(size)
    .borderRadius(size / 2)
    .clip(true)
  }

  @Builder
  private buildMonthCell(cell: CalendarGridCell, compactRow: boolean) {
    if (cell.day <= 0) {
      Column()
        .layoutWeight(1)
        .height(compactRow ? 30 : 34)
    } else {
      Column({ space: 1 }) {
        // Day number (Today highlighted in luminous star-blue circular pill)
        Text(String(cell.day))
          .fontSize(compactRow ? 10.5 : 11.5)
          .fontWeight(cell.isToday ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(cell.isToday ? '#FFFFFF' : (cell.weekday === 0 || cell.weekday === 6 ? '#A6C6EA' : '#EDF4FF'))
          .textAlign(TextAlign.Center)
          .width(compactRow ? 18 : 20)
          .height(compactRow ? 16 : 18)
          .backgroundColor(cell.isToday ? '#2E7CF6' : '#00000000')
          .borderRadius(WIDGET_RADIUS_PILL)

        // Beneath day number: primary moon phase label OR real mini moon disc + celestial event dot
        Row({ space: 2 }) {
          if (cell.phaseMilestone.length > 0) {
            Text(cell.phaseMilestone)
              .fontSize(8)
              .fontWeight(FontWeight.Medium)
              .fontColor(cell.phaseMilestone === '望' ? '#FFE082' : '#B8D4F8')
              .maxLines(1)
          } else {
            this.buildMiniMoonDisc(cell.moonIllumination, cell.moonAge, compactRow ? 8 : 9)
          }
          if (cell.eventKind.length > 0 && cell.eventKind !== 'moon') {
            Column()
              .width(4)
              .height(4)
              .borderRadius(2)
              .backgroundColor(this.cellDotColor(cell))
          }
        }
        .height(10)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
      }
      .layoutWeight(1)
      .height(compactRow ? 30 : 34)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(cell.isToday ? '#262E7CF6' : (cell.eventCount > 0 ? '#14FFFFFF' : '#00000000'))
      .borderRadius(6)
      .onClick(() => this.openCalendarAt(cell.jd, cell.eventTarget, cell.eventId))
    }
  }

  @Builder
  private buildWeekCell(cell: CalendarGridCell) {
    if (cell.day <= 0) {
      Column()
        .layoutWeight(1)
        .height(54)
    } else {
      Column({ space: 3 }) {
        Text(WEEKDAY_HEADERS[cell.weekday])
          .fontSize(9)
          .fontColor(cell.isToday ? '#9CC8FF' : '#7E9DC2')
        Text(String(cell.day))
          .fontSize(12)
          .fontWeight(cell.isToday ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(cell.isToday ? '#FFFFFF' : '#EBF3FF')
          .textAlign(TextAlign.Center)
          .width(22)
          .height(20)
          .backgroundColor(cell.isToday ? '#2E7CF6' : '#00000000')
          .borderRadius(WIDGET_RADIUS_PILL)
        Row({ space: 2 }) {
          this.buildMiniMoonDisc(cell.moonIllumination, cell.moonAge, 11)
          if (cell.eventKind.length > 0 && cell.eventKind !== 'moon') {
            Column()
              .width(4)
              .height(4)
              .borderRadius(2)
              .backgroundColor(this.cellDotColor(cell))
          }
        }
        .height(12)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
      }
      .layoutWeight(1)
      .height(56)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(cell.isToday ? '#282E7CF6' : (cell.eventCount > 0 ? '#16FFFFFF' : '#0CFFFFFF'))
      .borderRadius(WIDGET_RADIUS_BADGE)
      .onClick(() => this.openCalendarAt(cell.jd, cell.eventTarget, cell.eventId))
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      StarfieldLayer({
        sunAlt: this.cardThemeStyle === 'deep' ? -30 : -22,
        themeStyle: this.cardThemeStyle === 'deep' ? 'deep' : 'sky'
      })

      // Soft celestial moonlit top-right glow
      Column()
        .width(140)
        .height(140)
        .borderRadius(WIDGET_RADIUS_PILL)
        .clip(true)
        .radialGradient({
          center: ['50%', '50%'],
          radius: 70,
          colors: [
            ['#2668A8FF', 0.0],
            ['#00000000', 1.0]
          ]
        })
        .position({ x: '66%', y: -40 })
        .hitTestBehavior(HitTestMode.None)

      Column({ space: this.isTall() ? 5 : 6 }) {
        // Header: Planet pill + Month Switcher + Today / Solar Term badge
        Row({ space: 6 }) {
          Text(this.observerPlanetName + ' · 月历 ↻')
            .fontSize(10.5)
            .fontWeight(FontWeight.Medium)
            .fontColor('#D4E8FF')
            .height(24)
            .padding({ left: 8, right: 8 })
            .backgroundColor('#28FFFFFF')
            .borderRadius(WIDGET_RADIUS_PILL)
            .maxLines(1)
            .onClick(() => this.cyclePlanet())

          Row({ space: 4 }) {
            Text('‹')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor('#CFE3FF')
              .width(22)
              .height(24)
              .textAlign(TextAlign.Center)
              .backgroundColor('#1EFFFFFF')
              .borderRadius(WIDGET_RADIUS_PILL)
              .onClick(() => this.stepMonth(-1))

            Text(this.plan().monthTitleZh)
              .fontSize(this.isTall() ? 13 : 12.5)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
              .maxLines(1)
              .onClick(() => this.triggerOverflowOrOpen())

            Text('›')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor('#CFE3FF')
              .width(22)
              .height(24)
              .textAlign(TextAlign.Center)
              .backgroundColor('#1EFFFFFF')
              .borderRadius(WIDGET_RADIUS_PILL)
              .onClick(() => this.stepMonth(1))
          }
          .alignItems(VerticalAlign.Center)

          Blank()

          if (this.monthOffset() !== 0) {
            Text('今')
              .fontSize(10)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFE09A')
              .height(22)
              .padding({ left: 7, right: 7 })
              .backgroundColor('#28FFE09A')
              .borderRadius(WIDGET_RADIUS_PILL)
              .onClick(() => this.resetMonth())
          } else if (this.plan().solarTermLabel.length > 0 && this.isTall()) {
            Text(this.plan().solarTermLabel)
              .fontSize(10)
              .fontColor('#9CD4B2')
              .height(22)
              .padding({ left: 7, right: 7 })
              .backgroundColor('#2081C784')
              .borderRadius(WIDGET_RADIUS_PILL)
              .maxLines(1)
          } else if (!this.isTall()) {
            Text(this.todayPhaseSummary())
              .fontSize(10)
              .fontColor('#CFE3FF')
              .maxLines(1)
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        if (this.isTall()) {
          // 4*4 Full Monthly Astronomy Calendar Grid
          Row({ space: 2 }) {
            ForEach(WEEKDAY_HEADERS, (wd: string, idx: number) => {
              Text(wd)
                .fontSize(9.5)
                .fontWeight(FontWeight.Medium)
                .fontColor(idx === 0 || idx === 6 ? '#9ABCE0' : '#7D99BC')
                .textAlign(TextAlign.Center)
                .layoutWeight(1)
            }, (wd: string) => wd)
          }
          .width('100%')
          .padding({ top: 1, bottom: 1 })

          Column({ space: this.plan().rowCount >= 6 ? 1.5 : 3 }) {
            ForEach(this.rowIndices(this.plan().rowCount), (rowIdx: number) => {
              Row({ space: 2 }) {
                ForEach(this.rowCells(this.plan().cells, rowIdx), (cell: CalendarGridCell) => {
                  this.buildMonthCell(cell, this.plan().rowCount >= 6)
                }, (cell: CalendarGridCell) => cell.key)
              }
              .width('100%')
            }, (rowIdx: number) => 'row-' + String(rowIdx) + '-' + String(this.plan().month) + '-' + String(this.plan().year))
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.SpaceEvenly)

          // Bottom Month Highlights Strip (up to 2 key sky events in this month, with direct one-tap reminder pill)
          if (this.plan().highlights.length > 0) {
            Row({ space: 6 }) {
              ForEach(this.plan().highlights.slice(0, 2), (hl: CalendarMonthHighlight) => {
                Row({ space: 4 }) {
                  Column()
                    .width(5)
                    .height(5)
                    .borderRadius(2.5)
                    .backgroundColor(this.highlightBadgeColor(hl.kind))
                  Text(hl.dateLabel + ' ' + hl.title)
                    .fontSize(10)
                    .fontColor('#E4F0FF')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .layoutWeight(1)
                  if ((hl.jd - 2440587.5) * 86400000 > Date.now() + 60000) {
                    Text(this.isHighlightReminded(hl) ? '★' : '约')
                      .fontSize(9.5)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.isHighlightReminded(hl) ? '#1B1404' : '#DCEEFF')
                      .textAlign(TextAlign.Center)
                      .width(20)
                      .height(18)
                      .backgroundColor(this.isHighlightReminded(hl) ? '#FFD166' : '#32FFFFFF')
                      .borderRadius(WIDGET_RADIUS_PILL)
                      .onClick(() => this.toggleHighlightReminder(hl))
                  }
                }
                .layoutWeight(1)
                .height(26)
                .padding({ left: 7, right: 5 })
                .backgroundColor('#1EFFFFFF')
                .borderRadius(WIDGET_RADIUS_ROW)
                .alignItems(VerticalAlign.Center)
                .onClick(() => this.openCalendarAt(hl.jd, hl.target, hl.eventId))
              }, (hl: CalendarMonthHighlight) => hl.key + '_' + (this.isHighlightReminded(hl) ? '1' : '0'))
            }
            .width('100%')
          } else {
            Row({ space: 6 }) {
              Text('今日月相：' + this.todayPhaseSummary() + ' · 点按任意日期直达天象日历')
                .fontSize(10)
                .fontColor('#A8C4E4')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
            }
            .width('100%')
            .height(24)
            .padding({ left: 8, right: 8 })
            .backgroundColor('#18FFFFFF')
            .borderRadius(WIDGET_RADIUS_ROW)
            .alignItems(VerticalAlign.Center)
            .onClick(() => this.openCalendarAt(0, '', ''))
          }
        } else {
          // 2*4 Compact Weekly Astronomy Calendar Strip
          Row({ space: 4 }) {
            ForEach(this.plan().weekCells, (cell: CalendarGridCell) => {
              this.buildWeekCell(cell)
            }, (cell: CalendarGridCell) => cell.key)
          }
          .width('100%')
          .layoutWeight(1)
          .alignItems(VerticalAlign.Center)

          // Bottom 1-line highlight bar
          Row({ space: 6 }) {
            if (this.plan().highlights.length > 0) {
              Column()
                .width(6)
                .height(6)
                .borderRadius(3)
                .backgroundColor(this.highlightBadgeColor(this.plan().highlights[0].kind))
              Text(this.plan().highlights[0].dateLabel + ' ' + this.plan().highlights[0].title)
                .fontSize(10.5)
                .fontColor('#EBF4FF')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
              Text('月历 ›')
                .fontSize(10)
                .fontColor('#9CC8FF')
            } else {
              Text('今日月相 ' + this.todayPhaseSummary() + ' · 点按展开完整天象月历')
                .fontSize(10.5)
                .fontColor('#C6DDF8')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
            }
          }
          .width('100%')
          .height(24)
          .padding({ left: 8, right: 8 })
          .backgroundColor('#1EFFFFFF')
          .borderRadius(WIDGET_RADIUS_ROW)
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            if (this.plan().highlights.length > 0) {
              const first = this.plan().highlights[0]
              this.openCalendarAt(first.jd, first.target, first.eventId)
            } else {
              this.openCalendarAt(0, '', '')
            }
          })
        }
      }
      .width('100%')
      .height('100%')
      .padding({ left: 11, right: 11, top: 10, bottom: 10 })
    }
    .width('100%')
    .height('100%')
    .linearGradient({
      angle: 160,
      colors: [
        [this.cardThemeStyle === 'deep' ? '#050811' : '#081024', 0.0],
        [this.cardThemeStyle === 'deep' ? '#0D1528' : '#132242', 1.0]
      ]
    })
    .border({ width: 0.6, color: '#24FFFFFF' })
    .onSizeChange((_oldSize: SizeOptions, newSize: SizeOptions) => {
      if (typeof newSize.height === 'number' && newSize.height > 0) {
        this.cardHeight = newSize.height
      }
    })
  }
}
