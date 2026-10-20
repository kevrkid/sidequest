# How well known each place and sight is (0-100), from data/popular.json (written by rank_popular.rb). The map draws
# the best-known ones first and fills in the rest as you zoom in. Reloaded when the file changes; 0 when unranked.
require 'json'

module Popular
  FILE = ENV['SQ_POPULAR_FILE'] ? File.join(__dir__, ENV['SQ_POPULAR_FILE']) : File.join(__dir__, 'data', 'popular.json')
  @scores = {}; @mtime = nil
  @lock = Mutex.new

  def self.scores
    @lock.synchronize do
      m = File.file?(FILE) ? File.mtime(FILE) : nil
      if m != @mtime
        @mtime = m
        @scores = m ? (JSON.parse(File.read(FILE))['scores'] rescue {}) : {}
      end
      @scores
    end
  end

  def self.[](id) scores[id.to_s] || 0 end
end
