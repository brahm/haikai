module Txp
  module Tags
    # General purpose tags: page/site info, forms, variables, conditionals.
    module Core
      def tag_page_title(atts, _thing = nil)
        a = lAtts({ "separator" => " | " }, atts)
        sep = Php.str(a["separator"])
        sitename = Php.str(get_pref("sitename"))
        appending = sep != "" ? txpspecialchars(sep + sitename) : ""
        pg = @pretext["pg"]
        page_str = Php.truthy?(pg) ? "#{sep}#{gTxt('page')} #{pg}" : ""
        q = Php.str(@pretext["q"])
        c = Php.str(@pretext["c"])
        s = Php.str(@pretext["s"])
        author = Php.str(@pretext["author"])

        # $parentid is set for the popup comments window (Textpattern 4.9 never
        # sets it, so its "Comments on" title never shows).
        parent_id = Php.intval(@parentid)
        if parent_id.positive?
          "#{gTxt('comments_on')} #{escape_title(DB.field("SELECT Title FROM textpattern WHERE ID = #{parent_id}"))}#{appending}"
        elsif @thisarticle && !@thisarticle["title"].nil?
          "#{escape_title(@thisarticle['title'])}#{appending}"
        elsif q != ""
          "#{gTxt('search_results')} #{gTxt('txt_quote_double_open')}#{txpspecialchars(q)}#{gTxt('txt_quote_double_close')}#{page_str}#{appending}"
        elsif c != ""
          "#{txpspecialchars(fetch_category_title(c, @pretext['context']))}#{page_str}#{appending}"
        elsif s != "" && s != "default"
          "#{txpspecialchars(fetch_section_title(s))}#{page_str}#{appending}"
        elsif author != ""
          "#{txpspecialchars(get_author_name(author))}#{page_str}#{appending}"
        elsif Php.truthy?(pg)
          "#{gTxt('page')} #{pg}#{appending}"
        else
          txpspecialchars(sitename)
        end
      end

      def split_format(format)
        f = Php.str(format).downcase.gsub(/\s+/, "")
        parts = "#{f}.#{f}".split(".", -1)
        [ parts[0], parts[1] ]
      end

      def tag_css(atts, _thing = nil)
        a = lAtts({
          "escape" => true, "format" => "url", "media" => "screen", "name" => @pretext["css"],
          "rel" => "stylesheet", "theme" => @pretext["skin"], "title" => ""
        }, atts)
        name = Php.empty?(a["name"]) ? "default" : Php.str(a["name"])
        theme = Php.str(a["theme"])
        mode, format = split_format(a["format"])

        url = if mode == "flat"
          skin_dir = Php.urlencode(get_pref("skin_dir", "themes"))
          do_list_unique(name).map { |n| "#{hu}#{skin_dir}/#{Php.urlencode(theme)}/#{THEME_TREE['styles']}/#{Php.urlencode(n)}.css" }
        else
          "#{hu}css.php?n=#{Php.urlencode(name)}&t=#{Php.urlencode(theme)}"
        end

        content = nil
        if format == "" || format == "inline"
          css = do_list_unique(name).map { |n| Style.where(name: n, skin: theme).pick(:css) }.compact.join("\n")
          content = a["escape"] == true ? css : txp_escape(a["escape"], css)
        end

        case format
        when "link"
          Array(url).map do |href|
            tag_void("link", { "rel" => a["rel"], "type" => html5? ? "" : "text/css", "media" => a["media"], "title" => a["title"], "href" => href }) + "\n"
          end.join
        when "" then Php.str(content)
        when "inline" then Php.empty?(content) ? "" : tag(content, "style")
        else txpspecialchars(url.is_a?(Array) ? url.join(",") : url)
        end
      end

      def tag_component(atts, _thing = nil)
        a = lAtts({ "format" => "url", "form" => "", "context" => nil, "rel" => "", "title" => "" }, atts, false)
        return "" if Php.empty?(a["form"])

        mode, format = split_format(a["format"])
        internals = %w[id s c context q m pg p month author]
        qs = get_context(a["context"], internals).merge(atts.except("format", "form", "context", "rel", "title"))

        urls = if mode == "flat"
          skin_dir = Php.urlencode(get_pref("skin_dir", "themes"))
          do_list_unique(a["form"]).map do |n|
            type = File.extname(n).delete(".")
            if Form.custom_types(@prefs).key?(type)
              "#{hu}#{skin_dir}/#{current_skin}/#{THEME_TREE['forms']}/#{Php.urlencode(type)}/#{Php.urlencode(n)}#{qs.any? ? join_qs(qs) : ''}"
            else
              pagelinkurl({ "f" => n }.merge(qs))
            end
          end
        else
          [ pagelinkurl({ "f" => a["form"] }.merge(qs)) ]
        end

        case format
        when "url", "flat" then urls.join(",")
        when "link" then urls.map { |h| tag_void("link", { "rel" => a["rel"], "title" => a["title"], "href" => h }) + "\n" }.join
        when "script" then urls.map { |h| "<script#{join_atts({ 'title' => a['title'], 'type' => html5? ? '' : 'application/javascript', 'src' => h })}></script>\n" }.join
        when "image" then urls.map { |h| tag_void("img", { "title" => a["title"], "src" => h }) + "\n" }.join
        else urls.map { |h| href(Php.empty?(a["title"]) ? h : a["title"], h, { "rel" => a["rel"] }) + "\n" }.join
        end
      end

      def tag_output_form(atts, thing = nil)
        atts = atts.dup
        unless atts.key?("form")
          trigger_error(gTxt("form_not_specified"))
          return ""
        end

        form = atts.delete("form")
        to_yield = atts.key?("yield") ? atts.delete("yield") : false
        @txp_atts&.delete("form")
        @txp_atts&.delete("yield")

        return fetch_form(do_list_unique(to_yield)).last if form == true && atts.empty?

        if Php.truthy?(to_yield)
          to_yield = to_yield == true ? atts.dup : do_list_unique(to_yield).index_with { nil }
          @txp_atts = @txp_atts.except(*to_yield.keys) if @txp_atts && !@txp_atts.empty?
        end

        if atts.key?("format")
          atts = atts.except(*@txp_atts.keys) if @txp_atts && !@txp_atts.empty?
          return tag_component(atts.merge("form" => form))
        elsif to_yield.is_a?(Hash)
          atts = lAtts(to_yield, atts)
        end

        atts.each { |name, value| @txp_yield[name] << [ value, false ] }
        @yield_stack.push(thing)
        out = parse_form(form)
        @yield_stack.pop

        atts.each_key do |name|
          result = @txp_yield[name].pop
          @txp_atts&.delete(name) if result && result[1]
        end

        out
      end

      def tag_yield(atts, thing = nil)
        a = lAtts({ "name" => "", "else" => false, "default" => false, "item" => nil }, atts)
        name = a["name"]
        inner = nil

        if !a["item"].nil?
          key = a["item"] == true ? "1" : Php.str(a["item"])
          inner = @txp_item[key]
        elsif name == "" || name.nil?
          # A self-closed caller has nothing to yield (Textpattern 4.9 prints
          # "1" there, and default="" never applies).
          unless @yield_stack.empty? || @yield_stack.last.nil?
            was_form = @is_form
            @is_form -= 1
            last = @yield_stack.pop
            inner = parse(last, Php.empty?(a["else"]))
            @yield_stack.push(last)
            @is_form = was_form
          end
        elsif @txp_yield.key?(name) && !@txp_yield[name].empty?
          inner = @txp_yield[name].last[0]
          @txp_yield[name].last[1] = true
        end

        if inner.nil?
          escape = @txp_atts ? @txp_atts["escape"] : nil
          inner = if a["default"] != false
            a["default"] == true ? tag_page_url({ "type" => name, "escape" => escape }) : a["default"]
          else
            thing ? parse(thing) : thing
          end
        end

        inner
      end

      def tag_if_yield(atts, thing = nil)
        a = lAtts({ "else" => false, "item" => nil, "name" => "", "match" => "exact", "separator" => "", "value" => nil }, atts)
        name = a["name"]
        inner = nil

        if !a["item"].nil?
          inner = @txp_item[a["item"] == true ? "1" : Php.str(a["item"])]
        elsif name == ""
          # False for a self-closed caller (true in Textpattern 4.9).
          unless @yield_stack.empty? || @yield_stack.last.nil?
            last = @yield_stack.pop
            inner = if a["value"].nil?
              Php.truthy?(a["else"]) ? getIfElse(last, false) : true
            else
              parse(last, Php.empty?(a["else"]))
            end
            @yield_stack.push(last)
          end
        elsif @txp_yield.key?(name) && !@txp_yield[name].empty?
          inner = @txp_yield[name].last[0]
        end

        x = !inner.nil? && (a["value"].nil? || (a["value"] == true && Php.truthy?(inner)) || txp_match(a, inner))
        parse(thing, x)
      end

      # getIfElse(): the if (or else) part of a string, unparsed.
      def getIfElse(thing, condition = true)
        return (condition ? thing : nil) if thing.nil? || !thing.include?(":else")

        parsed = tokenizer.parse(thing)
        return (condition ? thing : nil) if parsed.nil?

        tags = parsed.tags
        first = parsed.first
        last = parsed.last
        if condition
          last = first - 2
          first = 1
        elsif first <= last
          first += 2
        else
          return nil
        end

        out = +Php.str(tags[first - 1])
        while first <= last
          t = tags[first]
          out << t[0].to_s << t[3].to_s << t[4].to_s
          first += 1
          out << Php.str(tags[first])
          first += 1
        end
        out
      end

      def tag_page_url(atts, thing = nil)
        specials = {
          "admin_root" => ahu,
          "images_root" => "#{ihu}#{get_pref('img_dir', 'images')}",
          "themes_root" => "#{hu}#{get_pref('skin_dir', 'themes')}",
          "theme_path" => "#{hu}#{get_pref('skin_dir', 'themes')}/#{@pretext['skin']}",
          "theme" => @pretext["skin"]
        }
        internals = %w[id s c context q m p month author f]
        defaults = { "context" => nil, "default" => false, "escape" => nil, "lang" => nil, "root" => nil, "type" => nil }
        old_context = @txp_context
        old_base = @prefs["@txp_root"]
        old_lang = @prefs["@txp_lang"]
        extra = nil

        if !atts.key?("context")
          if @txp_context.nil? || @txp_context.empty?
            atts = lAtts(defaults, atts)
          else
            atts = lAtts(defaults.merge(@txp_context), atts)
            @txp_context = atts.slice(*@txp_context.keys)
          end
        elsif atts["context"] == true
          atts = lAtts(defaults, atts)
        else
          extra_keys = do_list_unique(atts["context"])
          atts = lAtts(defaults.merge(extra_keys.index_with { nil }), atts)
          extra = atts.slice(*extra_keys)
        end

        context = atts["context"]
        default = atts["default"]
        type = atts["type"]
        escape = atts["escape"]
        @prefs["@txp_root"] = atts["root"] == true ? rhu : atts["root"] unless atts["root"].nil?
        @prefs["@txp_lang"] = atts["lang"] == true ? lang : atts["lang"] unless atts["lang"].nil?
        @txp_context = get_context(extra || context, internals)

        if default != false
          if default == true
            type.nil? ? (@txp_context = {}) : @txp_context.delete(type)
          elsif !@txp_context.key?(type)
            @txp_context[type] = default
          end
        end

        type ||= "request_uri"

        out = if thing
          parse(thing)
        elsif !context.nil? || !atts["lang"].nil? || !atts["root"].nil?
          u = pagelinkurl(@txp_context)
          escape.nil? ? u : u.gsub("&amp;", "&")
        elsif specials.key?(type)
          specials[type]
        elsif type == "pg" && Php.str(@pretext["pg"]) == ""
          "1"
        elsif @pretext.key?(type) && (default == true || default == false)
          v = type == "s" && @pretext["s"] == "default" ? "" : Php.str(@pretext[type])
          escape.nil? ? txpspecialchars(v) : v
        else
          v = gps(type, default == false ? "" : default)
          v = v.join(",") if v.is_a?(Array)
          v = v.values.join(",") if v.is_a?(Hash)
          escape.nil? ? txpspecialchars(v) : Php.str(v)
        end

        @txp_context = old_context
        @prefs["@txp_root"] = old_base
        @prefs["@txp_lang"] = old_lang
        @prefs.delete("@txp_root") if old_base.nil?
        @prefs.delete("@txp_lang") if old_lang.nil?
        out
      end

      def tag_date(atts, _thing = nil)
        a = lAtts({ "calendar" => "", "format" => "", "gmt" => "", "lang" => "", "time" => true, "type" => nil }, atts)
        time = a["time"]
        type = a["type"]

        if time == true
          time = Time.now.to_i
        elsif !type.nil?
          assert_context(type)
          obj = instance_variable_get(:"@this#{type}")
          return "" unless obj.is_a?(Hash) && !obj[time].nil? && obj[time] != ""

          time = obj[time]
        end

        unless Php.numeric?(time)
          time = site_strtotime(time)
          return "" if time.nil?
        end

        format = a["format"]
        if Php.empty?(format)
          format = case type
          when "article"
            Php.truthy?(@pretext["id"]) || Php.truthy?(@pretext["c"]) || Php.truthy?(@pretext["pg"]) ? get_pref("archive_dateformat") : get_pref("dateformat")
          when "file" then get_pref("archive_dateformat")
          when "comment" then get_pref("comments_dateformat")
          else get_pref("dateformat")
          end
        end

        locale = Php.str(a["lang"])
        locale = "#{locale.presence || lang}@calendar=#{a['calendar']}" if Php.truthy?(a["calendar"])
        safe_strftime(format, time, Php.truthy?(a["gmt"]), locale)
      end

      def tag_feed_link(atts, thing = nil)
        a = lAtts({
          "category" => @pretext["c"], "flavor" => "rss", "format" => "a", "label" => "", "limit" => "",
          "section" => @pretext["s"] == "default" ? "" : @pretext["s"], "title" => gTxt("rss_feed_title")
        }, atts)
        flavor = Php.str(a["flavor"])
        url = pagelinkurl({ flavor => "1", "section" => a["section"], "category" => a["category"], "limit" => a["limit"] })
        title = a["title"]
        title = gTxt("atom_feed_title") if flavor == "atom" && title == gTxt("rss_feed_title")
        title = txpspecialchars(title)
        type = flavor == "atom" ? "application/atom+xml" : "application/rss+xml"

        if a["format"] == "link"
          return %(<link rel="alternate" type="#{type}" title="#{title}" href="#{url}"#{void_close})
        end

        txt = thing.nil? ? a["label"] : parse(thing)
        href(txt, url, { "type" => type, "title" => title })
      end

      def tag_link_feed_link(atts, _thing = nil)
        a = lAtts({
          "category" => @pretext["c"], "flavor" => "rss", "format" => "a", "label" => "",
          "title" => gTxt("rss_feed_title"), "wraptag" => "", "class" => "link_feed_link"
        }, atts)
        flavor = Php.str(a["flavor"])
        url = pagelinkurl({ flavor => "1", "area" => "link", "category" => a["category"] })
        title = a["title"]
        title = gTxt("atom_feed_title") if flavor == "atom" && title == gTxt("rss_feed_title")
        title = txpspecialchars(title)
        type = flavor == "atom" ? "application/atom+xml" : "application/rss+xml"

        return %(<link rel="alternate" type="#{type}" title="#{title}" href="#{url}"#{void_close}) if a["format"] == "link"

        out = href(a["label"], url, { "type" => type, "title" => title })
        Php.truthy?(a["wraptag"]) ? do_tag(out, a["wraptag"], a["class"]) : out
      end

      def entity_obfuscate(address)
        address.to_s.each_char.map { |c| "&##{c.ord};" }.join
      end

      def tag_email(atts, thing = nil)
        a = lAtts({ "email" => "", "linktext" => gTxt("contact"), "title" => "" }, atts)
        return "" if Php.empty?(a["email"])

        linktext = thing.nil? ? a["linktext"] : parse(thing)
        linktext = entity_obfuscate(linktext) if Php.str(linktext).match?(URI::MailTo::EMAIL_REGEXP)
        href(linktext, entity_obfuscate("mailto:#{a['email']}"), Php.truthy?(a["title"]) ? %( title="#{txpspecialchars(a['title'])}") : "")
      end

      def tag_popup(atts, _thing = nil)
        a = lAtts({
          "label" => gTxt("browse"), "wraptag" => "", "class" => "", "section" => "", "target" => false,
          "this_section" => 0, "type" => "category"
        }, atts)
        type = Php.str(a["type"])[0]
        rows = if type == "s"
          DB.rows("SELECT name, title FROM txp_section WHERE name != 'default' ORDER BY name")
        else
          DB.rows("SELECT name, title FROM txp_category WHERE type = 'article' AND name != 'root' ORDER BY name")
        end
        return nil if rows.empty?

        current = type == "s" ? @pretext["s"] : @pretext["c"]
        selected = false
        options = rows.map do |r|
          sel = r["name"] == current
          selected ||= sel
          %(<option value="#{txpspecialchars(r['name'])}"#{sel ? ' selected="selected"' : ''}>#{txpspecialchars(r['title'])}</option>)
        end

        section = Php.truthy?(a["this_section"]) ? (@pretext["s"] == "default" ? "" : @pretext["s"]) : a["section"]
        out = %(\n<select name="#{txpspecialchars(type)}" onchange="submit(this.form);">\n\t<option value=""#{selected ? '' : ' selected="selected"'}>&#160;</option>\n\t#{options.join("\n\t")}\n</select>)
        out = "#{a['label']}#{html5? ? '<br>' : '<br />'}#{out}" if Php.truthy?(a["label"])
        out = do_tag(out, a["wraptag"], a["class"]) if Php.truthy?(a["wraptag"])

        if type == "s" || get_pref("permlink_mode") == "messy"
          action = hu
          his = Php.str(section) != "" ? "\n#{h_input('s', section)}" : ""
        else
          action = pagelinkurl({ "s" => section })
          his = ""
        end

        tag("<div>#{his}\n#{out}\n<noscript><div><input type=\"submit\" value=\"#{gTxt('go')}\"#{void_close}</div></noscript>\n</div>",
          "form", { "method" => "get", "action" => action, "target" => a["target"] })
      end

      def tag_search_input(atts, thing = nil)
        inside = @search_input_outside.is_a?(Hash)
        a = lAtts({
          "form" => nil, "wraptag" => "p", "class" => "search_input", "size" => "15", "html_id" => "",
          "label" => gTxt("search"), "aria_label" => "", "placeholder" => "", "button" => "", "section" => "",
          "match" => "exact"
        }, inside ? @search_input_outside.merge(atts) : atts)
        atts = atts.except("form")
        form = a["form"]
        form = "search_input" if !inside && form.nil? && thing.nil? && atts.empty?

        if Php.truthy?(form)
          fetched = fetch_form(form).last
          form = fetched
          thing = fetched if fetched
        end

        if thing
          old = @search_input_outside
          @search_input_outside = atts
          out = parse(thing)
          @search_input_outside = old
        else
          out = f_input(html5? ? "search" : "text", {
            "name" => "q", "aria-label" => a["aria_label"], "placeholder" => a["placeholder"],
            "required" => html5?, "size" => a["size"],
            "class" => Php.truthy?(a["wraptag"]) || Php.empty?(atts["class"]) ? false : a["class"]
          }, @pretext["q"])
        end

        if Php.truthy?(form) || inside
          out = do_tag(out, a["wraptag"], a["class"]) unless Php.empty?(atts["wraptag"])
          return out
        end

        sub = Php.truthy?(a["button"]) ? %(<input type="submit" value="#{txpspecialchars(a['button'])}"#{void_close}) : ""
        id = Php.truthy?(a["html_id"]) ? %( id="#{txpspecialchars(a['html_id'])}") : ""
        out = Php.truthy?(a["label"]) ? "#{txpspecialchars(a['label'])}#{html5? ? '<br>' : '<br />'}#{out}#{sub}" : "#{out}#{sub}"
        out = h_input("m", txpspecialchars(a["match"])) + out if a["match"] != "exact"
        out = do_tag(out, a["wraptag"], a["class"]) if Php.truthy?(a["wraptag"])

        if Php.empty?(a["section"])
          %(<form role="search" method="get" action="#{hu}"#{id}>\n#{out}\n</form>)
        elsif get_pref("permlink_mode") != "messy"
          %(<form role="search" method="get" action="#{pagelinkurl({ 's' => a['section'] })}"#{id}>\n#{out}\n</form>)
        else
          %(<form role="search" method="get" action="#{hu}"#{id}>\n#{h_input('s', a['section'])}\n#{out}\n</form>)
        end
      end

      def tag_search_term(_atts, _thing = nil)
        Php.empty?(@pretext["q"]) ? "" : txpspecialchars(@pretext["q"])
      end

      def tag_if_search(_atts, thing = nil)
        x = Php.truthy?(@pretext["q"])
        thing.nil? ? x : parse(thing, x)
      end

      def tag_site_name(_atts = {}, _thing = nil)
        txpspecialchars(get_pref("sitename"))
      end

      def tag_site_slogan(_atts = {}, _thing = nil)
        txpspecialchars(get_pref("site_slogan"))
      end

      def tag_link_to_home(atts, thing = nil)
        a = lAtts({ "class" => false }, atts)
        return hu unless Php.truthy?(thing)

        klass = Php.truthy?(a["class"]) ? %( class="#{txpspecialchars(a['class'])}") : ""
        href(parse(thing), hu, "#{klass} rel=\"home\"")
      end

      def tag_site_url(atts, _thing = nil)
        a = lAtts({ "type" => "" }, atts)
        a["type"] == "admin" ? ahu : hu
      end

      def tag_lang(_atts = {}, _thing = nil)
        txpspecialchars(lang)
      end

      def tag_text(atts, _thing = nil)
        a = lAtts({ "item" => "", "escape" => nil }, atts, false)
        return "" if Php.empty?(a["item"])

        tags = atts.except("item", "escape").to_h { |k, v| [ "{#{k}}", Php.str(v) ] }
        gTxt(a["item"], tags, a["escape"].nil? ? "html" : "")
      end

      def tag_error_message(_atts = {}, _thing = nil)
        @txp_error_message.to_s
      end

      def tag_error_status(_atts = {}, _thing = nil)
        @txp_error_status.to_s
      end

      def tag_if_status(atts, thing = nil)
        a = lAtts({ "status" => "200" }, atts)
        page_status = @txp_error_code || @pretext["status"]
        x = Php.loose_eq(a["status"], page_status)
        thing.nil? ? x : parse(thing, x)
      end

      def set_error_page(msg, status, code)
        @txp_error_message = msg
        @txp_error_status = status
        @txp_error_code = code
      end

      def tag_txp_die(atts, _thing = nil)
        a = lAtts({ "msg" => "", "status" => "503", "url" => "" }, atts)
        txp_die(a["msg"], a["status"], a["url"])
      end

      def tag_if_different(atts, thing = nil)
        a = lAtts({ "test" => nil, "not" => "", "id" => nil }, atts)
        @if_different_last ||= {}
        @if_different_tested ||= {}
        key = a["id"].nil? ? thing.to_s : Php.str(a["id"])
        out = a["test"].nil? ? parse(thing) : a["test"]

        if !a["test"].nil?
          different = !@if_different_tested.key?(key) || !Php.loose_eq(out, @if_different_tested[key])
          @if_different_tested[key] = out if different
        else
          different = !@if_different_last.key?(key) || !Php.loose_eq(out, @if_different_last[key])
          @if_different_last[key] = out if different
        end

        condition = Php.truthy?(a["not"]) ? !different : different
        return parse(thing, condition) unless a["test"].nil?

        condition ? out : parse(thing, false)
      end

      def tag_if_first(_atts, thing = nil, type = "article")
        obj = instance_variable_get(:"@this#{type}")
        x = obj.is_a?(Hash) && Php.truthy?(obj["is_first"])
        thing.nil? ? x : parse(thing, x)
      end

      def tag_if_last(_atts, thing = nil, type = "article")
        obj = instance_variable_get(:"@this#{type}")
        x = obj.is_a?(Hash) && Php.truthy?(obj["is_last"])
        thing.nil? ? x : parse(thing, x)
      end

      def tag_if_plugin(atts, thing = nil)
        a = lAtts({ "name" => "", "version" => "" }, atts)
        x = if Php.empty?(a["name"])
          Gem::Version.new(Txp::VERSION) >= Gem::Version.new(Php.str(a["version"]).presence || "0")
        else
          plugin = Txp::Plugins.active[Php.str(a["name"])]
          !plugin.nil? && (Php.empty?(a["version"]) || Gem::Version.new(plugin[:version].to_s) >= Gem::Version.new(Php.str(a["version"])))
        end
        thing.nil? ? x : parse(thing, x)
      rescue ArgumentError
        thing.nil? ? false : parse(thing, false)
      end

      def tag_rsd(_atts = {}, _thing = nil)
        trigger_error(gTxt("deprecated_tag"))
        ""
      end

      def tag_variable(atts, thing = nil)
        set = !thing.nil? || atts.key?("value") || atts.key?("add") || atts.key?("reset")
        a = lAtts({
          "name" => "", "value" => nil, "default" => false, "add" => nil, "reset" => nil,
          "separator" => nil, "output" => nil
        }, atts)
        name = Php.str(a["name"])
        value = a["value"]
        add = a["add"]
        output = a["output"]
        var = @variable[name]
        breakform = nil

        if name != "" && !set && var.nil? && output.nil?
          Rails.logger.debug { "[txp] Unknown variable '#{name}'" }
        elsif add == true
          thing = parse(thing) unless Php.empty?(thing)
          if value.nil?
            add = thing.nil? ? 1 : thing
          elsif value == true
            add = var
            var = thing unless thing.nil?
          else
            add = thing.nil? ? var : thing
            var = value
          end
        elsif value == true
          var = thing.nil? ? nil : parse(thing) if var.nil?
        else
          var = if !value.nil?
            value
          else
            thing.nil? ? var : parse(thing)
          end
          breakform = [ thing.strip ] if !value.nil? && !thing.nil?
        end

        var = a["default"] if a["default"] != false && Php.str(var).strip == ""

        if !add.nil? && add != ""
          if a["separator"].nil? && Php.numeric?(add) && (Php.empty?(var) || Php.numeric?(var))
            sum = Php.num(var || 0) + Php.num(add)
            var = sum
          else
            var = "#{Php.str(var)}#{Php.truthy?(var) ? Php.str(a['separator']) : ''}#{Php.str(add)}"
          end
        end

        if set
          if @txp_atts && !@txp_atts.empty?
            @txp_atts = @txp_atts.merge("breakform" => breakform) if breakform && !@txp_atts.key?("breakform")
            var = txp_wraptag(@txp_atts, var)
          end

          if name != ""
            if !a["reset"].nil?
              @variable[name] = a["reset"] == true ? nil : a["reset"]
              output = 1 if output.nil?
            else
              @variable[name] = var
            end
          end
        end

        output = 1 unless !output.nil? || (set && name != "")
        return "" if Php.empty?(output)

        Php.intval(output) != 0 ? var : txp_escape({ "escape" => output }, var)
      end

      def tag_if_variable(atts, thing = nil)
        a = lAtts({ "name" => "", "value" => false, "match" => "", "separator" => "" }, atts)

        if Php.empty?(a["name"])
          trigger_error(gTxt("variable_name_empty"))
          return ""
        end

        v = @variable[Php.str(a["name"])]
        x = v.nil? ? false : (a["value"] == false ? true : txp_match(a, v))
        thing.nil? ? x : parse(thing, x)
      end

      # txp_match(): compares a value using the match/value/separator attributes.
      def txp_match(atts, what)
        value = atts["value"]
        match = Php.str(atts["match"])
        separator = atts["separator"]
        return !what.nil? if value.nil?

        sep = Php.truthy?(separator) ? Php.str(separator) : ","
        list = ->(v) { Php.do_list(v, sep) }

        cond = case match
        when ""
          what.is_a?(Array) ? what == list.call(value) : Php.loose_eq(what, value)
        when "exact"
          what.is_a?(Array) ? what == list.call(value) : Php.str(what) == Php.str(value)
        when "any", "all"
          values = Php.do_list_unique(value)
          contents = Php.truthy?(separator) && !what.is_a?(Array) ? Php.do_list_unique(what, Php.str(separator)) : (what.is_a?(Array) ? what : Php.str(what))
          test = ->(term) { contents.is_a?(Array) ? contents.include?(term) : contents.include?(term) }
          match == "any" ? values.any?(&test) : values.all?(&test)
        when "<", "less" then compare_values(what, value, list) { |c| c.negative? }
        when "<=" then compare_values(what, value, list) { |c| c <= 0 }
        when ">", "greater" then compare_values(what, value, list) { |c| c.positive? }
        when ">=" then compare_values(what, value, list) { |c| c >= 0 }
        when "pattern"
          subject = what.is_a?(Array) ? what.join : Php.str(what)
          re = if separator == true
            Php.pcre(value)
          elsif Php.truthy?(separator) && %w[/ @ # ~ ` | ! %].include?(Php.str(separator))
            Php.str(value).start_with?(Php.str(separator)) ? Php.pcre(value) : Php.pcre("#{separator}#{value}#{separator}")
          else
            begin
              Regexp.new(Php.str(value))
            rescue RegexpError
              nil
            end
          end
          re ? re.match?(subject) : false
        else
          trigger_error(gTxt("invalid_attribute_value", "{name}" => "match"))
          false
        end

        cond ? true : false
      end

      def compare_values(what, value, list)
        cmp = if what.is_a?(Array)
          what <=> list.call(value)
        else
          Php.loose_cmp(what, value)
        end
        cmp.nil? ? false : yield(cmp)
      end

      def tag_if_request(atts, thing = nil)
        a = lAtts({ "name" => "", "type" => "request", "value" => nil, "match" => "", "separator" => "" }, atts)
        m = a.slice("value", "match", "separator")
        name = Php.str(a["name"])
        type = Php.str(a["type"]).upcase

        x = case type
        when "REQUEST", "GET", "POST", "COOKIE", "SERVER", "SESSION"
          source = request_source(type)
          name == "" ? !source.empty? : txp_match(m, source[name])
        when "HEADER"
          txp_match(m, @response_headers[name.downcase])
        when "SYSTEM"
          @prefs.key?(name) && php_allowed?(true) && txp_match(m, @prefs[name])
        when "NAME"
          txp_match(m, name)
        else
          trigger_error(gTxt("invalid_attribute_value", "{name}" => "type"))
          false
        end

        thing.nil? ? x : parse(thing, x)
      end

      def request_source(type)
        case type
        when "GET" then params[:get]
        when "POST" then params[:post]
        when "COOKIE" then @request ? @request.cookies.to_h : {}
        when "SERVER"
          return {} unless @request

          env = @request.env
          env.select { |k, v| v.is_a?(String) && (k.upcase == k) }.merge(
            "REQUEST_URI" => @request.original_fullpath, "REQUEST_METHOD" => @request.request_method,
            "HTTP_HOST" => @request.host_with_port, "HTTPS" => @request.ssl? ? "on" : ""
          )
        # $_REQUEST with request_order="GP" (POST overrides GET). Textpattern
        # 4.9 only sees it once PHP happens to have created the superglobal
        # (after a tag class was autoloaded), so type="request" is unreliable
        # there. The public side starts no session: type="session" never matches.
        when "REQUEST" then params[:get].merge(params[:post])
        else {}
        end
      end

      def tag_hide(atts = {}, thing = nil)
        return "" unless atts.key?("process")

        process = lAtts({ "process" => nil }, atts)["process"]

        if Php.empty?(process)
          Php.str(process).strip == "" && @pretext["secondpass"] < intval(get_pref("secondpass", 1)) ? postpone_process : thing
        elsif Php.numeric?(process)
          p = Php.intval(process)
          if p.abs > @pretext["secondpass"] + 1
            postpone_process(p)
          else
            p.positive? ? parse(thing) : "<txp:hide>#{parse(thing)}</txp:hide>"
          end
        elsif process == true
          parse(thing)
          ""
        elsif Php.str(process).downcase == production_status
          parse(thing)
        else
          ""
        end
      end

      # PHP code cannot run here; <txp:php> reports an error and outputs nothing.
      # php(): same permission rules as Textpattern; PHP code itself cannot run
      # in this implementation, which is reported when it would be allowed.
      def tag_php(_atts = nil, thing = nil)
        error = if !@is_article_body || @is_form.to_i.positive?
          "php_code_disabled_page" unless Php.truthy?(get_pref("allow_page_php_scripting"))
        elsif !Php.truthy?(get_pref("allow_article_php_scripting"))
          "php_code_disabled_article"
        elsif !php_allowed?("article.php")
          "php_code_forbidden_user"
        end
        return error.nil? if thing.nil?

        # The code runs inside ob_start(), so its error messages end up in the
        # tag's output rather than at the top of the page.
        shown = @errors.size
        trigger_error(gTxt(error || "php_code_unsupported"), error ? :notice : :warning)
        @errors.slice!(shown..).join
      end

      # php(null, null, true) privilege check used by tags that change the
      # response (header, file downloads) or read server data.
      def php_allowed?(priv = true)
        return true unless @is_article_body && @is_form.to_i.zero?

        author = @is_article_body == true ? nil : @is_article_body
        return true if author.nil?

        Txp::Privs.has?(priv == true ? "form" : priv, author_row(author)&.dig("privs"))
      end

      def tag_header(atts, _thing = nil)
        return nil unless php_allowed?(true)

        a = lAtts({
          "name" => atts.key?("value") ? "" : "Content-Type", "replace" => 1,
          "value" => atts.key?("name") ? true : "text/html; charset=utf-8"
        }, atts)
        name = Php.str(a["name"]).downcase
        return nil if name == ""

        if a["value"] == true
          @response_headers[name]
        else
          if Php.truthy?(a["replace"]) || !@response_headers.key?(name)
            @response_headers[name] = Php.str(a["value"])
          else
            @response_headers[name] = "#{@response_headers[name]}, #{a['value']}"
          end
          nil
        end
      end

      def tag_meta_keywords(atts, _thing = nil)
        a = lAtts({ "escape" => true, "format" => "meta", "separator" => nil }, atts)
        kw = @pretext["id_keywords"]
        return "" if Php.empty?(kw)

        content = a["escape"] == true ? txpspecialchars(kw) : txp_escape(a["escape"], kw)
        content = Php.do_list(content).join(Php.str(a["separator"])) unless a["separator"].nil?
        a["format"] == "meta" ? %(<meta name="keywords" content="#{content}"#{void_close}) : content
      end

      def tag_meta_author(atts, _thing = nil)
        a = lAtts({ "escape" => true, "format" => "meta", "title" => 0 }, atts)
        author = @pretext["id_author"]
        return "" if Php.empty?(author)

        name = Php.truthy?(a["title"]) ? get_author_name(author) : author
        name = a["escape"] == true ? txpspecialchars(name) : txp_escape(a["escape"], name)
        a["format"] == "meta" ? %(<meta name="author" content="#{name}"#{void_close}) : name
      end

      def meta_description_content(type = nil)
        c = @pretext["c"]
        s = @pretext["s"]
        context = @pretext["context"]

        if type.nil?
          if Php.truthy?(@thiscategory) then Php.str(@thiscategory["description"])
          elsif Php.truthy?(@thissection) then Php.str(@thissection["description"])
          elsif Php.truthy?(@thisarticle) then Php.str(@thisarticle["description"])
          elsif Php.truthy?(c) then Php.str(DB.field("SELECT description FROM txp_category WHERE name = #{q c} AND type = #{q context}"))
          elsif Php.truthy?(s) then Php.str(@txp_sections.dig(s, "description"))
          else ""
          end
        elsif type.start_with?("category")
          if Php.truthy?(@thiscategory)
            Php.str(@thiscategory["description"])
          else
            ctx = type.split(".")[1] || context
            Php.str(DB.field("SELECT description FROM txp_category WHERE name = #{q c} AND type = #{q ctx}"))
          end
        elsif type == "section"
          name = Php.truthy?(@thissection) ? @thissection["name"] : s
          Php.str(@txp_sections.dig(name, "description"))
        elsif type == "article"
          assert_article
          Php.truthy?(@thisarticle) ? Php.str(@thisarticle["description"]) : ""
        else
          ""
        end
      end

      def tag_if_description(atts, thing = nil)
        a = lAtts({ "type" => nil }, atts)
        x = !Php.empty?(meta_description_content(a["type"]))
        thing.nil? ? x : parse(thing, x)
      end

      def tag_meta_description(atts, _thing = nil)
        a = lAtts({ "escape" => true, "format" => "meta", "type" => nil }, atts)
        content = meta_description_content(a["type"])
        return "" if Php.empty?(content)

        content = a["escape"] == true ? txpspecialchars(content) : txp_escape(a["escape"], content)
        a["format"] == "meta" ? %(<meta name="description" content="#{content}"#{void_close}) : content
      end

      def tag_breadcrumb(atts, thing = nil)
        a = lAtts({
          "type" => @pretext["context"], "category" => @pretext["c"], "section" => @pretext["s"], "wraptag" => "p",
          "separator" => "&#160;&#187;&#160;", "limit" => nil, "offset" => 0, "link" => 1,
          "label" => get_pref("sitename"), "title" => "", "class" => "", "linkclass" => ""
        }, atts)
        content = []
        label = txpspecialchars(a["label"])
        type = a["type"] == true ? @pretext["context"] : valid_context(a["type"])
        section = a["section"] == "default" ? "" : Php.str(a["section"])
        link = Php.truthy?(a["link"])
        label = do_tag(label, "a", a["linkclass"], %( href="#{hu}")) if link && label != ""

        unless section.empty?
          stitle = Php.truthy?(a["title"]) ? fetch_section_title(section) : section
          html = escape_title(stitle)
          content << (link ? do_tag(html, "a", a["linkclass"], %( href="#{pagelinkurl({ 's' => @pretext['s'] })}")) : html)
        end

        catpath = Php.empty?(a["category"]) ? [] : get_root_path(a["category"], type).reverse
        if !a["limit"].nil? || Php.truthy?(a["offset"])
          offset = Php.intval(a["offset"])
          offset -= 1 if offset.negative?
          catpath = offset.negative? ? catpath.last(-offset) : catpath.drop(offset)
          catpath = catpath.first(Php.intval(a["limit"])) unless a["limit"].nil?
        end

        old = @thiscategory
        catpath.each do |cat|
          @thiscategory = cat.merge("type" => type)
          html = thing ? parse(thing) : (Php.truthy?(a["title"]) ? escape_title(cat["title"]) : cat["name"])
          content << (link ? do_tag(html, "a", a["linkclass"], %( href="#{pagelinkurl({ 'c' => cat['name'], 'context' => type, 's' => section })}")) : html)
        end
        @thiscategory = old

        return nil if content.empty?

        do_wrap(label != "" ? [ label ] + content : content, a["wraptag"], a["separator"], a["class"])
      end

      def valid_context(context)
        %w[article image file link].each do |t|
          return t if context == t || context == gTxt("#{t}_context")
        end
        "article"
      end

      def tag_evaluate(atts, thing = nil)
        @txp_atts&.delete("evaluate")
        txp_eval(atts, thing)
      end

      # txp_eval(): XPath evaluation (<txp:evaluate query="..." />).
      def txp_eval(atts, thing = nil)
        @txp_atts&.delete("evaluate")
        staged = nil
        a = lAtts({ "alias" => nil, "query" => nil, "test" => !atts.key?("query") }, atts)
        query = a["query"]
        test = a["test"]

        if thing.nil? && atts.key?("test") && atts["test"] != true
          thing = atts["test"]
          test = nil
        end

        if query.nil? || query == true
          x = true
        elsif (query = Php.str(query).strip).empty?
          x = query
        else
          unless a["alias"].nil?
            names = a["alias"] == true ? @variable.keys : Php.do_list(a["alias"])
            unless names.empty?
              query = query.gsub(/\$(#{names.map { |n| Regexp.escape(n) }.join('|')})\b/) do
                var = Php.str(@variable[Regexp.last_match(1)])
                if var != "" && !Php.numeric?(var)
                  var.include?("'") ? "concat('#{var.gsub("'", %(',"'",'))}')" : "'#{var}'"
                else
                  var
                end
              end
            end
          end

          if query.include?("<+>")
            staged = x = true
          else
            x = xpath_evaluate(query)
          end
        end

        if thing.nil?
          return test == true ? Php.truthy?(x) : x
        elsif Php.empty?(x)
          return test.nil? ? false : parse(thing, false)
        end

        @txp_tag = nil

        if !test.nil? && query != true
          @txp_atts = (@txp_atts || {}).merge("evaluate" => test)
          x = parse(thing)
          @txp_atts&.delete("evaluate")
        else
          x = thing
        end

        if @txp_tag != false
          if staged
            quoted = txp_escape("quote", x)
            result = xpath_evaluate(query.gsub("<+>", Php.str(quoted)))
            return test.nil? ? false : parse(thing, false) if result == false

            return result == true ? x : result
          elsif query == true
            x = parse(thing, test.nil? || Php.truthy?(test))
          end
        else
          @txp_atts = nil
          x = test.nil? ? false : parse(thing, false)
        end

        test.nil? && query != true ? Php.truthy?(x) : x
      end

      def xpath_evaluate(query)
        @xpath_doc ||= Nokogiri::XML("<txp/>")
        result = @xpath_doc.xpath(query)
        case result
        when Nokogiri::XML::NodeSet then result.length
        when Float then result.finite? && result == result.to_i ? result.to_i : result
        else result
        end
      rescue Nokogiri::XML::XPath::SyntaxError, RuntimeError => e
        trigger_error(txpspecialchars(e.message), :warning)
        false
      end
    end
  end
end
