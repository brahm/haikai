module Txp
  module Tags
    # Comment tags and the public comment submission workflow (preview with
    # nonce/secret anti-spam scheme, moderation, remember-me cookies).
    module Comments
      # Port of Textpattern's comment_evaluation class.
      class Evaluator
        attr_reader :status, :message

        def initialize(visible_by_default)
          @status = { SPAM => [], MODERATE => [], VISIBLE => [], RELOAD => [] }
          @message = { SPAM => [], MODERATE => [], VISIBLE => [], RELOAD => [] }
          @status[visible_by_default ? VISIBLE : MODERATE] << 0.5
        end

        def add_estimate(type = SPAM, probability = 0.75, msg = "")
          @status[type] << probability.to_f.clamp(0, 1)
          @message[type] << msg if msg.to_s.strip != ""
        end

        def result
          avg = @status.transform_values { |v| v.sum / [ 1, v.length ].max }
          avg.max_by { |k, v| [ v, -@status.keys.index(k) ] }.first
        end

        def result_message
          @message[result]
        end
      end

      def comment_evaluator
        @comment_evaluator ||= Evaluator.new(!Php.truthy?(get_pref("comments_moderate")) || !logged_in_user.nil?)
      end

      def logged_in_user
        return @logged_in_user if defined?(@logged_in_user)

        @logged_in_user = @user ? { "name" => @user.name, "RealName" => @user.RealName, "email" => @user.email, "privs" => @user.privs } : nil
      end

      def check_comments_allowed(id)
        id = Php.intval(id)
        return false if !Php.truthy?(get_pref("use_comments")) || id.zero?

        if @thisarticle && Php.intval(@thisarticle["thisid"]) == id && @thisarticle.key?("annotate")
          annotate = @thisarticle["annotate"]
          posted = @thisarticle["posted"]
        else
          row = DB.row("SELECT Annotate, #{DB.timestamp('Posted', 'uPosted')} FROM textpattern WHERE ID = #{id}")
          return false unless row

          annotate = row["Annotate"]
          posted = row["uPosted"]
        end

        return false if Php.empty?(annotate)

        weeks = Php.intval(get_pref("comments_disabled_after"))
        return true if weeks.zero?

        # Textpattern stores this preference in days despite the "weeks" widget.
        (weeks * 86_400) > (Time.now.to_i - posted.to_i)
      end

      # getComment()
      def get_comment(obfuscated = false)
        c = psa(%w[parentid name email web message backpage remember]).transform_values { |v| Php.str(v) }
        candidates = params[:post].filter_map do |k, v|
          combined = "#{k}#{v}"
          combined if combined.match?(/\A[A-Fa-f0-9]{32}\z/)
        end
        c["nonce"] = ""
        c["secret"] = ""

        if candidates.any?
          row = DB.row("SELECT nonce, secret FROM txp_discuss_nonce WHERE nonce IN (#{DB.quote_list(candidates)})")
          if row
            c["nonce"] = row["nonce"]
            c["secret"] = row["secret"]
          end
        end

        c["message"] = Php.str(ps(Php.md5("message#{c['secret']}"))) if obfuscated || c["message"] == ""
        c["name"] = Php.strip_tags(CGI.unescapeHTML(c["name"])).strip
        c["web"] = clean_url(Php.strip_tags(CGI.unescapeHTML(c["web"]))).strip
        c["email"] = clean_url(Php.strip_tags(CGI.unescapeHTML(c["email"]))).strip
        c["message"] = CGI.unescapeHTML(c["message"].strip)[0, 65_535].strip
        c
      end

      def clean_url(url)
        Php.str(url).gsub(/"|'|(?:\s.*\z)/m, "")
      end

      def check_comment_required(comment)
        ev = comment_evaluator
        ev.add_estimate(RELOAD, 1, gTxt("comment_name_required")) if Php.truthy?(get_pref("comments_require_name")) && Php.empty?(comment["name"])
        ev.add_estimate(RELOAD, 1, gTxt("comment_email_required")) if Php.truthy?(get_pref("comments_require_email")) && Php.empty?(comment["email"])
        ev.add_estimate(RELOAD, 1, gTxt("comment_required")) if Php.empty?(comment["message"])
      end

      def check_nonce(nonce)
        return false if nonce.to_s.empty? || !nonce.match?(/\A[a-zA-Z0-9]*\z/)

        DB.execute("DELETE FROM txp_discuss_nonce WHERE issue_time < #{DB.unixtime(Time.now.to_i - 600)}")
        !DB.row("SELECT nonce FROM txp_discuss_nonce WHERE nonce = #{q nonce} AND used = 0").nil?
      end

      def set_comment_cookies(name, email, web)
        expires = 1.year.from_now
        set_cookie("txp_name", name, expires: expires)
        set_cookie("txp_email", email, expires: expires)
        set_cookie("txp_web", web, expires: expires)
        set_cookie("txp_last", Time.now.strftime("%H:%M %d/%m/%Y"), expires: expires)
        set_cookie("txp_remember", "1", expires: expires)
      end

      def destroy_comment_cookies
        %w[txp_name txp_email txp_web txp_last txp_remember].each { |n| set_cookie(n, "", expires: 1.hour.ago) }
      end

      # Handles a comment preview/submission before the page is rendered.
      def handle_comment_post
        return unless Php.truthy?(gps("parentid"))

        if Php.truthy?(ps("submit"))
          save_comment
        elsif Php.truthy?(ps("preview"))
          check_comment_required(get_comment)
        end
      end

      # saveComment()
      def save_comment
        comment = get_comment(true)
        ev = comment_evaluator
        parentid = Php.intval(comment["parentid"])
        txp_die(gTxt("comments_closed"), "403") unless check_comments_allowed(parentid)

        if comment["remember"] == "1" || (ps("checkbox_type") == "forget" && ps("forget") != "1")
          set_comment_cookies(comment["name"], comment["email"], comment["web"])
        else
          destroy_comment_cookies
        end

        message2db = TextFilter.comment(comment["message"], @prefs)
        isdup = DB.row("SELECT message FROM txp_discuss WHERE name = #{q comment['name']} AND message = #{q message2db}")
        check_comment_required(comment)
        ev.add_estimate(RELOAD, 1, gTxt("comment_duplicate")) if isdup

        if ev.result != RELOAD && check_nonce(comment["nonce"])
          visible = ev.result
          if visible != RELOAD
            rec = Comment.create!(
              parentid: parentid, name: comment["name"], email: comment["email"], web: comment["web"],
              message: message2db, visible: visible, posted: Time.now.utc
            )
            DB.execute("UPDATE txp_discuss_nonce SET used = 1 WHERE nonce = #{q comment['nonce']}")
            Pref.touch_lastmod! if Php.truthy?(get_pref("comment_means_site_updated"))
            Article.update_comments_count(parentid)
            Txp::Callbacks.fire("comment.saved", comment: rec, evaluator: ev)
            CommentMailer.notify(rec, ev.result).deliver_later if Php.truthy?(get_pref("comments_sendmail")) && !(get_pref("comments_sendmail") == "2" && ev.result == SPAM) && defined?(CommentMailer)

            backpage = Php.str(comment["backpage"])[0, Php.intval(get_pref("max_url_len", 1000))].sub(/[\n\r#].*\z/m, "")
            backpage = "#{hu.sub(%r{\A(https?://[^/]+)/.*\z}, '\1')}#{backpage}"
            backpage += "#{backpage.include?('?') ? '&' : '?'}commented=#{visible == VISIBLE ? '1' : '0'}"
            anchor = Php.truthy?(get_pref("comments_moderate")) && logged_in_user.nil? ? "#txpCommentInputForm" : format("#c%06d", rec.id)
            raise Redirect.new("#{backpage}#{anchor}", 302)
          end
        end

        # Force another preview.
        params[:post]["preview"] = RELOAD.to_s
      end

      # Tags --------------------------------------------------------------------

      def tag_comments_count(_atts = {}, _thing = nil)
        assert_article
        @thisarticle["comments_count"]
      end

      def tag_comments_invite(atts, _thing = nil)
        a = lAtts({ "class" => "comments_invite", "showcount" => true, "textonly" => false, "showalways" => false, "wraptag" => "" }, atts)
        assert_article
        invite = Php.empty?(@thisarticle["comments_invite"]) ? get_pref("comments_default_invite") : @thisarticle["comments_invite"]
        count = Php.intval(@thisarticle["comments_count"])
        out = ""

        if (Php.truthy?(@thisarticle["annotate"]) || count.positive?) && (Php.truthy?(a["showalways"]) || @is_article_list)
          invite = txpspecialchars(invite)
          ccount = count.positive? && Php.truthy?(a["showcount"]) ? " [#{count}]" : ""

          out = if Php.truthy?(a["textonly"])
            "#{invite}#{ccount}"
          elsif Php.empty?(get_pref("comments_mode"))
            do_tag(invite, "a", a["class"], %( href="#{permlinkurl(@thisarticle)}##{gTxt('comment')}" )) + ccount
          else
            klass = Php.truthy?(a["class"]) ? %( class="#{txpspecialchars(a['class'])}") : ""
            %(<a href="#{hu}?parentid=#{@thisarticle['thisid']}" onclick="window.open(this.href, 'popupwindow', 'width=500,height=500,scrollbars,resizable,status'); return false;"#{klass}>#{invite}</a> #{ccount})
          end
          out = do_tag(out, a["wraptag"], a["class"]) if Php.truthy?(a["wraptag"])
        end
        out
      end

      # $thiscommentsform (set by comments_form). Reading it before any
      # comments_form has run makes PHP warn once per offset read.
      def comments_form_atts(*keys)
        null_offset_warning(keys.size) if @thiscommentsform.nil?
        @thiscommentsform || {}
      end

      def tag_comments_form(atts, thing = nil)
        deprecated = %w[isize msgrows msgcols msgstyle previewlabel submitlabel rememberlabel forgetlabel]
        deprecated.each { |att| trigger_error(gTxt("deprecated_attribute", "{name}" => att)) if atts.key?(att) }

        a = lAtts({
          "class" => "comments_form", "form" => "comment_form", "isize" => "25", "msgcols" => "25", "msgrows" => "5",
          "msgstyle" => "", "show_preview" => !@has_comments_preview, "wraptag" => "",
          "previewlabel" => gTxt("preview"), "submitlabel" => gTxt("submit"),
          "rememberlabel" => gTxt("remember"), "forgetlabel" => gTxt("forget")
        }, atts)
        @thiscommentsform = a.slice(*deprecated)
        assert_article

        out = +""
        if !check_comments_allowed(@thisarticle["thisid"])
          out = graf(gTxt("comments_closed"), ' id="comments_closed"')
        elsif gps("commented") != ""
          msg = gTxt("comment_posted")
          msg += " #{gTxt('comment_moderated')}" if gps("commented") == "0"
          out = graf(msg, ' id="txpCommentInputForm"')
        else
          out << tag_comments_preview({}) if Php.truthy?(ps("preview")) && Php.truthy?(a["show_preview"])
          parentid = ps("parentid")
          backpage = ps("backpage")
          url = @pretext["request_uri"].presence || "/"
          form = thing.nil? ? parse_form(a["form"]) : parse(thing)
          out << %(<form id="txpCommentInputForm" method="post" action="#{txpspecialchars(url)}#cpreview">) +
            %(\n<div class="comments-wrapper">\n#{Php.str(form)}) +
            "\n#{h_input('parentid', Php.truthy?(parentid) ? parentid : @thisarticle['thisid'])}" +
            "\n#{h_input('backpage', Php.truthy?(ps('preview')) ? backpage : url)}" +
            "\n</div>\n</form>"
        end

        Php.empty?(a["wraptag"]) ? out : do_tag(out, a["wraptag"], a["class"])
      end

      def tag_comment_input(atts, _thing = nil, field = "name", clean = false)
        a = lAtts({ "class" => "", "size" => comments_form_atts("isize")["isize"], "aria_label" => "", "placeholder" => "" }, atts)
        val = pcs(field)
        val = clean_url(val) if clean
        required = Php.truthy?(get_pref("comments_require_#{field}"))
        warn = false

        if Php.truthy?(ps("preview"))
          val = get_comment[field]
          warn = required && Php.empty?(val)
        end

        klass = "comment_#{field}_input#{Php.truthy?(a['class']) ? " #{a['class']}" : ''}#{warn ? ' comments_error' : ''}"
        f_input(field == "email" ? "email" : "text", {
          "name" => field, "aria-label" => a["aria_label"],
          "autocomplete" => field == "web" ? "url" : field, "placeholder" => a["placeholder"],
          "required" => html5? && required
        }, val, klass, "", "", a["size"], "", field)
      end

      def tag_comment_message_input(atts, _thing = nil)
        form_atts = comments_form_atts("msgrows", "msgcols")
        a = lAtts({
          "class" => "", "rows" => form_atts["msgrows"], "cols" => form_atts["msgcols"],
          "aria_label" => "", "placeholder" => ""
        }, atts)
        style = comments_form_atts("msgstyle")["msgstyle"]
        n_message = "message"
        formnonce = ""
        message = ""
        warn = false

        if Php.truthy?(ps("preview"))
          message = get_comment["message"]
          split = rand(1..31)
          nonce = SecureRandom.hex(16)
          secret = SecureRandom.hex(16)
          DB.execute("INSERT INTO txp_discuss_nonce (issue_time, nonce, used, secret) VALUES (#{DB.now}, #{q nonce}, 0, #{q secret})")
          n_message = Php.md5("message#{secret}")
          formnonce = "\n#{h_input(nonce[0, split], nonce[split..])}"
          warn = message.strip.empty?
        end

        attr = join_atts({
          "cols" => Php.intval(a["cols"]), "rows" => Php.intval(a["rows"]), "required" => html5?,
          "style" => style, "aria-label" => a["aria_label"], "placeholder" => a["placeholder"]
        })
        klass = "txpCommentInputMessage#{Php.truthy?(a['class']) ? " #{txpspecialchars(a['class'])}" : ''}#{warn ? ' comments_error' : ''}"
        %(<textarea class="#{klass}" id="message" name="#{n_message}"#{attr}>#{txpspecialchars(message.strip[0, 65_535])}</textarea>#{formnonce})
      end

      def tag_comment_remember(atts, _thing = nil)
        form_atts = comments_form_atts("rememberlabel", "forgetlabel")
        a = lAtts({ "class" => "", "rememberlabel" => form_atts["rememberlabel"], "forgetlabel" => form_atts["forgetlabel"] }, atts)
        klass = Php.truthy?(a["class"]) ? %( class="#{txpspecialchars(a['class'])}") : ""
        checkbox_type = ps("checkbox_type")
        remember = ps("remember")
        forget = ps("forget")

        unless Php.truthy?(ps("preview"))
          cookie = cs("txp_remember")
          checkbox_type = Php.empty?(cookie) ? "remember" : "forget"
          destroy_comment_cookies if forget == "1" || cookie == "0"
        end

        box = if checkbox_type == "forget"
          "#{checkbox('forget', 1, forget, '', 'forget')} #{tag(txpspecialchars(a['forgetlabel']), 'label', %( for="forget"#{klass}))}"
        else
          "#{checkbox('remember', 1, remember, '', 'remember')} #{tag(txpspecialchars(a['rememberlabel']), 'label', %( for="remember"#{klass}))}"
        end
        "#{box} #{h_input('checkbox_type', checkbox_type)}"
      end

      def tag_comment_preview(atts, _thing = nil)
        a = lAtts({ "class" => "", "label" => comments_form_atts("previewlabel")["previewlabel"] }, atts)
        klass = Php.truthy?(a["class"]) ? " #{txpspecialchars(a['class'])}" : ""
        f_input("submit", "preview", a["label"], "button#{klass}", "", "", "", "", "txpCommentPreview", false)
      end

      def tag_comment_submit(atts, _thing = nil)
        a = lAtts({ "class" => "", "label" => comments_form_atts("submitlabel")["submitlabel"] }, atts)
        klass = Php.truthy?(a["class"]) ? " #{txpspecialchars(a['class'])}" : ""
        # If all fields check out, the submit button is active/clickable.
        if Php.truthy?(ps("preview"))
          f_input("submit", "submit", a["label"], "button#{klass}", "", "", "", "", "txpCommentSubmit", false)
        else
          f_input("submit", "submit", a["label"], "button disabled#{klass}", "", "", "", "", "txpCommentSubmit", true)
        end
      end

      def tag_comments_error(atts, _thing = nil)
        a = lAtts({ "break" => "br", "class" => "comments_error", "wraptag" => "div" }, atts)
        errors = comment_evaluator.result_message
        errors.any? ? do_wrap(errors, a["wraptag"], a["break"], a["class"]) : nil
      end

      def tag_if_comments_error(_atts, thing = nil)
        x = comment_evaluator.result_message.any? && [ RELOAD ].include?(comment_evaluator.result)
        thing.nil? ? x : parse(thing, x)
      end

      def comment_row_data(row)
        r = row.dup
        r["time"] = r.delete("utime") || DB.to_unix(r["posted"])
        r["discussid"] = zerofill_discussid(r["discussid"])
        r
      end

      def tag_comments(atts, thing = nil)
        are_ol = Php.truthy?(get_pref("comments_are_ol"))
        a = lAtts({
          "form" => "comments", "wraptag" => are_ol ? "ol" : "", "break" => are_ol ? "li" : "div",
          "class" => "comments", "limit" => 0, "offset" => 0, "sort" => "posted ASC"
        }, atts)
        assert_article
        return "" if Php.empty?(@thisarticle["comments_count"])

        limit = Php.truthy?(a["limit"]) ? " LIMIT #{Php.intval(a['offset'])}, #{Php.intval(a['limit'])}" : ""
        rows = DB.rows("SELECT *, #{DB.timestamp('posted', 'utime')} FROM txp_discuss WHERE parentid = #{Php.intval(@thisarticle['thisid'])} AND visible = #{VISIBLE} ORDER BY #{sanitize_for_sort(a['sort'])}#{limit}")
        return "" if rows.empty?

        list = rows.map do |row|
          @thiscomment = comment_row_data(row)
          out = "#{thing.nil? ? parse_form(a['form']) : parse(thing)}\n"
          @thiscomment = nil
          out
        end
        do_wrap(list, a["wraptag"], a["break"], a["class"])
      end

      def tag_comments_preview(atts, thing = nil)
        return "" unless Php.truthy?(ps("preview"))

        a = lAtts({ "form" => "comments", "wraptag" => "", "class" => "comments_preview" }, atts)
        assert_article
        preview = psa(%w[name email web message parentid remember]).transform_values { |v| Php.str(v) }
        preview["time"] = Time.now.to_i
        preview["discussid"] = 0
        preview["name"] = Php.strip_tags(preview["name"])
        preview["email"] = clean_url(preview["email"])
        preview["message"] = get_comment["message"] if preview["message"] == ""
        preview["message"] = TextFilter.comment(preview["message"].strip[0, 65_535], @prefs)
        preview["web"] = clean_url(preview["web"])
        @thiscomment = preview
        out = "#{thing.nil? ? parse_form(a['form']) : parse(thing)}\n"
        @thiscomment = nil
        @has_comments_preview = true
        do_tag(out, a["wraptag"], a["class"])
      end

      def tag_if_comments_preview(_atts, thing = nil)
        x = Php.truthy?(ps("preview")) && check_comments_allowed(gps("parentid"))
        thing.nil? ? x : parse(thing, x)
      end

      def tag_comment_permlink(atts, thing = nil)
        a = lAtts({ "anchor" => @thiscomment.nil? || Php.empty?(@thiscomment["has_anchor_tag"]) }, atts)
        assert_article
        assert_comment
        id = discussid(@thiscomment)
        link = "#{Php.str(permlinkurl(@thisarticle))}#c#{id}"
        name = Php.truthy?(a["anchor"]) ? %( id="c#{id}") : ""
        tag(Php.str(parse(thing)), "a", %( href="#{link}"#{name}))
      end

      # txp_discuss.discussid is INT(6) ZEROFILL in Textpattern's schema, so
      # stored comments read back zero-padded (a preview's id is a plain 0).
      def zerofill_discussid(id)
        format("%06d", id.to_i)
      end

      def discussid(comment)
        Php.str(comment && comment["discussid"])
      end

      def tag_comment_id(_atts = {}, _thing = nil)
        assert_comment
        discussid(@thiscomment)
      end

      def tag_comment_name(atts, _thing = nil)
        a = lAtts({ "link" => 1 }, atts)
        assert_comment
        name = txpspecialchars(@thiscomment["name"])

        if Php.truthy?(a["link"])
          web = tag_comment_web
          nofollow = Php.empty?(get_pref("comment_nofollow")) ? "" : ' rel="nofollow"'
          return href(name, web, nofollow) unless Php.empty?(web)

          email = Php.str(@thiscomment["email"])
          return href(name, entity_obfuscate("mailto:#{email}"), nofollow) if email != "" && Php.empty?(get_pref("never_display_email"))
        end
        name
      end

      def tag_comment_email(_atts = {}, _thing = nil)
        assert_comment
        txpspecialchars(@thiscomment["email"])
      end

      def tag_comment_web(_atts = {}, _thing = nil)
        assert_comment
        web = Php.str(@thiscomment["web"])
        return "" unless web.match?(/\A\S/)

        web = "http://#{web}" unless web.match?(%r{\Ahttps?://|\A#|\A/[^/]})
        @thiscomment["web"] = web
        txpspecialchars(web)
      end

      def tag_comment_message(_atts = {}, _thing = nil)
        assert_comment
        Php.str(@thiscomment["message"])
      end

      def tag_comment_anchor(_atts = {}, _thing = nil)
        assert_comment
        @thiscomment["has_anchor_tag"] = 1
        %(<a id="c#{discussid(@thiscomment)}"></a>)
      end

      def tag_if_comments(_atts, thing = nil)
        assert_article
        x = Php.intval(@thisarticle["comments_count"]).positive?
        thing.nil? ? x : parse(thing, x)
      end

      def tag_if_comments_allowed(_atts, thing = nil)
        assert_article
        x = check_comments_allowed(@thisarticle["thisid"])
        thing.nil? ? x : parse(thing, x)
      end

      def tag_if_comments_disallowed(_atts, thing = nil)
        assert_article
        x = !check_comments_allowed(@thisarticle["thisid"])
        thing.nil? ? x : parse(thing, x)
      end

      def tag_recent_comments(atts, thing = nil)
        a = lAtts({ "break" => "br", "class" => "recent_comments", "form" => "", "limit" => 10, "offset" => 0, "sort" => "posted DESC", "wraptag" => "" }, atts)
        sort = sanitize_for_sort(a["sort"]).gsub(/\bposted\b/, "d.posted")
        expired = Php.truthy?(get_pref("publish_expired_articles")) ? "" : " AND (#{DB.now} <= t.Expires OR t.Expires IS NULL) "
        limit = Php.truthy?(a["limit"]) ? Php.intval(a["limit"]) : (1 << 62)
        rows = DB.rows("SELECT d.name, d.email, d.web, d.message, d.discussid, #{DB.timestamp('d.posted', 'time')}, #{DB.timestamp('t.Posted', 'posted')}, " \
                       "t.ID AS thisid, t.Title AS title, t.Section AS section, t.Category1, t.Category2, t.url_title " \
                       "FROM txp_discuss AS d INNER JOIN textpattern AS t ON d.parentid = t.ID " \
                       "WHERE t.Status >= #{STATUS_LIVE}#{expired} AND d.visible = #{VISIBLE} ORDER BY #{sort} LIMIT #{Php.intval(a['offset'])}, #{limit}")
        return "" if rows.empty?

        old = @thisarticle
        out = rows.map do |c|
          if a["form"] == "" && thing.nil?
            href("#{txpspecialchars(c['name'])} (#{escape_title(c['title'])})", "#{permlinkurl(c)}#c#{zerofill_discussid(c['discussid'])}")
          else
            @thiscomment = c.slice("name", "email", "web", "message", "time").merge("discussid" => zerofill_discussid(c["discussid"]))
            @thisarticle = (@thisarticle || {}).merge(c.slice("thisid", "posted", "title", "section", "url_title"))
            thing.nil? && a["form"] != "" ? parse_form(a["form"]) : parse(thing)
          end
        end
        @thiscomment = nil
        @thisarticle = old
        do_wrap(out, a["wraptag"], a["break"], a["class"])
      end
    end
  end
end
