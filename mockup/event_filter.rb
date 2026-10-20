# What the events service sends, cleaned up before the app sees it: kids' activities are left out (Side Quest is for
# adults going out: no storytimes, toddler raves or homeschool classes), then the spots get fixed (geofix.rb).
require 'json'
require_relative 'geofix'

module EventFilter
  # Clearly for children. Not "family", "baby" or "teen" on their own: "Faith & Family Night" is a volleyball game,
  # "Cry Baby Tour" a concert and "a 2004 teen slasher script" a grown-up theater night.
  KIDS = /\b(kids?|kid'?s|children'?s?|child|toddlers?|preschool(ers)?|story\s?time|homeschool(ers|ing)?|tweens?|(for|calling\sall)\steens|teens?\s(ages?|program|club|only|night|and\stweens)|
          little\s(ones|builders)|books\sand\sbabies|babies\s(from|ages?)|ages?\s\d{1,2}\s?(-|–|to)\s?\d{1,2}|grades?\s(k|pre-?k|\d{1,2})\b|k-12|
          trunk[-\s]or[-\s]treat|truck[-\s]or[-\s]treat|make\s(&|and)\splay|tutoring|stroller|lego)\b/ix   # x: spaces are \s
  # Kids' events say so in the title or the first line of the description. The scrapers' "family" category also
  # covers things for everyone ("Dia de los Muertos ... family-friendly"), so it only counts with a kids word or
  # "Family" in the title ("Family Drum and Dance Workshop").
  def self.kids?(e)
    head = "#{e['title']} #{e['description'].to_s[0, 160]}"
    head =~ KIDS || (e['category'] == 'family' && e['title'].to_s =~ /\bfamily\b/i) ? true : false
  end

  def self.clean(body)
    j = JSON.parse(body)
    list = j.is_a?(Hash) ? j['events'] : j
    return body unless list.is_a?(Array)
    list.reject! { |e| kids?(e) }
    Geofix.fix_body(JSON.generate(j))
  rescue JSON::ParserError
    body
  end
end
