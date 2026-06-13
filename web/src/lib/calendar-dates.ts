const MS_PER_DAY = 86_400_000

const monthNameFormatter = new Intl.DateTimeFormat('en-US', {
  month: 'long',
})

const fullDateFormatter = new Intl.DateTimeFormat('en-US', {
  weekday: 'long',
  year: 'numeric',
  month: 'long',
  day: 'numeric',
})

export type CalendarRange = {
  start: Date
  end: Date
  weekCount: number
  todayWeekIndex: number
}

export function toLocalDate(date: Date) {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate())
}

export function addDays(date: Date, amount: number) {
  const next = toLocalDate(date)
  next.setDate(next.getDate() + amount)
  return toLocalDate(next)
}

export function addYears(date: Date, amount: number) {
  const year = date.getFullYear() + amount
  const month = date.getMonth()
  const day = Math.min(date.getDate(), daysInMonth(year, month))

  return new Date(year, month, day)
}

export function startOfMondayWeek(date: Date) {
  const localDate = toLocalDate(date)
  const daysSinceMonday = (localDate.getDay() + 6) % 7

  return addDays(localDate, -daysSinceMonday)
}

export function endOfMondayWeek(date: Date) {
  return addDays(startOfMondayWeek(date), 6)
}

export function getCalendarRange(today: Date): CalendarRange {
  const localToday = toLocalDate(today)
  const start = startOfMondayWeek(addYears(localToday, -10))
  const end = endOfMondayWeek(addYears(localToday, 10))
  const todayWeekStart = startOfMondayWeek(localToday)
  const weekCount = Math.floor(differenceInCalendarDays(end, start) / 7) + 1
  const todayWeekIndex = Math.floor(differenceInCalendarDays(todayWeekStart, start) / 7)

  return {
    start,
    end,
    weekCount,
    todayWeekIndex,
  }
}

export function differenceInCalendarDays(left: Date, right: Date) {
  return dateToUtcDayNumber(left) - dateToUtcDayNumber(right)
}

export function isSameCalendarDate(left: Date, right: Date) {
  return differenceInCalendarDays(left, right) === 0
}

export function isWeekend(date: Date) {
  const day = date.getDay()

  return day === 0 || day === 6
}

export function formatVisibleMonth(date: Date) {
  return `${date.getFullYear()} ${monthNameFormatter.format(date)}`
}

export function formatFullDate(date: Date) {
  return fullDateFormatter.format(date)
}

export function toISODate(date: Date) {
  const year = date.getFullYear().toString().padStart(4, '0')
  const month = (date.getMonth() + 1).toString().padStart(2, '0')
  const day = date.getDate().toString().padStart(2, '0')

  return `${year}-${month}-${day}`
}

function daysInMonth(year: number, month: number) {
  return new Date(year, month + 1, 0).getDate()
}

function dateToUtcDayNumber(date: Date) {
  return Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()) / MS_PER_DAY
}
