import { AstronomyCalendarEvent, CalendarDay, calendarMonth, calendarDays, calendarDayEvents } from './AstronomyCalendarEvent'
import { CalendarFilterState, filterCalendarEvents } from './AstronomyCalendarFilter'

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
  observerPlanet: string = 'Earth'
  selectedCategories: string[] = []
  satelliteSubFilter: string = 'all'
  highlightOnly: boolean = false
  satellitePassesLoading: boolean = false
  filterRevision: number = 0

  filterState(): CalendarFilterState {
    return {
      selectedCategories: this.selectedCategories,
      satelliteSubFilter: this.satelliteSubFilter,
      highlightOnly: this.highlightOnly
    }
  }

  filteredEvents(): AstronomyCalendarEvent[] {
    return filterCalendarEvents(this.events, this.filterState(), this.observerPlanet)
  }

  visibleEvents(): AstronomyCalendarEvent[] {
    return calendarDayEvents(this.filteredEvents(), this.selectedDay)
  }

  selectedEvents(): AstronomyCalendarEvent[] {
    return this.events.filter((event: AstronomyCalendarEvent) => event.id === this.selectedEventId)
  }
}
