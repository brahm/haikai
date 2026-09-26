module Admin
  # The Write panel (event=article): create, edit, publish and duplicate articles.
  class WriteController < BaseController
    self.event_name = "article"
    self.default_step = :edit

    step "create", :edit
    step "edit", :edit
    step "publish", :publish, post: true
    step "save", :save, post: true
    step "delete", :destroy, post: true

    # POST /textpattern/preview -- Textile/HTML preview for the Write panel.
    def textile_preview
      html = Txp::TextFilter.apply(params[:text].to_s, params[:filter].to_s.presence || Txp::USE_TEXTILE)
      render html: html.html_safe
    end

    private

    def edit
      @article = if params[:ID].present?
        Article.find_by(ID: params[:ID].to_i)
      else
        new_article
      end

      unless @article
        return redirect_with_message(admin_url(event: "list"), gTxt("article_not_found"), :error)
      end

      if @article.persisted? && !can_edit_article?(@article)
        return require_privs!("__never__")
      end

      render_form
    end

    def new_article
      Article.new(
        Status: (@prefs["default_publish_status"].presence || Txp::STATUS_LIVE).to_i,
        Section: @prefs["default_section"].presence || Section.where.not(name: "default").order(:name).pick(:name),
        textile_body: @prefs["use_textile"].presence || Txp::USE_TEXTILE,
        textile_excerpt: @prefs["use_textile"].presence || Txp::USE_TEXTILE,
        Annotate: @prefs["comments_on_default"].to_i,
        AnnotateInvite: @prefs["comments_default_invite"].to_s,
        AuthorID: current_user.name
      )
    end

    def render_form(status: :ok)
      @page_title = @article.persisted? ? @article.Title.presence || gTxt("untitled") : gTxt("write")
      @custom_fields = (1..10).filter_map { |i| [ i, @prefs["custom_#{i}_set"] ] if @prefs["custom_#{i}_set"].present? }
      @recent = Article.order(LastMod: :desc).limit(10).pluck(:ID, :Title)
      @override_forms = Form.where(type: Txp::Php.do_list(@prefs["override_form_types"].presence || "article"))
                            .where(skin: Section.where(name: @article.Section).pick(:skin) || Section.pick(:skin)).order(:name).pluck(:name)
      if @article.persisted?
        @prev_id = Article.where("Posted < ? OR (Posted = ? AND ID < ?)", @article.Posted, @article.Posted, @article.ID).order(Posted: :desc, ID: :desc).pick(:ID)
        @next_id = Article.where("Posted > ? OR (Posted = ? AND ID > ?)", @article.Posted, @article.Posted, @article.ID).order(Posted: :asc, ID: :asc).pick(:ID)
      end
      render "admin/write/edit", status: status
    end

    def publish
      @article = new_article
      assign_attributes(@article)
      @article.AuthorID = current_user.name
      persist(new_record: true)
    end

    def save
      @article = Article.find_by(ID: params[:ID].to_i)
      return redirect_with_message(admin_url(event: "list"), gTxt("article_not_found"), :error) unless @article
      return require_privs!("__never__") unless can_edit_article?(@article)

      if params[:copy].present?
        copy = Article.new(@article.attributes.except("ID", "uid", "url_title", "comments_count", "feed_time"))
        assign_attributes(copy)
        copy.Title = gTxt("duplicate_of", "{title}" => copy.Title) if copy.Title == @article.Title
        copy.Status = Txp::STATUS_DRAFT
        copy.AuthorID = current_user.name
        copy.Posted = Time.now.utc.change(usec: 0)
        @article = copy
        return persist(new_record: true, message: gTxt("article_duplicated"))
      end

      assign_attributes(@article)
      persist(new_record: false)
    end

    def destroy
      article = Article.find_by(ID: params[:ID].to_i)
      return redirect_with_message(admin_url(event: "list"), gTxt("article_not_found"), :error) unless article

      own = article.AuthorID == current_user.name
      unless has_privs?("article.delete") || (own && has_privs?("article.delete.own"))
        return require_privs!("__never__")
      end

      article.destroy
      redirect_with_message(admin_url(event: "list"), gTxt("article_deleted"))
    end

    def assign_attributes(article)
      p = params
      article.Title = p[:Title].to_s.strip
      article.Body = p[:Body].to_s
      article.Excerpt = p[:Excerpt].to_s
      if has_privs?("article.set_markup")
        article.textile_body = p[:textile_body].to_s if p.key?(:textile_body)
        article.textile_excerpt = p[:textile_excerpt].to_s if p.key?(:textile_excerpt)
      end

      status = p[:Status].to_i
      status = Txp::STATUS_LIVE unless Txp::STATUSES.key?(status)
      if [ Txp::STATUS_LIVE, Txp::STATUS_STICKY ].include?(status) && !has_privs?("article.publish")
        status = Txp::STATUS_PENDING
      end
      article.Status = status

      article.Section = p[:Section].to_s if Section.exists?(name: p[:Section].to_s)
      article.Category1 = p[:Category1].to_s
      article.Category2 = p[:Category2].to_s
      article.Annotate = p[:Annotate].to_i
      article.AnnotateInvite = p[:AnnotateInvite].to_s
      article.override_form = p[:override_form].to_s
      article.description = p[:description].to_s
      article.Keywords = Txp::Php.do_list_unique(p[:Keywords].to_s).join(",")
      article.Image = p[:Image].to_s.gsub(/\s+/, "")
      (1..10).each { |i| article["custom_#{i}"] = p["custom_#{i}"].to_s if p.key?("custom_#{i}") }

      url_title = p[:url_title].to_s.strip
      url_title = Txp::Text.strip_space(article.Title, @prefs, force: true) if url_title.empty?
      article.url_title = url_title.to_s

      if p[:reset_time].present? || (article.new_record? && p[:posted_date].blank?)
        article.Posted = Time.now.utc.change(usec: 0)
      elsif p[:posted_date].present?
        article.Posted = parse_local(p[:posted_date], p[:posted_time]) || article.Posted
      end

      article.Expires = p[:expires_date].present? ? parse_local(p[:expires_date], p[:expires_time].presence || "00:00:00") : nil
      article.LastModID = current_user.name
    end

    def parse_local(date, time)
      zone.parse("#{date} #{time.presence || '00:00:00'}")&.utc&.change(usec: 0)
    rescue ArgumentError
      nil
    end

    def persist(new_record:, message: nil)
      if @article.Title.blank? && @article.Body.blank?
        announce(gTxt("article_title_required"), :error)
        return render_form(status: :unprocessable_entity)
      end

      if @article.save
        Pref.touch_lastmod!
        dupe = Article.where(url_title: @article.url_title, Section: @article.Section).where.not(ID: @article.ID).exists?
        msg = message || status_message(@article.Status, new_record)
        type = :success
        if dupe
          msg = "#{msg} #{gTxt('url_title_is_duplicate', '{url_title}' => @article.url_title)}"
          type = :warning
        end
        redirect_with_message(admin_url(event: "article", step: "edit", ID: @article.ID), msg, type)
      else
        announce(@article.errors.full_messages.to_sentence, :error)
        render_form(status: :unprocessable_entity)
      end
    end

    def status_message(status, new_record)
      case status
      when Txp::STATUS_DRAFT then gTxt("article_saved_draft")
      when Txp::STATUS_HIDDEN then gTxt("article_saved_hidden")
      when Txp::STATUS_PENDING then gTxt("article_saved_pending")
      else new_record ? gTxt("article_posted") : gTxt("article_saved")
      end
    end
  end
end
