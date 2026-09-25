module Admin
  # The Images panel (event=image).
  class ImagesController < BaseController
    self.event_name = "image"
    self.default_step = :index

    step "image_list", :index
    step "list", :index
    step "image_edit", :edit
    step "image_insert", :insert, post: true
    step "image_replace", :replace, post: true
    step "image_save", :save, post: true
    step "thumbnail_create", :thumbnail_create, post: true
    step "thumbnail_insert", :thumbnail_insert, post: true
    step "thumbnail_delete", :thumbnail_delete, post: true
    step "image_multi_edit", :multi_edit, post: true

    SORTS = { "id" => "id", "name" => "name", "date" => "date", "category" => "category",
              "author" => "author", "thumbnail" => "thumbnail", "dimensions" => "w" }.freeze
    SEARCH_METHODS = { "name" => "name", "id" => "id", "alt" => "alt_text", "caption" => "caption",
                       "category" => "category", "author" => "author", "ext" => "type" }.freeze

    private

    def index
      @page_title = gTxt("tab_image")
      @state = list_state("image", SORTS.keys, "date")
      scope = search(Image.all).order(*sort_terms(@state, SORTS[@state[:sort]], "id"))
      @images = paginate(scope, @state).to_a
      render "admin/images/index"
    end

    def search(scope)
      crit = params[:crit].to_s.strip
      return scope if crit.empty?

      like = "%#{Image.sanitize_sql_like(crit)}%"
      case params[:search_method]
      when "id" then scope.where(id: Txp::Php.do_list(crit, [ ",", "-" ]).map(&:to_i))
      when "alt" then scope.where("alt LIKE ?", like)
      when "caption" then scope.where("caption LIKE ?", like)
      when "category" then scope.where("category LIKE ?", like)
      when "author" then scope.where("author LIKE ?", like)
      when "ext" then scope.where("ext LIKE ?", like)
      else scope.where("name LIKE ?", like)
      end
    end

    def edit
      @image = Image.find_by(id: params[:id])
      return redirect_with_message(admin_url(event: "image"), gTxt("image_not_found"), :error) unless @image
      return require_privs!("__never__") unless can_edit?(@image)

      @page_title = gTxt("edit_image")
      render "admin/images/edit"
    end

    def insert
      files = Array(params[:thefile]).select { |f| f.respond_to?(:original_filename) }
      return redirect_with_message(admin_url(event: "image"), gTxt("upload_err_no_file"), :error) if files.empty?

      names = []
      errors = []
      files.each do |upload|
        image = Image.new(name: upload.original_filename.to_s, category: params[:category].to_s, author: current_user.name, caption: "", alt: "")
        begin
          Image.transaction { image.store_upload(upload) }
          names << image.name
          image.create_thumbnail(width: 200, height: 200, crop: true) if params[:auto_thumb].present?
        rescue ArgumentError
          errors << upload.original_filename
        end
      end

      Pref.touch_lastmod! if names.any?
      if errors.any?
        redirect_with_message(admin_url(event: "image"), "#{gTxt('invalid_image_type')} (#{errors.join(', ')})", :error)
      elsif names.size == 1
        redirect_with_message(admin_url(event: "image", step: "image_edit", id: Image.order(:id).last.id), gTxt("image_uploaded", "{name}" => names.first))
      else
        redirect_with_message(admin_url(event: "image"), gTxt("image_uploaded", "{name}" => names.join(", ")))
      end
    end

    def replace
      image = find_editable or return
      upload = upload_param(:thefile)
      return redirect_with_message(admin_url(event: "image", step: "image_edit", id: image.id), gTxt("upload_err_no_file"), :error) unless upload

      old_path = image.path
      begin
        image.store_upload(upload)
        FileUtils.rm_f(old_path) if old_path.to_s != image.path.to_s
        redirect_with_message(admin_url(event: "image", step: "image_edit", id: image.id), gTxt("image_updated", "{name}" => image.name))
      rescue ArgumentError
        redirect_with_message(admin_url(event: "image", step: "image_edit", id: image.id), gTxt("invalid_image_type"), :error)
      end
    end

    def save
      image = find_editable or return
      image.update!(name: params[:name].to_s.strip.presence || image.name, alt: params[:alt].to_s,
        caption: params[:caption].to_s, category: params[:category].to_s)
      Pref.touch_lastmod!
      redirect_with_message(admin_url(event: "image"), gTxt("image_updated", "{name}" => image.name))
    end

    def thumbnail_create
      image = find_editable or return
      ok = image.create_thumbnail(width: params[:width].to_i, height: params[:height].to_i, crop: params[:crop].present?)
      redirect_with_message(admin_url(event: "image", step: "image_edit", id: image.id), gTxt(ok ? "thumbnail_saved" : "thumbnail_tools_missing", ok ? { "{id}" => image.id } : {}), ok ? :success : :error)
    end

    def thumbnail_insert
      image = find_editable or return
      upload = upload_param(:thefile)
      return redirect_with_message(admin_url(event: "image", step: "image_edit", id: image.id), gTxt("upload_err_no_file"), :error) unless upload

      image.store_thumbnail(upload)
      redirect_with_message(admin_url(event: "image", step: "image_edit", id: image.id), gTxt("thumbnail_saved", "{id}" => image.id))
    end

    def thumbnail_delete
      image = find_editable or return
      image.delete_thumbnail
      redirect_with_message(admin_url(event: "image", step: "image_edit", id: image.id), gTxt("thumbnail_deleted"))
    end

    def multi_edit
      images = Image.where(id: selected_ids.map(&:to_i)).to_a
      done = []
      case params[:edit_method]
      when "delete"
        images.each do |img|
          next unless has_privs?("image.delete") || (img.author == current_user.name && has_privs?("image.delete.own"))

          img.destroy && done << img.name
        end
        return redirect_with_message(admin_url(event: "image"), gTxt("images_deleted", "{list}" => done.join(", ")))
      when "changecategory"
        images.each { |img| can_edit?(img) && img.update(category: params[:category].to_s) && done << img.name }
      when "changeauthor"
        images.each { |img| img.update(author: params[:author].to_s) && done << img.name } if has_privs?("image.edit") && User.exists?(name: params[:author].to_s)
      when "create_thumbnails"
        images.each { |img| can_edit?(img) && img.create_thumbnail(width: 200, height: 200, crop: true) && done << img.name }
      end
      redirect_with_message(admin_url(event: "image"), gTxt("items_updated", "{list}" => done.join(", ")))
    end

    def can_edit?(image)
      has_privs?("image.edit") || (image.author == current_user.name && has_privs?("image.edit.own"))
    end

    def find_editable
      image = Image.find_by(id: params[:id])
      unless image
        redirect_with_message(admin_url(event: "image"), gTxt("image_not_found"), :error)
        return nil
      end
      unless can_edit?(image)
        require_privs!("__never__")
        return nil
      end
      image
    end
  end
end
