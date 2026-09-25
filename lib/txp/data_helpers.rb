require "marcel"

module Txp
  # Database lookups used by tags (categories, sections, authors, images, files).
  module DataHelpers
    def q(value)
      DB.quote(value)
    end

    def fetch_category_title(name, type = "article")
      @category_titles ||= {}
      key = "#{type}:#{name}"
      return @category_titles[key] if @category_titles.key?(key)

      if @thiscategory && !Php.empty?(@thiscategory["title"]) && @thiscategory["name"] == name && @thiscategory["type"] == type
        return @category_titles[key] = @thiscategory["title"]
      end

      @category_titles[key] = Php.str(DB.field("SELECT title FROM txp_category WHERE name = #{q name} AND type = #{q type}"))
    end

    def fetch_section_title(name)
      @section_titles ||= {}
      return @section_titles[name] if @section_titles.key?(name)
      return Php.str(@thissection["title"]) if @thissection && !@thissection.empty? && @thissection["name"] == name
      return "" if name == "default" || Php.empty?(name)
      return @section_titles[name] = Php.str(@txp_sections[name]["title"]) if @txp_sections.key?(name)

      @section_titles[name] = Php.str(DB.field("SELECT title FROM txp_section WHERE name = #{q name}"))
    end

    def author_row(name)
      @authors ||= {}
      return @authors[name] if @authors.key?(name)

      @authors[name] = DB.row("SELECT name, RealName, email, privs FROM txp_users WHERE name = #{q name}")
    end

    def get_author_name(name)
      row = author_row(Php.str(name))
      row && row["RealName"].to_s != "" ? row["RealName"] : Php.str(name)
    end

    def get_author_email(name)
      row = author_row(Php.str(name))
      row ? Php.str(row["email"]) : ""
    end

    def ck_cat(type, name)
      row = DB.row("SELECT id, name, title, description, type FROM txp_category WHERE name = #{q name} AND type = #{q type}")
      row && row["name"] == name ? row : false
    end

    def category_rows(type)
      @category_rows ||= {}
      @category_rows[type] ||= DB.rows("SELECT id, name, parent, title, description, lft, rgt FROM txp_category WHERE type = #{q type}").index_by { |r| r["name"] }
    end

    # getRootPath(): the category and its ancestors up to (excluding) root.
    def get_root_path(target, type = "article", root = "root")
      rows = category_rows(type)
      out = []
      seen = {}
      target = Php.str(target)

      while target != root && rows.key?(target) && !seen[target]
        seen[target] = true
        out << rows[target]
        target = rows[target]["parent"]
      end
      out
    end

    # get_tree(): category tree used by category_list, the article category
    # filter (depth attribute) and the admin panels. Port of Textpattern's
    # get_tree(); returns an ordered Hash name => row (with "level" and
    # "children" keys).
    def get_tree(atts = {}, tbl = "txp_category")
      defaults = {
        "categories" => nil, "exclude" => "", "parent" => "", "children" => true, "sort" => "name ASC",
        "type" => "article", "where" => "1", "limit" => "", "offset" => "", "flatten" => true
      }
      atts = atts.transform_keys(&:to_s)
      o = defaults.merge(atts.slice(*defaults.keys))
      categories = o["categories"]

      if !categories.nil?
        categories = Php.do_list_unique(categories)
        return {} if categories.empty?
      else
        categories = []
      end

      @tree_cache ||= {}
      @tree_level = (@tree_level || 0) + 1
      level = @tree_level
      parent = o["parent"]
      catonly = categories.any? && Php.empty?(parent)
      roots = Php.do_list_unique(parent)
      roots = categories if roots.empty?
      roots = [ "root" ] if roots.empty?
      rooted = roots.include?("root")
      multiple = roots.length > 1
      roots = roots.sort
      root = roots.join(",")
      children = o["children"]
      children = if children == true
        1 << 62
      else
        Php.numeric?(children) ? Php.intval(children) : (Php.truthy?(children) ? 1 : 0)
      end
      exclude = if Php.empty?(o["exclude"])
        []
      elsif o["exclude"] == true
        roots
      else
        o["exclude"].is_a?(Array) ? o["exclude"] : Php.do_list_unique(o["exclude"])
      end
      sort = Php.str(o["sort"])
      type = Php.str(o["type"])
      order = if sort != ""
        " ORDER BY #{sanitize_for_sort(sort)}"
      elsif categories.any?
        " ORDER BY FIELD(name, #{DB.quote_list(categories)})"
      else
        ""
      end
      sql_query = "#{o['where']} AND type = #{q type}#{order}"
      limit = o["limit"]
      offset = o["offset"]
      sql_limit = limit != "" || Php.truthy?(offset) ? "LIMIT #{Php.intval(offset)}, #{limit == '' || limit == true ? (1 << 62) : Php.intval(limit)}" : ""
      sql_exclude = exclude.any? && sql_limit != "" ? " AND name NOT IN (#{DB.quote_list(exclude)})" : ""

      nocache = children.zero? || sql_limit != "" || children == level
      hash = nocache ? SecureRandom.hex(8) : sql_query
      cache = (@tree_cache[hash] ||= { "" => {} })
      cache[""]["root"] = false if rooted

      if !cache.key?(root) || (!multiple && root != "root" && Php.empty?(cache[root][root]))
        cache[root] = {}
        cats = []

        if children.zero? || !rooted || categories.any?
          names = (roots + categories).uniq

          if catonly
            cats = DB.rows("SELECT id, name, parent, title, description FROM #{tbl} WHERE name IN (#{DB.quote_list(names)}) AND #{sql_query}")
          else
            found = DB.rows("SELECT id, name, parent, title, description, lft, rgt FROM #{tbl} WHERE name IN (#{DB.quote_list(names)}) AND #{sql_query}")
            if found.any?
              retrieved = categories.empty?
              between = []
              beyond = []

              found.each do |cat|
                lft = cat["lft"].to_i
                rgt = cat["rgt"].to_i
                sname = DB.escape(cat["name"])

                if roots.include?(cat["name"])
                  between << (children.positive? ? "lft>=#{lft} AND rgt<=#{rgt}" : "name='#{sname}' OR parent='#{sname}'")
                  retrieved &&= (rgt - lft == 1)
                end

                beyond << (children.positive? ? "lft<=#{lft} AND rgt>=#{rgt}" : "name='#{sname}'") if categories.include?(cat["name"])
              end

              cats = found.map { |c| c.except("lft", "rgt") }
              unless retrieved
                bounds = "#{between.any? ? "(#{between.join(' OR ')})" : '1'} AND #{beyond.any? ? "(#{beyond.join(' OR ')})" : '1'}"
                cats = DB.rows("SELECT id, name, parent, title, description FROM #{tbl} WHERE name != 'root' #{sql_exclude} AND #{bounds} AND #{sql_query} #{sql_limit}")
              end
            end
          end
        else
          cats = DB.rows("SELECT id, name, parent, title, description FROM #{tbl} WHERE name != 'root' #{sql_exclude} AND #{sql_query} #{sql_limit}")
        end

        cats.each do |cat|
          name = cat["name"]
          cparent = cat["parent"]
          node = children == level ? root : name
          (cache[node] ||= {})[name] = cat

          next if children == level

          cache[root][name] = cat if multiple && roots.include?(name)
          cache[cparent] ||= {}
          cache[""][name] = false
          cache[cparent][name] = cat
          cache[""][cparent] = true unless cache[""].key?(cparent)
          cache[root][name] = cat if multiple && roots.include?(cparent)
        end

        cache[""] = cache[""].select { |_k, v| v }
      end

      out = {}
      (cache[root] || {}).each do |name, cat|
        next if exclude.include?(name)
        next if categories.any? && catonly && !categories.include?(name)
        next unless level > 1 || children <= level || rooted || roots.include?(name) || exclude.include?(cat["parent"])

        out[name] = cat.merge("level" => level - 1)

        next unless cache.key?(name) && children > level && cache[name].length > 1

        nodes = get_tree(atts.merge("parent" => name, "exclude" => exclude + [ name ]), tbl)
        next if nodes.empty?

        if o["flatten"]
          out[name]["children"] = nodes.length
          out.merge!(nodes) { |_k, old, _new| old }
        else
          out[name]["children"] = nodes
        end
      end

      @tree_level -= 1

      if nocache
        @tree_cache.delete(hash)
      elsif @tree_level <= 0
        cache[""].each_key { |p| cache.delete(p) }
      end

      out
    end

    def sanitize_for_sort(text)
      Php.str(text).gsub("#", " ").gsub("--", " ").strip
    end

    # getTree(): category names below the given roots, optionally restricted
    # to the given depth levels (0 = the roots themselves).
    def get_tree_names(roots, type = "article", depth = true, where = "1")
      roots = Php.do_list_unique(roots)
      atts = Php.truthy?(depth) ? { "parent" => roots } : { "categories" => roots }
      levels = depth == true || Php.empty?(depth) ? nil : Php.do_list(depth, [ ",", "-" ]).map(&:to_i)
      rows = get_tree(atts.merge("type" => type, "where" => where, "children" => Php.truthy?(depth)))
      rows.select { |_name, r| levels.nil? || levels.include?(r["level"].to_i) }.keys
    end

    # imageFetchInfo(): by id, by name, the current image, or the image
    # given by the "p" URL parameter.
    def image_fetch_info(id = "", name = "")
      id = Php.str(id)
      name = Php.str(name)
      @images ||= { "i" => {}, "n" => {} }
      key = ->(v) { v.to_s.match?(/\A\d+\z/) ? v.to_i : v.to_s }

      if Php.truthy?(id)
        return @images["i"][key.call(id)] if @images["i"].key?(key.call(id))
        return external_image_info(id) unless id.strip.match?(/\A\d+\z/)

        where = "id = #{id.to_i}"
      elsif Php.truthy?(name)
        return @images["n"][name] if @images["n"].key?(name)

        where = "name = #{q name}"
      elsif Php.truthy?(@thisimage)
        return @images["i"][Php.intval(@thisimage["id"])] = @thisimage
      elsif Php.truthy?(@pretext["p"])
        p = @pretext["p"]
        return @images["i"][key.call(p)] if @images["i"].key?(key.call(p))

        where = "id = #{Php.intval(p)}"
      else
        assert_image
        return false
      end

      row = DB.row("SELECT *, #{DB.timestamp("date", "udate")} FROM txp_image WHERE #{where}")
      if row
        @images["i"][row["id"].to_i] = image_format_info(row)
      else
        trigger_error(gTxt("unknown_image"))
        false
      end
    end

    def external_image_info(url)
      { "id" => url, "name" => File.basename(url), "ext" => File.extname(url), "category" => "", "alt" => "",
        "caption" => "", "author" => "", "w" => 0, "h" => 0, "thumbnail" => 0, "thumb_w" => 0, "thumb_h" => 0, "date" => nil }
    end

    def image_format_info(row)
      r = row.dup
      r["date"] = r["udate"] || DB.to_unix(r["date"]) if r.key?("date")
      r.delete("udate")
      r["mime"] = Txp::Images.mime_for(r["ext"])
      w = r["w"].to_i
      h = r["h"].to_i
      r["aspect"] = h.positive? ? (w.to_f / h).round(2) : ""
      r
    end

    # fileDownloadFetchInfo(): adds the sniffed MIME type and the extension.
    def file_download_fetch_info(where)
      row = DB.row("SELECT *, #{DB.timestamps('created' => 'ucreated', 'modified' => 'umodified')} FROM txp_file WHERE #{where}")
      return false unless row

      r = file_download_format_info(row)
      r["ext"] = File.extname(r["filename"].to_s).delete(".")
      # Sniffed from the file; empty when it is missing (Textpattern 4.9 lets
      # PHP's mime_content_type() warn about it on every page).
      path = TxpFile.base_path.join(r["filename"].to_s)
      r["mime"] = File.file?(path) ? Marcel::MimeType.for(path, name: r["filename"].to_s) : ""
      r
    end

    def file_download_format_info(row)
      r = row.dup
      r["created"] = r.delete("ucreated") || DB.to_unix(r["created"])
      r["modified"] = r.delete("umodified") || DB.to_unix(r["modified"])
      r
    end

    def custom_fields
      @custom_fields ||= begin
        out = {}
        @prefs.each do |name, val|
          m = /\Acustom_(\d+)_set\z/.match(name)
          out[m[1].to_i] = val.to_s.downcase if m && val.to_s != ""
        end
        out.sort.to_h
      end
    end

    def section_rows
      @txp_sections
    end

    # filterFrontPage(): restricts a query to sections flagged in $column.
    def filter_front_page(field = "Section", column = [ "on_frontpage" ], negate = false)
      column = Php.do_list_unique(column) unless column.is_a?(Array)
      sample = @txp_sections["default"] || @txp_sections.values.first || {}
      column &= sample.keys
      column.sort!
      @front_page_cache ||= {}
      key = "#{field}.#{column.join('.')}"
      not_sql = negate ? "NOT " : ""

      unless @front_page_cache.key?(key)
        value = "0"
        if field
          num = @txp_sections.length
          flagged = {}
          column.each do |col|
            @txp_sections.each { |name, s| flagged[name] = true if Php.truthy?(s[col]) }
          end
          count = flagged.length
          if count.positive?
            value = if count == num
              "1"
            elsif 2 * count < num
              "#{field} IN (#{DB.quote_list(flagged.keys)})"
            else
              "NOT #{field} IN (#{DB.quote_list(@txp_sections.keys - flagged.keys)})"
            end
          end
        elsif column.any?
          value = column.map { |col| Php.numeric?(sample[col]) || sample[col].is_a?(Integer) ? col : "#{col} > ''" }.join(" AND ")
        end
        @front_page_cache[key] = value
      end

      " AND #{("#{not_sql}#{@front_page_cache[key]}").sub(/\ANOT NOT /, '')}"
    end

    # buildTimeSql()
    def build_time_sql(month, time, field = "Posted")
      month = month.strip if month.is_a?(String)
      time = time.strip if time.is_a?(String)
      safe_field = "`#{DB.escape(field)}`"

      if %w[past any future].include?(month)
        return "#{safe_field} <= #{DB.now}" if month == "past"
        return "#{safe_field} > #{DB.now}" if month == "future"

        return "1"
      end

      if %w[past any future].include?(time)
        timeq = if time == "past"
          "#{safe_field} <= #{DB.now}"
        elsif time == "future"
          "#{safe_field} > #{DB.now}"
        else
          "1"
        end

        if Php.truthy?(month)
          from, to = month_range(month)
          timeq += from ? " AND #{safe_field} >= #{DB.unixtime(from)} AND #{safe_field} < #{DB.unixtime(to)}" : " AND #{safe_field} LIKE #{q "#{month}%"}"
        end

        return timeq
      end

      if time.is_a?(String) && time.include?("%")
        start = Php.truthy?(month) ? (site_strtotime(month) || Time.now.to_i) : Time.now.to_i
        pattern = safe_strftime(time, start)
        return "strftime('%Y-%m-%d %H:%M:%S', #{safe_field}, #{q utc_offset_modifier(start)}) LIKE #{q pattern}"
      end

      start = Php.truthy?(month) ? site_strtotime(month) : false
      if start.nil? || start == false
        from = Php.truthy?(month) ? q(month) : DB.now
        start = Time.now.to_i
      else
        from = DB.unixtime(start)
      end

      case time
      when "since" then "#{safe_field} > #{from}"
      when "until" then "#{safe_field} <= #{from}"
      else
        stop = time.nil? ? Time.now.to_i : (site_strtotime(time, start) || Time.now.to_i)
        start, stop = stop, start if start > stop
        start == stop ? "#{safe_field} = #{DB.unixtime(start)}" : "#{safe_field} BETWEEN #{DB.unixtime(start)} AND #{DB.unixtime(stop)}"
      end
    end

    # Converts "2026", "2026-09" or "2026-09-21" (site time) to a UTC range.
    def month_range(month)
      parts = month.to_s.split("-").map(&:to_i)
      return [ nil, nil ] if parts.empty? || parts[0].zero?

      zone = site_zone
      start = case parts.length
      when 1 then zone.local(parts[0], 1, 1)
      when 2 then zone.local(parts[0], parts[1].clamp(1, 12), 1)
      else zone.local(parts[0], parts[1].clamp(1, 12), parts[2].clamp(1, 31))
      end
      stop = case parts.length
      when 1 then start + 1.year
      when 2 then start + 1.month
      else start + 1.day
      end
      [ start.to_i, stop.to_i ]
    rescue ArgumentError
      [ nil, nil ]
    end

    def utc_offset_modifier(ts)
      offset = site_zone.at(ts).utc_offset
      sign = offset.negative? ? "-" : "+"
      "#{sign}#{offset.abs / 60} minutes"
    end

    # buildCustomSql()
    def build_custom_sql(custom, pairs, exclude = {})
      out = []
      (pairs || {}).each do |k, val|
        no = custom.nil? ? k : custom.key(k)
        next if no.nil?

        negate = exclude == true || (exclude.is_a?(Hash) && exclude.key?(k)) ? "NOT " : ""
        field = no.is_a?(Integer) || Php.numeric?(no) ? "custom_#{no}" : no

        if val == true
          out << "(#{negate}#{field} != '')"
        elsif !val.nil?
          parts = Array(val).map do |v|
            from, to = Php.str(v).split("%%", 2)
            if to.nil?
              "#{negate}#{field} LIKE #{q from}"
            elsif from != ""
              to == "" ? "#{negate}#{field} >= #{q from}" : "#{negate}#{field} BETWEEN #{q from} AND #{q to}"
            elsif to != ""
              "#{negate}#{field} <= #{q to}"
            end
          end.compact
          out << "(#{parts.join(negate.empty? ? ' OR ' : ' AND ')})" if parts.any?
        end
      end
      out.any? ? " AND #{out.join(' AND ')} " : ""
    end
  end
end
