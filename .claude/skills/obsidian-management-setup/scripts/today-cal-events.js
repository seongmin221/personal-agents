#!/usr/bin/osascript -l JavaScript
// today-cal-events.js — print today's events from the given work calendars/accounts.
// Usage:
//   osascript -l JavaScript today-cal-events.js "<cal1,cal2,...>" "<account1,account2,...>"
// Both args are comma-separated; either may be empty. Prints one normalized line per
// event (sorted: start-time ascending, all-day first on ties):
//   (종일) <title>            for all-day events
//   HH:MM-HH:MM <title>       for timed events  (HH:MM <title> if zero-length)
// Uses EventKit directly, so recurring events are expanded into today's occurrences
// (osascript->Calendar.app and icalBuddy both mishandle this) and it runs under the
// terminal app's existing Calendar permission (status is normally already authorized).
ObjC.import('EventKit')
ObjC.import('Foundation')

function run(argv) {
  const targetCals = (argv[0] || '').split(',').map(s => s.trim()).filter(Boolean)
  const targetAccts = (argv[1] || '').split(',').map(s => s.trim()).filter(Boolean)
  if (targetCals.length === 0 && targetAccts.length === 0) return '' // nothing to collect

  const store = $.EKEventStore.alloc.init
  const status = $.EKEventStore.authorizationStatusForEntityType($.EKEntityTypeEvent)
  // 0=notDetermined 1=restricted 2=denied 3/4=authorized(full)
  if (status === 2 || status === 1) {
    return 'ERROR: Calendar access not authorized (TCC status ' + status +
           '). Grant the terminal app Calendar access in System Settings > Privacy & Security > Calendars.'
  }

  const cals = store.calendarsForEntityType($.EKEntityTypeEvent)
  const chosen = []
  const n = cals.count
  for (let i = 0; i < n; i++) {
    const c = cals.objectAtIndex(i)
    const name = c.title.js
    let acct = ''
    try { acct = c.source.title.js } catch (e) {}
    if (targetCals.indexOf(name) >= 0 || targetAccts.indexOf(acct) >= 0) chosen.push(c)
  }
  if (chosen.length === 0) return '' // filter matched no calendars

  const cal = $.NSCalendar.currentCalendar
  const start = cal.startOfDayForDate($.NSDate.date)
  const comps = $.NSDateComponents.alloc.init
  comps.day = 1
  const end = cal.dateByAddingComponentsToDateOptions(comps, start, 0)

  const pred = store.predicateForEventsWithStartDateEndDateCalendars(start, end, $(chosen))
  const events = store.eventsMatchingPredicate(pred)

  const tf = $.NSDateFormatter.alloc.init
  tf.dateFormat = 'HH:mm'

  const rows = []
  const m = events.count
  for (let i = 0; i < m; i++) {
    const e = events.objectAtIndex(i)
    const allday = e.isAllDay
    const s = tf.stringFromDate(e.startDate).js
    const en = tf.stringFromDate(e.endDate).js
    rows.push({ title: e.title.js, sd: e.startDate, s: s, e: en, allday: allday })
  }
  rows.sort((a, b) => a.allday === b.allday ? a.sd.compare(b.sd) : (a.allday ? -1 : 1))

  return rows.map(r =>
    r.allday ? '(종일) ' + r.title
             : (r.s === r.e ? r.s + ' ' + r.title : r.s + '-' + r.e + ' ' + r.title)
  ).join('\n')
}
