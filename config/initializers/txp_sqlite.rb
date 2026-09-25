# Registers MySQL-compatible SQL functions on every SQLite connection so that
# Textpattern templates and queries using them (sort="rand()",
# FIELD(ID, 3, 1, 2), FIND_IN_SET(), UNIX_TIMESTAMP()...) keep working.
module TxpSqliteFunctions
  FORMAT = "%Y-%m-%d %H:%M:%S".freeze

  def self.to_time(value)
    return nil if value.nil? || value.to_s.empty?
    return Time.at(value).utc if value.is_a?(Numeric)

    Time.find_zone("UTC").parse(value.to_s)
  rescue ArgumentError
    nil
  end

  def self.mysql_to_strftime(format)
    map = {
      "%i" => "%M", "%s" => "%S", "%M" => "%B", "%b" => "%b", "%W" => "%A", "%a" => "%a",
      "%c" => "%-m", "%e" => "%-d", "%D" => "%-d", "%k" => "%-H", "%l" => "%-I", "%h" => "%I",
      "%r" => "%I:%M:%S %p", "%T" => "%H:%M:%S", "%u" => "%W", "%v" => "%V", "%x" => "%G", "%X" => "%Y"
    }
    format.to_s.gsub(/%[a-zA-Z%]/) { |m| map.fetch(m, m) }
  end

  def self.register(db)
    db.create_function("FIELD", -1) do |func, *args|
      needle = args.shift
      idx = args.index { |a| a.to_s == needle.to_s }
      func.result = idx ? idx + 1 : 0
    end

    db.create_function("FIND_IN_SET", 2) do |func, needle, list|
      idx = list.to_s.split(",").index(needle.to_s)
      func.result = idx ? idx + 1 : 0
    end

    db.create_function("RAND", -1) { |func, *_| func.result = rand }

    db.create_function("NOW", 0) { |func| func.result = Time.now.utc.strftime(FORMAT) }

    db.create_function("UNIX_TIMESTAMP", -1) do |func, *args|
      func.result = args.empty? ? Time.now.to_i : to_time(args.first)&.to_i
    end

    db.create_function("FROM_UNIXTIME", -1) do |func, ts, *fmt|
      t = ts.nil? ? nil : Time.at(ts.to_i).utc
      func.result = t && (fmt.empty? ? t.strftime(FORMAT) : t.strftime(mysql_to_strftime(fmt.first)))
    end

    db.create_function("DATE_FORMAT", 2) do |func, value, fmt|
      t = to_time(value)
      func.result = t&.strftime(mysql_to_strftime(fmt))
    end

    { "YEAR" => "%Y", "MONTH" => "%m", "DAY" => "%d", "DAYOFMONTH" => "%d", "HOUR" => "%H",
      "MINUTE" => "%M", "WEEK" => "%U", "DAYOFYEAR" => "%j" }.each do |name, f|
      db.create_function(name, 1) do |func, value|
        t = to_time(value)
        func.result = t && t.strftime(f).to_i
      end
    end

    db.create_function("QUARTER", 1) do |func, value|
      t = to_time(value)
      func.result = t && ((t.month - 1) / 3) + 1
    end

    db.create_function("REGEXP", 2) do |func, pattern, value|
      func.result = begin
        Regexp.new(pattern.to_s, Regexp::IGNORECASE).match?(value.to_s) ? 1 : 0
      rescue RegexpError
        0
      end
    end

    db.create_function("CHAR_LENGTH", 1) { |func, v| func.result = v.to_s.length }
    db.create_function("LEFT", 2) { |func, v, n| func.result = v.to_s[0, n.to_i] }
    db.create_function("RIGHT", 2) { |func, v, n| func.result = n.to_i.zero? ? "" : v.to_s[-n.to_i..] || v.to_s }
    db.create_function("CONCAT_WS", -1) { |func, sep, *args| func.result = args.compact.join(sep.to_s) }

    # Search relevance used for sort="score" on search result pages.
    db.create_function("TXP_SCORE", -1) do |func, query, *cols|
      terms = query.to_s.downcase.split(/\s+/).reject(&:empty?)
      score = 0
      cols.each_with_index do |col, i|
        text = col.to_s.downcase
        weight = i.zero? ? 3 : 1
        terms.each { |t| score += text.scan(t).length * weight }
      end
      func.result = score
    end
  end
end

ActiveSupport.on_load(:active_record_sqlite3adapter) do
  prepend(Module.new do
    def configure_connection
      super
      TxpSqliteFunctions.register(@raw_connection)
    end
  end)
end
