module Txp
  module Tags
    # Link (blogroll) tags.
    module Links
      def tag_linklist(atts, thing = nil)
        filters = %w[id category author realname month time].any? { |k| atts.key?(k) }
        a = lAtts({
          "break" => "", "category" => "", "author" => "", "realname" => "", "exclude" => "",
          "auto_detect" => filters ? "" : "category, author", "class" => "linklist",
          "form" => thing.nil? ? "plainlinks" : "", "id" => "", "pageby" => "", "limit" => 0, "offset" => 0,
          "month" => "", "time" => nil, "sort" => "linksort asc", "wraptag" => ""
        }, atts)
        where = []
        context_list = Php.empty?(a["auto_detect"]) ? [] : Php.do_list_unique(a["auto_detect"])
        limit = Php.intval(a["limit"])
        pageby = a["pageby"] == "limit" ? limit : Php.intval(a["pageby"])
        exclude = a["exclude"] == true ? true : (Php.truthy?(a["exclude"]) ? Php.do_list_unique(a["exclude"]) : [])
        ex = ->(k) { exclude == true || (exclude.is_a?(Array) && exclude.include?(k)) }
        context = @pretext["context"]
        c = @pretext["c"]

        if Php.truthy?(a["id"])
          where << "id #{ex.call('id') ? 'NOT ' : ''}IN (#{DB.quote_list(Php.do_list_unique(a['id'], [ ',', '-' ]))})"
        end

        category = if Php.truthy?(a["category"])
          Php.do_list_unique(a["category"])
        elsif context == "link" && Php.truthy?(c) && context_list.include?("category")
          [ c ]
        else
          []
        end
        if category.any?
          cq = category.map { |cat| "category LIKE #{q cat.gsub('_', '\\_').tr('*', '_')} ESCAPE '\\'" }
          where << "#{ex.call('category') ? 'NOT ' : ''}(#{cq.join(' OR ')})"
        end

        author = if Php.truthy?(a["author"])
          Php.do_list_unique(a["author"])
        elsif context == "link" && Php.truthy?(@pretext["author"]) && context_list.include?("author")
          [ @pretext["author"] ]
        else
          []
        end
        where << "author #{ex.call('author') ? 'NOT ' : ''}IN (#{DB.quote_list(author)})" if author.any?

        if Php.truthy?(a["realname"])
          names = DB.column("SELECT name FROM txp_users WHERE RealName IN (#{DB.quote_list(Php.do_list_unique(a['realname']).map { |n| Php.urldecode(n) })})")
          where << "author #{ex.call('realname') ? 'NOT ' : ''}IN (#{DB.quote_list(names)})" if names.any?
        end

        time = a["time"]
        month = a["month"]
        if Php.truthy?(time) || Php.truthy?(month)
          where << "#{ex.call('month') || ex.call('time') ? 'NOT ' : ''}(#{build_time_sql(month, time.nil? ? 'past' : time, 'date')})"
        end

        return thing.nil? ? "" : parse(thing, false) if where.empty? && filters

        where << build_time_sql(month, "past", "date") if time.nil? && Php.empty?(month)
        where_sql = where.empty? ? "1" : where.join(" AND ")
        offset = Php.intval(a["offset"])

        if limit.positive? && pageby.positive?
          pg = Php.empty?(@pretext["pg"]) ? 1 : Php.intval(@pretext["pg"])
          pgoffset = offset + (pg - 1) * pageby
          if @thispage.nil?
            grand_total = DB.count("txp_link", where_sql)
            total = grand_total - offset
            @thispage = {
              "pg" => pg, "numPages" => (total.to_f / pageby).ceil, "s" => @pretext["s"], "c" => c,
              "context" => "link", "grand_total" => grand_total, "total" => total
            }
          end
        else
          pgoffset = offset
        end

        limit_sql = limit.positive? ? " LIMIT #{pgoffset}, #{limit}" : ""
        rows = DB.rows("SELECT *, #{DB.timestamp('date', 'udate')} FROM txp_link WHERE #{where_sql} ORDER BY #{sanitize_for_sort(a['sort'])}#{limit_sql}")
        out = parse_list(rows, "link", populate: ->(r) { r.merge("date" => r["udate"] || DB.to_unix(r["date"])).except("udate") }, form: a["form"], thing: thing)
        out.any? ? do_wrap(out, a["wraptag"], a["break"], a["class"]) : ""
      end

      def tag_link(atts, _thing = nil)
        a = lAtts({ "rel" => "", "id" => "", "name" => "", "escape" => true }, atts)
        rs = @thislink
        sql = if Php.truthy?(a["id"])
          "id = #{Php.intval(a['id'])}"
        elsif Php.truthy?(a["name"])
          "linkname = #{q a['name']}"
        end
        rs = DB.row("SELECT linkname, url FROM txp_link WHERE #{sql}") if sql

        unless rs
          trigger_error(gTxt("unknown_link"))
          return ""
        end

        tag(Php.truthy?(a["escape"]) ? txp_escape(a["escape"], rs["linkname"]) : rs["linkname"], "a",
          "#{Php.truthy?(a['rel']) ? %( rel="#{txpspecialchars(a['rel'])}") : ''} href=\"#{txpspecialchars(rs['url'])}\"")
      end

      def tag_linkdesctitle(atts, _thing = nil)
        a = lAtts({ "rel" => "", "escape" => true }, atts)
        assert_link
        desc = Php.truthy?(@thislink["description"]) ? %( title="#{txpspecialchars(@thislink['description'])}") : ""
        tag(Php.truthy?(a["escape"]) ? txp_escape(a["escape"], @thislink["linkname"]) : @thislink["linkname"], "a",
          "#{Php.truthy?(a['rel']) ? %( rel="#{txpspecialchars(a['rel'])}") : ''} href=\"#{txpspecialchars(@thislink['url'])}\"#{desc}")
      end

      def tag_link_name(atts, _thing = nil)
        a = lAtts({ "escape" => nil }, atts)
        assert_link
        a["escape"].nil? ? txpspecialchars(@thislink["linkname"]) : @thislink["linkname"]
      end

      def tag_link_url(_atts = {}, _thing = nil)
        assert_link
        txpspecialchars(@thislink["url"])
      end

      def tag_link_author(atts, _thing = nil)
        a = lAtts({ "link" => 0, "title" => 1, "section" => "", "this_section" => "" }, atts)
        assert_link
        return nil if Php.empty?(@thislink["author"])

        author_name = get_author_name(@thislink["author"])
        display = txpspecialchars(Php.truthy?(a["title"]) ? author_name : @thislink["author"])
        section = Php.truthy?(a["this_section"]) ? (@pretext["s"] == "default" ? "" : @pretext["s"]) : a["section"]
        Php.truthy?(a["link"]) ? href(display, pagelinkurl({ "s" => section, "author" => author_name, "context" => "link" })) : display
      end

      def tag_link_description(atts, _thing = nil)
        a = lAtts({ "escape" => nil }, atts)
        assert_link
        return nil if Php.empty?(@thislink["description"])

        a["escape"].nil? ? txpspecialchars(@thislink["description"]) : @thislink["description"]
      end

      def tag_link_category(atts, _thing = nil)
        a = lAtts({ "title" => 0 }, atts)
        assert_link
        return nil if Php.empty?(@thislink["category"])

        Php.truthy?(a["title"]) ? fetch_category_title(@thislink["category"], "link") : @thislink["category"]
      end

      def tag_link_id(_atts = {}, _thing = nil)
        assert_link
        @thislink["id"]
      end
    end
  end
end
