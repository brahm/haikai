module Txp
  # URL schemes: pagelinkurl(), permlinkurl(), filedownloadurl(), image URLs.
  module UrlHelpers
    CONTEXT_INTERNALS = %w[id s c context q m pg p month author f].freeze

    def get_context(context = true, internals = CONTEXT_INTERNALS)
      return (@txp_context || {}).dup if context.nil?
      return {} if Php.empty?(context)

      unless context.is_a?(Hash)
        keys = context == true ? internals : Php.do_list_unique(context)
        context = keys.index_with { nil }
      end

      out = {}
      context.each do |q, v|
        if !v.nil?
          out[q] = v
        elsif @pretext.key?(q) && internals.include?(q)
          val = q == "author" ? @pretext["realname"] : @pretext[q]
          out[q] = val unless Php.empty?(val)
        else
          out[q] = gps(q, v)
        end
      end
      out
    end

    def context_label(context)
      gTxt("#{context}_context")
    end

    def pagelinkurl(parts, inherit = {}, url_mode = nil)
      parts = parts.transform_keys(&:to_s)
      return permlinkurl_id(parts["id"]) if Php.truthy?(parts["id"])

      base = @prefs["@txp_root"] || hu
      keys = parts.dup
      inherit.each { |k, v| keys[k.to_s] = v unless keys.key?(k.to_s) } if inherit.is_a?(Hash)
      (@txp_context || {}).each { |k, v| keys[k] = v unless keys.key?(k) }
      keys.delete("id")

      if keys.key?("s")
        url_mode ||= @txp_sections.dig(keys["s"], "permlink_mode") if @txp_sections.key?(keys["s"])
        keys.delete("s") if keys["s"] == "default"
      end

      url_mode = @prefs["permlink_mode"] if Php.empty?(url_mode)
      keys.delete("context") if keys["context"] == "article"

      loc = @prefs["@txp_lang"].nil? || @prefs["@txp_lang"].to_s.downcase == lang
      numkeys = []
      keys.keys.each do |k|
        next unless k.match?(/\A\d+\z/)

        numkeys << "#{Php.urlencode(keys[k])}/"
        keys.delete(k)
      end

      url = +""
      if url_mode == "messy"
        url = +"index.php"
      elsif Php.truthy?(keys["rss"])
        url = +"rss/"
        keys.delete("rss")
      elsif Php.truthy?(keys["atom"])
        url = +"atom/"
        keys.delete("atom")
      elsif Php.truthy?(keys["s"])
        url = +"#{Php.urlencode(keys['s'])}/"
        keys.delete("s")
        if Php.truthy?(keys["c"]) && %w[section_category_title breadcrumb_title].include?(url_mode)
          catpath = url_mode == "breadcrumb_title" ? get_root_path(keys["c"], Php.empty?(keys["context"]) ? "article" : keys["context"]).map { |r| r["name"] } : [ keys["c"] ]
          url << catpath.reverse.map { |c| Php.urlencode(c) }.join("/") << "/"
          keys.delete("c")
        elsif Php.truthy?(keys["month"]) && url_mode == "year_month_day_title" && is_date(keys["month"])
          url << Php.urlencode(keys["month"]).split("-").join("/") << "/"
          keys.delete("month")
        end
      elsif Php.truthy?(keys["author"]) && url_mode != "year_month_day_title"
        ct = Php.empty?(keys["context"]) ? "" : "#{Php.urlencode(context_label(keys['context'])).downcase}/"
        url = +"#{loc ? Php.urlencode(gTxt('author')).downcase : 'author'}/#{ct}#{Php.urlencode(keys['author'])}/"
        keys.delete("author")
        keys.delete("context")
      elsif Php.truthy?(keys["c"]) && url_mode != "year_month_day_title"
        ct = Php.empty?(keys["context"]) ? "" : "#{Php.urlencode(context_label(keys['context'])).downcase}/"
        url = +"#{loc ? Php.urlencode(gTxt('category')).downcase : 'category'}/#{ct}"
        catpath = url_mode == "breadcrumb_title" ? get_root_path(keys["c"], Php.empty?(keys["context"]) ? "article" : keys["context"]).map { |r| r["name"] } : [ keys["c"] ]
        url << catpath.reverse.map { |c| Php.urlencode(c) }.join("/") << "/"
        keys.delete("c")
        keys.delete("context")
      elsif Php.truthy?(keys["month"]) && is_date(keys["month"])
        url = +"#{Php.urlencode(keys['month']).split('-').join('/')}/"
        keys.delete("month")
      end

      keys["context"] = context_label(keys["context"]) if Php.truthy?(keys["context"])
      url = url.sub(%r{/+\z}, "") if Php.intval(@prefs["trailing_slash"]).negative?
      "#{base}#{url}#{join_qs(keys)}"
    end

    def permlinkurl_id(id)
      id = Php.intval(id)
      @permlinks ||= {}
      return permlinkurl({ "id" => id }) if @permlinks.key?(id)
      return permlinkurl(@thisarticle) if @thisarticle && Php.intval(@thisarticle["thisid"]) == id

      row = id.zero? ? nil : DB.row("SELECT ID AS thisid, Section AS section, Title AS title, url_title, Category1 AS category1, Category2 AS category2, #{DB.timestamps('Posted' => 'posted', 'Expires' => 'expires')} FROM textpattern WHERE ID = #{id}")
      permlinkurl(row)
    end

    def permlinkurl(article, base = nil)
      return false if article.nil? || article.empty?

      a = article.transform_keys { |k| k.to_s.downcase }
      base ||= @prefs["@txp_root"] || hu
      thisid = Php.intval(a["thisid"].nil? || a["thisid"] == "" ? a["id"] : a["thisid"])
      keys = get_context(nil)
      %w[id s context p].each { |k| keys.delete(k) }
      @permlinks ||= {}

      if @permlinks.key?(thisid)
        link = @permlinks[thisid]
        return link == true ? "#{base}index.php#{join_qs({ 'id' => thisid }.merge(keys))}" : "#{base}#{link}#{join_qs(keys)}"
      end

      url_title = Php.str(a["url_title"])
      return url_title if url_title.match?(%r{\A(?:https?:)?//\S+\z}i)

      section = Php.str(a["section"])
      url_mode = if section == ""
        "messy"
      elsif @txp_sections.key?(section)
        Php.empty?(@txp_sections[section]["permlink_mode"]) ? @prefs["permlink_mode"] : @txp_sections[section]["permlink_mode"]
      else
        @prefs["permlink_mode"]
      end

      url_mode = "id_title" if url_mode == "title_only" && @txp_sections.key?(url_title) && Php.truthy?(@prefs["trailing_slash"])

      posted = a["uposted"] || a["posted"]
      posted = DB.to_unix(posted) unless posted.nil? || Php.numeric?(posted)

      if (url_title == "" && !%w[section_id_title id_title].include?(url_mode)) ||
         (url_mode == "year_month_day_title" && posted.nil?)
        url_mode = "messy"
      end

      esection = Php.urlencode(section)
      etitle = Php.urlencode(url_title)
      attach = Php.truthy?(@prefs["attach_titles_to_permalinks"])

      out = case url_mode
      when "section_id_title"
        etitle != "" && attach ? "#{esection}/#{thisid}/#{etitle}" : "#{esection}/#{thisid}"
      when "year_month_day_title"
        "#{local_time(Php.intval(posted)).strftime('%Y/%m/%d')}/#{etitle}"
      when "id_title"
        etitle != "" && attach ? "#{thisid}/#{etitle}" : thisid.to_s
      when "section_title"
        "#{esection}/#{etitle}"
      when "section_category_title"
        path = +"#{esection}/"
        path << "#{Php.urlencode(a['category1'])}/" unless Php.empty?(a["category1"])
        path << "#{Php.urlencode(a['category2'])}/" unless Php.empty?(a["category2"])
        path << etitle
      when "breadcrumb_title"
        breadcrumb_path(esection, a["category1"], a["category2"], etitle)
      when "title_only"
        etitle
      else
        keys["id"] = thisid
        "index.php"
      end

      if url_mode == "messy"
        @permlinks[thisid] = true
        "#{base}index.php#{join_qs({ 'id' => thisid }.merge(keys.except('id')))}"
      else
        out = "#{out}/" if Php.intval(@prefs["trailing_slash"]).positive?
        @permlinks[thisid] = out
        "#{base}#{out}#{join_qs(keys)}"
      end
    end

    def breadcrumb_path(section, cat1, cat2, title)
      out = +"#{section}/"
      path_of = ->(c) { get_root_path(c).map { |r| r["name"] }.reverse }
      if Php.empty?(cat1)
        out << path_of.call(cat2).map { |c| Php.urlencode(c) }.join("/") << "/" unless Php.empty?(cat2)
      elsif Php.empty?(cat2)
        out << path_of.call(cat1).map { |c| Php.urlencode(c) }.join("/") << "/"
      else
        c2 = path_of.call(cat2)
        if c2.include?(cat1)
          out << c2.map { |c| Php.urlencode(c) }.join("/") << "/"
        else
          c1 = path_of.call(cat1)
          if c1.include?(cat2)
            out << c1.map { |c| Php.urlencode(c) }.join("/") << "/"
          else
            common = c1 & c2
            out << common.map { |c| Php.urlencode(c) }.join("/") << "/" unless common.empty?
            out << "#{Php.urlencode(cat1)}/#{Php.urlencode(cat2)}/"
          end
        end
      end
      out << title
    end

    def filedownloadurl(id, filename = "")
      if @prefs["permlink_mode"] == "messy"
        return "#{hu}index.php#{join_qs('s' => 'file_download', 'id' => Php.intval(id))}"
      end

      fname = filename.to_s == "" ? "" : "/#{Php.urlencode(filename)}"
      fname = "#{fname}&" if fname.match?(/gz\z/i)
      slash = Php.intval(@prefs["trailing_slash"]).positive? ? "/" : ""
      "#{hu}file_download/#{Php.intval(id)}#{fname}#{slash}"
    end

    def img_dir
      Php.str(get_pref("img_dir", "images"))
    end

    def imagesrcurl(id, ext, thumbnail = false)
      return id unless id.to_s.match?(/\A\d+\z/)

      "#{ihu}#{img_dir}/#{id}#{thumbnail ? 't' : ''}#{ext}"
    end

    # imageBuildURL(): full image, custom thumbnail, or resized (auto) thumbnail.
    def image_build_url(img = nil, thumbnail = nil)
      img ||= @thisimage || {}
      img = img.transform_keys(&:to_s)
      id = img["id"]
      ext = img["ext"]
      params = {}

      if Php.loose_eq(thumbnail, THUMB_AUTO)
        params["w"] = img["w"] if Php.truthy?(img["w"])
        params["h"] = img["h"] if Php.truthy?(img["h"])
        params["c"] = img["c"] if Php.truthy?(img["c"])
        params["q"] = img["q"] if Php.truthy?(img["q"]) && Php.intval(img["q"]).between?(1, 100)
        params["t"] = img["t"].to_s.delete(".") if Php.truthy?(img["t"])
      end

      if Php.loose_eq(thumbnail, THUMB_AUTO) && params.any? && ext.to_s.downcase != ".svg" && id.to_s.match?(/\A\d+\z/)
        paramlist = Txp::Thumbnails.encode(params)
        out_ext = params["t"] ? ".#{params['t']}" : ext
        base = "#{img_dir}/thumb/#{paramlist}/#{id}#{out_ext}"
        cached = Rails.root.join("public", base)
        token = File.exist?(cached) ? "" : "?token=#{Txp::Thumbnails.token(id, paramlist, @prefs)}"
        "#{ihu}#{base}#{token}"
      elsif Php.loose_eq(thumbnail, THUMB_CUSTOM)
        imagesrcurl(id, ext, true)
      elsif thumbnail.is_a?(String) && thumbnail == THUMB_NONE
        ""
      else
        imagesrcurl(id, ext, false)
      end
    end

    def is_date(month)
      month = Php.str(month)
      return false unless month.match?(/\A\d{1,4}(?:-\d{1,2}){0,2}\z/)

      parts = month.split("-", 3)
      case parts.length
      when 3
        return false unless Date.valid_date?(parts[0].to_i, parts[1].to_i, parts[2].to_i)

        parts[2] = parts[2].rjust(2, "0")
        parts[1] = parts[1].rjust(2, "0")
      when 2
        return false unless parts[1].to_i.between?(1, 12)

        parts[1] = parts[1].rjust(2, "0")
      end
      return false unless parts[0].to_i.positive?

      parts[0] = parts[0].rjust(4, "0")
      parts.join("-")
    end
  end
end
