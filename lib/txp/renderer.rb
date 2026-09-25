module Txp
  # Per-request template rendering context. It holds the state that
  # Textpattern keeps in globals ($pretext, $thisarticle, $txp_atts, ...) and
  # implements the parser (parse / processTags / splat / lAtts). Tag handlers
  # live in Txp::Tags::* modules which are mixed into this class.
  class Renderer
    include Php
    # PHP-style helpers (txpspecialchars, intval, do_list...) are callable by
    # plugins as txp.txpspecialchars(...), like Textpattern's global functions.
    public(*Php.private_instance_methods(false))
    include HtmlHelpers
    include UrlHelpers
    include DataHelpers
    include DateHelpers
    include Router
    include Feeds
    Tags.modules.each { |m| include m }

    attr_accessor :txp_atts, :pretext, :prefs, :thisarticle, :thiscategory, :thissection, :thisimage,
      :thisfile, :thislink, :thiscomment, :thisauthor, :thispage, :variable, :txp_item, :txp_context,
      :is_article_list, :is_article_body, :is_form, :request, :txp_sections, :txp_current_form,
      :txp_current_tag, :txp_tag, :user, :status, :content_type
    attr_reader :errors, :response_headers, :cookies_to_set, :registry, :trace

    def self.tokenizer(short_tags)
      @tokenizers ||= {}
      @tokenizers[short_tags ? true : false] ||= Tokenizer.new(short_tags: short_tags)
    end

    def initialize(prefs: nil, request: nil, user: nil, registry: Registry.default, pretext: {})
      @prefs = prefs || Pref.site_prefs
      @request = request
      @user = user
      @registry = registry
      @pretext = { "secondpass" => 0, "@txp_atts" => false, "s" => "", "c" => "", "q" => "", "m" => "",
                   "pg" => "", "p" => "", "id" => "", "month" => "", "author" => "", "realname" => "",
                   "context" => "article", "status" => "200", "skin" => "", "page" => "", "css" => "",
                   "f" => "" }.merge(pretext)
      @txp_sections = Section.index_by_name
      @variable = {}
      @txp_item = {}
      @txp_context = {}
      @yield_stack = []
      @txp_yield = Hash.new { |h, k| h[k] = [] }
      @txp_atts = nil
      @txp_tag = nil
      @txp_current_tag = ""
      @txp_current_form = nil
      @is_form = 0
      @is_article_list = true
      @is_article_body = nil
      @errors = []
      @response_headers = {}
      @cookies_to_set = {}
      @form_cache = {}
      @form_stack = Hash.new(0)
      @article_stack = []
      @filter_atts_out = {}
      @sandbox = {}
      @status = 200
      @content_type = nil
      @splat_cache = {}
      @trace = Trace.new
    end

    # ---------------------------------------------------------------------
    # Preferences, language, request

    def get_pref(name, default = "")
      @prefs.key?(name.to_s) ? @prefs[name.to_s] : default
    end

    def production_status
      get_pref("production_status", "testing")
    end

    def lang
      @lang ||= Textpack.normalize(get_pref("language", "en")).presence || "en"
    end

    # Public-side gTxt(): "public" and "common" strings, plus mode.ini's
    # debugging strings when the site is not live.
    def gTxt(key, atts = {}, escape = "html")
      Textpack.txt(lang, key, atts, escape, events: Textpack::PUBLIC_EVENTS, debug: get_pref("production_status") != "live")
    end

    def short_tags?
      truthy?(get_pref("enable_short_tags", "1"))
    end

    def tokenizer
      @tokenizer ||= self.class.tokenizer(short_tags?)
    end

    def params
      @params ||= begin
        get = @request ? @request.query_parameters.to_h : {}
        post = @request ? @request.request_parameters.to_h : {}
        { get: get.transform_keys(&:to_s), post: post.transform_keys(&:to_s) }
      end
    end

    # GET/POST parameter, GET first (gps()).
    def gps(name, default = "")
      name = name.to_s
      if params[:get].key?(name)
        v = params[:get][name]
        v.is_a?(String) ? v.delete("\0").gsub(/[\r\n]/, "") : v
      elsif params[:post].key?(name)
        v = params[:post][name]
        v.is_a?(String) ? v.delete("\0") : v
      else
        default
      end
    end

    def ps(name, default = "")
      v = params[:post].fetch(name.to_s, default)
      v.is_a?(String) ? v.delete("\0") : v
    end

    def psa(names)
      names.index_with { |n| ps(n) }.transform_keys(&:to_s)
    end

    def cs(name)
      return "" unless @request

      @request.cookies[name.to_s].to_s
    end

    def pcs(name)
      params[:post].key?(name.to_s) ? ps(name) : cs(name)
    end

    def set_cookie(name, value, expires: nil)
      @cookies_to_set[name.to_s] = { value: value.to_s, expires: expires, path: "/" }
    end

    def hu
      @hu ||= Txp.site_url(@prefs, @request)
    end

    def rhu
      @rhu ||= hu.sub(%r{\Ahttps?://[^/]+}, "")
    end

    # $siteurl: the site's host and path, without protocol or trailing slash.
    def siteurl
      hu.sub(%r{\Ahttps?://}, "").chomp("/")
    end

    def ihu
      hu
    end

    def ahu
      "#{hu}textpattern/"
    end

    # ---------------------------------------------------------------------
    # Errors

    def trigger_error(message, level = :notice)
      Rails.logger.debug { "[txp] #{level}: #{Php.strip_tags(message)} (#{@txp_current_tag})" }

      # tagErrorHandler(): E_USER_* levels are Textpattern's own errors,
      # :php_warning/:php_notice/:php_deprecated stand for PHP's E_WARNING,
      # E_NOTICE and E_DEPRECATED (shown by its number in debug mode).
      labels = {
        php_warning: "Warning", error: "Textpattern Error", warning: "Textpattern Warning"
      }
      labels.merge!(php_notice: "Notice", notice: "Textpattern Notice", php_deprecated: "8192") if production_status == "debug"
      label = labels[level] if %w[testing debug].include?(production_status)
      return unless label

      page = @pretext["page"].to_s.empty? ? gTxt("none") : @pretext["page"]
      form = @txp_current_form || gTxt("none")
      locus = gTxt("while_parsing_page_form", "{page}" => page, "{form}" => form)
      @errors << %(<pre dir="auto">#{gTxt('tag_error')} <b>#{txpspecialchars(@txp_current_tag)}</b> -> <b> #{label}: #{message} #{locus}</b></pre>)
      return unless production_status == "debug"

      root = "#{Rails.root}/"
      callers = caller_locations(1, 10).map { |l| "#{l.path.delete_prefix(root)}:#{l.lineno} #{l.label}()" }
      @errors << %(\n<pre class="backtrace" dir="ltr"><code>#{txpspecialchars(callers.join("\n"))}</code></pre>)
      @trace.log("#{gTxt('tag_error')} #{@txp_current_tag} -> #{label}: #{message} #{locus}")
    end

    # Whether PHP would have created $_REQUEST by now (see Tags::CLASS_BACKED).
    def request_global!
      @request_global = true
    end

    def request_global?
      @request_global == true
    end

    # PHP's "Trying to access array offset on null" warning, which Textpattern
    # emits when a tag reads a missing context such as $thiscommentsform.
    def null_offset_warning(count = 1)
      count.times { trigger_error("Trying to access array offset on null", :php_warning) }
    end

    def tag_exception(error)
      if error.is_a?(TagError)
        trigger_error(error.message)
      else
        Rails.logger.error("[txp] #{error.class}: #{error.message}\n#{error.backtrace&.first(8)&.join("\n")}")
        raise error if Rails.env.test? && ENV["TXP_RAISE"]

        trigger_error("#{error.class}: #{txpspecialchars(error.message)}", :warning)
      end
    end

    # Aborts rendering with an error page (txp_die()).
    def txp_die(msg, status = "503", url = "")
      raise Die.new(msg, status, url)
    end

    # ---------------------------------------------------------------------
    # Parser

    # parse(): processes the Textpattern tags in a string, honouring
    # <txp:else />, the "not" and "evaluate" global attributes.
    def parse(thing, condition = true, in_tag = true)
      not_flag = false

      if in_tag && @txp_atts && truthy?(@txp_atts["not"])
        condition = empty?(condition)
        not_flag = true
      end

      old_tag = @txp_tag
      @txp_tag = truthy?(condition)
      parsed = thing.nil? ? nil : tokenizer.parse(thing) { |w| trigger_error(gTxt(w.key, w.params), :warning) }

      if parsed.nil?
        out = truthy?(condition) ? (thing.nil? ? "1" : thing) : ""
        out = txp_eval("query" => @txp_atts["$query"], "test" => out) if in_tag && @txp_atts&.key?("$query")
        return out
      end

      tags = parsed.tags
      first = parsed.first
      last = parsed.last

      if truthy?(condition)
        last = first - 2
        first = 1
      elsif first <= last
        first += 2
      else
        return ""
      end

      this_tag = @txp_current_tag
      isempty = false
      dotest = in_tag && @txp_atts && truthy?(@txp_atts["evaluate"])
      evaluate = dotest ? (@txp_atts["evaluate"] == true ? true : do_list(@txp_atts["evaluate"])) : nil
      evaluate = parsed.test if parsed.test && (!evaluate || evaluate == true)
      test = nil

      if evaluate
        test = evaluate.is_a?(Array) ? evaluate.to_h { |k| [ test_key(k), [] ] } : false
        isempty = last >= first
      end

      if !test || test.empty?
        out = Php.str(tags[first - 1]).dup

        while first <= last
          t = tags[first]
          @txp_tag = t
          @txp_current_tag = "#{t[0]}#{t[3]}#{t[4]}"
          nextag = Php.str(process_tags(t[1], t[2], t[3]))
          first += 1
          out << nextag << Php.str(tags[first])
          isempty &&= nextag.strip.empty?
          first += 1
        end
      else
        pre = !test.key?(0)
        test[0] = [] if pre
        outarr = { first - 1 => tags[first - 1] }
        n = first

        while n <= last
          t = tags[n]
          outarr[n] = nil
          ordinal = (n + 1) / 2

          if test.key?(ordinal)
            test[ordinal] << n
            isempty = true
          elsif test.key?(t[1])
            test[t[1]] << n
            isempty = true
          else
            test[0] << n
          end

          n += 1
          outarr[n] = tags[n]
          n += 1
        end

        out = nil
        test.each do |k, list|
          if k == 0 && pre && dotest && isempty == !not_flag
            out = false
            break
          end

          list.each do |idx|
            t = tags[idx]
            @txp_tag = t
            @txp_current_tag = "#{t[0]}#{t[3]}#{t[4]}"
            nextag = Php.str(process_tags(t[1], t[2], t[3]))
            outarr[idx] = nextag
            isempty &&= nextag.strip.empty? if k != 0
          end
        end

        out = outarr.values.map { |v| Php.str(v) }.join if out.nil?
      end

      if dotest && isempty == !not_flag
        out = false
      elsif in_tag && @txp_atts&.key?("$query")
        out = txp_eval("query" => @txp_atts["$query"], "test" => out)
      end

      condition = false if out == false
      @txp_tag = truthy?(old_tag) || truthy?(condition)
      @txp_current_tag = this_tag
      out
    end

    # processTags(): parses a tag's attributes and calls its handler, then
    # applies the remaining global attributes (wraptag, escape, ...).
    def process_tags(tag, atts = "", thing = nil)
      return false if tag.nil? || tag.empty?

      old_atts = @txp_atts

      if atts.is_a?(Hash) || (atts && !atts.empty?)
        split = splat(atts)

        if @txp_atts && @txp_atts["evaluate"].is_a?(String) && @txp_atts["evaluate"].include?("<+>")
          @txp_atts["$query"] = @txp_atts.delete("evaluate")
        end
      else
        @txp_atts = nil
        split = {}
      end

      log = production_status == "debug"
      if log
        # $txp_tag = [opening tag, name, atts, thing, closing tag]
        source = @txp_tag.is_a?(Array) ? @txp_tag : [ "<txp:#{tag} />", tag, atts, thing, nil ]
        tag_stop = Php.str(source[4]).presence
        @trace.start(source[0], "Tags" => [ tag ])
      end
      @txp_tag = nil
      @request_global ||= Tags::CLASS_BACKED.include?(tag)
      out = @registry.process(self, tag, split, thing)

      if out == false
        trigger_error("#{tag} #{gTxt('unknown_tag')}", :warning)
        out = ""
      else
        if @txp_tag.nil? && @txp_atts && truthy?(@txp_atts["not"])
          out = truthy?(out) ? "" : "1"
        elsif @txp_atts&.key?("$query") && @txp_tag != false
          out = txp_eval("query" => @txp_atts["$query"], "test" => out)
        end

        if @txp_atts
          @txp_atts.delete("evaluate")
          @txp_atts.delete("not")
          @txp_atts.delete("$query")
        end

        if @txp_atts && !@txp_atts.empty? && @txp_tag != false
          @pretext["@txp_atts"] = true
          @txp_atts.keys.each do |attr|
            next unless @txp_atts&.key?(attr)
            next if @txp_atts[attr].nil? || !@registry.registered_attr?(attr)

            out = @registry.process_attr(self, attr, @txp_atts, out)
          end
          @pretext["@txp_atts"] = false
        end
      end

      @trace.stop(tag_stop) if log
      @txp_atts = old_atts
      out
    end

    ATTR_RE = /(\$?#{Tokenizer::TAG_NAME})(?:\s*=\s*(?:"((?:[^"]|"")*)"|'((?:[^']|'')*)'|([^\s'"\/>]+)))?/m

    # splat(): converts an attribute string into a Hash, parsing tags in
    # single-quoted values.
    def splat(text)
      globals = @registry.global_atts

      if text.is_a?(Hash)
        @txp_atts = text.select { |k, _| globals.key?(k) }
        return text
      end

      stack, parse_list, global = (@splat_cache[text] ||= begin
        st = {}
        pl = []
        text.scan(ATTR_RE) do |name, dq, sq, uq|
          name = name.downcase
          val = if !dq.nil?
            dq.gsub('""', '"')
          elsif !sq.nil?
            pl << name if sq.include?(":")
            sq.gsub("''", "'")
          elsif !uq.nil?
            trigger_error(gTxt("attribute_values_must_be_quoted"), :warning)
            uq
          else
            true
          end
          st[name] = val
        end
        g = st.select { |k, _| globals.key?(k) }
        [ st.freeze, pl.freeze, g.empty? ? nil : g.freeze ]
      end)

      @txp_atts = global&.dup
      atts = stack.dup
      return atts if parse_list.empty?

      parse_list.each do |p|
        atts[p] = Php.str(parse(atts[p], true, false))
        @txp_atts[p] = atts[p] if @txp_atts&.key?(p)
      end

      atts
    end

    # lAtts(): merges tag attributes with defaults, consuming the global
    # attributes the tag handles itself.
    def lAtts(pairs = {}, atts = {}, warn = true)
      pairs = pairs.transform_keys(&:to_s)
      atts = (atts || {}).dup
      raise TagIntrospection::Grok, pairs.merge(atts) if @pretext["@txp_grok"]

      globals = @registry.global_atts

      if atts.key?("yield") && !pairs.key?("yield")
        parse_qs(atts["yield"]).each do |name, alias_name|
          value = tag_yield({ "name" => alias_name == false ? name : alias_name })
          atts[name] = value unless value.nil?
        end
        atts.delete("yield")
      end

      if atts.key?("offset") && atts["offset"] != true && !numeric?(atts["offset"])
        pageby = atts.key?("limit") ? intval(atts["limit"]) : (pairs.key?("limit") ? intval(pairs["limit"]) : 10)
        atts["offset"] = pageby != 0 ? (intval(gps(atts["offset"], 1)) - 1) * pageby : intval(gps(atts["offset"], 0))
      end

      if !@pretext["@txp_atts"]
        atts.each do |name, value|
          if pairs.key?(name)
            @txp_atts&.delete(name) unless pairs[name].nil?
            pairs[name] = value
          elsif warn && production_status != "live" && !globals.key?(name)
            trigger_error(gTxt("unknown_attribute", "{att}" => name))
          end
        end
      else
        atts.each do |name, value|
          next unless pairs.key?(name) && (!globals.key?(name) || (@txp_atts && !@txp_atts[name].nil?))

          pairs[name] = value
          @txp_atts&.delete(name)
        end
      end

      pairs
    end

    def postpone_process(maxpass = nil)
      @txp_atts = nil
      pass = [ @pretext["secondpass"].to_i + 2, intval(maxpass) ].max - 1

      if pass <= intval(get_pref("secondpass", 1))
        @txp_current_tag
      elsif maxpass.nil?
        trigger_error("#{gTxt('secondpass')} < #{pass}", :warning)
        nil
      end
    end

    # ---------------------------------------------------------------------
    # Templates

    def current_skin
      @pretext["skin"].to_s
    end

    def fetch_form(name, theme = nil)
      theme ||= current_skin
      cache = (@form_cache[theme] ||= {})
      names = do_list_unique(name, "|")
      found = names.last

      names.each do |n|
        return [ n, false ] if n == "*"

        unless cache.key?(n)
          cache[n] = Form.where(name: n, skin: theme).pick(:Form) || false
          if cache[n] == false
            trigger_error(gTxt("form_not_found", "{theme}" => theme, "{form}" => n))
          elsif production_status != "live"
            @trace.log("[Loading form: '#{@pretext['skin']}.#{n}']", "Forms" => [ n ])
          end
        end
        found = n
        break unless cache[n] == false
      end

      [ found, found.nil? ? false : cache[found] ]
    end

    def parse_form(name, theme = nil)
      fname, form = fetch_form(Php.str(name), theme)
      return false if form == false || form.nil?

      depth = intval(get_pref("form_circular_depth", 15))
      depth = 15 if depth <= 0

      if @form_stack[fname] >= depth
        trigger_error(gTxt("form_circular_reference", "{name}" => fname))
        return ""
      end

      @form_stack[fname] += 1
      old_form = @txp_current_form
      @txp_current_form = fname
      @is_form += 1
      out = parse(form)
      @is_form -= 1
      @txp_current_form = old_form
      @form_stack[fname] -= 1
      out
    end

    def fetch_page(name, theme)
      theme = @pretext["skin"] if theme.to_s.empty?
      page = Page.where(name: name.to_s, skin: theme.to_s).pick(:user_html)
      return false if page.nil?

      @trace.log("[Page: '#{theme}.#{name}']", "Pages" => [ name.to_s ])
      page
    end

    def parse_page(name, theme, page = nil)
      page = fetch_page(name, theme) if page.nil? || page == ""
      return false if page == false

      secondpass = intval(get_pref("secondpass", 1))

      while @pretext["secondpass"] <= secondpass && tokenizer.tags?(page)
        @is_form = 1
        page = Php.str(parse(page))
        @pretext["secondpass"] += 1
      end

      page
    end

    # Renders a template string with the current context.
    def render_string(markup)
      Php.str(parse_page(nil, nil, markup))
    end

    # txp_sandbox(): renders an article field that may contain tags.
    def txp_sandbox(atts = {}, thing = nil)
      id = atts["id"]
      field = atts["field"]

      if id.nil? || id == ""
        assert_article
        id = @thisarticle["thisid"] || 0
        article = @thisarticle
      else
        return nil unless @sandbox.key?("article:#{id}")

        article = @sandbox["article:#{id}"]
      end

      if thing
        return nil unless @sandbox.key?(thing)

        thing = @sandbox[thing]
      end

      stack_key = "sandbox:#{id}"
      if field && thing.nil?
        depth = intval(get_pref("form_circular_depth", 15))
        if @form_stack[stack_key] >= depth
          trigger_error(gTxt("form_circular_reference", "{name}" => %(<txp:article id="#{id}"/>)))
          return ""
        end
        @form_stack[stack_key] += 1
      end

      old_article = @thisarticle
      @thisarticle = article
      was_body = @is_article_body
      @is_article_body = article && article["authorid"].to_s != "" ? article["authorid"] : true
      was_form = @is_form
      @is_form = 0

      out = if thing
        Php.str(parse(thing))
      elsif field && article && article.key?(field)
        Php.str(parse(Php.str(article[field])))
      else
        ""
      end

      @is_article_body = was_body
      @is_form = was_form
      @thisarticle = old_article
      @form_stack[stack_key] -= 1 if field && thing.nil?

      if @pretext["secondpass"] >= intval(get_pref("secondpass", 1)) || !tokenizer.tags?(out)
        return out
      end

      hash = Digest::MD5.hexdigest(out)
      @sandbox[hash] = out
      @sandbox["article:#{id}"] ||= article
      %(<txp:#{Tags::SANDBOX_TAG} id="#{id}">#{hash}</txp:#{Tags::SANDBOX_TAG}>)
    end

    def tag_txp_sandbox(atts, thing = nil)
      txp_sandbox(atts, thing)
    end

    # ---------------------------------------------------------------------
    # Context assertions

    # assert_context(): outside a live site a missing context aborts the tag
    # with an error. On a live site Textpattern carries on with the empty
    # (null) context, which an empty Hash mirrors here: every field reads as
    # nil and fields set by the tag (e.g. comment_anchor) are kept.
    def assert_context(type)
      value = instance_variable_get(:"@this#{type}")
      return true unless value.nil? || (value.respond_to?(:empty?) && value.empty?)
      raise TagError, gTxt("error_#{type}_context") if production_status != "live"

      instance_variable_set(:"@this#{type}", {}) unless value.is_a?(Hash)
      false
    end

    def assert_article = assert_context("article")
    def assert_comment = assert_context("comment")
    def assert_file = assert_context("file")
    def assert_image = assert_context("image")
    def assert_link = assert_context("link")
    def assert_section = assert_context("section")
    def assert_category = assert_context("category")

    def article_push
      @article_stack.push(@thisarticle)
    end

    def article_pop
      @thisarticle = @article_stack.pop
    end

    def php_str(value)
      Php.str(value)
    end

    private

    def test_key(key)
      return key if key.is_a?(Integer)

      s = key.to_s
      s.match?(/\A-?\d+\z/) ? s.to_i : s
    end
  end
end
