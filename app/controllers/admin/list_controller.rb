module Admin
  # The Articles panel (event=list).
  class ListController < BaseController
    self.event_name = "list"
    self.default_step = :index

    step "list", :index
    step "list_multi_edit", :multi_edit, post: true
    step "multi_edit", :multi_edit, post: true

    SORTS = {
      "id" => "textpattern.ID", "title" => "textpattern.Title", "posted" => "textpattern.Posted",
      "lastmod" => "textpattern.LastMod", "expires" => "textpattern.Expires", "section" => "textpattern.Section",
      "category1" => "textpattern.Category1", "category2" => "textpattern.Category2", "status" => "textpattern.Status",
      "author" => "textpattern.AuthorID", "comments" => "textpattern.comments_count"
    }.freeze

    SEARCH_METHODS = {
      "title_body_excerpt" => "title_body_excerpt", "id" => "id", "section" => "section", "keywords" => "keywords",
      "categories" => "categories", "status" => "status", "author" => "author", "article_image" => "article_image",
      "posted" => "posted", "lastmod" => "modified"
    }.freeze

    private

    def index
      @page_title = gTxt("tab_list")
      @state = list_state("article", SORTS.keys, "posted")
      scope = search(Article.all)
      scope = scope.order(*sort_terms(@state, SORTS[@state[:sort]], "textpattern.ID"))
      @articles = paginate(scope, @state).to_a
      @show_authors = User.count > 1 || Article.distinct.count(:AuthorID) > 1
      @section_titles = Section.pluck(:name, :title).to_h
      @category_titles = Category.of_type("article").pluck(:name, :title).to_h
      @comment_counts = Comment.where(parentid: @articles.map(&:ID)).group(:parentid).count
      render "admin/list/index"
    end

    def search(scope)
      crit = params[:crit].to_s.strip
      return scope if crit.empty?

      like = "%#{Article.sanitize_sql_like(crit)}%"
      case params[:search_method].presence || "title_body_excerpt"
      when "id" then scope.where(ID: Txp::Php.do_list(crit, [ ",", "-" ]).map(&:to_i))
      when "section" then scope.where("Section LIKE :q OR Section IN (SELECT name FROM txp_section WHERE title LIKE :q)", q: like)
      when "keywords" then scope.where("FIND_IN_SET(?, Keywords) > 0 OR Keywords LIKE ?", crit, like)
      when "categories" then scope.where("Category1 LIKE :q OR Category2 LIKE :q OR Category1 IN (SELECT name FROM txp_category WHERE type='article' AND title LIKE :q) OR Category2 IN (SELECT name FROM txp_category WHERE type='article' AND title LIKE :q)", q: like)
      when "status"
        num = Txp::STATUSES.find { |k, v| v == crit.downcase || gTxt(v).casecmp?(crit) || k.to_s == crit }&.first
        num ? scope.where(Status: num) : scope.none
      when "author" then scope.where("AuthorID LIKE :q OR AuthorID IN (SELECT name FROM txp_users WHERE RealName LIKE :q)", q: like)
      when "article_image" then scope.where("Image LIKE ?", like)
      when "posted" then scope.where("Posted LIKE ?", "#{crit}%")
      when "lastmod" then scope.where("LastMod LIKE ?", "#{crit}%")
      else scope.where("Title LIKE :q OR Body LIKE :q OR Excerpt LIKE :q", q: like)
      end
    end

    def multi_edit
      ids = selected_ids.map(&:to_i)
      articles = Article.where(ID: ids).to_a
      method = params[:edit_method].to_s
      allowed = articles.select { |a| editable?(a, method) }
      done = []

      case method
      when "delete"
        allowed.each { |a| a.destroy && done << a.ID }
        return redirect_with_message(admin_url(event: "list"), gTxt("articles_deleted", "{list}" => done.join(", ")))
      when "duplicate"
        allowed.each do |a|
          copy = Article.new(a.attributes.except("ID", "uid", "url_title", "comments_count", "feed_time"))
          copy.Title = gTxt("duplicate_of", "{title}" => a.Title)
          copy.Status = Txp::STATUS_DRAFT
          copy.AuthorID = current_user.name
          copy.Posted = Time.now.utc.change(usec: 0)
          copy.save && done << copy.ID
        end
        return redirect_with_message(admin_url(event: "list"), gTxt("articles_duplicated", "{list}" => done.join(", ")))
      when "changesection"
        value = params[:Section].to_s
        allowed.each { |a| a.update(Section: value) && done << a.ID } if Section.exists?(name: value)
      when "changecategory1", "changecategory2"
        column = method.end_with?("1") ? :Category1 : :Category2
        value = params[column].to_s
        allowed.each { |a| a.update(column => value) && done << a.ID }
      when "changestatus"
        value = params[:Status].to_i
        value = Txp::STATUS_PENDING if [ Txp::STATUS_LIVE, Txp::STATUS_STICKY ].include?(value) && !has_privs?("article.publish")
        allowed.each { |a| a.update(Status: value) && done << a.ID } if Txp::STATUSES.key?(value)
      when "changeauthor"
        value = params[:AuthorID].to_s
        allowed.each { |a| a.update(AuthorID: value) && done << a.ID } if has_privs?("article.edit") && User.exists?(name: value)
      when "changecomments"
        value = params[:Annotate].to_i
        allowed.each { |a| a.update(Annotate: value) && done << a.ID }
      end

      Pref.touch_lastmod! if done.any?
      redirect_with_message(admin_url(event: "list"), gTxt("articles_modified", "{list}" => done.join(", ")), done.any? ? :success : :warning)
    end

    def editable?(article, method)
      own = article.AuthorID == current_user.name
      if method == "delete"
        has_privs?("article.delete") || (own && has_privs?("article.delete.own"))
      else
        can_edit_article?(article)
      end
    end
  end
end
