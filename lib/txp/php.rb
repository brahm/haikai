module Txp
  # Helpers reproducing PHP semantics that Textpattern templates rely on
  # (truthiness, loose comparisons, list splitting, HTML escaping...).
  module Php
    module_function

    NUMERIC_RE = /\A\s*[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?\s*\z/

    # PHP empty()
    def empty?(value)
      case value
      when nil, false then true
      when String then value.empty? || value == "0"
      when Numeric then value.zero?
      when Array, Hash then value.empty?
      else false
      end
    end

    def truthy?(value)
      !empty?(value)
    end

    def numeric?(value)
      case value
      when Integer, Float then true
      when String then NUMERIC_RE.match?(value)
      else false
      end
    end

    def intval(value)
      case value
      when nil, false then 0
      when true then 1
      when Integer then value
      when Float then value.finite? ? value.to_i : 0
      when String
        s = value.strip
        if s.match?(/\A[+-]?\d*\.?\d+[eE][+-]?\d+/)
          s.to_f.to_i
        else
          s.to_i
        end
      when Array then value.empty? ? 0 : 1
      else value.to_i
      end
    end

    def floatval(value)
      case value
      when nil, false then 0.0
      when true then 1.0
      when Numeric then value.to_f
      else value.to_s.strip.to_f
      end
    end

    # PHP string conversion ((string) cast).
    def str(value)
      case value
      when nil, false then ""
      when true then "1"
      when Float
        value == value.to_i && value.abs < 1e15 ? value.to_i.to_s : value.to_s
      when Array then "Array"
      else value.to_s
      end
    end

    def num(value)
      return value if value.is_a?(Numeric)

      s = str(value)
      s.match?(/[.eE]/) ? s.to_f : s.to_i
    end

    # PHP 8 loose equality (==) for scalars.
    def loose_eq(a, b)
      return a == b if a.is_a?(Array) || b.is_a?(Array)
      return truthy?(a) == truthy?(b) if a == true || a == false || b == true || b == false
      return b.nil? || b == "" if a.nil?
      return a == "" if b.nil?

      if numeric?(a) && numeric?(b)
        num(a) == num(b)
      else
        str(a) == str(b)
      end
    end

    # PHP 8 loose comparison (<=>) for scalars.
    def loose_cmp(a, b)
      if numeric?(a) && numeric?(b)
        num(a) <=> num(b)
      else
        str(a) <=> str(b)
      end
    end

    # do_list(): splits a string by delimiter, trimming items. $delim may be an
    # array [delim, range] to expand ranges such as "1-5".
    def do_list(list, delim = ",")
      return [] if list.nil?
      return list.map { |v| str(v).strip } if list.is_a?(Array)

      range = nil
      delim, range = delim if delim.is_a?(Array)
      list = str(list)
      array = list.split(delim, -1)
      array = [ "" ] if array.empty?

      if range && list.include?(range)
        pattern = /\A\s*(\w|[-+]?\d+)\s*#{Regexp.escape(range)}\s*(\w|[-+]?\d+)\s*\z/
        out = []
        array.each do |item|
          m = pattern.match(item)
          if m
            from, to = m[1], m[2]
            if from.match?(/\A[-+]?\d+\z/) && to.match?(/\A[-+]?\d+\z/)
              a, b = from.to_i, to.to_i
              (a <= b ? a.upto(b) : a.downto(b)).each { |v| out << v.to_s }
            else
              (from <= to ? (from..to).to_a : (to..from).to_a.reverse).each { |v| out << v }
            end
          else
            out << item.strip
          end
        end
        return out
      end

      array.map(&:strip)
    end

    def do_list_unique(list, delim = ",", strip_empty: :string)
      out = do_list(list, delim).uniq
      case strip_empty
      when :string then out.reject { |v| v == "" }
      when :empty then out.select { |v| truthy?(v) }
      else out
      end
    end

    def in_list(val, list, delim = ",")
      do_list(list, delim).include?(str(val))
    end

    # parse_qs(): "a=b, c" => {"a" => "b", "c" => false}
    def parse_qs(match, sep = "=")
      pairs = {}
      do_list_unique(match).each do |chunk|
        name, alias_name = chunk.split(sep, 2)
        name = name.to_s
        pairs[name.downcase] = alias_name.nil? || alias_name == "" ? false : alias_name
      end
      pairs
    end

    HTML_ESCAPES = { "&" => "&amp;", "<" => "&lt;", ">" => "&gt;", '"' => "&quot;", "'" => "&#039;" }.freeze

    def txpspecialchars(string, double_encode: true)
      s = str(string)
      if double_encode
        s.gsub(/[&<>"']/, HTML_ESCAPES)
      else
        s.gsub(/&(?!(?:[a-zA-Z][a-zA-Z0-9]*|#\d+|#x[0-9a-fA-F]+);)|[<>"']/) { |c| HTML_ESCAPES[c] || "&amp;" }
      end
    end

    def escape_title(title)
      str(title).gsub(/[<>"']/, "<" => "&#60;", ">" => "&#62;", "'" => "&#39;", '"' => "&#34;")
    end

    def escape_js(js)
      str(js).gsub(/[\\'"\/\n\r<>]/) do |c|
        case c
        when "\n" then "\\n"
        when "\r" then "\\r"
        when "<" then "\\x3c"
        when ">" then "\\x3e"
        else "\\#{c}"
        end
      end
    end

    def urlencode(s)
      URI.encode_www_form_component(str(s))
    end

    def rawurlencode(s)
      ERB::Util.url_encode(str(s))
    end

    def urldecode(s)
      URI.decode_www_form_component(str(s))
    rescue ArgumentError
      str(s)
    end

    def strip_tags(s)
      str(s).gsub(/<!--.*?-->/m, "").gsub(/<\/?[a-zA-Z!?][^>]*>/m, "")
    end

    def ucwords(s)
      str(s).gsub(/(\A|\s)(\S)/) { "#{$1}#{$2.upcase}" }
    end

    # PHP trim() with a character list.
    def trim_chars(s, chars)
      pattern = Regexp.escape(chars.to_s).gsub("\\.\\.", "-")
      str(s).gsub(/\A[#{pattern}]+|[#{pattern}]+\z/, "")
    end

    def md5(s)
      Digest::MD5.hexdigest(str(s))
    end

    # Converts a PCRE pattern "/foo/i" into a Ruby Regexp, or nil.
    def pcre(pattern)
      pattern = str(pattern)
      return nil if pattern.length < 3

      delim = pattern[0]
      return nil if delim.match?(/[\w\s\\]/)

      closing = { "(" => ")", "[" => "]", "{" => "}", "<" => ">" }[delim] || delim
      last = pattern.rindex(closing)
      return nil if last.nil? || last.zero?

      body = pattern[1...last]
      mods = pattern[(last + 1)..].to_s
      return nil unless mods.match?(/\A[imsxuUADSXJ]*\z/)

      opts = 0
      opts |= Regexp::IGNORECASE if mods.include?("i")
      opts |= Regexp::MULTILINE if mods.include?("s")
      opts |= Regexp::EXTENDED if mods.include?("x")
      body = body.gsub("\\/", "/") if delim == "/"
      # PHP's ^/$ are string anchors unless /m is given.
      body = body.gsub(/(?<![\\\[])\^/, "\\A").gsub(/(?<!\\)\$(?=\)|\||\z)/, "\\z") unless mods.include?("m")
      Regexp.new(body, opts)
    rescue RegexpError
      nil
    end

    def pcre?(pattern)
      s = str(pattern)
      s.length > 2 && s.match?(/\A([^\\\w\s]).+\1[UsiAmuSx]*\z/m)
    end
  end
end
