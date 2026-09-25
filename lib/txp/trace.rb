module Txp
  # Port of Textpattern's Trace class (lib/class.trace.php). Outside live
  # mode public pages end with a "Trace summary" HTML comment (run time, SQL
  # queries, memory, pages and forms used); debug mode adds the tags used and
  # a full trace log.
  class Trace
    def initialize
      @big_bang = now
      @queries = 0
      @query_time = 0.0
      @trace = []
      @nest = []
      @stats = { "Pages" => [], "Forms" => [], "Tags" => [] }
    end

    def start(msg, stats = nil)
      @nest.push(@trace.size)
      add(msg, stats: stats)
    end

    # Closes the innermost entry; +msg+ (e.g. the closing tag) is logged after.
    def stop(msg = nil)
      start = @nest.pop
      @trace[start][:end] = now if start
      add(msg) if msg
    end

    def log(msg, stats = nil)
      add(msg, stats: stats)
    end

    # Records an SQL query that took +duration+ seconds.
    def query(sql, duration)
      @queries += 1
      @query_time += duration
      finish = now
      @trace << { level: @nest.size, begin: finish - duration, end: finish, query: true, msg: "[SQL: #{sql} ]" }
    end

    def summary
      summary = {
        "Runtime" => "#{format('%4.2f', (now - @big_bang) * 1000)} ms",
        "Query time" => "#{format('%4.2f', @query_time * 1000)} ms",
        "Queries" => @queries,
        "Memory (*)" => "#{peak_memory_kb} kB"
      }

      @stats.each do |key, values|
        next if values.empty?

        if key == "Tags"
          # array_count_values() + arsort() (stable since PHP 8).
          counts = values.tally.each_with_index.sort_by { |(_tag, count), i| [ -count, i ] }.map(&:first)
          summary["Tags (#{values.size})"] = counts.map { |tag, count| "#{tag} (#{count})" }.join(", ")
        else
          summary[key] = values.join(", ")
        end
      end

      out("Trace summary:\n#{summary.map { |k, v| format("%-10s: %s\n", k, v) }.join}")
    end

    def result
      tracelog = +"Trace log:\n  Time(ms) | Duration | Trace\n"
      querylog = +"Query log:\nDuration | Query\n"

      @trace.each do |t|
        tracelog << format("  %8.2f | ", (t[:begin] - @big_bang) * 1000)
        line = t[:end] ? format("%8.2f | ", (t[:end] - t[:begin]) * 1000) : "#{' ' * 8} | "
        querylog << "#{line}#{t[:msg]}\n" if t[:query]
        tracelog << "#{line}#{"\t" * t[:level]}#{t[:msg]}\n"
      end

      out(tracelog) + (@queries.positive? ? out(querylog) : "")
    end

    private

    def add(msg, stats: nil)
      @trace << { level: @nest.size, begin: now, query: false, msg: msg.to_s }
      stats&.each { |key, values| (@stats[key] ||= []).concat(Array(values)) }
    end

    def out(str)
      "\n<!-- #{str.gsub('--', '- - ')}-->\n"
    end

    def now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def peak_memory_kb
      File.read("/proc/self/status")[/^VmHWM:\s+(\d+)/, 1].to_i
    rescue StandardError
      0
    end
  end
end
