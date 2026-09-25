module Txp
  module Tags
    # Image tags.
    module Images
      def tag_thumbnail(atts, _thing = nil)
        tag_image(atts.key?("thumbnail") ? atts : atts.merge("thumbnail" => nil))
      end

      def tag_image(atts, _thing = nil)
        tag_atts = {
          "escape" => true, "alt" => nil, "title" => "", "class" => "", "crop" => "", "html_id" => "",
          "height" => "0", "id" => "", "link" => 0, "link_rel" => "", "loading" => nil, "name" => "",
          "poplink" => 0, "quality" => "", "wraptag" => "", "width" => "0", "type" => "", "thumbnail" => false
        }
        ext_atts = join_atts(atts.reject { |k, _| tag_atts.key?(k) || @txp_atts&.key?(k) }, strip_txp: true)
        given = atts.slice(*tag_atts.keys)
        a = lAtts(tag_atts, given)
        thumb_type = a["thumbnail"]
        trigger_error(gTxt("deprecated_attribute", "{name}" => "poplink")) if given.key?("poplink")

        data = image_fetch_info(a["id"], a["name"])
        return nil unless data

        data = data.dup
        thumbnail = Php.str(data["thumbnail"])
        col_prefix = Php.loose_eq(thumb_type, THUMB_CUSTOM) || thumb_type.nil? ? "thumb_" : ""

        if col_prefix != "" && Php.empty?(data["thumbnail"])
          col_prefix = ""
          return nil if thumb_type.nil?
        end

        alt = a["alt"]
        if alt == true
          data["alt"] = data["name"] if Php.str(data["alt"]) == ""
        elsif !alt.nil?
          data["alt"] = alt
        end

        alt = Php.str(data["alt"])
        alt = txp_escape(a["escape"], alt) if Php.truthy?(a["escape"])
        title = a["title"] == true ? data["caption"] : a["title"]
        auto = Php.loose_eq(thumbnail, THUMB_AUTO) || Php.loose_eq(thumb_type, THUMB_AUTO)
        width = a["width"]
        height = a["height"]
        width = (col_prefix != "" && Php.truthy?(data["thumb_w"]) ? data["thumb_w"] : data["w"]) if width == "" || width == true
        height = (col_prefix != "" && Php.truthy?(data["thumb_h"]) ? data["thumb_h"] : data["h"]) if height == "" || height == true
        crop = auto && a["crop"] == true ? "1x1" : a["crop"]
        payload = { "id" => data["id"], "ext" => data["ext"] }
        payload.merge!("w" => width, "h" => height, "c" => crop, "q" => a["quality"], "t" => a["type"]) if auto
        thumb_wanted = thumb_type.nil? ? thumbnail : thumb_type
        thumb_wanted = nil if thumb_wanted == false
        src = image_build_url(payload, thumb_wanted)

        out = +%(<img src="#{src}" alt="#{txpspecialchars(alt, double_encode: false)}")
        out << %( title="#{txpspecialchars(title, double_encode: false)}") if Php.truthy?(title)
        out << %( id="#{txpspecialchars(a['html_id'])}") if Php.truthy?(a["html_id"]) && Php.empty?(a["wraptag"])
        out << %( class="#{txpspecialchars(a['class'])}") if Php.truthy?(a["class"]) && Php.empty?(a["wraptag"])
        out << %( width="#{Php.intval(width)}") if Php.truthy?(width)
        out << %( height="#{Php.intval(height)}") if Php.truthy?(height)
        loading = a["loading"]
        out << %( loading="#{loading}") if loading && html5? && %w[auto eager lazy].include?(loading)
        out << ext_atts << void_close

        if Php.truthy?(a["link"]) && col_prefix != ""
          attribs = Php.truthy?(a["link_rel"]) ? " rel='#{txpspecialchars(a['link_rel'])}'" : ""
          out = href(out, image_build_url(payload, nil), attribs)
        elsif Php.truthy?(a["poplink"])
          full = image_build_url(payload, nil)
          out = %(<a href="#{full}" onclick="window.open(this.href, 'popupwindow', 'width=#{data['w']}, height=#{data['h']}, scrollbars, resizable'); return false;">#{out}</a>)
        end

        Php.truthy?(a["wraptag"]) ? do_tag(out, a["wraptag"], a["class"], "", a["html_id"]) : out
      end

      def tag_image_index(atts, _thing = nil)
        trigger_error(gTxt("deprecated_tag"))
        atts = atts.dup
        atts["category"] = @pretext["c"] unless atts.key?("category")
        atts["class"] = "image_index" unless atts.key?("class")
        Php.truthy?(atts["category"]) ? tag_images(atts) : ""
      end

      def tag_image_display(_atts, _thing = nil)
        trigger_error(gTxt("deprecated_tag"))
        Php.truthy?(@pretext["p"]) ? tag_image({ "id" => @pretext["p"], "thumbnail" => false }) : nil
      end

      def tag_images(atts, thing = nil)
        filters = %w[id name category author realname extension size month time].any? { |k| atts.key?(k) }
        a = lAtts({
          "name" => "", "id" => "", "category" => "", "author" => "", "realname" => "", "extension" => "",
          "thumbnail" => true, "size" => "", "month" => "", "time" => nil, "exclude" => "",
          "auto_detect" => filters ? "" : "article, category, author", "break" => "br", "wraptag" => "",
          "class" => "images", "html_id" => "", "form" => "", "pageby" => "", "limit" => 0, "offset" => 0,
          "sort" => "name ASC"
        }, atts)
        where = []
        has_content = !thing.nil? || Php.truthy?(a["form"])
        thumbnail = a["thumbnail"]
        thumbnail = nil unless has_content || Php.truthy?(thumbnail)
        context_list = Php.empty?(a["auto_detect"]) ? [] : Php.do_list_unique(a["auto_detect"])
        limit = Php.intval(a["limit"])
        pageby = a["pageby"] == "limit" ? limit : Php.intval(a["pageby"])
        exclude = a["exclude"] == true ? true : (Php.truthy?(a["exclude"]) ? Php.do_list_unique(a["exclude"]) : [])
        ex = ->(k) { exclude == true || (exclude.is_a?(Array) && exclude.include?(k)) }
        context = @pretext["context"]
        c = @pretext["c"]

        if exclude.is_a?(Array)
          ranges = exclude.select { |e| e.match?(/\A\d+(?:\s*-\s*\d+)?\z/) }
          ranges.each do |value|
            from, to = value.split("-").map(&:strip)
            where << (to ? "id NOT BETWEEN #{from.to_i} AND #{to.to_i}" : "id != #{from.to_i}")
          end
          exclude -= ranges
        end

        where << "name#{ex.call('name') ? ' NOT' : ''} IN (#{DB.quote_list(Php.do_list_unique(a['name']))})" if Php.truthy?(a["name"])

        category = if Php.truthy?(a["category"])
          Php.do_list_unique(a["category"])
        elsif context == "image" && Php.truthy?(c) && context_list.include?("category")
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
        elsif context == "image" && Php.truthy?(@pretext["author"]) && context_list.include?("author")
          [ @pretext["author"] ]
        else
          []
        end
        where << "author#{ex.call('author') ? ' NOT' : ''} IN (#{DB.quote_list(author)})" if author.any?

        if Php.truthy?(a["realname"])
          names = DB.column("SELECT name FROM txp_users WHERE RealName IN (#{DB.quote_list(Php.do_list_unique(a['realname']).map { |n| Php.urldecode(n) })})")
          where << "author#{ex.call('realname') ? ' NOT' : ''} IN (#{DB.quote_list(names)})" if names.any?
        end

        if Php.truthy?(a["extension"])
          exts = Php.do_list_unique(a["extension"]).map { |e| e.start_with?(".") ? e : ".#{e}" }
          where << "ext#{ex.call('extension') ? ' NOT' : ''} IN (#{DB.quote_list(exts)})"
        end

        where << "thumbnail = #{thumbnail}" if [ THUMB_NONE, THUMB_CUSTOM, THUMB_AUTO ].include?(thumbnail)

        if Php.truthy?(a["size"])
          sizes = Php.do_list_unique(a["size"]).filter_map do |size|
            case size
            when "portrait" then "h > w"
            when "landscape" then "w > h"
            when "square" then "w = h"
            else
              if Php.numeric?(size)
                "ROUND(w*1.0/h, 2) = #{size.to_f}"
              elsif size.include?(":")
                rw, rh = size.split(":")
                if Php.numeric?(rw) && Php.numeric?(rh)
                  "ROUND(w*1.0/h, 2) = #{(rw.to_f / rh.to_f).round(2)}"
                elsif Php.numeric?(rw)
                  "w = #{rw.to_i}"
                elsif Php.numeric?(rh)
                  "h = #{rh.to_i}"
                end
              end
            end
          end
          where << "#{ex.call('size') ? 'NOT ' : ''}(#{sizes.join(' OR ')})" if sizes.any?
        end

        time = a["time"]
        month = a["month"]
        if Php.truthy?(time) || Php.truthy?(month)
          where << "#{ex.call('month') || ex.call('time') ? 'NOT ' : ''}(#{build_time_sql(month, time.nil? ? 'past' : time, 'date')})"
        end

        id = a["id"]
        id = if id == true || (Php.empty?(id) && context_list.include?("article"))
          @thisarticle.nil? || Php.empty?(@thisarticle["article_image"]) ? 0 : @thisarticle["article_image"]
        else
          id
        end

        ids = []
        if Php.truthy?(id)
          negate = ex.call("id") ? " NOT" : ""
          numid = Php.do_list_unique(Php.str(id), [ ",", "-" ]).select { |v| v.match?(/\A\d+\z/) }
          ids = numid
          where << (numid.any? ? "id#{negate} IN (#{numid.join(',')})" : (negate != "" ? "1" : "0"))
        end

        if where.empty? && filters
          return thing.nil? ? "" : parse(thing, false)
        end

        where << build_time_sql(month, "past", "date") if time.nil? && Php.empty?(month)
        where_sql = where.empty? ? "1" : where.join(" AND ")
        sort = !atts.key?("sort") && ids.any? ? "FIELD(id, #{ids.join(',')})" : sanitize_for_sort(a["sort"])
        offset = Php.intval(a["offset"])

        if limit.positive? && pageby.positive?
          pg = Php.empty?(@pretext["pg"]) ? 1 : Php.intval(@pretext["pg"])
          pgoffset = offset + (pg - 1) * pageby
          if @thispage.nil?
            grand_total = DB.count("txp_image", where_sql)
            total = grand_total - offset
            @thispage = {
              "pg" => pg, "numPages" => (total.to_f / pageby).ceil, "s" => @pretext["s"], "c" => c,
              "context" => "image", "grand_total" => grand_total, "total" => total
            }
          end
        else
          pgoffset = offset
        end

        limit_sql = limit.positive? ? " LIMIT #{pgoffset}, #{limit}" : ""
        rows = DB.rows("SELECT *, #{DB.timestamp('date', 'udate')} FROM txp_image WHERE #{where_sql} ORDER BY #{sort}#{limit_sql}")

        unless has_content
          url = %(<txp:page_url context='s, c, p' c='<txp:image_info type="category" />' p='<txp:image_info type="id" escape="" />' />&amp;context=image)
          thumb = thumbnail.nil? ? 0 : (thumbnail != true ? 1 : '<txp:image_info type="thumbnail" escape="" />')
          thing = %(<a href="#{url}"><txp:image thumbnail='#{thumb}' /></a>)
        end

        out = parse_list(rows, "image", populate: ->(r) { image_format_info(r) }, form: a["form"], thing: thing)
        return thing.nil? ? "" : parse(thing, false) if out.empty?

        do_wrap(out, a["wraptag"], { "break" => a["break"], "class" => a["class"], "html_id" => a["html_id"] })
      end

      def tag_image_info(atts, _thing = nil)
        a = lAtts({ "name" => "", "id" => "", "type" => "caption", "escape" => true, "wraptag" => "", "class" => "", "break" => "" }, atts)
        valid = %w[id name category category_title alt caption ext mime author w h thumbnail thumb_w thumb_h date aspect]
        out = []

        if (data = image_fetch_info(a["id"], a["name"]))
          Php.do_list(a["type"]).each do |item|
            unless valid.include?(item)
              trigger_error(gTxt("invalid_attribute_value", "{name}" => item))
              next
            end
            value = item == "category_title" ? fetch_category_title(data["category"], "image") : data[item]
            next if value.nil?

            out << (Php.truthy?(a["escape"]) ? txp_escape(a["escape"], Php.str(value)) : value)
          end
        end

        do_wrap(out, a["wraptag"], a["break"], a["class"])
      end

      def tag_image_url(atts, thing = nil)
        a = lAtts({
          "name" => "", "id" => "", "thumbnail" => 0, "link" => "auto", "width" => "0", "height" => "0",
          "crop" => "", "quality" => "", "type" => ""
        }, atts)
        thumbnail = Php.empty?(a["thumbnail"]) ? nil : a["thumbnail"]
        stash = @thisimage if (Php.truthy?(a["name"]) || Php.truthy?(a["id"])) && Php.truthy?(thing)
        data = image_fetch_info(a["id"], a["name"])
        out = nil

        if data
          img = data.dup
          @thisimage = img
          width = a["width"]
          height = a["height"]
          width = (thumbnail && Php.truthy?(img["thumb_w"]) ? img["thumb_w"] : img["w"]) if width == "" || width == true
          height = (thumbnail && Php.truthy?(img["thumb_h"]) ? img["thumb_h"] : img["h"]) if height == "" || height == true
          crop = a["crop"] == true ? "1x1" : a["crop"]

          if Php.str(thumbnail) == THUMB_AUTO || Php.truthy?(width) || Php.truthy?(height) || Php.truthy?(crop)
            img.merge!("w" => width, "h" => height, "c" => crop, "q" => a["quality"], "t" => a["type"])
            thumbnail = THUMB_AUTO if Php.truthy?(width) || Php.truthy?(height) || Php.truthy?(crop)
          elsif Php.str(thumbnail) == THUMB_CUSTOM
            img.merge!("w" => "", "h" => "")
          end

          url = image_build_url(img, thumbnail)
          link = a["link"] == "auto" ? Php.truthy?(thing) : Php.truthy?(a["link"])
          out = Php.truthy?(thing) ? parse(thing) : url
          out = href(out, url) if link
        end

        @thisimage = stash if defined?(stash) && stash
        out.nil? ? "" : out
      end

      def tag_image_author(atts, _thing = nil)
        a = lAtts({ "name" => "", "id" => "", "link" => 0, "title" => 1, "section" => "", "this_section" => "" }, atts)
        data = image_fetch_info(a["id"], a["name"])
        return nil unless data

        author_name = get_author_name(data["author"])
        display = txpspecialchars(Php.truthy?(a["title"]) ? author_name : data["author"])
        section = Php.truthy?(a["this_section"]) ? (@pretext["s"] == "default" ? "" : @pretext["s"]) : a["section"]
        Php.truthy?(a["link"]) ? href(display, pagelinkurl({ "s" => section, "author" => author_name, "context" => "image" })) : display
      end

      def tag_image_date(atts, _thing = nil)
        a = lAtts({ "name" => "", "id" => "", "format" => "" }, atts)
        data = image_fetch_info(a["id"], a["name"])
        return nil unless data

        format_time_attr(data["date"], a["format"])
      end

      # fileDownloadFormatTime()
      def format_time_attr(time, format)
        return "" if time.nil?

        format = get_pref("archive_dateformat") if Php.empty?(format)
        safe_strftime(format, time)
      end

      def tag_if_thumbnail(_atts, thing = nil)
        assert_image
        x = Php.intval(@thisimage["thumbnail"]) == 1
        thing.nil? ? x : parse(thing, x)
      end
    end
  end
end
