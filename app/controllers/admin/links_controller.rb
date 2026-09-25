module Admin
  # The Links panel (event=link).
  class LinksController < BaseController
    self.event_name = "link"
    self.default_step = :index

    step "link_list", :index
    step "list", :index
    step "link_edit", :edit
    step "link_save", :save, post: true
    step "link_multi_edit", :multi_edit, post: true

    SORTS = { "id" => "id", "name" => "linkname", "description" => "description", "url" => "url",
              "category" => "category", "date" => "date", "author" => "author" }.freeze
    SEARCH_METHODS = { "name" => "link_name", "id" => "id", "url" => "url", "description" => "description",
                       "category" => "category", "author" => "author" }.freeze

    private

    def index
      @page_title = gTxt("tab_link")
      @state = list_state("link", SORTS.keys, "name", "asc")
      scope = search(Link.all).order(Arel.sql("#{SORTS[@state[:sort]]} #{@state[:dir]}, id #{@state[:dir]}"))
      @links = paginate(scope, @state).to_a
      @link = Link.new(category: params[:category].to_s) if @link.nil?
      render "admin/links/index"
    end

    def search(scope)
      crit = params[:crit].to_s.strip
      return scope if crit.empty?

      like = "%#{Link.sanitize_sql_like(crit)}%"
      case params[:search_method]
      when "id" then scope.where(id: Txp::Php.do_list(crit, [ ",", "-" ]).map(&:to_i))
      when "url" then scope.where("url LIKE ?", like)
      when "description" then scope.where("description LIKE ?", like)
      when "category" then scope.where("category LIKE ?", like)
      when "author" then scope.where("author LIKE ?", like)
      else scope.where("linkname LIKE ?", like)
      end
    end

    def edit
      @link = params[:id].present? ? Link.find_by(id: params[:id]) : Link.new
      return redirect_with_message(admin_url(event: "link"), gTxt("not_found"), :error) unless @link

      @page_title = @link.persisted? ? gTxt("edit_link") : gTxt("create_link")
      render "admin/links/edit"
    end

    def save
      @link = params[:id].present? ? Link.find_by(id: params[:id]) : Link.new(author: current_user.name)
      return redirect_with_message(admin_url(event: "link"), gTxt("not_found"), :error) unless @link

      unless can_edit_link?(@link)
        return require_privs!("__never__")
      end

      new_record = @link.new_record?
      @link.assign_attributes(linkname: params[:linkname].to_s.strip, url: params[:url].to_s.strip,
        linksort: params[:linksort].to_s.strip, description: params[:description].to_s,
        category: params[:category].to_s)
      if @link.linkname.blank? || @link.url.blank?
        announce(gTxt("link_empty"), :error)
        @page_title = gTxt("create_link")
        return render("admin/links/edit", status: :unprocessable_entity)
      end

      @link.save!
      Pref.touch_lastmod!
      redirect_with_message(admin_url(event: "link"), gTxt(new_record ? "link_created" : "link_saved", "{name}" => @link.linkname))
    end

    def can_edit_link?(link)
      link.new_record? || has_privs?("link.edit") || (link.author == current_user.name && has_privs?("link.edit.own"))
    end

    def multi_edit
      links = Link.where(id: selected_ids.map(&:to_i)).to_a
      done = []
      case params[:edit_method]
      when "delete"
        links.each do |l|
          next unless has_privs?("link.delete") || (l.author == current_user.name && has_privs?("link.delete.own"))

          l.destroy && done << l.linkname
        end
        return redirect_with_message(admin_url(event: "link"), gTxt("links_deleted", "{list}" => done.join(", ")))
      when "changecategory"
        links.each { |l| can_edit_link?(l) && l.update(category: params[:category].to_s) && done << l.linkname }
      when "changeauthor"
        links.each { |l| l.update(author: params[:author].to_s) && done << l.linkname } if has_privs?("link.edit") && User.exists?(name: params[:author].to_s)
      end
      redirect_with_message(admin_url(event: "link"), gTxt("items_updated", "{list}" => done.join(", ")))
    end
  end
end
