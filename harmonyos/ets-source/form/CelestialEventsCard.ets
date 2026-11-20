import {
  CompactEventItem,
  formatCountdownZh,
  formatPlanetDisplayList,
  formatShortDateZh,
  parseRemindedEventIds,
  parseUpcomingEvents
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
  @State heroIndex: number = 0

  private isTall(): boolean { return this.cardHeight >= 230 }

  private allEvents(): CompactEventItem[] {
    return parseUpcomingEvents(this.upcomingEventsJson)
  }

  private visibleEvents(): CompactEventItem[] {
    const all = this.allEvents()
    return this.isTall() ? all.slice(0, 4) : all.slice(0, 2)
  }

  private heroEvent(): CompactEventItem | undefined {
    const all = this.allEvents()
    if (all.length === 0) return undefined
    const safeIdx = ((this.heroIndex % all.length) + all.length) % all.length
    return all[safeIdx]
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

  private stepHero(delta: number): void {
    const count = this.allEvents().length
    if (count <= 1) return
    animateTo({ duration: 260, curve: Curve.EaseInOut }, () => {
      this.heroIndex = ((this.heroIndex + delta) % count + count) % count
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
        observerPlanet: this.observerPlanet,
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
        observerPlanet: this.observerPlanet
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

      // Subtle corner accent aurora matching focused event kind
      Circle()
        .width(130)
        .height(130)
        .fill(Color.Transparent)
        .radialGradient({
          center: ['50%', '50%'],
          radius: 65,
          colors: [
            ['#33' + this.accent().slice(1), 0.0],
            ['#00000000', 1.0]
          ]
        })
        .position({ x: '68%', y: -32 })
        .hitTestBehavior(HitTestMode.None)

      Column({ space: this.isTall() ? 10 : 6 }) {
        // Hero Next-Event Countdown Header with interactive ‹/› event pager
        Row({ space: 8 }) {
          Column({ space: 3 }) {
            Row({ space: 6 }) {
              Text(this.observerPlanetName + ' · 天象预告')
                .fontSize(10)
                .fontWeight(FontWeight.Medium)
                .fontColor('#B8D6F8')
                .maxLines(1)
              Text(eventBadgeText(this.heroKind()))
                .fontSize(10)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.accent())
                .padding({ left: 6, right: 6, top: 1, bottom: 1 })
                .backgroundColor('#26FFFFFF')
                .borderRadius(8)
              if (this.reminderToast.length > 0) {
                Text(this.reminderToast)
                  .fontSize(10)
                  .fontColor('#FFE09A')
                  .maxLines(1)
              }
            }
            Text(this.heroTitle())
              .fontSize(this.isTall() ? 17 : 15)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Row({ space: 8 }) {
            Column({ space: 2 }) {
              Row({ space: 6 }) {
                if (this.allEvents().length > 1) {
                  Text('‹')
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#E4F1FF')
                    .textAlign(TextAlign.Center)
                    .width(30)
                    .height(30)
                    .backgroundColor('#2CFFFFFF')
                    .borderRadius(15)
                    .onClick(() => this.stepHero(-1))
                }
                Text(this.heroCountdown())
                  .fontSize(this.isTall() ? 20 : 17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.accent())
                  .maxLines(1)
                if (this.allEvents().length > 1) {
                  Text('›')
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#E4F1FF')
                    .textAlign(TextAlign.Center)
                    .width(30)
                    .height(30)
                    .backgroundColor('#2CFFFFFF')
                    .borderRadius(15)
                    .onClick(() => this.stepHero(1))
                }
              }
              .alignItems(VerticalAlign.Center)

              if (this.heroAtMs() > 0) {
                Text(formatShortDateZh(this.heroAtMs()))
                  .fontSize(10)
                  .fontColor('#9ABCE0')
                  .maxLines(1)
              }
            }
            .alignItems(HorizontalAlign.End)

            Stack() {
              CelestialOrbView({
                orbBody: this.orbBody,
                orbSize: this.isTall() ? 50 : 36,
                showPhase: false,
                glowIntensity: 0.75
              })
            }
            .onClick(() => this.triggerOverflowOrOpen())
          }
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')

        // Upcoming Timeline Rows (each row routes to calendar; right bell pill toggles desktop reminder silently!)
        if (this.visibleEvents().length > 0) {
          Column({ space: this.isTall() ? 9 : 5 }) {
            ForEach(this.visibleEvents(), (ev: CompactEventItem) => {
              Row({ space: 7 }) {
                Circle()
                  .width(6)
                  .height(6)
                  .fill(eventAccentColor(ev.kind))
                Text(ev.title)
                  .fontSize(this.isTall() ? 13 : 12)
                  .fontWeight(FontWeight.Regular)
                  .fontColor('#EEF5FF')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                Text(formatShortDateZh(ev.at))
                  .fontSize(10)
                  .fontColor('#96B6DA')
                  .maxLines(1)
                // Ergonomic one-tap silent desktop reminder button (32vp tall, 58vp wide)
                Text(this.isReminded(ev.id) ? '★ 已约' : '提醒')
                  .fontSize(12)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.isReminded(ev.id) ? '#1B1404' : '#EAF4FF')
                  .textAlign(TextAlign.Center)
                  .constraintSize({ minWidth: 58 })
                  .height(this.isTall() ? 32 : 28)
                  .padding({ left: 10, right: 10 })
                  .backgroundColor(this.isReminded(ev.id) ? '#FFD166' : '#3AFFFFFF')
                  .borderRadius(16)
                  .onClick(() => this.toggleReminder(ev))
              }
              .width('100%')
              .padding({ left: 11, right: 7, top: this.isTall() ? 7 : 4, bottom: this.isTall() ? 7 : 4 })
              .backgroundColor('#22FFFFFF')
              .borderRadius(12)
              .onClick(() => this.openCalendar(ev))
            }, (ev: CompactEventItem, idx: number) => ev.id + '_' + String(idx))
          }
          .width('100%')
          .layoutWeight(this.isTall() ? 1 : 0)
          .justifyContent(this.isTall() ? FlexAlign.SpaceEvenly : FlexAlign.Start)
        } else {
          Row({ space: 8 }) {
            Text(this.dataStatus === '旧快照' ? '天象日历待同步 · 轻触打开星象仪刷新' : '轻触打开星象仪同步本月天象预告')
              .fontSize(12)
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
          .padding({ left: 12, right: 12, top: 9, bottom: 9 })
          .backgroundColor('#1EFFFFFF')
          .borderRadius(12)
        }
      }
      .width('100%')
      .height('100%')
      .padding({ left: 15, right: 14, top: 12, bottom: 11 })
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
