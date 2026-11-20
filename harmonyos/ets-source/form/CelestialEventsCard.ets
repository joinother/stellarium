import {
  CompactEventItem,
  UpcomingEventPage,
  formatCountdownZh,
  formatPlanetDisplayList,
  formatShortDateZh,
  parseRemindedEventIds,
  parseUpcomingEvents,
  routePlanetForCard,
  sliceUpcomingEventPage
} from './AstronomyCardData'
import {
  CelestialOrbView,
  StarfieldLayer,
  eventAccentColor,
  eventBadgeText
} from './WidgetVisuals'

const eventsCardStorage: LocalStorage = new LocalStorage()

@Entry(eventsCardStorage)
@Component
struct CelestialEventsCard {
  @LocalStorageProp('observerPlanet') observerPlanet: string = 'Earth'
  @LocalStorageProp('observerPlanetName') observerPlanetName: string = '地球'
  @LocalStorageProp('orbBody') orbBody: string = 'moon'
  @LocalStorageProp('nextEventTitle') nextEventTitle: string = '等待星历同步'
  @LocalStorageProp('nextEventKind') nextEventKind: string = 'sky'
  @LocalStorageProp('nextEventAt') nextEventAt: string = '0'
  @LocalStorageProp('nextEventJd') nextEventJd: string = '0'
  @LocalStorageProp('nextEventTarget') nextEventTarget: string = ''
  @LocalStorageProp('nextEventCountdown') nextEventCountdown: string = '查看日历'
  @LocalStorageProp('upcomingEventsJson') upcomingEventsJson: string = '[]'
  @LocalStorageProp('visiblePlanetsJson') visiblePlanetsJson: string = '[]'
  @LocalStorageProp('planetNames') planetNames: string = ''
  @LocalStorageProp('remindedEventIds') remindedEventIds: string = '[]'
  @LocalStorageProp('reminderToast') reminderToast: string = ''
  @LocalStorageProp('skyHexTop') skyHexTop: string = '#070D1D'
  @LocalStorageProp('skyHexHorizon') skyHexHorizon: string = '#152442'
  @LocalStorageProp('dataStatus') dataStatus: string = '本地快照'
  @LocalStorageProp('cardThemeStyle') cardThemeStyle: string = 'sky'
  @LocalStorageProp('cardLabelStyle') cardLabelStyle: string = 'name'
  @LocalStorageProp('cardOverflowMode') cardOverflowMode: string = 'auto'

  @State cardHeight: number = 160
  @State listPageIndex: number = 0

  private isTall(): boolean { return this.cardHeight >= 230 }

  private allEvents(): CompactEventItem[] {
    return parseUpcomingEvents(this.upcomingEventsJson)
  }

  private currentPage(): UpcomingEventPage {
    return sliceUpcomingEventPage(this.allEvents(), this.listPageIndex, this.isTall() ? 4 : 2)
  }

  private heroEvent(): CompactEventItem | undefined {
    return this.currentPage().hero
  }

  private subsequentEvents(): CompactEventItem[] {
    return this.currentPage().items
  }

  private heroTitle(): string {
    const ev = this.heroEvent()
    return ev !== undefined ? ev.title : this.nextEventTitle
  }

  private heroKind(): string {
    const ev = this.heroEvent()
    return ev !== undefined ? ev.kind : this.nextEventKind
  }

  private heroAtMs(): number {
    const ev = this.heroEvent()
    return ev !== undefined ? ev.at : Number(this.nextEventAt)
  }

  private heroCountdown(): string {
    const ev = this.heroEvent()
    return ev !== undefined ? formatCountdownZh(ev.at, Date.now()) : this.nextEventCountdown
  }

  private accent(): string {
    return eventAccentColor(this.heroKind())
  }

  private isReminded(eventId: string): boolean {
    if (eventId.length === 0) return false
    const ids = parseRemindedEventIds(this.remindedEventIds)
    return ids.includes(eventId)
  }

  private stepListPage(delta: number): void {
    const page = this.currentPage()
    if (page.pageCount <= 1) return
    animateTo({ duration: 240, curve: Curve.EaseInOut }, () => {
      this.listPageIndex = ((page.pageIndex + delta) % page.pageCount + page.pageCount) % page.pageCount
    })
  }

  private cyclePlanet(): void {
    this.listPageIndex = 0
    postCardAction(this, {
      action: 'message',
      abilityName: 'SkyInstrumentFormAbility',
      params: {
        message: 'cyclePlanet',
        formName: 'celestial_events_card',
        currentPlanet: this.observerPlanet
      }
    })
  }

