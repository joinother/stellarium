import { AstronomyCalendarEvent, CalendarDay, calendarMonth, calendarDays, calendarDayEvents } from './AstronomyCalendarEvent'

@Observed
export class AstronomyCalendarStore {
  year: number = new Date().getFullYear()
  month: number = new Date().getMonth() + 1
  selectedDay: number = 0
  selectedEventId: string = ''
  events: AstronomyCalendarEvent[] = []
  days: CalendarDay[] = calendarDays(calendarMonth(this.year, this.month), [])
  loading: boolean = false
  loaded: boolean = false
  error: string = ''
  coverage: string = ''
  sourceYear: number = 0
  actionMessage: string = ''
  reminderPendingId: string = ''
  throughYear: number = this.year
  throughMonth: number = this.month
  loadingMore: boolean = false

  visibleEvents(): AstronomyCalendarEvent[] {
    return calendarDayEvents(this.events, this.selectedDay)
  }

  selectedEvents(): AstronomyCalendarEvent[] {
    return this.events.filter((event: AstronomyCalendarEvent) => event.id === this.selectedEventId)
  }
}
