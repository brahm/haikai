module Txp
  # Localisation strings ("textpacks"), following \Textpattern\L10n\Lang.
  #
  # config/textpacks/<lang>.ini are Textpattern 4.9's own language files
  # ("[event]" sections with key="value" pairs). config/textpacks/extra/
  # holds the few strings this port adds, and config/textpacks/debug/mode.ini
  # is Textpattern's mode.ini (tag errors and other debugging messages, merged
  # in when the site is not live). Strings stored in the txp_lang table
  # (plugin textpacks, imported language files, customisations) take
  # precedence over the bundled files. Languages fall back to English.
  module Textpack
    module_function

    DIR = -> { Rails.root.join("config", "textpacks") }

    # These keywords cannot be .ini keys, Textpattern stores them as txp_<word>.
    RESERVED = %w[false no none null off on true yes].freeze

    # Events loaded on the public side.
    PUBLIC_EVENTS = %w[public common].freeze

    def normalize(code)
      code.to_s.strip.downcase.tr("_", "-")
    end

    def available
      Dir[DIR.call.join("*.ini")].map { |f| File.basename(f, ".ini") }.sort |
        LangString.distinct.pluck(:lang)
    end

    def installed_db
      LangString.distinct.pluck(:lang)
    end

    def names
      available.index_with { |code| file_meta(code)["lang_name"] || code }
    end

    def file_meta(code)
      @meta ||= {}
      @meta[code] ||= parse_ini(read_file(code)).fetch("@common", {})
    end

    def read_file(code, subdir = nil)
      path = DIR.call.join(*[ subdir, "#{normalize(code)}.ini" ].compact)
      File.exist?(path) ? File.read(path, encoding: "UTF-8") : ""
    end

    # Parses Textpattern .ini textpacks. Returns {event => {key => value}}.
    def parse_ini(content)
      out = Hash.new { |h, k| h[k] = {} }
      event = "common"
      content.to_s.each_line do |line|
        line = line.strip
        next if line.empty? || line.start_with?(";", "#")

        if (m = line.match(/\A\[([^\]]+)\]\z/))
          event = m[1]
        elsif (m = line.match(/\A([\w\-.]+)\s*=\s*"(.*)"\z/))
          out[event][m[1].downcase] = m[2].gsub('\\"', '"').gsub('\n', "\n")
        elsif (m = line.match(/\A([\w\-.]+)\s*=\s*(.*)\z/))
          out[event][m[1].downcase] = m[2].strip
        end
      end
      out
    end

    # Parses the legacy "#@event\nkey => value" textpack format, returning
    # [{lang:, event:, name:, data:}].
    def parse_textpack(content, default_lang = "en")
      lang = default_lang
      event = "public"
      owner = ""
      rows = []
      content.to_s.each_line do |line|
        line = line.rstrip
        next if line.strip.empty?

        if (m = line.match(/\A#@(?:language|lang)\s+(\S+)/))
          lang = normalize(m[1])
        elsif (m = line.match(/\A#@owner\s+(\S+)/))
          owner = m[1]
        elsif (m = line.match(/\A#@(\S+)/))
          event = m[1]
        elsif line.start_with?("#")
          next
        elsif (m = line.match(/\A\s*([\w\-]+)\s*=>\s*(.*)\z/))
          rows << { lang: lang, event: event, name: m[1].downcase, data: m[2], owner: owner }
        end
      end
      rows
    end

    # All strings for a language; +events+ limits them to those events (the
    # public side only sees "public" and "common" strings).
    def strings(code, events: nil)
      code = normalize(code)
      @strings ||= Concurrent::Map.new
      cache_key = events ? "#{code}|#{events.join(',')}" : code
      version = cache_version
      cached = @strings[cache_key]
      return cached[:data] if cached && cached[:version] == version

      data = {}
      wanted = ->(event) { events.nil? || events.include?(event.delete_prefix("@")) }
      [ "en", code.split("-").first, code ].uniq.each do |c|
        [ read_file(c, "extra"), read_file(c) ].each do |content|
          parse_ini(content).each { |event, pairs| data.merge!(pairs) if wanted.call(event) }
        end
      end
      scope = LangString.where(lang: [ code, code.split("-").first ].uniq)
      scope = scope.where(event: events) if events
      scope.pluck(:name, :data).each { |name, value| data[name.downcase] = value.to_s }
      @strings[cache_key] = { version: version, data: data.freeze }
      data
    end

    # Textpattern's mode.ini strings.
    def debug_strings
      @debug_strings ||= parse_ini(read_file("mode", "debug")).values.reduce({}, :merge).freeze
    end

    def cache_version
      @version_checked_at ||= 0
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      if now - @version_checked_at > 2 || @version.nil?
        @version_checked_at = now
        @version = [ LangString.maximum(:lastmod).to_i, LangString.count ]
      end
      @version
    rescue ActiveRecord::StatementInvalid
      [ 0, 0 ]
    end

    def reset!
      @strings = nil
      @version = nil
      @meta = nil
    end

    # gTxt() / Lang::txt(). With +debug+ the mode.ini strings fill in missing
    # keys, as load_lang() does when production_status is not "live".
    def txt(code, key, atts = {}, escape = "html", events: nil, debug: false)
      v = key.to_s.downcase
      v = "txp_#{v}" if RESERVED.include?(v)
      table = strings(code, events: events)
      value = table.key?(v) ? table[v] : (debug ? debug_strings[v] : nil)
      atts = (atts || {}).to_h { |k, val| [ k.to_s, escape == "html" ? Php.txpspecialchars(val) : Php.str(val) ] }

      if value && value != ""
        atts.empty? ? value : value.gsub(Regexp.union(atts.keys)) { |m| atts[m] }
      elsif atts.any?
        "#{key}: #{atts.values.join(', ')}"
      else
        key.to_s
      end
    end

    # Installs a Textpattern .ini (or legacy textpack) into the database.
    def import(content, lang: nil, owner: "")
      rows = if content.include?("=>")
        parse_textpack(content, lang || "en")
      else
        meta = parse_ini(content)
        code = normalize(lang || meta.dig("@common", "lang_code") || "en")
        meta.flat_map do |event, pairs|
          pairs.filter_map do |name, data|
            next if data.to_s.empty?

            { lang: code, event: event.delete_prefix("@").strip, name: name.delete_prefix("@"), data: data, owner: owner }
          end
        end
      end

      now = Time.now.utc
      LangString.transaction do
        rows.each do |r|
          rec = LangString.find_or_initialize_by(lang: r[:lang], name: r[:name])
          rec.update!(event: r[:event], data: r[:data], owner: r[:owner].to_s, lastmod: now)
        end
      end
      reset!
      rows.length
    end
  end
end
