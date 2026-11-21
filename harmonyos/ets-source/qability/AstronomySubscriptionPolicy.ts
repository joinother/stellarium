import { AstronomyCalendarEvent } from '../state/AstronomyCalendarEvent'
import { NotificationPreferenceSnapshot, isQuietMinute } from './AstronomyNotificationPolicy'
import { ContentNotice, validContentNotice } from '../state/OnlineContentContract'
import {
  SubscriptionTopicFlags,
  eventMatchesTopicFlags,
  normalizeTimingMode,
  resolveReminderTimingPlan
} from './AstronomyNotificationTiming'

export type AstronomySubscriptionCategory = 'astronomy' | 'satellite'

export interface AstronomySubscriptionFeed {
  events: AstronomyCalendarEvent[]
  generatedAt: number
  observerKey?: string
}

export function topicFlagsFromPreferences(preferences: NotificationPreferenceSnapshot): SubscriptionTopicFlags {
  const astroOn = preferences.astronomyEventsEnabled
  return {
    meteor: preferences.topicMeteor !== undefined ? preferences.topicMeteor : astroOn,
    planet: preferences.topicPlanet !== undefined ? preferences.topicPlanet : astroOn,
    moon: preferences.topicMoon !== undefined ? preferences.topicMoon : astroOn,
    solarTerm: preferences.topicSolarTerm !== undefined ? preferences.topicSolarTerm : astroOn,
    satellite: preferences.satellitePassEnabled === true,
    highlightOnly: preferences.highlightOnly === true
  }
}

export function acceptsRemoteAstronomyMessage(message: ContentNotice, preferences: NotificationPreferenceSnapshot,
  consent: boolean, notificationsEnabled: boolean, now: number): boolean {
  if (!consent || !notificationsEnabled || preferences.subscriptionsVersion !== 1 || !validContentNotice(message, now)) return false
  const date = new Date(now)
  if (preferences.dndEnabled && preferences.dndSatelliteOnly !== true && isQuietMinute(date.getHours() * 60 + date.getMinutes(),
    preferences.dndStartMinutes, preferences.dndEndMinutes)) return false
  return message.category === 'astronomy' ? preferences.astronomyEventsEnabled :
    message.category === 'digest' && preferences.digestEnabled === true
}

export function subscriptionCandidates(feed: AstronomySubscriptionFeed, category: AstronomySubscriptionCategory,
  preferences: NotificationPreferenceSnapshot, now: number, until: number): AstronomyCalendarEvent[] {
  if (!feed || !Array.isArray(feed.events) || !Number.isFinite(feed.generatedAt) ||
    Math.abs(feed.generatedAt - now) > 300000 ||
    (category === 'satellite' && (typeof feed.observerKey !== 'string' || !feed.observerKey.trim()))) {
    throw new Error('订阅数据不可用，请检查观测地点与本地数据。')
  }
  const flags = topicFlagsFromPreferences(preferences)
  const timingMode = normalizeTimingMode(preferences.timingMode)
  const seen = new Set<string>()
  const selected: AstronomyCalendarEvent[] = []
  for (const event of feed.events) {
    if (!event || typeof event.id !== 'string' || !event.id.trim() || typeof event.title !== 'string' || !event.title.trim() ||
      !Number.isFinite(event.at) || !Number.isFinite(event.jd) || Math.abs((event.jd - 2440587.5) * 86400000 - event.at) > 1000 ||
      typeof event.target !== 'string' || typeof event.kind !== 'string' ||
      (category === 'satellite' ? event.kind !== 'satellite-pass' : event.kind === 'satellite-pass' || event.kind === 'digest')) {
      throw new Error('订阅数据不可用，请检查观测地点与本地数据。')
    }
    if (category === 'astronomy' && !eventMatchesTopicFlags(event, flags)) continue
    const plan = resolveReminderTimingPlan(event, {
      nowMs: now,
      timingMode: timingMode,
      passLeadMinutes: preferences.passLeadMinutes,
      regionId: preferences.regionId,
      dndEnabled: preferences.dndEnabled,
      dndSatelliteOnly: preferences.dndSatelliteOnly,
      dndStartMinutes: preferences.dndStartMinutes,
      dndEndMinutes: preferences.dndEndMinutes
    })
    if (plan.skippedByQuietHours) continue
    if (plan.fireAt <= now + 30000 || event.at >= until) continue
    const key = event.kind + ':' + event.id + ':' + Math.floor(event.at / 1000)
    if (seen.has(key)) continue
    seen.add(key)
    selected.push(event)
  }
  return selected.sort((left: AstronomyCalendarEvent, right: AstronomyCalendarEvent) =>
    Number(left.kind === 'solar-term') - Number(right.kind === 'solar-term') || left.at - right.at)
    .slice(0, 6).sort((left: AstronomyCalendarEvent, right: AstronomyCalendarEvent) => left.at - right.at)
}
