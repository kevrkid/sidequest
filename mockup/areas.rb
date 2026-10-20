# Austin's neighborhoods, main streets and nearby towns (data/areas.json from fetch_areas.rb), so Scout can find
# "a good spot in Hyde Park". Reloaded when the file changes.
require 'json'

module Areas
  FILE = ENV['SQ_AREAS_FILE'] ? File.join(__dir__, ENV['SQ_AREAS_FILE']) : File.join(__dir__, 'data', 'areas.json')
  @list = []; @mtime = nil
  @lock = Mutex.new

  def self.list
    @lock.synchronize do
      m = File.file?(FILE) ? File.mtime(FILE) : nil
      if m != @mtime
        @mtime = m
        @list = m ? (JSON.parse(File.read(FILE))['areas'] rescue []) : []
      end
      @list
    end
  end

  def self.norm(s) s.to_s.downcase.gsub(/[’'.]/, '').gsub(/[^a-z0-9]+/, ' ').strip end

  # The area named in a question, longest name first ("East Cesar Chavez" over "Cesar Chavez"), or nil
  def self.find(q)
    t = " #{norm(q)} "
    list.flat_map { |a| ([a['name']] + (a['aka'] || [])).map { |n| [norm(n), a] } }
        .select { |n, _| n.size >= 4 && t.include?(" #{n} ") }.max_by { |n, _| n.size }&.last
  end
end
