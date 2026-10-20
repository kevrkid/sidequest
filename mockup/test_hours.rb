# ruby test_hours.rb: checks the opening-hours reader against real-world OpenStreetMap strings.
require_relative 'hours'

MON, TUE, WED, THU, FRI, SAT, SUN = (0..6).map { |d| d * 1440 }
at = ->(day, hhmm) { h, m = hhmm.split(':').map(&:to_i); day + h * 60 + m }
fails = 0
check = lambda do |hours, when_, want, label = nil|
  got = Hours.status(Hours.parse(hours), when_)
  ok = want.all? { |k, v| got[k] == v }
  fails += 1 unless ok
  puts "#{ok ? 'PASS' : 'FAIL'}  #{(label || hours).ljust(52)} → #{got}#{ok ? '' : "  (wanted #{want})"}"
end

check.('Mo-Fr 07:00-15:00; Sa,Su 08:00-14:00', at.(TUE, '10:00'), { state: 'open', until: at.(TUE, '15:00') })
check.('Mo-Fr 07:00-15:00; Sa,Su 08:00-14:00', at.(SAT, '07:30'), { state: 'soon', opens: at.(SAT, '08:00') })
check.('Mo-Fr 07:00-15:00; Sa,Su 08:00-14:00', at.(SUN, '16:00'), { state: 'closed', opens: at.(MON, '07:00') }, 'Sunday evening → opens Monday')
check.('Fr-Sa 17:00-02:00', at.(SAT, '01:30'), { state: 'open', until: at.(SAT, '02:00') }, 'late night: Friday into Saturday')
check.('Fr-Sa 17:00-02:00', at.(SUN, '01:00'), { state: 'open', until: at.(SUN, '02:00') }, 'late night: Saturday into Sunday')
check.('Fr-Sa 17:00-02:00', at.(SUN, '03:00'), { state: 'closed' })
check.('Mo-Su 11:00-02:00', at.(MON, '00:30'), { state: 'open', until: at.(MON, '02:00') }, 'Sunday night wraps into Monday')
check.('Mo-Su 11:00-02:00', at.(SUN, '23:00'), { state: 'open', until: at.(MON, '02:00') })
check.('24/7', at.(WED, '04:00'), { state: 'open', always: true })
check.('Mo-Th 11:00-22:00; Fr-Sa 11:00-24:00; Su off', at.(SAT, '23:59'), { state: 'open', until: at.(SUN, '00:00') })
check.('Mo-Th 11:00-22:00; Fr-Sa 11:00-24:00; Su off', at.(SUN, '12:00'), { state: 'closed', opens: at.(MON, '11:00') })
check.('Tu-Su 11:00-14:00,17:00-22:00; Mo off', at.(WED, '15:00'), { state: 'closed', opens: at.(WED, '17:00') }, 'lunch + dinner, closed between')
check.('Tu-Su 11:00-14:00,17:00-22:00; Mo off', at.(WED, '16:30'), { state: 'soon' })
check.('Su-Th 07:00-21:00; Fr-Sa 07:00-23:00', at.(SUN, '20:00'), { state: 'open', until: at.(SUN, '21:00') }, 'Su-Th wraps across the week')
check.('Mo-Fr 06:00-14:00, Sa 07:00-13:00', at.(SAT, '08:00'), { state: 'open', until: at.(SAT, '13:00') }, 'comma between rules')
check.('11:00-23:00', at.(THU, '22:00'), { state: 'open', until: at.(THU, '23:00') }, 'no days = every day')
check.('Mo-Sa 10:00-21:00; Su 12:00-18:00; PH off', at.(SUN, '13:00'), { state: 'open' }, 'holiday rule ignored')
check.('Mo-Fr 18:00-02:00; Sa 12:00-03:00; Su 12:00-24:00', at.(MON, '01:00'), { state: 'closed' }, 'Su till midnight, not into Monday')
check.('Mo-Fr 18:00-02:00; Sa 12:00-03:00; Su 12:00-24:00', at.(SUN, '02:30'), { state: 'open', until: at.(SUN, '03:00') })
check.('Mo-Su 07:00-02:00; Fr,Sa 07:00-03:00', at.(SAT, '02:30'), { state: 'open', until: at.(SAT, '03:00') }, 'later rule overrides Friday')
# honest unknowns
['Mo-Fr 10:00+', 'sunrise-sunset', 'Jan-Mar Mo-Fr 08:00-17:00', '"by appointment"', 'Mo-Fr 08:00-17:00 [1]', 'whenever', ''].each do |h|
  check.(h, at.(MON, '12:00'), { state: 'unknown' }, "unknown: #{h.inspect}")
end
puts "clock: #{[0, 90, 720, 1290, 1440 + 120].map { |m| Hours.clock(m) }.join(', ')}"
puts fails.zero? ? "\nAll opening-hours tests passed." : "\n#{fails} FAILED"
exit(fails.zero? ? 0 : 1)
