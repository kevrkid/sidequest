# Sights & history (data/sights.json from fetch_sights.rb): Texas historical markers, National Register places,
# Wikipedia landmarks, museums, viewpoints and public art. Loaded once and reloaded when the file changes.
require 'json'

module Sights
  FILE = ENV['SQ_SIGHTS_FILE'] ? File.join(__dir__, ENV['SQ_SIGHTS_FILE']) : File.join(__dir__, 'data', 'sights.json')
  KINDS = %w[marker landmark museum art nature venue view sight].freeze
  # What people say → words in the official names
  ALIASES = {
    /\bcapitol\b|capital building|state house/i => 'texas state capitol', /\bacl live\b|moody theat/i => 'acl live',
    /\bacl\b|austin city limits/i => 'austin city limits', /\bmuny\b|lions (municipal )?golf/i => 'lions municipal golf',
    /zilker golf|butler pitch/i => 'butler pitch', /\bbat(s)? bridge\b|congress (ave(nue)? )?bridge/i => 'congress avenue bridge',
    /\b(6th|sixth) st(reet)?\b/i => 'sixth street', /\but tower\b|main building/i => 'main building',
    /barton springs/i => 'barton springs', /mount bonnell|mt\.? bonnell/i => 'mount bonnell', /treaty oak/i => 'treaty oak',
    /moon ?light towers?/i => 'moonlight tower', /governor'?s mansion/i => 'governor s mansion', /\blbj\b/i => 'lyndon baines johnson',
    /bullock/i => 'bullock', /driskill/i => 'driskill', /paramount/i => 'paramount theatre', /o\.? ?henry/i => 'o henry',
    /rainey/i => 'rainey street', /pennybacker|360 bridge/i => 'pennybacker bridge', /deep eddy/i => 'deep eddy',
    /state cemetery/i => 'texas state cemetery', /french legation/i => 'french legation', /elisabet ney/i => 'elisabet ney'
  }.freeze
  STOP = %w[the a an of in on at to is was what whats who whos where wheres when how tell me about history historic historical
            story behind info information famous sightseeing sights sight see seeing visit places place things thing do near
            here around austin texas tx any some cool best fun interesting old oldest built building buildings and or for with
            from that this there their it its my i we you can could should give show list lived live people person marker markers
            landmark landmarks tour tourist go]

  @data = nil; @mtime = nil
  @lock = Mutex.new

  def self.list
    @lock.synchronize do
      m = File.file?(FILE) ? File.mtime(FILE) : nil
      if m != @mtime
        @mtime = m
        @data = m ? (JSON.parse(File.read(FILE))['sights'] rescue []) : []
        @by_id = @data.to_h { |s| [s['id'], s] }
      end
      @data
    end
  end

  def self.find(id) list; @by_id[id.to_s] end

  def self.km(a, b, c, d)
    dy = (a - c) * 110.57; dx = (b - d) * 111.32 * Math.cos(a * Math::PI / 180)
    Math.hypot(dx, dy)
  end

  def self.norm(s) s.to_s.downcase.gsub(/&/, 'and').gsub(/[^a-z0-9]+/, ' ').strip end

  # For the map: just what a dot needs. The story itself comes from /api/sight per tap.
  def self.for_map
    list.map { |s| [s['id'], s['kind'], s['name'], s['lat'], s['lng'], s['year'] || s['listed'], s['photo'] ? 1 : 0] }
  end

  # Search by name (with the aliases above), else nearest. Rich entries (a story to tell) come first.
  def self.search(q, near: nil, limit: 10)
    words = norm(q).split - STOP
    phrases = ALIASES.select { |re, _| q =~ re }.map(&:last)
    scored = list.map do |s|
      n = " #{norm(s['name'])} "
      score = phrases.sum { |p| n.include?(" #{p}") ? 10 : 0 }
      score += words.sum { |w| w.size < 3 ? 0 : n.include?(" #{w}") ? 3 : (s['text'].to_s.downcase.include?(w) ? 0.5 : 0) }
      [s, score]
    end
    named = scored.select { |_, sc| sc >= 3 }
    c = near || [30.2672, -97.7431]
    rich = ->(s) { (s['text'] ? 2 : 0) + (s['src'] == 'wikipedia' ? 1 : 0) + (s['rthl'] ? 1 : 0) }
    rows = if named.any?
             named.sort_by { |s, sc| [-sc, -rich.(s), km(c[0], c[1], s['lat'], s['lng'])] }.map(&:first)
           else   # "history near me", "what should I see": the nearest ones worth a story
             list.select { |s| s['text'] && km(c[0], c[1], s['lat'], s['lng']) < 6 }
                 .sort_by { |s| km(c[0], c[1], s['lat'], s['lng']) - rich.(s) * 0.4 }
           end
    [rows.first(limit), named.any?]
  end
end
