# Reads OpenStreetMap opening_hours into a weekly schedule, by hand (no gems).
#
# A schedule is a sorted list of [start, end] minutes from Monday 00:00 (0...10080). Overnight hours
# ("Fr-Sa 17:00-02:00") run into the next day; Sunday night wraps to Monday morning. Anything we
# can't read with confidence (months, sunset, "10:00+", "by appointment", school holidays…) comes
# back as nil, which the app shows as "hours unknown" rather than a guess. Public-holiday rules
# ("PH off") are ignored because we don't track holidays.
module Hours
  DAYS = %w[Mo Tu We Th Fr Sa Su].freeze
  WEEK = 7 * 1440
  DAY = /(?:Mo|Tu|We|Th|Fr|Sa|Su|PH|SH)/
  SELECTOR = /\A((?:#{DAY}(?:\s*-\s*#{DAY})?(?:\s*,\s*)?)+)\s*(.*)\z/
  UNSUPPORTED = /\b(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec|week|sunrise|sunset|dawn|dusk|easter|appointment|unknown)\b|["\[\]+]/i

  module_function

  def parse(text)
    s = text.to_s.strip
    return nil if s.empty?
    return [[0, WEEK]] if s =~ %r{\A24/7\z} || s =~ /\AMo-Su 00:00-24:00\z/
    days = Array.new(7)
    # rules are separated by ";" (or "||"), and sometimes by ", " when a new day list starts after a
    # time or "off" ("Mo-Fr 06:00-14:00, Sa 07:00-13:00"); a comma inside a day list ("Sa,Su") is not a break
    rules = s.split(/\s*;\s*|\s*\|\|\s*/).flat_map { |r| r.split(/(?<=\d|off|closed)\s*,\s*(?=(?:Mo|Tu|We|Th|Fr|Sa|Su|PH|SH)\b)/) }
    applied = false
    rules.each do |rule|
      rule = rule.strip
      next if rule.empty?
      return nil if rule =~ UNSUPPORTED
      sel, rest = (m = rule.match(SELECTOR)) ? [m[1], m[2].strip] : [nil, rule]
      target = sel ? days_of(sel) : (0..6).to_a
      next if target.empty?   # holiday-only rule
      intervals =
        if rest =~ /\A(off|closed)\z/i then []
        elsif rest.empty? || rest =~ %r{\A24/7\z} then [[0, 1440]]   # "Sa-Su" alone means open all day
        else times(rest) || (return nil)
        end
      target.each { |d| days[d] = intervals }
      applied = true
    end
    return nil unless applied
    week = []
    days.each_with_index do |ivs, d|
      (ivs || []).each do |a, b|
        s0 = d * 1440 + a
        e0 = d * 1440 + b
        e0 > WEEK ? (week << [s0, WEEK] << [0, e0 - WEEK]) : week << [s0, e0]
      end
    end
    merge(week)
  end

  def days_of(sel)
    out = []
    sel.split(',').map(&:strip).reject(&:empty?).each do |tok|
      next if tok =~ /\A(PH|SH)\z/
      a, b = tok.split(/\s*-\s*/)
      i = DAYS.index(a) or next
      j = b ? DAYS.index(b) : i
      return [] unless j
      loop { out << i; break if i == j; i = (i + 1) % 7 }   # wraps: Su-Th
    end
    out.uniq
  end

  def times(rest)
    rest.split(/\s*,\s*/).map do |span|
      m = span.match(/\A(\d{1,2}):(\d{2})\s*-\s*(\d{1,2}):(\d{2})\z/) or return nil
      a = m[1].to_i * 60 + m[2].to_i
      b = m[3].to_i * 60 + m[4].to_i
      return nil if a > 1440 || b > 2880
      b += 1440 if b <= a   # closes after midnight
      [a, b]
    end
  end

  def merge(list)
    list.sort.each_with_object([]) do |(a, b), out|
      if out.any? && a <= out.last[1] then out.last[1] = [out.last[1], b].max
      else out << [a, b]
      end
    end
  end

  # Minutes since Monday 00:00 for a Time (use Austin local time).
  def minute_of_week(t)
    ((t.wday + 6) % 7) * 1440 + t.hour * 60 + t.min
  end

  # {state: 'open'|'soon'|'closed'|'unknown', until:/opens: minute-of-week, in: minutes away}
  def status(week, now)
    return { state: 'unknown' } unless week
    return { state: 'open', always: true } if week == [[0, WEEK]]
    cur = week.find { |a, b| a <= now && now < b }
    if cur
      ends = cur[1]
      ends = WEEK + week.first[1] if ends == WEEK && week.first[0].zero?   # Sunday night into Monday
      return { state: 'open', until: ends % WEEK, in: ends - now }
    end
    nxt = week.map { |a, _| a > now ? a : a + WEEK }.min
    { state: nxt - now <= 60 ? 'soon' : 'closed', opens: nxt % WEEK, in: nxt - now }
  end

  def clock(mow)
    h, m = (mow % 1440).divmod(60)
    ampm = h < 12 ? 'AM' : 'PM'
    h12 = h % 12
    h12 = 12 if h12.zero?
    return 'midnight' if h.zero? && m.zero?
    m.zero? ? "#{h12} #{ampm}" : format('%d:%02d %s', h12, m, ampm)
  end
end
