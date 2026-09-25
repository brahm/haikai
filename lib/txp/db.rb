module Txp
  # Thin raw-SQL layer used by the tag library (Textpattern builds its queries
  # from SQL fragments, and templates may pass SQL snippets such as sort="...").
  module DB
    module_function

    def connection
      ActiveRecord::Base.connection
    end

    def rows(sql)
      connection.select_all(sql).to_a
    end

    def row(sql)
      rows("#{sql} LIMIT 1").first
    end

    def field(sql)
      connection.select_value(sql)
    end

    def column(sql)
      connection.select_values(sql)
    end

    def execute(sql)
      connection.execute(sql)
    end

    def quote(value)
      connection.quote(value.to_s)
    end

    # SQL-escapes a string without surrounding quotes (doSlash).
    def escape(value)
      value.to_s.gsub("'", "''")
    end

    def quote_list(list, separator = ",")
      Array(list).map { |v| quote(v) }.join(separator)
    end

    def count(table, where = "1")
      field("SELECT COUNT(*) FROM #{table} WHERE #{where}").to_i
    end

    # SQL expression converting a datetime column into a UNIX timestamp.
    def timestamp(field, as = nil)
      expr = "CAST(strftime('%s', #{field}) AS INTEGER)"
      as ? "#{expr} AS #{as}" : expr
    end

    def timestamps(map)
      map.map { |f, a| timestamp(f, a) }.join(", ")
    end

    # SQL literal for a UNIX timestamp (txp_unixtime).
    def unixtime(ts)
      quote(format_time(Time.at(ts.to_i).utc))
    end

    # SQL literal for the current time (now()).
    def now(_type = nil)
      quote(format_time(Time.now.utc))
    end

    def format_time(time)
      time.utc.strftime("%Y-%m-%d %H:%M:%S")
    end

    def to_unix(value)
      case value
      when nil, "" then nil
      when Integer then value
      when Time, DateTime, ActiveSupport::TimeWithZone then value.to_i
      else
        Time.find_zone("UTC").parse(value.to_s)&.to_i
      end
    end
  end
end
