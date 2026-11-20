import {
  CompactEventItem,
  formatCountdownZh,
  formatPlanetDisplayList,
  formatShortDateZh,
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
  @LocalStorageProp('skyHexTop') skyHexTop: string = '#070D1D'
  @LocalStorageProp('skyHexHorizon') skyHexHorizon: string = '#152442'
  @LocalStorageProp('dataStatus') dataStatus: string = '本地快照'
  @LocalStorageProp('cardThemeStyle') cardThemeStyle: string = 'sky'
  @LocalStorageProp('cardLabelStyle') cardLabelStyle: string = 'name'
  @LocalStorageProp('cardOverflowMode') cardOverflowMode: string = 'auto'

  @State cardHeight: number = 160

  private isTall(): boolean { return this.cardHeight >= 230 }

  private events(): CompactEventItem[] {
    const all = parseUpcomingEvents(this.upcomingEventsJson)
    return this.isTall() ? all.slice(0, 4) : all.slice(0, 2)
  }

  private accent(): string {
    return eventAccentColor(this.nextEventKind)
  }

  private openCalendar(ev?: CompactEventItem): void {
    const jdVal = ev !== undefined ? ev.jd : Number(this.nextEventJd)
    postCardAction(this, {
      action: 'router',
      abilityName: 'QAbility',
      params: {
        panel: 'calendar',
        observerPlanet: this.observerPlanet,
        eventId: ev !== undefined ? ev.id : '',
        target: ev !== undefined ? ev.target : this.nextEventTarget,
        jd: Number.isFinite(jdVal) && jdVal > 0 ? jdVal : 0
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

      // Subtle corner accent aurora matching upcoming event kind
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

      Column({ space: this.isTall() ? 10 : 7 }) {
        // Hero Next-Event Countdown Header
        Row({ space: 10 }) {
          Column({ space: 3 }) {
            Row({ space: 6 }) {
              Text(this.observerPlanetName + ' · 天象预告')
                .fontSize(10)
                .fontWeight(FontWeight.Medium)
                .fontColor('#B8D6F8')
                .maxLines(1)
              Text(eventBadgeText(this.nextEventKind))
                .fontSize(10)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.accent())
                .padding({ left: 6, right: 6, top: 1, bottom: 1 })
                .backgroundColor('#26FFFFFF')
                .borderRadius(8)
            }
            Text(this.nextEventTitle)
              .fontSize(this.isTall() ? 17 : 15)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Row({ space: 6 }) {
            Column({ space: 1 }) {
              Text(this.nextEventCountdown)
                .fontSize(this.isTall() ? 22 : 19)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.accent())
                .maxLines(1)
              if (Number(this.nextEventAt) > 0) {
                Text(formatShortDateZh(Number(this.nextEventAt)))
                  .fontSize(10)
                  .fontColor('#9ABCE0')
                  .maxLines(1)
              }
            }
            .alignItems(HorizontalAlign.End)

            Stack() {
              CelestialOrbView({
                orbBody: this.orbBody,
                orbSize: this.isTall() ? 52 : 38,
                showPhase: false,
                glowIntensity: 0.75
              })
            }
            .onClick(() => this.triggerOverflowOrOpen())
          }
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')

        // Upcoming Timeline Rows (each independently clickable)
        if (this.events().length > 0) {
          Column({ space: this.isTall() ? 9 : 5 }) {
            ForEach(this.events(), (ev: CompactEventItem) => {
              Row({ space: 8 }) {
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
                Text(formatCountdownZh(ev.at, Date.now()))
                  .fontSize(10)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(eventAccentColor(ev.kind))
                  .maxLines(1)
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: this.isTall() ? 11 : 6, bottom: this.isTall() ? 11 : 6 })
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
      .padding({ left: 15, right: 14, top: 13, bottom: 12 })
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
