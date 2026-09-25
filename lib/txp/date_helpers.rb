module Txp
  # Date formatting (safe_strftime / since) and parsing (strtotime subset).
  module DateHelpers
    NAMES = {
      "en" => {
        months: %w[January February March April May June July August September October November December],
        abbr_months: %w[Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec],
        days: %w[Sunday Monday Tuesday Wednesday Thursday Friday Saturday],
        abbr_days: %w[Sun Mon Tue Wed Thu Fri Sat],
        ampm: %w[AM PM]
      },
      "pt" => {
        months: %w[janeiro fevereiro março abril maio junho julho agosto setembro outubro novembro dezembro],
        abbr_months: %w[jan fev mar abr mai jun jul ago set out nov dez],
        days: %w[domingo segunda-feira terça-feira quarta-feira quinta-feira sexta-feira sábado],
        abbr_days: %w[dom seg ter qua qui sex sáb],
        ampm: %w[AM PM]
      },
      "es" => {
        months: %w[enero febrero marzo abril mayo junio julio agosto septiembre octubre noviembre diciembre],
        abbr_months: %w[ene feb mar abr may jun jul ago sept oct nov dic],
        days: %w[domingo lunes martes miércoles jueves viernes sábado],
        abbr_days: %w[dom lun mar mié jue vie sáb],
        ampm: %w[a.\ m. p.\ m.]
      },
      "fr" => {
        months: %w[janvier février mars avril mai juin juillet août septembre octobre novembre décembre],
        abbr_months: %w[janv. févr. mars avr. mai juin juil. août sept. oct. nov. déc.],
        days: %w[dimanche lundi mardi mercredi jeudi vendredi samedi],
        abbr_days: %w[dim. lun. mar. mer. jeu. ven. sam.],
        ampm: %w[AM PM]
      },
      "de" => {
        months: %w[Januar Februar März April Mai Juni Juli August September Oktober November Dezember],
        abbr_months: %w[Jan. Feb. März Apr. Mai Juni Juli Aug. Sept. Okt. Nov. Dez.],
        days: %w[Sonntag Montag Dienstag Mittwoch Donnerstag Freitag Samstag],
        abbr_days: %w[So. Mo. Di. Mi. Do. Fr. Sa.],
        ampm: %w[AM PM]
      }
    }.freeze

    def site_zone
      @site_zone ||= Txp.zone(@prefs)
    end

    def local_time(ts)
      site_zone.at(ts.to_i)
    end

    def date_names(locale = nil)
      locale = (locale.presence || lang).to_s.downcase
      NAMES[locale] || NAMES[locale.split(/[-_@]/).first] || NAMES["en"]
    end

    # since(): "3 hours ago"
    def since(stamp)
      diff = Time.now.to_i - stamp.to_i

      if diff <= 3600
        qty = (diff / 60.0).round
        if qty < 1
          qty = ""
          period = gTxt("a_few_seconds")
        else
          period = gTxt(qty == 1 ? "minute" : "minutes")
        end
      elsif diff <= 86_400
        qty = (diff / 3600.0).round
        qty = 1 if qty <= 1
        period = gTxt(qty == 1 ? "hour" : "hours")
      else
        qty = (diff / 86_400.0).round
        qty = 1 if qty <= 1
        period = gTxt(qty == 1 ? "day" : "days")
      end

      gTxt("ago", "{qty}" => qty.to_s, "{period}" => period).strip
    end

    NAMED_FORMATS = %w[atom w3cdtf rss cookie w3c iso8601 rfc822 rfc7231].freeze

    def safe_strftime(format, time = nil, gmt = false, locale = "")
      time = time.nil? ? Time.now.to_i : Php.intval(time)
      format = Php.str(format)
      utc = Time.at(time).utc

      case format
      when "since" then return since(time)
      when "atom", "w3cdtf", "w3c" then return utc.strftime("%Y-%m-%dT%H:%M:%S+00:00")
      when "rss" then return utc.strftime("%a, %d %b %Y %H:%M:%S +0000")
      when "cookie" then return utc.strftime("%A, %d-%b-%Y %H:%M:%S UTC")
      when "iso8601" then return utc.strftime("%Y-%m-%dT%H:%M:%S+0000")
      when "rfc822" then return utc.strftime("%a, %d %b %y %H:%M:%S +0000")
      when "rfc7231" then return utc.strftime("%a, %d %b %Y %H:%M:%S GMT")
      end

      t = gmt ? utc : local_time(time)
      names = date_names(locale.to_s.split("@").first)

      if !format.include?("%")
        icu_format(t, format, names)
      elsif !format.match?(/%[aAbBchOxX]/) && !locale.to_s.include?("calendar")
        # Numeric formats go through PHP's date() in Textpattern.
        php_date(format.gsub(DATE_MAP_RE) { |m| DATE_MAP[m] }, t)
      else
        pattern = format.gsub(INTL_MAP_RE) { |m| INTL_MAP[m] }
        pattern = pattern.gsub("%s", t.to_i.to_s)
        pattern = pattern.gsub(/%[cxX]/) { |m| intl_default_pattern(m, names) }
        icu_format(t, pattern, names)
      end
    end

    INTL_MAP = {
      "%a" => "eee", "%A" => "eeee", "%d" => "dd", "%e" => "d", "%Oe" => "d", "%j" => "D", "%u" => "c", "%w" => "e",
      "%U" => "w", "%V" => "ww", "%W" => "ww", "%b" => "MMM", "%B" => "MMMM", "%h" => "MMM", "%m" => "MM",
      "%g" => "yy", "%G" => "Y", "%Y" => "y", "%y" => "yy", "%H" => "HH", "%k" => "H", "%I" => "hh", "%l" => "h",
      "%M" => "mm", "%S" => "ss", "%p" => "a", "%P" => "a", "%r" => "h:mm:ss a", "%R" => "HH:mm", "%T" => "HH:mm:ss",
      "%z" => "Z", "%Z" => "z", "%D" => "MM/dd/yy", "%F" => "yy-MM-dd", "%n" => "\n", "%t" => "\t", "%%" => "%"
    }.freeze
    INTL_MAP_RE = Regexp.union(INTL_MAP.keys.sort_by { |k| -k.length })

    DATE_MAP = {
      "%a" => "D", "%A" => "l", "%d" => "d", "%e" => "j", "%Oe" => "jS", "%j" => "z", "%u" => "N", "%w" => "w",
      "%U" => "W", "%V" => "W", "%W" => "W", "%b" => "M", "%B" => "F", "%h" => "M", "%m" => "m", "%g" => "y",
      "%G" => "o", "%Y" => "Y", "%y" => "y", "%H" => "H", "%k" => "G", "%I" => "h", "%l" => "g", "%M" => "i",
      "%S" => "s", "%p" => "A", "%P" => "a", "%r" => "g:i:s A", "%R" => "H:i", "%T" => "H:i:s", "%z" => "O",
      "%Z" => "T", "%D" => "m/d/y", "%F" => "Y-m-d", "%s" => "U", "%n" => "\n", "%t" => "\t", "%%" => "%"
    }.freeze
    DATE_MAP_RE = Regexp.union(DATE_MAP.keys.sort_by { |k| -k.length })

    INTL_DEFAULTS = {
      "en" => { date: "MMMM d, y", time: "h:mm a", both: "MMMM d, y 'at' h:mm a" },
      "pt" => { date: "d 'de' MMMM 'de' y", time: "HH:mm", both: "d 'de' MMMM 'de' y 'às' HH:mm" },
      "es" => { date: "d 'de' MMMM 'de' y", time: "H:mm", both: "d 'de' MMMM 'de' y, H:mm" },
      "fr" => { date: "d MMMM y", time: "HH:mm", both: "d MMMM y 'à' HH:mm" },
      "de" => { date: "d. MMMM y", time: "HH:mm", both: "d. MMMM y 'um' HH:mm" }
    }.freeze

    def intl_default_pattern(code, names)
      key = NAMES.key(names) || "en"
      d = INTL_DEFAULTS[key] || INTL_DEFAULTS["en"]
      { "%c" => d[:both], "%x" => d[:date], "%X" => d[:time] }[code]
    end

    PHP_DAYS = %w[Sunday Monday Tuesday Wednesday Thursday Friday Saturday].freeze
    PHP_MONTHS = %w[January February March April May June July August September October November December].freeze

    # PHP date() formatter (English names, like PHP).
    def php_date(format, t)
      out = +""
      chars = format.chars
      i = 0
      while i < chars.length
        c = chars[i]
        if c == "\\"
          i += 1
          out << chars[i].to_s
          i += 1
          next
        end

        out << case c
        when "d" then t.strftime("%d")
        when "D" then PHP_DAYS[t.wday][0, 3]
        when "j" then t.day.to_s
        when "l" then PHP_DAYS[t.wday]
        when "N" then (t.wday.zero? ? 7 : t.wday).to_s
        when "S" then ordinal_day(t.day).sub(/\A\d+/, "")
        when "w" then t.wday.to_s
        when "z" then (t.yday - 1).to_s
        when "W" then t.strftime("%V")
        when "F" then PHP_MONTHS[t.month - 1]
        when "m" then t.strftime("%m")
        when "M" then PHP_MONTHS[t.month - 1][0, 3]
        when "n" then t.month.to_s
        when "t" then Time.days_in_month(t.month, t.year).to_s
        when "L" then Date.leap?(t.year) ? "1" : "0"
        when "o" then t.strftime("%G")
        when "Y" then t.year.to_s
        when "y" then t.strftime("%y")
        when "a" then t.hour < 12 ? "am" : "pm"
        when "A" then t.hour < 12 ? "AM" : "PM"
        when "g" then t.strftime("%-I")
        when "G" then t.hour.to_s
        when "h" then t.strftime("%I")
        when "H" then t.strftime("%H")
        when "i" then t.strftime("%M")
        when "s" then t.strftime("%S")
        when "u" then "000000"
        when "v" then "000"
        when "e" then t.respond_to?(:time_zone) ? t.time_zone.tzinfo.name : "UTC"
        when "I" then t.respond_to?(:dst?) && t.dst? ? "1" : "0"
        when "O" then t.strftime("%z")
        when "P" then t.strftime("%:z")
        when "p" then t.utc_offset.zero? ? "Z" : t.strftime("%:z")
        when "T" then t.strftime("%Z")
        when "Z" then t.utc_offset.to_s
        when "c" then t.strftime("%Y-%m-%dT%H:%M:%S%:z")
        when "r" then t.strftime("%a, %d %b %Y %H:%M:%S %z")
        when "U" then t.to_i.to_s
        else c
        end
        i += 1
      end
      out
    end

    def ordinal_day(day)
      suffix = if (11..13).cover?(day % 100)
        "th"
      else
        { 1 => "st", 2 => "nd", 3 => "rd" }.fetch(day % 10, "th")
      end
      "#{day}#{suffix}"
    end

    # Minimal ICU/intl date pattern support (used when the format has no "%").
    def icu_format(t, pattern, names)
      out = +""
      i = 0
      while i < pattern.length
        c = pattern[i]
        if c == "'"
          j = pattern.index("'", i + 1) || pattern.length
          out << (j == i + 1 ? "'" : pattern[(i + 1)...j])
          i = j + 1
          next
        end

        unless c.match?(/[A-Za-z]/)
          out << c
          i += 1
          next
        end

        j = i
        j += 1 while j < pattern.length && pattern[j] == c
        n = j - i
        out << case c
        when "y", "Y", "u" then n == 2 ? t.strftime("%y") : t.year.to_s.rjust(n, "0")
        when "M", "L"
          case n
          when 1 then t.month.to_s
          when 2 then t.strftime("%m")
          when 3 then names[:abbr_months][t.month - 1]
          else names[:months][t.month - 1]
          end
        when "d" then n == 1 ? t.day.to_s : t.strftime("%d")
        when "D" then t.yday.to_s
        when "E", "e", "c"
          if (c == "e" || c == "c") && n <= 2
            t.wday.to_s
          else
            n >= 4 ? names[:days][t.wday] : names[:abbr_days][t.wday]
          end
        when "H" then n == 1 ? t.hour.to_s : t.strftime("%H")
        when "h" then n == 1 ? t.strftime("%-I") : t.strftime("%I")
        when "k" then (t.hour.zero? ? 24 : t.hour).to_s
        when "K" then (t.hour % 12).to_s
        when "m" then n == 1 ? t.min.to_s : t.strftime("%M")
        when "s" then n == 1 ? t.sec.to_s : t.strftime("%S")
        when "a" then t.hour < 12 ? names[:ampm][0] : names[:ampm][1]
        when "Z" then t.strftime("%z")
        when "z" then t.strftime("%Z")
        when "w" then t.strftime("%V")
        when "G" then "AD"
        when "Q", "q" then ((t.month - 1) / 3 + 1).to_s
        else c * n
        end
        i = j
      end
      out
    end

    # strtotime() subset interpreted in the site timezone.
    def site_strtotime(str, base = nil)
      str = Php.str(str).strip
      return nil if str.empty?

      zone = site_zone
      now = base ? zone.at(base) : zone.now
      return now.to_i if str == "now"
      return now.beginning_of_day.to_i if str == "today" || str == "midnight"
      return (now.beginning_of_day + 1.day).to_i if str == "tomorrow"
      return (now.beginning_of_day - 1.day).to_i if str == "yesterday"
      return str.to_i if str.match?(/\A@-?\d+\z/)

      if str.match?(/\A(?:[+-]?\s*\d+\s*[a-z]+\s*(?:ago)?\s*)+\z/i) || str.match?(/\A(?:next|last)\s+[a-z]+\z/i)
        return relative_time(str, now)
      end

      t = zone.parse(str, now)
      t&.to_i
    rescue ArgumentError
      nil
    end

    UNITS = {
      "sec" => 1, "second" => 1, "min" => 60, "minute" => 60, "hour" => 3600, "day" => 86_400,
      "week" => 604_800, "fortnight" => 1_209_600
    }.freeze

    def relative_time(str, now)
      t = now
      if (m = str.match(/\A(next|last)\s+([a-z]+)\z/i))
        dir = m[1].downcase == "next" ? 1 : -1
        return shift_time(t, dir, m[2].downcase).to_i
      end

      str.scan(/([+-]?)\s*(\d+)\s*([a-z]+)\s*(ago)?/i) do |sign, qty, unit, ago|
        n = qty.to_i
        n = -n if sign == "-"
        n = -n if ago
        t = shift_time(t, n, unit.downcase)
      end
      t.to_i
    end

    def shift_time(t, n, unit)
      unit = unit.sub(/s\z/, "")
      case unit
      when "month" then t + n.months
      when "year" then t + n.years
      when *UNITS.keys then t + (n * UNITS[unit])
      else t
      end
    end
  end
end