  private openCalendar(ev?: CompactEventItem): void {
    const picked = ev !== undefined ? ev : this.heroEvent()
    const jdVal = picked !== undefined ? picked.jd : Number(this.nextEventJd)
    postCardAction(this, {
      action: 'router',
      abilityName: 'QAbility',
      params: {
        panel: 'calendar',
        observerPlanet: routePlanetForCard(this.observerPlanet),
        eventId: picked !== undefined ? picked.id : '',
        target: picked !== undefined ? picked.target : this.nextEventTarget,
        jd: Number.isFinite(jdVal) && jdVal > 0 ? jdVal : 0
      }
    })
  }

  private toggleReminder(ev: CompactEventItem): void {
    postCardAction(this, {
      action: 'message',
      abilityName: 'SkyInstrumentFormAbility',
      params: {
        message: 'toggleEventReminder',
        formName: 'celestial_events_card',
        eventId: ev.id,
        title: ev.title,
        kind: ev.kind,
        target: ev.target,
        at: ev.at,
        jd: ev.jd,
        observerPlanet: routePlanetForCard(this.observerPlanet)
      }
    })
  }

  private triggerOverflowOrOpen(): void {
    if (this.cardOverflowMode === 'off') {
      this.openCalendar()
      return
    }
    postCardAction(this, {
      action: 'message',
      abilityName: 'SkyInstrumentFormAbility',
      params: {
        message: 'requestOverflow',
        formName: 'celestial_events_card'
      }
    })
  }

