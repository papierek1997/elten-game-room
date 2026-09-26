require "date"
path = File.expand_path("../lib/game_statistics_periods.rb", __dir__)
require path if File.file?(path)

def assert(value, message)
  raise message unless value
end

assert(defined?(GameRoomStatistics::Periods), "Statistics period models are missing")
today = Date.new(2026, 1, 2)
periods = GameRoomStatistics::Periods.options(today: today, years: [])
period = periods.first
assert(period.key == "today" && period.label == "Today", "Today is not the first named period")
assert(period.from_date == today && period.to_date == today, "Today changed its civil date")
assert(period.from_day == 20260102 && period.to_day == 20260102, "Today is not an inclusive YYYYMMDD range")
[Date.new(2026, 1, 2), Date.new(2024, 3, 1), Date.new(2026, 3, 30), Date.new(2026, 10, 26)].each do |day|
  choices = GameRoomStatistics::Periods.options(today: day, years: [])
  [7, 30, 365].each do |length|
    rolling = choices.find { |item| item.key == "last_#{length}" }
    assert(rolling, "The last #{length} days are missing")
    assert(rolling.from_date == day - (length - 1) && rolling.to_date == day,
      "Rolling days excluded today or used elapsed hours across a leap year/DST boundary")
    assert(rolling.label == "Last #{length} days (including today)", "Rolling label does not explain inclusion of today")
  end
end
choices = GameRoomStatistics::Periods.options(today: today, years: [2024, 2025, 2024])
assert(choices.map(&:key) == %w[today last_7 last_30 last_365 year_2026 year_2025 year_2024 all_time],
  "Calendar years are missing, duplicated or not newest first")
year = choices.find { |item| item.key == "year_2024" }
assert(year.label == "2024" && year.from_day == 20240101 && year.to_day == 20241231,
  "A calendar year is not the complete inclusive January-December range")
assert(periods.any? { |item| item.key == "year_2026" }, "No data hides the current calendar year")
assert(choices.last.label == "All time" && choices.last.from_date.nil? && choices.last.from_day.nil? &&
  choices.last.to_day == 20260102, "All time must have an unbounded start and include today")
assert(GameRoomStatistics::Periods.respond_to?(:today), "Warsaw civil-date clock is missing")
zone = ENV["TZ"]
{
  Time.utc(2026, 1, 1, 23, 30) => Date.new(2026, 1, 2),
  Time.utc(2026, 7, 1, 22, 30) => Date.new(2026, 7, 2),
  Time.utc(2026, 3, 28, 22, 30) => Date.new(2026, 3, 28),
  Time.utc(2026, 3, 29, 22, 30) => Date.new(2026, 3, 30),
  Time.utc(2026, 10, 24, 22, 30) => Date.new(2026, 10, 25),
  Time.utc(2026, 10, 25, 22, 30) => Date.new(2026, 10, 25)
}.each do |instant, expected|
  assert(GameRoomStatistics::Periods.today(clock: -> { instant }) == expected,
    "Warsaw date used the system time zone or a fixed offset")
end
assert(ENV["TZ"] == zone, "Warsaw conversion changed the process time zone")
puts "PASS statistics periods"
