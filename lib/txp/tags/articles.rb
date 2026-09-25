module Txp
  module Tags
    # Article tags: <txp:article />, <txp:article_custom /> and friends.
    module Articles
      ARTICLE_COLUMN_MAP_BASE = {
        "thisid" => "ID", "posted" => "uPosted", "expires" => "uExpires", "modified" => "uLastMod",
        "annotate" => "Annotate", "comments_invite" => "AnnotateInvite", "authorid" => "AuthorID",
        "title" => "Title", "url_title" => "url_title", "description" => "description",
        "category1" => "Category1", "category2" => "Category2", "section" => "Section",
        "keywords" => "Keywords", "article_image" => "Image", "comments_count" => "comments_count",
        "body" => "Body_html", "excerpt" => "Excerpt_html", "override_form" => "override_form",
        "status" => "Status", "uid" => "uid"
      }.freeze

      AGGREGATE = {
        "avg" => "AVG(?)", "max" => "MAX(?)", "min" => "MIN(?)", "sum" => "SUM(?)",
        "list" => "GROUP_CONCAT(?, ',')", "concat" => "GROUP_CONCAT(?, ',')"
      }.freeze

      WINDOWED = {
        "count" => "COUNT(*)", "dense" => "DENSE_RANK()", "rank" => "RANK()", "row" => "ROW_NUMBER()"
      }.freeze

      DATE_FIELDS = { "posted" => "Posted", "modified" => "LastMod", "expires" => "Expires" }.freeze

      def article_column_map
        @article_column_map ||= begin
          map = ARTICLE_COLUMN_MAP_BASE.dup
          custom_fields.each { |i, name| map[name] = "custom_#{i}" unless map.key?(name) }
          map
        end
      end

      def core_columns
        {
          "posted" => DB.timestamp("Posted", "uPosted"),
          "expires" => DB.timestamp("Expires", "uExpires"),
          "modified" => DB.timestamp("LastMod", "uLastMod")
        }.merge(article_column_map) { |_k, old, _new| old }
      end

      def article_select_all
        "*, #{DB.timestamps('Posted' => 'uPosted', 'Expires' => 'uExpires', 'LastMod' => 'uLastMod')}"
      end

      # populateArticleData()
      def populate_article_data(row, all = true)
        @thisarticle = {} if all || @thisarticle.nil?
        article_column_map.each do |key, column|
          if row.key?(column)
            @thisarticle[key] = row[column]
          elsif all
            @thisarticle[key] = nil
          end
        end
        %w[posted expires modified].each do |k|
          v = @thisarticle[k]
          @thisarticle[k] = DB.to_unix(v) unless v.nil? || v.is_a?(Integer)
        end
        @thisarticle
      end

      def article_row_to_data(row)
        article_column_map.to_h { |key, column| [ key, row[column] ] }
      end

      def status_list(exclude = [])
        STATUSES.reject { |k, _| exclude.include?(k) }
      end

      # filterAtts(): builds the article query from tag attributes.
      def filter_atts(atts = nil, iscustom = nil)
        if atts == false
          return @filter_atts_out = {}
        elsif atts.nil?
          return @filter_atts_out
        elsif atts.is_a?(Hash) && atts.key?("?")
          return @filter_atts_out = atts
        end

        s = Php.empty?(@pretext["s"]) ? "default" : @pretext["s"]
        excluded = atts == true ? "" : (atts["exclude"] || "")
        excludid = []

        if Php.truthy?(excluded) && excluded != true
          excluded = Php.do_list_unique(excluded).map(&:downcase)
          excludid = excluded.select { |e| Php.numeric?(e) }
          excluded -= excludid
        else
          excluded = [] if Php.empty?(excluded)
        end
        excluded = excluded == true ? true : excluded.index_with(true)
        excluded_has = ->(k) { excluded.is_a?(Hash) && excluded.key?(k) }
        custom = iscustom && Php.intval(iscustom) >= 0

        extral = {
          "form" => "default", "allowoverride" => !iscustom, "limit" => 10, "offset" => 0, "pageby" => nil,
          "pgonly" => 0, "wraptag" => "", "break" => "", "label" => "", "labeltag" => "", "class" => "",
          "searchall" => !iscustom && Php.truthy?(@pretext["q"]) && s == "default"
        }

        sort_atts = {
          "fields" => nil, "sort" => "", "image" => "", "keywords" => "", "time" => nil,
          "status" => atts == true || Php.empty?(atts["id"]) ? STATUS_LIVE : true,
          "frontpage" => !iscustom && (Php.empty?(@pretext["s"]) || @pretext["s"] == "default"),
          "match" => "Category", "depth" => 0, "id" => excluded_has.call("id") ? true : "",
          "excerpted" => "", "exclude" => ""
        }

        if custom
          sort_atts.merge!(
            "category" => excluded_has.call("category") ? true : "",
            "section" => excluded_has.call("section") ? true : "",
            "author" => excluded_has.call("author") ? true : "",
            "month" => excluded_has.call("month") ? true : "",
            "expired" => excluded_has.call("expired") ? true : get_pref("publish_expired_articles")
          )
        else
          sort_atts.merge!(
            "category" => Php.truthy?(@pretext["c"]) ? @pretext["c"] : "",
            "section" => Php.truthy?(@pretext["s"]) && @pretext["s"] != "default" ? @pretext["s"] : "",
            "author" => Php.truthy?(@pretext["author"]) ? @pretext["author"] : "",
            "month" => Php.truthy?(@pretext["month"]) ? @pretext["month"] : "",
            "expired" => get_pref("publish_expired_articles")
          )
          extral.merge!("listform" => "", "searchform" => "", "searchsticky" => 0)
        end

        core_atts = sort_atts.merge(extral)
        return core_atts if atts == true

        cfields = custom_fields.merge("url_title" => "url_title")
        post_where = {}
        custom_pairs = {}
        customl = {}

        cfields.each do |num, field|
          customl[field] = nil
          if atts.key?("custom_#{num}")
            custom_pairs[field] = atts["custom_#{num}"]
            customl["custom_#{num}"] = nil
          elsif excluded_has.call(field)
            custom_pairs[field] = true
          end
        end

        atts = atts.dup
        (WINDOWED.keys + core_columns.keys).each do |field|
          next unless atts.key?("$#{field}")

          post_where["$#{field}"] = atts.delete("$#{field}")
          @txp_atts&.delete("$#{field}")
        end

        q = iscustom ? "" : Php.str(@pretext["q"]).strip
        the = lAtts(core_atts.merge(customl), atts)
        status = the["status"]
        issticky = %w[sticky 5].include?(Php.str(status).downcase)

        status = if status == true
          [ STATUS_LIVE, STATUS_STICKY ]
        elsif issticky
          [ STATUS_STICKY ]
        else
          allowed = status_list([ STATUS_DRAFT, STATUS_HIDDEN ])
          list = Php.do_list(status).filter_map do |st|
            if Php.numeric?(st)
              allowed.key?(st.to_i) ? st.to_i : nil
            else
              allowed.key(st)
            end
          end.uniq
          list.empty? ? [ STATUS_LIVE ] : list
        end

        # Categories
        operator = "AND"
        match = Php.parse_qs(the["match"])
        if match.key?("category")
          match["category1"] = match["category"] unless match.key?("category1")
          match["category2"] = match["category"] unless match.key?("category2")
          operator = "OR"
        end

        category = the["category"]
        depth = the["depth"]
        categories = category == true ? false : Php.do_list_unique(category)
        if categories.is_a?(Array) && categories.any?
          if Php.truthy?(depth)
            categories = get_tree_names(categories, "article", depth)
            categories = [ "/" ] if categories.empty?
          end
          categories = DB.quote_list(categories)
        else
          categories = false
        end

        catquery = []
        (1..2).each do |i|
          negate = excluded_has.call("category#{i}") ? "NOT " : ""
          if match.key?("category#{i}")
            if match["category#{i}"] == false
              if categories
                catquery << "#{negate}(Category#{i} IN (#{categories}))"
              elsif category == true || negate != ""
                catquery << "#{negate}(Category#{i} != '')"
              end
            elsif (val = gps(match["category#{i}"], false)) != false
              cats = Php.truthy?(depth) ? get_tree_names(Php.do_list(val), "article", depth) : Php.do_list(val)
              catquery << (cats.any? ? "#{negate}(Category#{i} IN (#{DB.quote_list(cats)}))" : "#{negate}0")
            end
          elsif negate != ""
            catquery << "(Category#{i} = '')"
          end
        end

        negate = (iscustom && excluded == true) || excluded_has.call("category") ? "NOT " : ""
        catsql = catquery.empty? ? "" : " AND #{negate}(#{catquery.join(" #{operator} ")})"

        # ID
        negate = excluded == true || excluded_has.call("id") ? "NOT" : ""
        idatt = the["id"]
        ids = if Php.truthy?(idatt)
          idatt == true ? Php.str(tag_article_id({})) : Php.do_list_unique(idatt, [ ",", "-" ]).map { |v| Php.intval(v) }.join(",")
        else
          false
        end
        idsql = (ids ? " AND ID #{negate} IN (#{ids})" : "") + (excludid.empty? ? "" : " AND ID NOT IN (#{excludid.map(&:to_i).join(',')})")
        getid = ids && negate == ""

        # Section
        section = the["section"]
        searchall = the["searchall"]
        section = "" if q != "" && Php.truthy?(searchall) && !issticky
        negate = (iscustom && excluded == true) || excluded_has.call("section") ? "NOT" : ""
        section = tag_section({}) if section == true
        secsql = (Php.empty?(section) ? "" : " AND Section #{negate} IN (#{DB.quote_list(Php.do_list_unique(section))})") +
          (getid || (Php.truthy?(section) && negate == "") || Php.truthy?(searchall) ? "" : filter_front_page("Section", [ "page" ]))

        # Author
        negate = (iscustom && excluded == true) || excluded_has.call("author") ? "NOT" : ""
        author = the["author"]
        author = tag_author({ "escape" => "", "title" => "" }) if author == true
        authsql = Php.empty?(author) ? "" : " AND AuthorID #{negate} IN (#{DB.quote_list(Php.do_list_unique(author))})"

        frontpage = the["frontpage"]
        frontsql = Php.truthy?(frontpage) && (q == "" || issticky) ? filter_front_page("Section", [ "on_frontpage" ], Php.intval(frontpage).negative?) : ""
        excerptsql = Php.empty?(the["excerpted"]) ? "" : " AND Excerpt != ''"

        # Time
        time = the["time"]
        month = the["month"]
        expired = the["expired"]
        timeq = ""
        if time.nil? || Php.truthy?(month) || Php.empty?(expired) || Php.str(expired) == "1"
          negate = (Php.truthy?(month) || !time.nil?) && ((iscustom && excluded == true) || excluded_has.call("month"))
          t = build_time_sql(month == true ? "" : month, time.nil? ? "past" : time)
          timeq = " AND #{negate ? "NOT (#{t})" : t}"
        end

        if Php.truthy?(expired) && Php.str(expired) != "1"
          timeq += " AND #{build_time_sql(expired, time.nil? && site_strtotime(expired).nil? ? 'any' : time, 'Expires')}"
        elsif Php.empty?(expired)
          timeq += " AND (Expires IS NULL OR #{DB.now} <= Expires)"
        end

        statusq = q != "" && Php.truthy?(the["searchsticky"]) ? " AND Status >= #{STATUS_LIVE}" : " AND Status IN (#{status.join(',')})"

        # Images and keywords
        keyquery = +""
        { "article_image" => "Image", "keywords" => "Keywords" }.each do |field, col|
          attr = col.downcase
          val = the[attr]
          negate = excluded == true || excluded_has.call(attr) ? "NOT " : ""
          parts = []
          if val == true
            parts << "#{col} != ''"
          else
            if Php.empty?(val) && match.key?(attr)
              val = match[attr] == false && @thisarticle&.key?(field) ? @thisarticle[field] : gps(match[attr] || attr)
            end
            Php.do_list_unique(val).each { |key| parts << "FIND_IN_SET(#{q key}, #{col})" } if Php.truthy?(val)
          end
          keyquery << " AND #{negate}(#{parts.join(' OR ')})" if parts.any?
        end

        # Search
        sort = the["sort"]
        search = score = ""
        if q != "" && !issticky
          s_filter = if Php.truthy?(searchall)
            filter_front_page("Section", [ "searchable" ])
          else
            s == "default" ? filter_front_page : ""
          end
          quoted = q.start_with?('"') && q.end_with?('"') && q.length > 1
          qq = quoted ? q[1..-2].strip : q
          m = Php.str(@pretext["m"])
          cols = Php.do_list_unique(get_pref("searchable_article_fields"))
          cols = %w[Title Body] if cols.empty?
          cols = cols.select { |c| c.match?(/\A\w+\z/) }

          if Php.empty?(sort) || Php.str(sort).include?("score")
            score = ", TXP_SCORE(#{q qq}, #{cols.map { |c| "`#{c}`" }.join(', ')}) AS score"
            sort = "score DESC, Posted DESC" if Php.empty?(sort)
          end

          like = ->(term) { q("%#{term.gsub(/[\\%_]/) { |c| "\\#{c}" }}%") }
          terms = qq.gsub(/\s+/, " ")
          conds = if quoted || m == "" || m == "exact"
            cols.map { |c| "`#{c}` LIKE #{like.call(terms)} ESCAPE '\\'" }
          else
            join = m == "all" ? " AND " : " OR "
            words = terms.split(" ")
            cols.map { |c| "(#{words.map { |w| "`#{c}` LIKE #{like.call(w)} ESCAPE '\\'" }.join(join)})" }
          end
          search = " AND (#{conds.join(' OR ')}) #{s_filter}"
          fname = Php.truthy?(the["searchform"]) ? the["searchform"] : "search_results"
        else
          fname = @is_article_list && !Php.empty?(the["listform"]) ? the["listform"] : the["form"]
        end

        # URL titles
        url_title = the["url_title"]
        atts["url_title"] = Php.do_list_unique(url_title) if Php.truthy?(url_title) && url_title != true

        # Custom fields
        cfields.each_value do |cf|
          custom_pairs[cf] = atts[cf] if atts.key?(cf) && !extral.key?(cf) && !sort_atts.key?(cf)
          next unless match.key?(cf)

          if match[cf] == false && @thisarticle&.key?(cf)
            custom_pairs[cf] = @thisarticle[cf]
          elsif (val = gps(match[cf] == false ? cf : match[cf], false)) != false
            custom_pairs[cf] = val
          end
        end

        sort = Php.truthy?(sort) ? sanitize_for_sort(sort) : ""
        fields = the["fields"]
        groupby = {}
        what = {}
        partition = {}
        if Php.truthy?(fields) && fields != true
          what, groupby, partition, fields_sort = build_article_fields(Php.str(fields), sort, custom_pairs)
          sort = fields_sort
        end

        custom_sql = build_custom_sql(cfields, custom_pairs, excluded)
        post_where = what.empty? ? {} : post_where.slice(*what.keys)

        fields_sql = if what.any?
          (groupby.any? ? "COUNT(*) AS count, " : "") + what.values.join(", ") + score
        else
          core_columns.values.join(", ") + score
        end

        out = the.dup
        out["status"] = status.join(",")
        out["id"] = ids
        out["form"] = fname
        out["sort"] = Php.truthy?(sort) ? sort : (getid ? "FIELD(ID, #{ids})" : "Posted DESC")
        out["%"] = groupby.empty? ? nil : groupby.keys.join(", ")
        out["$"] = "1#{timeq}#{idsql}#{catsql}#{secsql}#{frontsql}#{excerptsql}#{authsql}#{statusq}#{keyquery}#{search}#{custom_sql}"
        out["?"] = out["$"] + (groupby.empty? ? "" : " GROUP BY #{groupby.keys.join(', ')}")
        out["#"] = "textpattern"
        out["*"] = fields_sql

        if post_where.any?
          out["%"] = nil
          out["#"] = "(SELECT #{out['*']} FROM #{out['#']} WHERE #{out['?']}) AS textpattern"
          out["*"] = "*"
          out["$"] = out["?"] = "1#{build_custom_sql(nil, post_where, excluded)}"
        end

        @filter_atts_out = out.except(*extral.keys) unless iscustom
        out
      end

      # Parses the "fields" attribute (grouping/aggregates).
      def build_article_fields(fields, sort, custom_pairs)
        column_map = DATE_FIELDS.merge(article_column_map) { |_k, old, _new| old }
        reg_fields = (column_map.keys.map { |k| Regexp.escape(k) } + [ "\\*" ]).join("|")
        agg_reg = AGGREGATE.keys.join("|")
        regexp = "#{agg_reg}|#{WINDOWED.keys.join('|')}|date|day|month|year|week|quarter"
        pattern = /(?<=,|^)\s*(?:(#{regexp})(?:\[([^\]]*)\])?\((?:\s*(#{agg_reg})\(\s*)?)?(#{reg_fields})(\s+asc|\s+desc)?\s*\){0,2}\s*(?:,|$)/
        what = {}
        aliases = {}
        groupby = {}
        sortby = {}
        partition = {}
        groupped = true
        add_fields = false
        psort = sort

        fields.downcase.scan(pattern).each do |func, format, _inner, field, dir|
          dir = dir.to_s
          column = column_map[field] || "ID"
          format = format.to_s

          if WINDOWED.key?(func)
            if format == "*"
              parby = groupby.values.join(", ")
              groupped = false
            else
              parby = format.empty? ? "%" : format
            end
            if func == "count"
              pat = "(? OVER (PARTITION BY #{parby}))"
            else
              orderby = field == "*" ? psort : "`#{column}`#{dir}"
              pat = "(? OVER (PARTITION BY #{parby} ORDER BY #{orderby}))"
              sort = "" if field == "*"
            end
            key = field == "*" ? "$#{func}" : "$#{field}"
            what[key] = WINDOWED[func]
            aliases[key] = " AS `#{key}`"
            sortby[key] = ""
            partition[key] = pat
            custom_pairs.delete(field)
          elsif func.nil? && field == "*"
            add_fields = true
            groupped = false
          else
            custom = "`#{column}`"
            aliases[field] = func ? " AS `#{column}`" : ""
            sortby[column] = dir

            if func.nil?
              groupped = false if field == "thisid"
              what[field] = custom
              groupby[custom] = custom
            elsif AGGREGATE.key?(func)
              sep = format.empty? ? "," : format
              what[field] = AGGREGATE[func].sub("?", custom).sub("','", q(sep))
              parby = groupby.values.join(", ")
              if !format.empty? && func != "list"
                partition[field] = format == "*" ? "(? OVER (PARTITION BY #{parby}))" : "(? OVER (PARTITION BY #{format}))"
              end
            else
              what[field] = "MIN(#{custom})"
              expr = format.empty? ? "#{func.upcase}(#{custom})" : "DATE_FORMAT(#{custom}, #{q format})"
              groupby[expr] = custom
            end

            if DATE_FIELDS.key?(field)
              what["u#{field}"] = DB.timestamp(what[field])
              aliases["u#{field}"] = " AS `u#{column}`"
            end
          end
        end

        parby = groupby.values.join(", ")
        what.each_key do |field|
          what[field] = partition[field].sub("?", what[field]).gsub("%", parby) if partition.key?(field)
          what[field] = "#{what[field]}#{aliases[field]}"
        end

        if add_fields
          cc = core_columns
          column_map.each_key { |f| what[f] = cc[f] if !what.key?(f) && cc.key?(f) }
        end

        groupby = {} unless groupped
        sort = sortby.map { |k, v| "#{k}#{v}" }.join(", ") if Php.empty?(sort)
        [ what, groupby, partition, sort ]
      end

      # parseList(): iterates rows, rendering a form/container per item.
      def parse_list(rows, type, populate: nil, form: "", thing: nil, allowoverride: false)
        return [] if rows.nil? || rows.empty?

        breakby = @txp_atts&.[]("breakby") || ""
        breakform = @txp_atts&.[]("breakform") || ""
        ivar = :"@this#{type}"
        store = instance_variable_get(ivar)
        last = rows.length
        count = 0
        chunk = false
        articles = []
        old_item = @txp_item
        @txp_item = @txp_item.merge("total" => last)
        @txp_item.delete("breakby")
        groupmap = {}
        oldobject = nil

        groupby = if Php.empty?(breakby)
          false
        elsif Php.numeric?(Php.str(breakby).tr(" ,-", "000"))
          3
        elsif tokenizer.tags?(Php.str(breakby))
          php_allowed?("form") ? 1 : 0
        else
          2
        end
        groupby = false if groupby == 0

        if groupby == 3
          breaknum = Php.do_list(breakby).map(&:to_i).reject(&:zero?)
          list = (1..last).to_a
          if breaknum.any?
            i = 0
            item = 0
            while list.any?
              n = breaknum[i]
              newlist = n.positive? ? list.shift(n) : list.pop(-n)
              newlist.each { |pos| groupmap[pos] = item }
              i = (i + 1) % breaknum.length
              item += 1
            end
          else
            groupby = false
          end
        end

        while count <= last
          count += 1
          row = rows[count - 1]

          if row
            obj = populate ? populate.call(row) : row.dup
            obj = obj.merge("is_first" => count == 1, "is_last" => count == last)
            instance_variable_set(ivar, obj)
            @txp_item["count"] = row["count"] || count
            newbreak = case groupby
            when false then count
            when 1 then parse(breakby, true, false)
            when 2 then parse_form(breakby)
            else groupmap[count]
            end
          else
            newbreak = nil
          end

          if @txp_item.key?("breakby") && newbreak != @txp_item["breakby"]
            if groupby && Php.truthy?(breakform)
              tmp = instance_variable_get(ivar)
              instance_variable_set(ivar, oldobject)
              newform = Php.str(parse_form(breakform))
              chunk = newform.gsub("<+>", Php.str(chunk))
              instance_variable_set(ivar, tmp)
            end

            if chunk != false
              if groupby == 3
                articles[groupmap[count - 1]] = chunk
              else
                articles << chunk
              end
              chunk = false
            end
          end

          if count <= last
            item = false
            if allowoverride && row && !Php.empty?(row["override_form"])
              item = parse_form(row["override_form"], @txp_sections.dig(row["Section"], "skin"))
            elsif Php.truthy?(form)
              item = parse_form(form)
            end
            item = parse(thing) if item == false && !thing.nil?
            chunk = "#{chunk || ''}#{Php.str(item)}" unless item == false
          end

          oldobject = instance_variable_get(ivar)
          @txp_item["breakby"] = newbreak
        end

        if groupby && @txp_atts
          @txp_atts.delete("breakby")
          @txp_atts.delete("breakform")
        end

        @txp_item = old_item
        instance_variable_set(ivar, store)
        articles.compact
      end

      def tag_article(atts, thing = nil)
        parse_articles(atts, @is_article_body ? -1 : false, thing)
      end

      def tag_article_custom(atts, thing = nil)
        parse_articles(atts, "1", thing)
      end

      def parse_articles(atts, iscustom = false, thing = nil)
        old_ial = @is_article_list
        @is_article_list = Php.truthy?(iscustom) || Php.empty?(@pretext["id"])
        article_push
        out = @is_article_list ? do_articles(atts, iscustom, thing) : do_article(atts, thing)
        article_pop
        @is_article_list = old_ial
        out
      end

      def do_articles(atts, iscustom, thing = nil)
        atts = atts.merge("form" => "") if !thing.nil? && !atts.key?("form")
        the = filter_atts(atts, iscustom)
        issticky = the["status"] == STATUS_STICKY.to_s
        pg = Php.empty?(@pretext["pg"]) ? 1 : Php.intval(@pretext["pg"])
        pgonly = the["pgonly"]
        limit = the["limit"]
        pageby = the["pageby"]
        offset = the["offset"]
        custom_pg = Php.truthy?(pgonly) && pgonly != true && !Php.numeric?(pgonly)
        pgby = Php.intval(pageby.nil? || pageby == true ? (custom_pg || Php.empty?(limit) ? 1 : limit) : pageby)

        if offset == true || (!Php.truthy?(iscustom) && !issticky)
          offset = offset == true ? 0 : Php.intval(offset)
          pgoffset = (pg - 1) * pgby + offset
        else
          pgoffset = offset = Php.intval(offset)
        end

        groupby = if custom_pg
          Php.str(pgonly).strip
        elsif the["%"]
          the["%"]
        end

        columns = the["*"]
        where = the["$"]
        tables = the["#"]
        what = groupby.nil? || groupby == "" ? "1" : "DISTINCT #{groupby}"
        limit_sql = pgoffset.positive? || Php.truthy?(limit) ? "LIMIT #{pgoffset.to_i}, #{Php.truthy?(limit) ? Php.intval(limit) : (1 << 62)}" : ""

        if pageby == true || (!Php.truthy?(iscustom) && !issticky)
          if pageby == true || (@thispage.nil? && (pageby.nil? || Php.truthy?(pageby)))
            grand_total = DB.field("SELECT COUNT(#{what}) FROM #{tables} WHERE #{where}").to_i
            total = grand_total - offset.to_i
            num_pages = pgby.positive? ? (total.to_f / pgby).ceil : 1
            @thispage = {
              "pg" => pg, "numPages" => num_pages, "s" => Php.empty?(@pretext["s"]) ? "default" : @pretext["s"],
              "c" => Php.str(@pretext["c"]), "context" => "article", "grand_total" => grand_total, "total" => total
            }
          end
          return "" if Php.truthy?(pgonly)
        elsif Php.truthy?(pgonly)
          if pgby.positive?
            total = DB.field("SELECT COUNT(#{what}) FROM #{tables} WHERE #{where}").to_i
            return ((total - offset.to_i).to_f / pgby).ceil
          else
            return limit_sql != "" ? DB.field("SELECT COUNT(*) FROM (SELECT #{what} FROM #{tables} WHERE #{where} #{limit_sql}) AS tmp") : DB.field("SELECT EXISTS(SELECT 1 FROM #{tables} WHERE #{where})")
          end
        end

        rows = DB.rows("SELECT #{columns} FROM #{tables} WHERE #{the['?']} ORDER BY #{the['sort']} #{limit_sql}")
        articles = parse_list(rows, "article", populate: ->(r) { populate_article_data(r) },
          form: the["form"], thing: thing, allowoverride: Php.truthy?(the["allowoverride"]))

        if articles.any?
          do_label(the["label"], the["labeltag"]) + do_wrap(articles, the["wraptag"], { "break" => the["break"], "class" => the["class"] })
        else
          Php.truthy?(thing) ? parse(thing, false) : ""
        end
      end

      def do_article(atts, thing = nil)
        atts = atts.merge("form" => "") if !thing.nil? && !atts.key?("form")
        old_atts = filter_atts
        atts = filter_atts(atts)
        preview = Php.truthy?(@pretext["@txp_preview"])
        return "" if Php.truthy?(atts["pgonly"])

        if @thisarticle.nil? || @thisarticle.empty? || Php.str(@thisarticle["thisid"]) != Php.str(@pretext["id"])
          id = Php.intval(@pretext["id"])
          @thisarticle = nil
          where = preview ? "1" : atts["?"]
          row = DB.row("SELECT #{atts['*']} FROM textpattern WHERE ID = #{id} AND #{where}")
          if row
            populate_article_data(row)
            @thisarticle["is_first"] = @thisarticle["is_last"] = true
          end
        end

        article = false
        if @thisarticle && !@thisarticle.empty? && (Php.in_list(@thisarticle["status"], atts["status"]) || preview)
          @thisarticle["is_first"] = @thisarticle["is_last"] = true

          if Php.truthy?(atts["allowoverride"]) && Php.truthy?(@thisarticle["override_form"])
            article = parse_form(@thisarticle["override_form"])
          elsif Php.truthy?(atts["form"])
            article = parse_form(atts["form"])
          end

          article = parse(thing) if !thing.nil? && article == false

          if article != false && Php.truthy?(get_pref("use_comments")) && Php.truthy?(get_pref("comments_auto_append"))
            article = "#{article}#{parse_form('comments_display')}"
          end

          @thisarticle = nil
        else
          filter_atts(old_atts && !old_atts.empty? ? old_atts : false)
        end

        article != false ? article : (Php.truthy?(thing) ? parse(thing, false) : "")
      end

      # getNextPrev(): neighbouring articles according to the list sort order.
      def get_next_prev
        atts = filter_atts
        atts = filter_atts({}) if atts.nil? || atts.empty?
        atts = atts.dup
        assert_article
        return {} unless @thisarticle.is_a?(Hash)

        atts["thisid"] = @thisarticle["thisid"]
        sort = Php.str(atts["sort"].presence || "Posted DESC").strip

        if sort.empty?
          sortby = Php.truthy?(atts["id"]) ? "FIELD(ID, #{atts['id']})" : "Posted"
          sortdir = Php.truthy?(atts["id"]) ? "ASC" : "DESC"
        elsif (m = sort.match(/\A([$\w-\u{FFFF}]+|`[^`]+`)(\s+asc|\s+desc)?\z/i))
          sortby = m[1].delete("`").strip
          sortdir = m[2] ? m[2].strip : "ASC"
        elsif (m = sort.match(/\A(.+?)\s+(asc|desc)\z/i))
          sortby = m[1].strip
          sortdir = m[2]
        else
          sortby = "Posted"
          sortdir = "DESC"
        end

        threshold_type = "cooked"
        threshold = case sortby.downcase
        when "posted" then DB.unixtime(@thisarticle["posted"])
        when "expires" then DB.unixtime(@thisarticle["expires"])
        when "lastmod" then DB.unixtime(@thisarticle["modified"])
        else
          threshold_type = "raw"
          acm = article_column_map.invert
          key = acm.find { |col, _| col.casecmp?(sortby) }&.last
          key ? @thisarticle[key] : DB.field("SELECT #{sortby} FROM textpattern WHERE ID = #{Php.intval(atts['thisid'])}")
        end

        atts["sortby"] = sortby
        atts["sortdir"] = sortdir
        {
          ">" => get_neighbour(threshold, ">", atts, threshold_type),
          "<" => get_neighbour(threshold, "<", atts, threshold_type)
        }
      end

      def get_neighbour(threshold, type, atts, threshold_type = "raw")
        @neighbours ||= {}
        key = [ threshold, type, atts.values_at("?", "sortby", "sortdir", "thisid") ].hash
        return @neighbours[key] if @neighbours.key?(key)

        thisid = Php.intval(atts["thisid"])
        sortdir = Php.str(atts["sortdir"]).downcase == "desc" ? "desc" : "asc"
        sortby = atts["sortby"] || "Posted"
        op = type == ">" ? (sortdir == "desc" ? ">" : "<") : (sortdir == "desc" ? "<" : ">")
        threshold = q(Php.str(threshold)) unless threshold_type == "cooked"
        where = atts["?"] || "1"
        tables = atts["#"] || "textpattern"
        columns = atts["*"] == "*" || atts["*"].nil? ? article_select_all : "#{article_select_all.sub('*', 'textpattern.*')}"
        columns = article_select_all if tables == "textpattern"
        dir = op == "<" ? "DESC" : "ASC"

        sql = "SELECT #{columns} FROM #{tables} WHERE (#{sortby} #{op} #{threshold} OR " \
              "#{thisid.positive? ? "#{sortby} = #{threshold} AND ID #{op} #{thisid}" : '0'}) AND #{where} " \
              "ORDER BY #{sortby} #{dir}, ID #{dir} LIMIT 1"
        row = DB.rows(sql).first
        @neighbours[key] = row || false
      rescue ActiveRecord::StatementInvalid => e
        trigger_error(txpspecialchars(e.message), :warning)
        @neighbours[key] = false
      end

      def neighbour(dir)
        assert_article
        @thisarticle.merge!(get_next_prev) unless @thisarticle.key?(dir)
        @thisarticle[dir]
      end

      # Article data tags -------------------------------------------------------

      def tag_article_id(_atts = {}, _thing = nil)
        assert_article
        @thisarticle["thisid"]
      end

      def tag_article_url_title(_atts = {}, _thing = nil)
        assert_article
        @thisarticle["url_title"]
      end

      def tag_if_article_id(atts, thing = nil)
        a = lAtts({ "id" => @pretext["id"] }, atts)
        x = Php.truthy?(a["id"]) && @thisarticle && !@thisarticle["thisid"].nil? && Php.in_list(@thisarticle["thisid"], a["id"])
        thing.nil? ? x : parse(thing, x)
      end

      def tag_if_article_status(atts, thing = nil)
        a = lAtts({ "status" => "live" }, atts)
        status = a["status"] == true ? "live, sticky" : a["status"]
        allowed = Php.do_list(status).filter_map do |v|
          Php.numeric?(v) ? (STATUSES.key?(v.to_i) ? v.to_i.to_s : nil) : STATUSES.key(v)&.to_s
        end
        x = Php.truthy?(status) && @thisarticle && !@thisarticle["status"].nil? && allowed.include?(Php.str(@thisarticle["status"]))
        thing.nil? ? x : parse(thing, x)
      end

      def tag_if_expires(_atts, thing = nil)
        assert_article
        x = Php.truthy?(@thisarticle["expires"])
        thing.nil? ? x : parse(thing, x)
      end

      def tag_if_expired(atts, thing = nil)
        a = lAtts({ "date" => "expires", "time" => nil }, atts)
        now = a["time"].nil? ? Time.now.to_i : site_strtotime(a["time"]).to_i
        x = case a["date"]
        when "expires", "posted", "modified"
          assert_article
          v = @thisarticle[a["date"]]
          Php.truthy?(v) && v.to_i <= now
        else
          (site_strtotime(a["date"]) || Float::INFINITY) <= now
        end
        thing.nil? ? x : parse(thing, x)
      end

      def tag_author(atts, _thing = nil)
        a = lAtts({ "escape" => "html", "link" => 0, "title" => 1, "section" => "", "this_section" => 0, "format" => "" }, atts)
        link = a["format"] == "link" ? 1 : a["link"]
        fetch_real = Php.truthy?(link) || Php.truthy?(a["title"]) || a["format"] == "url"
        realname = nil

        if @thisauthor
          realname = @thisauthor["realname"]
          name = @thisauthor["name"]
        elsif Php.truthy?(@pretext["author"])
          name = @pretext["author"]
        else
          assert_article
          name = @thisarticle["authorid"]
        end

        realname ||= fetch_real ? get_author_name(name) : name
        display = Php.truthy?(a["title"]) ? realname : name
        display = if a["escape"] == "html"
          txpspecialchars(display)
        elsif Php.truthy?(a["escape"])
          txp_escape(a["escape"], display)
        else
          display
        end

        return display if !Php.truthy?(link) && a["format"] != "url"

        section = a["section"]
        section = @pretext["s"] if Php.truthy?(a["this_section"]) && @pretext["s"] != "default"
        url = pagelinkurl({ "s" => section, "author" => realname })
        a["format"] == "url" ? url : href(display, url, ' rel="author"')
      end

      def tag_author_email(atts, _thing = nil)
        a = lAtts({ "escape" => "html", "link" => "" }, atts)
        email = if @thisauthor
          get_author_email(@thisauthor["name"])
        else
          assert_article
          get_author_email(@thisarticle["authorid"])
        end
        display = a["escape"] == "html" ? txpspecialchars(email) : (Php.truthy?(a["escape"]) ? txp_escape(a["escape"], email) : email)
        Php.truthy?(a["link"]) ? tag_email({ "email" => email, "linktext" => display }) : display
      end

      def tag_if_author(atts, thing = nil)
        a = lAtts({ "type" => "article", "name" => "" }, atts)
        the_type = Php.truthy?(a["type"]) ? a["type"] == @pretext["context"] : true
        author = Php.str(@pretext["author"])
        x = if @thisauthor
          a["name"] == "" || Php.in_list(@thisauthor["name"], a["name"])
        elsif Php.truthy?(a["name"])
          the_type && Php.in_list(author, a["name"])
        else
          the_type && author != ""
        end
        thing.nil? ? x : parse(thing, x)
      end

      def tag_if_article_author(atts, thing = nil)
        a = lAtts({ "name" => "" }, atts)
        author = @thisarticle ? Php.str(@thisarticle["authorid"]) : ""
        x = Php.truthy?(a["name"]) ? Php.in_list(author, a["name"]) : author != ""
        thing.nil? ? x : parse(thing, x)
      end

      def tag_authors(atts, thing = nil)
        a = lAtts({ "form" => "", "group" => "", "limit" => "", "name" => "", "offset" => "", "sort" => "name ASC" }, atts)
        sql = [ "1 = 1" ]
        sql << "name IN (#{DB.quote_list(Php.do_list(a['name']))})" if Php.truthy?(a["name"])

        if Php.str(a["group"]) != ""
          privs = Php.do_list(a["group"]).map { |p| GROUPS.key(p)&.to_s || p }
          sql << "CAST(privs AS TEXT) IN (#{DB.quote_list(privs)})"
        end

        limit = a["limit"] != "" || Php.truthy?(a["offset"]) ? " LIMIT #{Php.intval(a['offset'])}, #{a['limit'] == '' ? (1 << 62) : Php.intval(a['limit'])}" : ""
        rows = DB.rows("SELECT user_id AS id, name, RealName AS realname, email, privs, last_access FROM txp_users WHERE #{sql.join(' AND ')} ORDER BY #{sanitize_for_sort(a['sort'])}#{limit}")
        return "" if rows.empty?

        thing = fetch_form(a["form"]).last if thing.nil? && a["form"] != ""
        out = rows.map do |r|
          old = @thisauthor
          @thisauthor = r
          res = parse(thing)
          @thisauthor = old
          res
        end
        @thisauthor = nil
        do_wrap(out)
      end

      def tag_body(atts = {}, _thing = nil)
        txp_sandbox({ "id" => nil, "field" => "body" }.merge(atts))
      end

      def tag_excerpt(atts = {}, _thing = nil)
        txp_sandbox({ "id" => nil, "field" => "excerpt" }.merge(atts))
      end

      def tag_title(atts, _thing = nil)
        a = lAtts({ "escape" => nil, "no_widow" => "" }, atts)
        assert_article
        t = a["escape"].nil? ? escape_title(@thisarticle["title"]) : Php.str(@thisarticle["title"])
        t = Text.no_widow(t) if Php.truthy?(a["no_widow"]) && a["escape"].nil?
        t
      end

      def tag_article_category(atts, thing = nil)
        assert_article
        cat = "category#{atts.key?('number') ? Php.intval(atts['number']) : 1}"

        if Php.truthy?(@thisarticle[cat])
          atts = atts.except("number").merge("name" => @thisarticle[cat], "type" => "article")
          atts = { "rel" => "tag" }.merge(atts) unless @is_article_list || get_pref("permlink_mode") == "messy"
          tag_category(atts, thing)
        elsif Php.truthy?(thing)
          parse(thing, false)
        end
      end

      def tag_keywords(_atts = {}, _thing = nil)
        assert_article
        txpspecialchars(@thisarticle["keywords"])
      end

      def tag_if_keywords(atts, thing = nil)
        a = lAtts({ "keywords" => "" }, atts)
        assert_article
        x = if Php.empty?(a["keywords"])
          Php.truthy?(@thisarticle["keywords"])
        else
          (Php.do_list(a["keywords"]) & Php.do_list(@thisarticle["keywords"])).any?
        end
        thing.nil? ? x : parse(thing, x)
      end

      def tag_if_article_image(_atts, thing = nil)
        x = @thisarticle && Php.truthy?(@thisarticle["article_image"])
        thing.nil? ? x : parse(thing, x)
      end

      def tag_article_image(atts, _thing = nil)
        tag_atts = {
          "range" => "1", "title" => "", "class" => "", "crop" => "", "quality" => "", "html_id" => "",
          "width" => "0", "height" => "0", "wraptag" => "", "break" => "", "loading" => nil,
          "thumbnail" => false, "type" => ""
        }
        ext_atts = join_atts(atts.reject { |k, _| tag_atts.key?(k) || @txp_atts&.key?(k) }, strip_txp: true)
        a = lAtts(tag_atts, atts.slice(*tag_atts.keys))
        assert_article

        images = Php.truthy?(@thisarticle["article_image"]) ? Php.do_list_unique(@thisarticle["article_image"], [ ",", "-" ]) : []
        return "" if images.empty?

        thumb = a["thumbnail"]
        resize = !Php.empty?(atts["width"]) || !Php.empty?(atts["height"]) || atts.key?("crop")
        n = images.length

        items = if a["range"] == true
          (0...n).to_a
        else
          Php.do_list(a["range"]).flat_map do |item|
            if Php.numeric?(item)
              v = item.to_i
              [ v.positive? ? v - 1 : n + v ]
            elsif (m = item.match(/\A([-+]?\d+)\s*(?:-|\.{2})\s*([-+]?\d+)\z/))
              start = m[1].to_i.positive? ? m[1].to_i - 1 : n + m[1].to_i
              stop = m[2].to_i.positive? ? m[2].to_i - 1 : n + m[2].to_i
              start <= stop ? (start..stop).to_a : start.downto(stop).to_a
            else
              []
            end
          end
        end

        numeric = items.filter_map { |i| images[i] if i >= 0 }.map(&:to_i).select(&:positive?)
        dbimages = numeric.empty? ? {} : DB.rows("SELECT *, #{DB.timestamp('date', 'udate')} FROM txp_image WHERE id IN (#{numeric.join(',')})").index_by { |r| r["id"].to_i }

        out = []
        items.each do |i|
          next if i.negative? || images[i].nil?

          image = images[i]
          img = ""
          w = h = 0

          if image.to_i.positive?
            rs = dbimages[image.to_i]
            if rs.nil?
              trigger_error(gTxt("unknown_image"))
              next
            end
            next if (thumb == THUMB_CUSTOM && Php.empty?(rs["thumbnail"])) || thumb == THUMB_NONE

            db_thumbnail = Php.str(rs["thumbnail"])
            auto = db_thumbnail == THUMB_AUTO || thumb == THUMB_AUTO
            crop = a["crop"]
            crop = "1x1" if auto && crop == true
            thumb_wanted = thumb == true ? db_thumbnail : thumb
            shrink = thumb_wanted == THUMB_CUSTOM || (Php.truthy?(thumb_wanted) && !resize && Php.empty?(a["quality"]))
            w = shrink ? rs["thumb_w"] : rs["w"]
            h = shrink ? rs["thumb_h"] : rs["h"]
            w = a["width"] == true ? w : a["width"]
            h = a["height"] == true ? h : a["height"]
            payload = { "id" => rs["id"], "ext" => rs["ext"] }
            payload.merge!("w" => w, "h" => h, "c" => crop, "q" => a["quality"], "t" => a["type"]) if auto
            title = a["title"] == true ? rs["caption"] : a["title"]
            url = image_build_url(payload, thumb_wanted == false ? nil : thumb_wanted)
            if url
              img = %(<img src="#{url}" alt="#{txpspecialchars(rs['alt'], double_encode: false)}")
              img << %( title="#{txpspecialchars(title, double_encode: false)}") if Php.truthy?(title)
            end
          else
            w = a["width"] != "" ? a["width"] : 0
            h = a["height"] != "" ? a["height"] : 0
            img = %(<img src="#{txpspecialchars(image)}" alt="")
            img << %( title="#{txpspecialchars(a['title'])}") if Php.truthy?(a["title"]) && a["title"] != true
          end

          if img != ""
            loading = a["loading"]
            img << %( loading="#{loading}") if loading && html5? && %w[auto eager lazy].include?(loading)
            img << %( id="#{txpspecialchars(a['html_id'])}") if Php.truthy?(a["html_id"]) && Php.empty?(a["wraptag"])
            img << %( class="#{txpspecialchars(a['class'])}") if Php.truthy?(a["class"]) && Php.empty?(a["wraptag"])
            img << %( width="#{Php.intval(w)}") if Php.truthy?(w) && w != true
            img << %( height="#{Php.intval(h)}") if Php.truthy?(h) && h != true
            img << ext_atts << void_close
            out << img
          end
        end

        do_wrap(out, a["wraptag"], { "break" => a["break"], "class" => a["class"], "html_id" => a["html_id"] })
      end

      def tag_if_excerpt(_atts, thing = nil)
        assert_article
        x = Php.str(@thisarticle["excerpt"]).strip != ""
        thing.nil? ? x : parse(thing, x)
      end

      def tag_if_individual_article(_atts, thing = nil)
        x = !@is_article_list
        thing.nil? ? x : parse(thing, x)
      end

      def tag_if_article_list(atts, thing = nil)
        x = @is_article_list ? true : false

        if x && !atts.empty?
          a = lAtts({ "type" => "" }, atts)
          types = a["type"] == true ? %w[s c q month author] : Php.do_list_unique(a["type"])
          types.each do |t|
            x = if t == "s"
              Php.truthy?(@pretext["s"]) && @pretext["s"] != "default"
            else
              Php.truthy?(@pretext[t]) || (!@pretext.key?(t) && Php.truthy?(gps(t)))
            end
            break if x
          end
        end

        thing.nil? ? x : parse(thing, x)
      end

      def tag_permlink(atts, thing = nil)
        has_content = !thing.nil? || !Php.empty?(atts["form"])
        defaults = { "class" => has_content ? "" : nil, "context" => nil, "form" => "", "id" => "", "style" => "", "title" => "" }
        old_context = @txp_context
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
          keys = Php.do_list_unique(atts["context"])
          atts = lAtts(defaults.merge(keys.index_with { nil }), atts)
          extra = atts.slice(*keys)
        end

        id = atts["id"]
        url = nil
        if Php.truthy?(id) || (@thisarticle && !@thisarticle.empty?)
          @txp_context = get_context(extra || atts["context"])
          url = Php.truthy?(id) ? permlinkurl_id(id) : permlinkurl(@thisarticle)
        end
        @txp_context = old_context

        return nil if url.nil? || url == false
        return url unless has_content

        content = Php.empty?(atts["form"]) ? Php.str(parse(thing)) : Php.str(parse_form(atts["form"]))
        tag(content, "a", {
          "rel" => url.start_with?(hu) || !url.match?(%r{\Ahttps?://}) ? "bookmark" : "external",
          "href" => url, "title" => atts["title"], "style" => atts["style"], "class" => atts["class"]
        })
      end

      def tag_link_to(atts, thing = nil, target = "next")
        atts = { "context" => @txp_context.nil? || @txp_context.empty? ? true : nil }.merge(atts)
        form = atts["form"] || ""
        link = atts.key?("link") ? atts["link"] : 1
        showalways = atts["showalways"] || 0
        return "" unless %w[next prev].include?(target)

        assert_article
        dir = target == "next" ? ">" : "<"
        @thisarticle.merge!(get_next_prev) unless @thisarticle.key?(dir)
        url = nil

        if @thisarticle[dir] != false && @thisarticle[dir]
          old = @thisarticle
          neighbour_row = @thisarticle[dir]
          @thisarticle = populate_article_data(neighbour_row)
          url = tag_permlink(atts.except("form", "link", "showalways"))

          if Php.truthy?(form) || !thing.nil?
            @thisarticle["is_first"] = @thisarticle["is_last"] = true
            content = Php.truthy?(form) ? parse_form(form) : parse(thing)
            target_title = escape_title(neighbour_row["Title"])
            url = if Php.truthy?(link)
              href(content, url, "#{target_title == content ? '' : " title=\"#{target_title}\""} rel=\"#{target}\"")
            else
              content
            end
          end

          @thisarticle = old
        end

        @thisarticle.delete(dir)
        # (With showalways, Textpattern 4.9 prints "1" for a self-closed tag.)
        url.nil? ? (Php.truthy?(showalways) && !thing.nil? ? parse(thing) : "") : url
      end

      def tag_next_title(_atts = {}, _thing = nil)
        return (@is_article_list ? "" : nil) if @thisarticle.nil? || @thisarticle.empty?

        @thisarticle.merge!(get_next_prev) unless @thisarticle.key?(">")
        @thisarticle[">"] ? escape_title(@thisarticle[">"]["Title"]) : ""
      end

      def tag_prev_title(_atts = {}, _thing = nil)
        return (@is_article_list ? "" : nil) if @thisarticle.nil? || @thisarticle.empty?

        @thisarticle.merge!(get_next_prev) unless @thisarticle.key?("<")
        @thisarticle["<"] ? escape_title(@thisarticle["<"]["Title"]) : ""
      end

      def tag_custom_field(atts = {}, _thing = nil)
        a = lAtts({ "name" => get_pref("custom_1_set"), "escape" => nil }, atts)
        assert_article
        name = Php.str(a["name"]).downcase

        unless @thisarticle.key?(name)
          trigger_error(gTxt("field_not_found", "{name}" => name))
          return ""
        end

        a["escape"].nil? ? txpspecialchars(@thisarticle[name]) : txp_sandbox({ "id" => nil, "field" => name }.merge(atts.except("name", "escape")))
      end

      def tag_if_custom_field(atts, thing = nil)
        a = lAtts({ "name" => get_pref("custom_1_set"), "value" => nil, "match" => "", "separator" => "" }, atts)
        assert_article
        name = Php.str(a["name"]).downcase

        unless @thisarticle.key?(name)
          trigger_error(gTxt("field_not_found", "{name}" => name))
          return ""
        end

        cond = a["value"].nil? ? Php.str(@thisarticle[name]) != "" : txp_match(a, @thisarticle[name])
        thing.nil? ? cond : parse(thing, cond)
      end

      def tag_items_count(atts, _thing = nil)
        a = lAtts({ "text" => nil, "pageby" => 1 }, atts)
        return postpone_process if @thispage.nil? || @thispage.empty?

        pageby = a["pageby"]
        t = @thispage[pageby == true ? "numPages" : "grand_total"].to_i
        by = Php.intval(pageby)
        by = 1 if by.zero?
        t = (t.to_f / by).ceil if by != 1
        text = a["text"]
        text ||= pageby == true || by > 1 ? gTxt(t == 1 ? "page" : "pages") : gTxt(t == 1 ? "article_found" : "articles_found")
        "#{t}#{Php.truthy?(text) ? " #{text}" : ''}"
      end

      def tag_if_items_count(atts, thing = nil)
        a = lAtts({ "min" => 1, "max" => 0, "pageby" => 1 }, atts)
        return (@is_article_list ? postpone_process : "") if @thispage.nil? || @thispage.empty?

        pageby = a["pageby"]
        results = @thispage[pageby == true ? "numPages" : "grand_total"].to_i
        by = Php.intval(pageby)
        by = 1 if by.zero?
        results = (results.to_f / by).ceil if by != 1
        max = Php.intval(a["max"])
        x = results >= Php.intval(a["min"]) && (max.zero? || results <= max)
        thing.nil? ? x : parse(thing, x)
      end

      def tag_search_result_title(atts, _thing = nil)
        tag_permlink(atts, "<txp:title />")
      end

      def tag_search_result_excerpt(atts, _thing = nil)
        a = lAtts({ "hilight" => "strong", "limit" => 5, "separator" => " &#8230;" }, atts)
        assert_article
        m = Php.str(@pretext["m"])
        qstr = Php.str(@pretext["q"])
        quoted = qstr[0] == '"' && qstr[-1] == '"'
        qstr = quoted ? Php.trim_chars(qstr, '"').strip : qstr.strip
        # Without a search term Textpattern 4.9 prints "&#8230;<strong></strong> &#8230;".
        return "" if qstr.empty?

        result = Php.strip_tags(Php.str(@thisarticle["body"]).gsub("><", "> <")).gsub(/\s+/, " ")
        if quoted || m == "" || m == "exact"
          terms = Regexp.escape(qstr)
        else
          terms = qstr.split(/\s+/).map { |w| Regexp.escape(w) }.join("|")
        end
        search = /(?:\G|\s).{0,50}(?:#{terms}).{0,50}(?:\s|\z)/iu
        hilite = /(#{terms})/i
        chunks = result.scan(search).first(Php.intval(a["limit"])).map(&:strip)
        concat = chunks.join("#{a['separator']}\n")
        concat = concat.sub(/\A[^>]+>/, "")
        hl = Php.str(a["hilight"])
        concat = concat.gsub(hilite) { "<#{hl}>#{Regexp.last_match(1)}</#{hl}>" }
        concat.empty? ? "" : "#{a['separator']}#{concat}#{a['separator']}".strip
      end

      def tag_search_result_url(atts, _thing = nil)
        assert_article
        tag_permlink(atts, permlinkurl(@thisarticle))
      end

      def tag_recent_articles(atts, thing = nil)
        atts = { "break" => "br", "class" => "recent_articles", "form" => "", "label" => gTxt("recent_articles"),
                 "labeltag" => "", "no_widow" => "" }.merge(atts)
        if thing.nil? && Php.empty?(atts["form"])
          thing = %(<txp:permlink><txp:title no_widow="#{Php.truthy?(atts['no_widow']) ? '1' : ''}" /></txp:permlink>)
        end
        tag_article_custom(atts.except("no_widow"), thing)
      end

      def tag_related_articles(atts, thing = nil)
        assert_article
        atts = lAtts({ "break" => "br", "class" => "related_articles", "label" => gTxt("related_articles"),
                       "labeltag" => "", "form" => "", "match" => "Category", "no_widow" => "" }, {}).merge(atts)
        allowed = %w[category category1 category2 author image keywords section] + custom_fields.values
        match = Php.do_list_unique(Php.str(atts["match"]).downcase) & allowed
        categories = []
        cats = []

        match.each do |cf|
          case cf
          when "category", "category1", "category2"
            (cf == "category" ? %w[category1 category2] : [ cf ]).each { |c| cats << @thisarticle[c] if Php.truthy?(@thisarticle[c]) }
            categories << cf
          when "author" then atts["author"] = @thisarticle["authorid"]
          when "section" then atts["section"] = @thisarticle["section"] if Php.empty?(atts["section"])
          else
            f = cf == "image" ? "article_image" : cf
            return "" if Php.empty?(@thisarticle[f])

            atts[cf] = @thisarticle[f]
          end
        end

        if cats.any?
          atts["category"] = cats.join(",")
        elsif categories.any?
          return ""
        end

        atts["match"] = categories.join(",")
        atts["exclude"] = @thisarticle["thisid"]
        if atts["form"] == "" && thing.nil?
          thing = %(<txp:permlink><txp:title no_widow="#{Php.truthy?(atts['no_widow']) ? '1' : ''}" /></txp:permlink>)
        end
        tag_article_custom(atts.except("no_widow"), thing)
      end
    end
  end
end
