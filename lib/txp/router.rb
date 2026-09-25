module Txp
  # Public URL resolution (port of preText()): works out the section,
  # category, author, article, search and pagination context of a request for
  # every Textpattern permanent link scheme (messy, section/id/title,
  # section/title, year/month/day/title, title_only, id/title,
  # section/category/title and breadcrumb/title).
  module Router
    VALID_CONTEXTS = %w[article image file link].freeze

    def chop_url(req, min = 4)
      req = req.to_s.split("?", 2).first.to_s.sub(/index\.php\z/i, "")
      parts = req.split("/", -1).map { |p| Php.urldecode(p) }
      n = [ min, parts.length ].max
      out = { "u0" => req }
      (1...n).each { |i| out["u#{i}"] = parts[i] }
      out
    end

    def valid_context_name(context)
      VALID_CONTEXTS.each do |t|
        return t if context == t || context == gTxt("#{t}_context")
      end
      "article"
    end

    def localized_segment(key)
      Php.urldecode(Php.urlencode(gTxt(key)).downcase)
    end

    def router_status_value(value)
      value.is_a?(Array) || value.is_a?(Hash) ? nil : value
    end

    # Resolves the request into @pretext (and @thisarticle / @thiscategory /
    # @thisfile where relevant).
    def pretext!(status: "200")
      out = @pretext
      request_uri = @request ? @request.original_fullpath : "/"
      out["request_uri"] = request_uri
      out["qs"] = @request ? @request.query_string.to_s : ""
      subpath = rhu
      req = request_uri.sub(/\A#{Regexp.escape(subpath)}/i, "/")
      out["subpath"] = subpath
      out["req"] = req
      url = chop_url(req, 5)
      segs = [ 0 ]
      i = 1
      while url.key?("u#{i}") && !url["u#{i}"].nil?
        segs << url["u#{i}"]
        segs[0] = i
        i += 1
      end

      out["feed"] = "rss" if url["u1"] == "rss" || Php.truthy?(gps("rss"))
      out["feed"] = "atom" if url["u1"] == "atom" || Php.truthy?(gps("atom"))
      out["status"] = status.to_s

      %w[id s c context q m pg p month author f token].each do |key|
        v = gps(key)
        if v.is_a?(String)
          out[key] = v
        elsif v.nil?
          out[key] = ""
        else
          out[key] = ""
          out["status"] = "404"
        end
      end
      out["skin"] = out["page"] = out["css"] = ""

      is_404 = out["status"] == "404"
      title = nil
      month = nil
      trailing = Php.intval(get_pref("trailing_slash", 0))
      permlink_mode = get_pref("permlink_mode", "section_title")
      status_sql = " AND Status IN (#{STATUS_LIVE},#{STATUS_STICKY})"
      preview = Php.str(out["id"]).include?(".")

      if preview
        handle_preview_id!(out)
        status_sql = ""
      end

      out["path_from_root"] = out["pfr"] = rhu
      out["permlink_mode"] = permlink_mode
      out["sitename"] = get_pref("sitename")
      u1 = url["u1"].to_s.downcase
      u2 = url["u2"]
      u3 = url["u3"]
      u4 = url["u4"]
      u5 = url["u5"]
      img_parts = img_dir.split("/")

      if !is_404 && Php.empty?(out["id"]) && Php.empty?(out["s"]) && u1 != ""
        last_seg = segs[segs[0]]

        if img_parts[0] == u1
          is_404 = true
        elsif (trailing.positive? && last_seg != "") || (trailing.negative? && last_seg == "")
          is_404 = true
        else
          n = trailing.positive? ? segs[0] - 1 : segs[0]
          un = segs[n]

          case u1
          when "atom", "rss"
            out["feed"] = u1
          when "section", localized_segment("section")
            out["s"] = u2.to_s
          when "category", localized_segment("category")
            out["context"] = Php.truthy?(u3) ? valid_context_name(u2) : "article"
            if permlink_mode == "breadcrumb_title"
              out["c"] = Php.truthy?(un) ? un : segs[n - 1].to_s if n >= 2
            else
              out["c"] = Php.truthy?(u3) ? u3 : u2.to_s
            end
          when "author", localized_segment("author")
            if Php.truthy?(u3)
              out["context"] = valid_context_name(u2)
              out["author"] = u3
            else
              out["context"] = "article"
              out["author"] = u2.to_s
            end
          when "file_download", localized_segment("file_download")
            out["s"] = "file_download"
            out["id"] = u2.to_s
            out["filename"] = u3.to_s
          else
            modes = { "default" => permlink_mode }
            @txp_sections.each { |name, s| modes[name] = s["permlink_mode"] }
            custom_modes = modes.select { |_k, v| Php.truthy?(v) && v != permlink_mode }
            guess = nil

            if custom_modes.empty?
              guess = permlink_mode
            elsif Php.truthy?(un) && (n > 1 || modes.value?("title_only") || modes.value?("id_title"))
              slash = trailing <= 0 ? "" : "/"
              cond = n < 3 && Php.numeric?(un) ? "(url_title = #{q un} OR ID = #{Php.intval(un)})" : "url_title = #{q un}"
              DB.rows("SELECT #{article_select_all} FROM textpattern WHERE #{cond}#{status_sql}").each do |a|
                populate_article_data(a)
                if "/#{a['Section']}/#{a['url_title']}#{slash}" == url["u0"]
                  guess = "section_title"
                  break
                end
                if permlinkurl(@thisarticle, "/") == url["u0"]
                  guess = modes[a["Section"]].presence || permlink_mode
                  break
                end
              end

              if guess.nil?
                @thisarticle = nil
                is_404 = true if trailing.zero?
              else
                out["id"] = @thisarticle["thisid"].to_s
                out["s"] = @thisarticle["section"]
                title = @thisarticle["url_title"]
                month = local_time(@thisarticle["posted"]).strftime("%Y-%m-%d")
              end
            end

            if !is_404 && Php.empty?(out["id"])
              if guess.nil?
                guess = if modes.key?(u1) && Php.truthy?(modes[u1])
                  modes[u1]
                elsif u1.match?(/\A\d{4}\z/) && custom_modes.value?("year_month_day_title")
                  "year_month_day_title"
                else
                  permlink_mode
                end
              end

              case guess.presence || permlink_mode
              when "section_id_title"
                out["s"] = u1
                if Php.numeric?(u2)
                  out["id"] = u2
                else
                  title = Php.empty?(u2) ? nil : u2
                end
              when "section_category_title", "breadcrumb_title"
                out["s"] = u1
                title = n < 2 || Php.empty?(un) ? nil : un
                out["c"] = segs[n - 1].to_s if title.nil? && n > 2
              when "year_month_day_title"
                if (m = is_date([ u1, u2, u3 ].compact.join("-").sub(/-+\z/, "")))
                  month = m
                  title = Php.empty?(u4) ? nil : u4
                elsif Php.truthy?(u2) && (m = is_date([ u2, u3, u4 ].compact.join("-").sub(/-+\z/, "")))
                  month = m
                  title = Php.empty?(u5) ? nil : u5
                  out["s"] = u1
                elsif Php.empty?(u3)
                  out["s"] = u1
                  title = Php.empty?(u2) ? nil : u2
                else
                  is_404 = true
                end
              when "section_title"
                out["s"] = u1
                title = Php.empty?(u2) ? nil : u2
              when "id_title"
                if Php.numeric?(u1)
                  out["id"] = u1
                else
                  out["s"] = u1
                  title = Php.empty?(u2) ? nil : u2
                end
              else
                if (!u2.nil? || trailing.negative?) && modes.key?(u1)
                  out["s"] = u1
                  title = Php.empty?(u2) ? nil : u2
                else
                  title = u1
                end
              end
            end
          end
        end
      end

      out["context"] = valid_context_name(out["context"])

      if Php.truthy?(out["month"]) && (om = is_date(out["month"]))
        out["month"] = om
        if month.nil? || month.start_with?(om)
          month = om
        elsif om.start_with?(month.to_s)
          out["month"] = month
        else
          month = ""
          is_404 = true
        end
      elsif Php.truthy?(out["month"])
        out["month"] = ""
        is_404 = true
      elsif Php.truthy?(month)
        out["month"] = month if title.nil?
      end

      if !is_404 && Php.truthy?(out["author"]) && (name = DB.field("SELECT name FROM txp_users WHERE RealName LIKE #{q out['author']}"))
        out["realname"] = out["author"]
        out["author"] = name
      else
        is_404 ||= Php.truthy?(out["author"])
        out["author"] = out["realname"] = ""
      end

      if !is_404 && Php.truthy?(out["c"])
        cat = ck_cat(out["context"], out["c"])
        if cat
          @thiscategory = cat.merge("is_first" => true, "is_last" => true, "section" => out["s"])
        else
          is_404 = true
          out["c"] = ""
          @thiscategory = nil
        end
      end

      if out["s"] == "file_download"
        row = nil
        if !is_404 && Php.numeric?(out["id"])
          fname = Php.str(out["filename"]).sub(/gz&\z/i, "gz")
          fcond = fname.empty? ? "" : " AND filename = #{q fname}"
          row = DB.row("SELECT *, #{DB.timestamps('created' => 'ucreated', 'modified' => 'umodified')} FROM txp_file " \
                       "WHERE id = #{Php.intval(out['id'])} AND status = #{STATUS_LIVE} AND created <= #{DB.now}#{fcond}")
          row &&= file_download_format_info(row)
          @thisfile = row || nil
        end
        is_404 ||= !row
        if is_404
          out.merge!("id" => "", "file_error" => 404, "status" => "404")
        else
          out.merge!(row.transform_keys(&:to_s)) { |k, old, new| %w[id].include?(k) ? new : old }
        end
      elsif !is_404 && out["context"] == "article"
        if Php.truthy?(out["s"]) && !@txp_sections.key?(out["s"])
          is_404 = true
        elsif (@thisarticle.nil? || @thisarticle.empty?) && (Php.truthy?(out["id"]) || Php.truthy?(title))
          rs = if Php.empty?(out["s"])
            if Php.truthy?(out["id"])
              DB.row("SELECT #{article_select_all} FROM textpattern WHERE ID = #{Php.intval(out['id'])}")
            else
              lookup_by_date_title(month, title)
            end
          elsif Php.truthy?(out["id"])
            DB.row("SELECT #{article_select_all} FROM textpattern WHERE ID = #{Php.intval(out['id'])} AND Section = #{q out['s']}")
          else
            DB.row("SELECT #{article_select_all} FROM textpattern WHERE url_title = #{q title} AND Section = #{q out['s']}")
          end

          is_404 ||= rs.nil? || (status_sql != "" && ![ STATUS_LIVE, STATUS_STICKY ].include?(rs["Status"].to_i))
          if is_404
            out["id"] = out["s"] = ""
          else
            out["id"] = rs["ID"].to_s
            populate_article_data(rs)
          end
        end

        if @thisarticle && !@thisarticle.empty?
          @thiscategory = nil
          out["s"] = @thisarticle["section"]
          out["id_keywords"] = @thisarticle["keywords"]
          out["id_author"] = @thisarticle["authorid"]
          expires = @thisarticle["expires"]
          if status_sql != "" && !Php.truthy?(get_pref("publish_expired_articles")) && Php.truthy?(expires) && Time.now.to_i > expires.to_i
            is_404 = "410"
          end
        end
      end

      out["status"] = is_404.is_a?(String) ? is_404 : (is_404 ? "404" : "200")
      out["pg"] = Php.numeric?(out["pg"]) ? Php.intval(out["pg"]) : ""
      out["id"] = Php.numeric?(out["id"]) ? Php.intval(out["id"]) : ""

      if Php.empty?(out["@txp_preview"]) && Php.empty?(out["id"])
        @is_article_list = true
      else
        out["q"] = ""
        @is_article_list = false
      end

      if @user && Txp::Privs.has?("skin.preview", @user.privs) && Php.truthy?(get_pref("enable_dev_preview", "1"))
        @txp_sections = @txp_sections.transform_values do |sec|
          sec = sec.dup
          sec["skin"] = sec["dev_skin"] if Php.truthy?(sec["dev_skin"])
          sec["page"] = sec["dev_page"] if Php.truthy?(sec["dev_page"])
          sec["css"] = sec["dev_css"] if Php.truthy?(sec["dev_css"])
          sec
        end
      end

      s = is_404 || Php.empty?(out["s"]) ? "default" : out["s"]
      s = "default" unless @txp_sections.key?(s) || s == "file_download"
      out["s"] = s
      rs = @txp_sections[s] || @txp_sections["default"] || {}
      out["skin"] = Php.str(rs["skin"])
      out["page"] = Php.str(rs["page"])
      out["css"] = Php.str(rs["css"])
      @pretext = out
    end

    def lookup_by_date_title(month, title)
      cond = "url_title = #{q title}"
      if Php.truthy?(month)
        from, to = month_range(month)
        cond += " AND Posted >= #{DB.unixtime(from)} AND Posted < #{DB.unixtime(to)}" if from
      end
      row = DB.row("SELECT #{article_select_all} FROM textpattern WHERE #{cond}")
      row && row["url_title"] == title ? row : nil
    end

    # Article previews from the admin side: id="<id>.<token>".
    def handle_preview_id!(out)
      id, hash = Php.str(out["id"]).split(".", 2)
      expected = Txp::Preview.token(@user, id)
      unless @user && Txp::Privs.has?("article.preview", @user.privs) && ActiveSupport::SecurityUtils.secure_compare(hash.to_s, expected)
        raise Die.new(gTxt("restricted_area"), "401")
      end

      out["@txp_preview"] = hash
      out["id"] = id.to_s
      @nolog = true
    end
  end
end
