module Txp
  module Tags
    # File download tags.
    module Files
      def tag_file_download_list(atts, thing = nil)
        filters = %w[id category author realname status month time].any? { |k| atts.key?(k) }
        a = lAtts({
          "break" => "br", "category" => "", "author" => "", "realname" => "", "exclude" => "",
          "auto_detect" => filters ? "" : "category, author", "class" => "file_download_list",
          "form" => thing.nil? ? "files" : "", "id" => "", "pageby" => "", "limit" => 10, "offset" => 0,
          "month" => "", "time" => nil, "sort" => "filename asc", "wraptag" => "", "status" => STATUS_LIVE
        }, atts)
        status = Php.numeric?(a["status"]) ? Php.intval(a["status"]) : (STATUSES.key(Php.str(a["status"])) || STATUS_LIVE)
        where = []
        context_list = Php.empty?(a["auto_detect"]) ? [] : Php.do_list_unique(a["auto_detect"])
        limit = Php.intval(a["limit"])
        pageby = a["pageby"] == "limit" ? limit : Php.intval(a["pageby"])
        exclude = a["exclude"] == true ? true : (Php.truthy?(a["exclude"]) ? Php.do_list_unique(a["exclude"]) : [])
        ex = ->(k) { exclude == true || (exclude.is_a?(Array) && exclude.include?(k)) }
        context = @pretext["context"]
        c = @pretext["c"]
        ids = Php.truthy?(a["id"]) ? Php.do_list_unique(a["id"], [ ",", "-" ]).map { |v| Php.intval(v) } : []

        where << "id #{ex.call('id') ? 'NOT ' : ''}IN (#{ids.join(',')})" if ids.any?

        category = if Php.truthy?(a["category"])
          Php.do_list_unique(a["category"])
        elsif context == "file" && Php.truthy?(c) && context_list.include?("category")
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
        elsif context == "file" && Php.truthy?(@pretext["author"]) && context_list.include?("author")
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
          where << "#{ex.call('month') || ex.call('time') ? 'NOT ' : ''}(#{build_time_sql(month, time.nil? ? 'past' : time, 'created')})"
        end

        where << "status #{ex.call('status') ? '!' : ''}= #{status}" if status.positive?

        return thing.nil? ? "" : parse(thing, false) if where.empty? && filters

        where << build_time_sql(month, "past", "created") if time.nil? && Php.empty?(month)
        where_sql = where.empty? ? "1" : where.join(" AND ")
        offset = Php.intval(a["offset"])

        if limit.positive? && pageby.positive?
          pg = Php.empty?(@pretext["pg"]) ? 1 : Php.intval(@pretext["pg"])
          pgoffset = offset + (pg - 1) * pageby
          if @thispage.nil?
            grand_total = DB.count("txp_file", where_sql)
            total = grand_total - offset
            @thispage = {
              "pg" => pg, "numPages" => (total.to_f / pageby).ceil, "s" => @pretext["s"], "c" => c,
              "context" => "file", "grand_total" => grand_total, "total" => total
            }
          end
        else
          pgoffset = offset
        end

        sort = ids.any? && !atts.key?("sort") ? "FIELD(id, #{ids.join(',')})" : sanitize_for_sort(a["sort"])
        limit_sql = limit.positive? ? " LIMIT #{pgoffset}, #{limit}" : ""
        rows = DB.rows("SELECT *, #{DB.timestamps('created' => 'ucreated', 'modified' => 'umodified')} FROM txp_file WHERE #{where_sql} ORDER BY #{sort}#{limit_sql}")
        out = parse_list(rows, "file", populate: ->(r) { file_download_format_info(r) }, form: a["form"], thing: thing)
        out.any? ? do_wrap(out, a["wraptag"], { "break" => a["break"], "class" => a["class"] }) : ""
      end

      def tag_file_download(atts, thing = nil)
        a = lAtts({ "filename" => "", "form" => atts.key?("type") ? "" : "files", "id" => "", "sort" => "", "type" => nil }, atts)
        old = @thisfile
        where = []
        where << "id IN (#{Php.do_list(a['id'], [ ',', '-' ]).map { |v| Php.intval(v) }.join(',')})" if Php.truthy?(a["id"])
        where << "filename = #{q a['filename']}" if Php.truthy?(a["filename"])

        if where.any?
          cond = where.join(" AND ")
          cond += " AND status = #{STATUS_LIVE}" if Php.truthy?(a["type"])
          order = Php.truthy?(a["sort"]) ? " ORDER BY #{sanitize_for_sort(a['sort'])}" : ""
          @thisfile = file_download_fetch_info("#{cond} AND created <= #{DB.now}#{order}") || nil
        else
          assert_file
        end

        out = if Php.empty?(@thisfile)
          Php.truthy?(thing) ? parse(thing, false) : ""
        else
          res = thing.nil? ? (Php.truthy?(a["form"]) ? parse_form(a["form"]) : "") : parse(thing)
          if Php.truthy?(a["type"]) && php_allowed?(true)
            @file_to_send = { file: @thisfile, type: a["type"] == true ? Php.str(@thisfile["mime"]).presence : a["type"] }
          end
          res
        end

        @thisfile = old
        out
      end

      def file_to_send
        @file_to_send
      end

      def tag_file_download_link(atts, thing = nil)
        a = lAtts({ "download" => false, "filename" => "", "id" => "" }, atts)
        old = @thisfile

        if Php.truthy?(a["id"])
          @thisfile = file_download_fetch_info("id = #{Php.intval(a['id'])} AND created <= #{DB.now}") || nil
        elsif Php.truthy?(a["filename"])
          @thisfile = file_download_fetch_info("filename = #{q a['filename']} AND created <= #{DB.now}") || nil
        else
          assert_file
        end

        out = nil
        if Php.truthy?(@thisfile)
          url = filedownloadurl(@thisfile["id"], @thisfile["filename"])
          out = if Php.truthy?(thing)
            href(parse(thing), url, a["download"] == true ? " download" : (Php.truthy?(a["download"]) ? { "download" => a["download"] } : ""))
          else
            url
          end
        end

        @thisfile = old
        out.nil? ? (Php.truthy?(thing) ? parse(thing, false) : nil) : out
      end

      def tag_file_download_info(atts, _thing = nil)
        a = lAtts({ "filename" => "", "id" => "", "type" => "description", "escape" => true, "wraptag" => "", "class" => "", "break" => "" }, atts)
        valid = %w[id filename title category category_title description ext mime author size downloads status created modified]
        from_form = false
        file = if Php.truthy?(a["id"])
          file_download_fetch_info("id = #{Php.intval(a['id'])}")
        elsif Php.truthy?(a["filename"])
          file_download_fetch_info("filename = #{q a['filename']}")
        else
          assert_file
          from_form = true
          @thisfile
        end

        out = []
        if file
          Php.do_list(a["type"]).each do |item|
            unless valid.include?(item)
              trigger_error(gTxt("invalid_attribute_value", "{name}" => item))
              next
            end
            value = item == "category_title" ? fetch_category_title(file["category"], "file") : file[item]
            next if value.nil?

            out << (Php.truthy?(a["escape"]) ? txp_escape(a["escape"], Php.str(value)) : value)
          end
        end
        _ = from_form
        do_wrap(out, a["wraptag"], a["break"], a["class"])
      end

      def format_filesize(bytes, decimals = 2, format = "")
        units = %w[b k m g t p e z y]
        bytes = bytes.to_f
        index = format.to_s != "" && units.include?(format) ? units.index(format) : [ (Math.log(bytes.nonzero? || 1) / Math.log(1024)).floor, units.length - 1 ].min.clamp(0, 8)
        value = bytes / (1024**index)
        label = gTxt("units_#{units[index]}")
        label = %w[B KB MB GB TB PB EB ZB YB][index] if label == "units_#{units[index]}"
        "#{format("%.#{decimals}f", value)}&#160;#{label}"
      end

      def tag_file_download_size(atts, _thing = nil)
        a = lAtts({ "decimals" => 2, "format" => "" }, atts)
        assert_file
        decimals = Php.numeric?(a["decimals"]) && Php.intval(a["decimals"]) >= 0 ? Php.intval(a["decimals"]) : 2
        return "" if @thisfile["size"].nil?

        format_filesize(@thisfile["size"], decimals, Php.str(a["format"])[0].to_s.downcase)
      end

      def tag_file_download_id(_atts = {}, _thing = nil)
        assert_file
        @thisfile["id"]
      end

      def tag_file_download_name(atts, _thing = nil)
        a = lAtts({ "title" => 0 }, atts)
        assert_file
        Php.truthy?(a["title"]) ? Php.str(@thisfile["title"]) : @thisfile["filename"]
      end

      def tag_file_download_category(atts, _thing = nil)
        a = lAtts({ "title" => 0 }, atts)
        assert_file
        return nil if Php.empty?(@thisfile["category"])

        Php.truthy?(a["title"]) ? fetch_category_title(@thisfile["category"], "file") : @thisfile["category"]
      end

      def tag_file_download_author(atts, _thing = nil)
        a = lAtts({ "link" => 0, "title" => 1, "section" => "", "this_section" => "" }, atts)
        assert_file
        return nil if Php.empty?(@thisfile["author"])

        author_name = get_author_name(@thisfile["author"])
        display = txpspecialchars(Php.truthy?(a["title"]) ? author_name : @thisfile["author"])
        section = Php.truthy?(a["this_section"]) ? (@pretext["s"] == "default" ? "" : @pretext["s"]) : a["section"]
        Php.truthy?(a["link"]) ? href(display, pagelinkurl({ "s" => section, "author" => author_name, "context" => "file" })) : display
      end

      def tag_file_download_downloads(_atts = {}, _thing = nil)
        assert_file
        @thisfile["downloads"]
      end

      def tag_file_download_description(atts, _thing = nil)
        a = lAtts({ "escape" => nil }, atts)
        assert_file
        return nil if Php.empty?(@thisfile["description"])

        a["escape"].nil? ? txpspecialchars(@thisfile["description"]) : @thisfile["description"]
      end
    end
  end
end
