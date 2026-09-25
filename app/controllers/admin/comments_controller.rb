module Admin
  # The Comments panel (event=discuss).
  class CommentsController < BaseController
    self.event_name = "discuss"
    self.default_step = :index

    step "discuss_list", :index
    step "list", :index
    step "discuss_edit", :edit
    step "discuss_save", :save, post: true
    step "discuss_multi_edit", :multi_edit, post: true

    SORTS = { "id" => "txp_discuss.discussid", "date" => "txp_discuss.posted", "name" => "txp_discuss.name",
              "email" => "txp_discuss.email", "website" => "txp_discuss.web", "message" => "txp_discuss.message",
              "status" => "txp_discuss.visible", "parent" => "txp_discuss.parentid" }.freeze
    SEARCH_METHODS = { "message" => "message", "id" => "id", "parent" => "parent", "name" => "name",
                       "email" => "email", "website" => "website" }.freeze

    private

    def index
      @page_title = gTxt("tab_comments")
      @state = list_state("discuss", SORTS.keys, "date")
      scope = search(Comment.all)
      @filter = params[:show].presence || "all"
      scope = case @filter
      when "unmoderated" then scope.where(visible: Txp::MODERATE)
      when "spam" then scope.where(visible: Txp::SPAM)
      when "visible" then scope.where(visible: Txp::VISIBLE)
      else scope
      end
      scope = scope.order(*sort_terms(@state, SORTS[@state[:sort]], "txp_discuss.discussid"))
      @comments = paginate(scope, @state).to_a
      @articles = Article.where(ID: @comments.map(&:parentid).uniq).pluck(:ID, :Title).to_h
      @counts = { "unmoderated" => Comment.moderated.count, "spam" => Comment.spam.count, "visible" => Comment.visible.count }
      render "admin/comments/index"
    end

    def search(scope)
      crit = params[:crit].to_s.strip
      return scope if crit.empty?

      like = "%#{Comment.sanitize_sql_like(crit)}%"
      case params[:search_method]
      when "id" then scope.where(discussid: Txp::Php.do_list(crit, [ ",", "-" ]).map(&:to_i))
      when "parent" then scope.where(parentid: Txp::Php.do_list(crit, [ ",", "-" ]).map(&:to_i))
      when "name" then scope.where("name LIKE ?", like)
      when "email" then scope.where("email LIKE ?", like)
      when "website" then scope.where("web LIKE ?", like)
      else scope.where("message LIKE ?", like)
      end
    end

    def edit
      @comment = Comment.find_by(discussid: params[:discussid])
      return redirect_with_message(admin_url(event: "discuss"), gTxt("not_found"), :error) unless @comment

      @page_title = gTxt("edit_comment")
      @article = Article.find_by(ID: @comment.parentid)
      render "admin/comments/edit"
    end

    def save
      @comment = Comment.find_by(discussid: params[:discussid])
      return redirect_with_message(admin_url(event: "discuss"), gTxt("not_found"), :error) unless @comment

      @comment.update!(name: params[:name].to_s, email: params[:email].to_s, web: params[:web].to_s,
        message: params[:message].to_s, visible: params[:visible].to_i.clamp(-1, 1))
      Pref.touch_lastmod!
      redirect_with_message(admin_url(event: "discuss"), gTxt("comment_updated", "{id}" => @comment.discussid))
    end

    def multi_edit
      comments = Comment.where(discussid: selected_ids.map(&:to_i)).to_a
      ids = comments.map(&:discussid)
      case params[:edit_method]
      when "delete"
        comments.each(&:destroy)
        return redirect_with_message(admin_url(event: "discuss"), gTxt("comments_deleted", "{list}" => ids.join(", ")))
      when "visible" then comments.each { |c| c.update(visible: Txp::VISIBLE) }
      when "unmoderated" then comments.each { |c| c.update(visible: Txp::MODERATE) }
      when "spam" then comments.each { |c| c.update(visible: Txp::SPAM) }
      end
      Pref.touch_lastmod!
      redirect_with_message(admin_url(event: "discuss", show: params[:show]), gTxt("comments_marked", "{list}" => ids.join(", ")))
    end
  end
end