  private planetBarText(): string {
    return formatPlanetDisplayList(this.visiblePlanetsJson, this.planetNames, this.cardLabelStyle)
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      StarfieldLayer({ sunAlt: -24, themeStyle: 'deep' })

      // Subtle corner accent aurora matching focused event kind (clipped circularly — zero square edge)
      Column()
        .width(130)
        .height(130)
        .borderRadius(65)
        .clip(true)
        .radialGradient({
          center: ['50%', '50%'],
          radius: 65,
          colors: [
            ['#2C' + this.accent().slice(1), 0.0],
            ['#00000000', 1.0]
          ]
        })
        .position({ x: '68%', y: -32 })
        .hitTestBehavior(HitTestMode.None)

      Column({ space: this.isTall() ? 8 : 4 }) {
        // Hero Spotlight: Nearest upcoming event (NEVER duplicated in the subsequent list below!)
        Row({ space: 8 }) {
          Column({ space: 2 }) {
            Row({ space: 6 }) {
              Text(this.observerPlanetName + ' · 天象 ↻')
                .fontSize(10)
                .fontWeight(FontWeight.Medium)
                .fontColor('#D4E8FF')
                .height(22)
                .padding({ left: 8, right: 8 })
                .backgroundColor('#28FFFFFF')
                .borderRadius(11)
                .maxLines(1)
                .onClick(() => this.cyclePlanet())
              Text(eventBadgeText(this.heroKind()))
                .fontSize(10)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.accent())
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .backgroundColor('#22FFFFFF')
                .borderRadius(8)
              if (this.reminderToast.length > 0) {
                Text(this.reminderToast)
                  .fontSize(10)
                  .fontColor('#FFE09A')
                  .maxLines(1)
              }
            }
            Text(this.heroTitle())
              .fontSize(this.isTall() ? 16 : 14)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Row({ space: 7 }) {
            Column({ space: 1 }) {
              Text(this.heroCountdown())
                .fontSize(this.isTall() ? 18 : 15)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.accent())
                .maxLines(1)
              if (this.heroAtMs() > 0) {
                Text(formatShortDateZh(this.heroAtMs()))
                  .fontSize(10)
                  .fontColor('#9ABCE0')
                  .maxLines(1)
              }
            }
            .alignItems(HorizontalAlign.End)

            // Direct reminder pill for the #1 hero event so it never needs to be duplicated in the list
            if (this.heroEvent() !== undefined) {
              Text(this.isReminded(this.heroEvent()!.id) ? '★ 已约' : '提醒')
                .fontSize(11)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.isReminded(this.heroEvent()!.id) ? '#1B1404' : '#EAF4FF')
                .textAlign(TextAlign.Center)
                .constraintSize({ minWidth: 52 })
                .height(28)
                .padding({ left: 9, right: 9 })
                .backgroundColor(this.isReminded(this.heroEvent()!.id) ? '#FFD166' : '#3AFFFFFF')
                .borderRadius(14)
                .onClick(() => {
                  const ev = this.heroEvent()
                  if (ev !== undefined) this.toggleReminder(ev)
                })
            }

            Stack() {
              CelestialOrbView({
                orbBody: this.orbBody,
                orbSize: this.isTall() ? 46 : 34,
                showPhase: false,
                glowIntensity: 0.75
              })
            }
            .onClick(() => this.triggerOverflowOrOpen())
          }
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')

        // Subsequent Events Paginated Timeline (starts at Event #2; ‹ 1/N › ONLY appears when more pages exist!)
        if (this.subsequentEvents().length > 0) {
          if (this.currentPage().pageCount > 1) {
            Row({ space: 6 }) {
              Text('后续天象 · 共 ' + String(this.allEvents().length - 1) + ' 场')
                .fontSize(10)
                .fontWeight(FontWeight.Regular)
                .fontColor('#8FB4DA')
                .maxLines(1)
              Blank()
              Row({ space: 5 }) {
                Text('‹')
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#E4F1FF')
                  .textAlign(TextAlign.Center)
                  .width(26)
                  .height(22)
                  .backgroundColor('#2CFFFFFF')
                  .borderRadius(11)
                  .onClick(() => this.stepListPage(-1))
                Text(String(this.currentPage().pageIndex + 1) + '/' + String(this.currentPage().pageCount))
                  .fontSize(10)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#C6E0FA')
                  .maxLines(1)
                Text('›')
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#E4F1FF')
                  .textAlign(TextAlign.Center)
                  .width(26)
                  .height(22)
                  .backgroundColor('#2CFFFFFF')
                  .borderRadius(11)
                  .onClick(() => this.stepListPage(1))
              }
              .alignItems(VerticalAlign.Center)
            }
            .width('100%')
          }

          Column({ space: this.isTall() ? 8 : 4 }) {
            ForEach(this.subsequentEvents(), (ev: CompactEventItem) => {
              Row({ space: 7 }) {
                Circle()
                  .width(6)
                  .height(6)
                  .fill(eventAccentColor(ev.kind))
                Text(ev.title)
                  .fontSize(this.isTall() ? 13 : 11)
                  .fontWeight(FontWeight.Regular)
                  .fontColor('#EEF5FF')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                Text(formatShortDateZh(ev.at))
                  .fontSize(10)
                  .fontColor('#96B6DA')
                  .maxLines(1)
                Text(this.isReminded(ev.id) ? '★ 已约' : '提醒')
                  .fontSize(11)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.isReminded(ev.id) ? '#1B1404' : '#EAF4FF')
                  .textAlign(TextAlign.Center)
                  .constraintSize({ minWidth: 52 })
                  .height(this.isTall() ? 30 : 25)
                  .padding({ left: 9, right: 9 })
                  .backgroundColor(this.isReminded(ev.id) ? '#FFD166' : '#3AFFFFFF')
                  .borderRadius(14)
                  .onClick(() => this.toggleReminder(ev))
              }
              .width('100%')
              .padding({ left: 10, right: 6, top: this.isTall() ? 6 : 3, bottom: this.isTall() ? 6 : 3 })
              .backgroundColor('#22FFFFFF')
              .borderRadius(11)
              .onClick(() => this.openCalendar(ev))
            }, (ev: CompactEventItem, idx: number) => ev.id + '_' + String(this.listPageIndex) + '_' + String(idx))
          }
          .width('100%')
          .layoutWeight(this.isTall() ? 1 : 0)
          .justifyContent(this.isTall() ? FlexAlign.SpaceEvenly : FlexAlign.Start)
        } else {
          Row({ space: 8 }) {
            Text(this.allEvents().length === 1
              ? '近期仅此 1 场重点天象 · 轻触查看完整年历'
              : (this.dataStatus === '旧快照' ? '天象日历待同步 · 轻触打开星象仪刷新' : '轻触打开星象仪同步本月天象预告'))
              .fontSize(11)
              .fontColor('#B0CCE8')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
          .padding({ left: 10, right: 10, top: 10, bottom: 10 })
          .backgroundColor('#1AFFFFFF')
          .borderRadius(12)
        }

        if (this.isTall()) {
          Row({ space: 6 }) {
            Text('可见行星')
              .fontSize(10)
              .fontColor('#88B0D4')
            Text(this.planetBarText())
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor('#E4F1FF')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .backgroundColor('#1EFFFFFF')
          .borderRadius(12)
        }
      }
      .width('100%')
      .height('100%')
      .padding({ left: 14, right: 13, top: 10, bottom: 9 })
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
      if (typeof newSize.height === 'number' && newSize.height > 0) this.cardHeight = newSize.height
    })
    .onClick(() => this.openCalendar())
  }
}
