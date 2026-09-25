module Txp
  # HTML building helpers used by tag handlers (tag(), href(), doWrap(),
  # doTag(), txp_escape(), txp_wraptag()...).
  module HtmlHelpers
    WRAP_IMPORT = %w[wraptag class html_id wrapform break breakby breakclass breakform escape trim replace limit offset sort].freeze

    def html5?
      get_pref("doctype", "html5") == "html5"
    end

    def void_close
      html5? ? ">" : " />"
    end

    def join_atts(atts, strip_empty: :string, strip_txp: false, glue: " ")
      return atts.to_s.strip.empty? ? "" : " #{atts.to_s.strip}" unless atts.is_a?(Hash)

      list = +""
      atts.each do |name, value|
        next if (strip_empty == :empty && Php.empty?(value)) || value == false || (strip_txp && value.nil?)

        if value.nil? || (strip_txp && value == true)
          list << " #{name}"
          next
        end

        value = if value.is_a?(Array)
          %w[href src].include?(name.to_s) ? join_qs(value) : txpspecialchars(value.join(glue))
        elsif !%w[href src].include?(name.to_s)
          txpspecialchars(value == true ? name : value)
        else
          txpspecialchars(Php.str(value).gsub("&amp;", "&"))
        end

        next if strip_empty && value == ""

        list << %( #{name}="#{value}")
      end
      list
    end

    def join_qs(query, sep = "&amp;")
      qs = []
      query.each do |k, v|
        v = v.join(",") if v.is_a?(Array)
        next if k.nil? || k.to_s == "" || Php.str(v) == ""

        qs << "#{Php.urlencode(k)}=#{Php.urlencode(Php.str(v))}"
      end
      str = qs.join(sep)
      str.empty? ? "" : "?#{str}"
    end

    def tag(content, tag, atts = "")
      content = Php.str(content)
      return content if tag.nil? || tag.to_s.empty? || content == ""

      tag = tag.to_s
      if tag.match?(/\A\w[\w\-.:]*\z/)
        a = atts.is_a?(Hash) ? join_atts(atts) : (atts.to_s.empty? ? "" : atts.to_s)
        "<#{tag}#{a}>#{content}</#{tag}>"
      elsif !tag.include?("<+>")
        "#{tag}#{content}#{tag}"
      else
        tag.gsub("<+>", content)
      end
    end

    def tag_void(tag, atts = "")
      close = HTML5_VOID_TAGS.include?(tag) && html5? ? ">" : " />"
      "<#{tag}#{join_atts(atts)}#{close}"
    end

    def tag_start(tag, atts = "")
      "<#{tag}#{join_atts(atts)}>"
    end

    def graf(item, atts = "")
      "\n#{tag(item, 'p', atts)}"
    end

    def hed(item, level, atts = "")
      "\n#{tag(item, "h#{level}", atts)}\n"
    end

    def href(item, href, atts = "")
      unless href == false
        if atts.is_a?(Hash)
          atts = atts.merge("href" => href)
        else
          href = join_qs(href) if href.is_a?(Hash)
          atts = "#{atts} href=\"#{href}\""
        end
      end
      tag(item, "a", atts)
    end

    def do_tag(content, tag, klass = "", atts = "", id = "")
      return content if Php.empty?(tag)

      atts = atts.to_s.dup
      atts << %( id="#{txpspecialchars(id)}") if Php.truthy?(id)
      atts << %( class="#{txpspecialchars(klass)}") if Php.truthy?(klass)
      Php.str(content) != "" ? tag(content, tag, atts) : "<#{tag} #{atts}#{html5? ? '>' : ' />'}"
    end

    def do_label(label = "", labeltag = "")
      return "" if Php.empty?(label)

      Php.empty?(labeltag) ? "#{label}<br#{html5? ? '>' : ' />'}" : tag(label, labeltag)
    end

    def txp_break(wraptag)
      case wraptag.to_s.downcase
      when "ul", "ol" then "li"
      when "p" then "br"
      when "pre" then "\n"
      when "table", "tbody", "thead", "tfoot" then "tr"
      when "tr" then "td"
      else ","
      end
    end

    # doWrap(): joins a list with break tags and wraps it, importing any
    # global wrapping attributes set on the current tag.
    def do_wrap(list, wraptag = nil, break_arg = nil, klass = nil, breakclass = nil, atts = nil, breakatts = nil, html_id = nil)
      list = Array(list).reject { |v| v == false }
      opts = { "wraptag" => wraptag, "class" => klass, "html_id" => html_id, "breakclass" => breakclass }
      brk = break_arg

      if break_arg.is_a?(Hash)
        break_arg = break_arg.transform_keys(&:to_s)
        break_arg.each { |k, v| opts[k] = v }
        brk = break_arg.key?("break") ? break_arg["break"] : ""
      end
      opts["break"] = brk

      WRAP_IMPORT.each do |g|
        if opts[g].nil?
          opts[g] = @txp_atts ? @txp_atts[g] : nil
        end
        @txp_atts&.delete(g)
      end

      wraptag, klass, html_id, wrapform, brk, breakby, breakclass, breakform, escape, trim, replace, limit, offset, sort =
        opts.values_at(*WRAP_IMPORT)
      atts = atts.to_s.dup
      breakatts = breakatts.to_s.dup

      unless trim.nil? && replace.nil?
        replacement = replace == true ? nil : replace

        if trim == true
          list = list.map { |v| Php.str(v).strip }
          list = list.map { |v| v.gsub(/\s+/, Php.str(replacement)) } unless replacement.nil?
          list = list.reject { |v| v == "" }
        elsif !trim.nil? && trim != ""
          list = if Php.pcre?(trim) && (re = Php.pcre(trim))
            list.map { |v| Php.str(v).gsub(re, Php.str(replacement)) }
          elsif !replacement.nil?
            list.map { |v| Php.str(v).gsub(Php.str(trim), Php.str(replacement)) }
          else
            list.map { |v| Php.trim_chars(v, trim) }
          end
          list = list.reject { |v| v == "" }
        elsif !replacement.nil?
          list = if Php.pcre?(replacement) && (re = Php.pcre(replacement))
            list.select { |v| re.match?(Php.str(v)) }
          else
            list.select { |v| Php.str(v).include?(Php.str(replacement)) }
          end
        end

        list = list.uniq if replace == true
      end

      return "" if list.empty?

      sort = sort.nil? ? "" : Php.str(sort).downcase
      if sort != "" || (Php.str(offset) == "?" && Php.intval(limit) > 0)
        randomize = sort.include?("rand")

        if randomize || Php.str(offset) == "?"
          lim = Php.intval(limit)
          if lim == 1
            list = [ list.sample ]
          elsif lim > 0 && lim < list.length
            list = list.sample(lim)
          end
          limit = offset = nil
        end

        if randomize
          list = list.shuffle
        elsif sort != ""
          natural = sort.include?("nat")
          case_sensitive = sort.include?("case")
          key = lambda do |v|
            s = Php.str(v)
            s = s.downcase unless case_sensitive
            natural ? s.split(/(\d+)/).map { |p| p.match?(/\A\d+\z/) ? [ 0, p.to_i ] : [ 1, p ] } : s
          end
          list = list.sort_by(&key)
          list = list.reverse if sort.include?("desc")
        end
      end

      if Php.truthy?(limit) || Php.truthy?(offset)
        if Php.empty?(offset) || Php.numeric?(offset)
          list = list.drop(Php.intval(offset))
          list = list.first(Php.intval(limit)) unless limit.nil? || limit == ""
        else
          count = list.length
          newlist = []
          Php.do_list(offset, [ ",", "-" ]).each do |ind|
            idx = ind == "?" ? rand(count) : (ind.to_i >= 0 ? ind.to_i - 1 : count + ind.to_i)
            newlist << list[idx] if idx >= 0 && idx < count
          end
          list = Php.truthy?(limit) ? newlist.first(Php.intval(limit)) : newlist
        end
      end

      if (Php.truthy?(brk) || Php.truthy?(breakform)) && Php.truthy?(breakby)
        nums = Php.do_list(breakby).map(&:to_i).reject(&:zero?)
        newlist = []
        if nums.length == 1 && nums[0].positive?
          newlist = list.each_slice(nums[0]).to_a if nums[0] != 1
        elsif nums.any?
          rest = list.dup
          i = 0
          while rest.any?
            n = nums[i]
            newlist << (n.positive? ? rest.shift(n) : rest.pop(-n))
            i = (i + 1) % nums.length
          end
        end
        list = newlist.map { |chunk| chunk.map { |v| Php.str(v) }.join } unless newlist.empty?
      end

      old_item = @txp_item
      @txp_item = (@txp_item || {}).merge("total" => list.length)

      list = list.map { |item| txp_escape(escape, item) } if Php.truthy?(escape)

      if Php.truthy?(breakform)
        thing = breakform.is_a?(Array) ? breakform[0] : nil
        list = list.each_with_index.map do |item, key|
          @txp_item = @txp_item.merge("count" => key + 1, "1" => item)
          form_out = thing.nil? ? parse_form(breakform) : parse(thing)
          Php.str(form_out).gsub("<+>", Php.str(item))
        end
      end

      atts << %( id="#{txpspecialchars(html_id)}") if Php.truthy?(html_id)
      atts << %( class="#{txpspecialchars(klass)}") if Php.truthy?(klass)
      breakatts << %( class="#{txpspecialchars(breakclass)}") if Php.truthy?(breakclass)
      brk = txp_break(wraptag) if brk == true
      list = list.map { |v| Php.str(v) }

      content = if Php.str(brk) == ""
        list.join
      elsif brk.include?("<+>")
        list.map { |item| brk.gsub("<+>", item) }.join
      elsif %w[br hr].include?(brk)
        list.join("<#{brk}#{breakatts.empty? ? '' : " #{breakatts.strip}"}#{html5? ? '>' : ' />'}\n")
      elsif !brk.match?(/\A\w[\w:\-.]*\z/)
        list.join(brk)
      else
        "<#{brk}#{breakatts}>" + list.join("</#{brk}>\n<#{brk}#{breakatts}>") + "</#{brk}>"
      end

      content = Php.str(parse_form(wrapform)).gsub("<+>", content) if Php.truthy?(wrapform)

      @txp_item = old_item
      Php.empty?(wraptag) ? content : tag(content, wraptag, atts)
    end

    # txp_escape(): applies the "escape" transformations.
    def txp_escape(escape, thing = "")
      escape = lAtts({ "escape" => true }, escape, false)["escape"] if escape.is_a?(Hash)
      return thing if Php.empty?(escape)

      list = escape == true ? [ "html" ] : Php.do_list(Php.str(escape).downcase)
      filter = tidy = quoted = false
      thing = "" if thing.nil?

      list.each do |attr|
        case attr
        when "html"
          thing = tidy ? Php.str(thing).gsub(/[^\x00-\x7F]/) { |c| "&##{c.ord};" }.then { |s| txpspecialchars(s) } : txpspecialchars(thing)
        when "db"
          thing = DB.escape(thing)
          quoted = true
        when "url"
          thing = tidy ? Php.rawurlencode(thing) : Php.urlencode(thing)
        when "url_title"
          thing = Txp.sanitize_for_url_title(Php.str(thing), @prefs)
        when "js"
          thing = Php.escape_js(thing)
        when "json"
          # json_encode(JSON_UNESCAPED_UNICODE) still escapes "/" and U+2028/9.
          thing = (JSON.generate(Php.str(thing), script_safe: true)[1..-2] rescue "")
        when "integer", "number", "float", "spell", "ordinal"
          if attr == "integer" && filter
            items = Php.do_list(thing).map { |v| tidy ? v.gsub(/[^\d.\-+]/, "") : v }
            thing = items.map { |v| Php.intval(v) }.reject(&:zero?).join(",")
            next
          end
          raw = Php.str(thing)
          raw = raw.gsub(/[^\d.\-+eE]/, "") if tidy
          value = Php.floatval(raw)
          thing = case attr
          when "integer" then Php.intval(value).to_s
          when "number" then format_number(value)
          when "spell" then (tidy || Php.numeric?(raw)) ? Txp::Numbers.spell(value, lang) : thing
          when "ordinal" then (tidy || Php.numeric?(raw)) ? Txp::Numbers.ordinal(value, lang) : thing
          else Php.str(value)
          end
        when "tags"
          thing = Php.strip_tags(thing)
        when "upper"
          thing = Php.str(thing).upcase
        when "lower"
          thing = Php.str(thing).downcase
        when "title"
          thing = Php.str(thing).split(/(\s+)/).map { |w| w.match?(/\s/) ? w : w.capitalize }.join
        when "trim", "ltrim", "rtrim"
          filter = true
          thing = if thing.is_a?(Integer)
            thing.zero? ? "" : thing
          else
            { "trim" => :strip, "ltrim" => :lstrip, "rtrim" => :rstrip }.then { |m| Php.str(thing).send(m[attr]) }
          end
        when "tidy"
          tidy = true
          thing = Php.str(thing).strip.gsub(/\s{2,}|[^\S ]/, " ")
        when "untidy"
          tidy = false
        when "textile"
          thing = Txp::TextFilter.textile(Php.str(thing), restricted: false, lite: tidy)
          thing = thing.strip if tidy
        when "quote"
          s = Php.str(thing)
          thing = quoted || !s.include?("'") ? "'#{s}'" : "concat('" + s.gsub("'", %(',"'",')) + "')"
        else
          pattern = tidy ? Regexp.escape(attr) : attr
          begin
            thing = Php.str(thing).gsub(%r{</?#{pattern}\b[^<>]*>}i, "")
          rescue RegexpError
            thing
          end
        end
      end

      thing
    end

    def format_number(value)
      value = value.to_f
      if value == value.round
        int = value.round.to_s
      else
        int = format("%.3f", value).sub(/0+\z/, "").sub(/\.\z/, "")
      end
      whole, frac = int.split(".")
      sep = lang.start_with?("en") ? "," : "."
      dec = lang.start_with?("en") ? "." : ","
      whole = whole.gsub(/(\d)(?=(\d{3})+\z)/, "\\1#{sep}")
      frac ? "#{whole}#{dec}#{frac}" : whole
    end

    # Global attribute handlers --------------------------------------------

    def txp_escape_attr(atts, thing = "")
      txp_escape(atts, thing)
    end

    def txp_deprecate(atts, thing = nil)
      trigger_error(gTxt("deprecated_tag")) if Php.truthy?(atts["$deprecate"])
      thing
    end

    def txp_wraptag(atts, thing = "")
      a = lAtts({
        "escape" => "", "label" => "", "labeltag" => "", "wraptag" => "", "class" => "", "html_id" => "",
        "break" => nil, "breakby" => nil, "trim" => nil, "replace" => nil, "limit" => nil,
        "offset" => nil, "sort" => nil, "default" => nil
      }, atts, false)

      dobreak = { "break" => a["break"] == true ? txp_break(a["wraptag"]) : a["break"] }
      thing = Php.str(thing)
      breakby = a["breakby"]

      unless breakby.nil?
        thing = if breakby == ""
          thing.chars
        elsif Php.numeric?(Php.str(breakby).delete(" ,-")) && (dobreak["breakby"] = breakby)
          Php.do_list(thing)
        elsif Php.pcre?(breakby) && (re = Php.pcre(breakby))
          thing.split(re).reject(&:empty?)
        else
          breakby == true ? Php.do_list(thing) : thing.split(Php.str(breakby), -1)
        end
      end

      if !a["trim"].nil? || !a["replace"].nil? || thing.is_a?(Array)
        thing = do_wrap(thing, nil, a.slice("escape", "trim", "replace", "limit", "offset", "sort").merge(dobreak))
      elsif Php.truthy?(a["escape"])
        thing = txp_escape(a["escape"], thing)
      end

      thing = Php.str(thing)
      thing = Php.str(a["default"]) if !a["default"].nil? && thing.strip == ""

      if thing.strip != ""
        thing = Php.truthy?(a["wraptag"]) ? do_tag(thing, a["wraptag"], a["class"], "", a["html_id"]) : thing
        thing = Php.truthy?(a["label"]) ? "#{do_label(a['label'], a['labeltag'])}\n#{thing}" : thing
      end

      thing
    end

    def txp_variable_attr(atts, thing = nil)
      name = atts["variable"]
      @txp_atts&.delete("variable")
      name.nil? ? thing : tag_variable({ "name" => name }, thing)
    end

    # Form inputs ---------------------------------------------------------------

    # fInput(): attribute order follows PHP's array union ($name + defaults).
    def f_input(type, name, value = "", klass = "", title = "", onclick = "", size = 0, tab = 0, id = "", disabled = false, required = false, placeholder = nil)
      atts = name.is_a?(Hash) ? name.transform_keys(&:to_s) : { "name" => name }
      defaults = {
        "class" => klass, "id" => id, "type" => type, "size" => Php.intval(size), "title" => title,
        "onclick" => onclick, "tabindex" => Php.intval(tab), "disabled" => Php.truthy?(disabled),
        "required" => Php.truthy?(required), "placeholder" => placeholder
      }
      atts = atts.merge(defaults) { |_key, left, _right| left }

      if Php.truthy?(atts["required"]) && atts["placeholder"].nil? && %w[email password search tel text url].include?(atts["type"])
        atts["placeholder"] = gTxt("required")
      end

      list = join_atts(atts, strip_empty: :empty)
      list += join_atts({ "value" => Php.str(value) }, strip_empty: false) unless %w[file image].include?(type)
      "\n#{tag_void('input', list)}"
    end

    def h_input(name, value)
      f_input("hidden", name, value)
    end

    def checkbox(name, value, checked = true, tabindex = 0, id = "", form = "")
      klass = Php.truthy?(checked) ? "checkbox active" : "checkbox"
      list = join_atts({
        "class" => klass, "id" => id, "name" => name, "type" => "checkbox", "form" => form,
        "checked" => Php.truthy?(checked), "tabindex" => Php.intval(tabindex)
      }, strip_empty: :empty)
      list += join_atts({ "value" => Php.str(value) }, strip_empty: false)
      "\n#{tag_void('input', list)}"
    end
  end
end
