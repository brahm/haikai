module Admin
  # The Files panel (event=file).
  class FilesController < BaseController
    self.event_name = "file"
    self.default_step = :index

    step "file_list", :index
    step "list", :index
    step "file_edit", :edit
    step "file_insert", :insert, post: true
    step "file_replace", :replace, post: true
    step "file_save", :save, post: true
    step "file_create", :create_from_disk, post: true
    step "file_multi_edit", :multi_edit, post: true

    SORTS = { "id" => "id", "filename" => "filename", "title" => "title", "description" => "description",
              "category" => "category", "date" => "created", "downloads" => "downloads", "size" => "size",
              "status" => "status", "author" => "author" }.freeze
    SEARCH_METHODS = { "filename" => "filename", "id" => "id", "title" => "title", "description" => "description",
                       "category" => "category", "author" => "author" }.freeze
    FILE_STATUSES = { Txp::STATUS_HIDDEN => "hidden", Txp::STATUS_PENDING => "pending", Txp::STATUS_LIVE => "live" }.freeze

    private

    def index
      @page_title = gTxt("tab_file")
      @state = list_state("file", SORTS.keys, "filename", "asc")
      scope = search(TxpFile.all).order(*sort_terms(@state, SORTS[@state[:sort]], "id"))
      @files = paginate(scope, @state).to_a
      known = TxpFile.pluck(:filename).to_set
      @existing = Dir.children(TxpFile.base_path).select { |f| File.file?(TxpFile.base_path.join(f)) && !known.include?(f) && !f.start_with?(".") }.sort
      render "admin/files/index"
    end

    def search(scope)
      crit = params[:crit].to_s.strip
      return scope if crit.empty?

      like = "%#{TxpFile.sanitize_sql_like(crit)}%"
      case params[:search_method]
      when "id" then scope.where(id: Txp::Php.do_list(crit, [ ",", "-" ]).map(&:to_i))
      when "title" then scope.where("title LIKE ?", like)
      when "description" then scope.where("description LIKE ?", like)
      when "category" then scope.where("category LIKE ?", like)
      when "author" then scope.where("author LIKE ?", like)
      else scope.where("filename LIKE ?", like)
      end
    end

    def edit
      @file = TxpFile.find_by(id: params[:id])
      return redirect_with_message(admin_url(event: "file"), gTxt("file_not_found", "{list}" => params[:id].to_s), :error) unless @file

      @page_title = gTxt("edit_file")
      render "admin/files/edit"
    end

    def insert
      upload = upload_param(:thefile)
      return redirect_with_message(admin_url(event: "file"), gTxt("upload_err_no_file"), :error) unless upload

      name = Txp::Text.sanitize_for_file(upload.original_filename.to_s)
      return redirect_with_message(admin_url(event: "file"), gTxt("file_already_exists", "{name}" => name), :error) if TxpFile.exists?(filename: name)

      max = @prefs["file_max_upload_size"].to_i
      return redirect_with_message(admin_url(event: "file"), gTxt("upload_err_no_file"), :error) if max.positive? && upload.size > max

      file = TxpFile.new(title: params[:title].presence, category: params[:category].to_s, author: current_user.name,
        status: Txp::STATUS_LIVE, description: "", permissions: "0")
      file.store_upload(upload)
      redirect_with_message(admin_url(event: "file", step: "file_edit", id: file.id), gTxt("file_uploaded", "{name}" => file.filename))
    end

    def replace
      file = TxpFile.find_by(id: params[:id])
      upload = upload_param(:thefile)
      return redirect_with_message(admin_url(event: "file"), gTxt(file ? "upload_err_no_file" : "file_not_found", file ? {} : { "{list}" => params[:id].to_s }), :error) unless file && upload

      FileUtils.cp(upload.path, file.path)
      file.update!(size: File.size(file.path), modified: Time.now.utc.change(usec: 0))
      redirect_with_message(admin_url(event: "file", step: "file_edit", id: file.id), gTxt("file_updated", "{name}" => file.filename))
    end

    def save
      file = TxpFile.find_by(id: params[:id])
      return redirect_with_message(admin_url(event: "file"), gTxt("file_not_found", "{list}" => params[:id].to_s), :error) unless file

      new_name = Txp::Text.sanitize_for_file(params[:filename].to_s)
      if new_name.present? && new_name != file.filename
        if TxpFile.exists?(filename: new_name)
          return redirect_with_message(admin_url(event: "file", step: "file_edit", id: file.id), gTxt("file_already_exists", "{name}" => new_name), :error)
        end
        old_path = file.path
        file.filename = new_name
        FileUtils.mv(old_path, file.path) if File.exist?(old_path)
      end

      status = params[:status].to_i
      file.update!(title: params[:title].to_s, description: params[:description].to_s, category: params[:category].to_s,
        status: FILE_STATUSES.key?(status) ? status : file.status, modified: Time.now.utc.change(usec: 0))
      Pref.touch_lastmod!
      redirect_with_message(admin_url(event: "file"), gTxt("file_updated", "{name}" => file.filename))
    end

    def create_from_disk
      name = Txp::Text.sanitize_for_file(params[:filename].to_s)
      path = TxpFile.base_path.join(name)
      return redirect_with_message(admin_url(event: "file"), gTxt("file_not_found", "{list}" => name), :error) unless name.present? && File.file?(path)

      file = TxpFile.create!(filename: name, author: current_user.name, status: Txp::STATUS_LIVE, size: File.size(path), description: "")
      redirect_with_message(admin_url(event: "file", step: "file_edit", id: file.id), gTxt("file_uploaded", "{name}" => name))
    end

    def multi_edit
      files = TxpFile.where(id: selected_ids.map(&:to_i)).to_a
      done = []
      case params[:edit_method]
      when "delete"
        files.each do |f|
          next unless has_privs?("file.delete") || (f.author == current_user.name && has_privs?("file.delete.own"))

          f.destroy && done << f.filename
        end
        return redirect_with_message(admin_url(event: "file"), gTxt("files_deleted", "{list}" => done.join(", ")))
      when "changecategory" then files.each { |f| f.update(category: params[:category].to_s) && done << f.filename }
      when "changestatus"
        status = params[:status].to_i
        files.each { |f| f.update(status: status) && done << f.filename } if FILE_STATUSES.key?(status)
      when "changeauthor"
        files.each { |f| f.update(author: params[:author].to_s) && done << f.filename } if User.exists?(name: params[:author].to_s)
      end
      redirect_with_message(admin_url(event: "file"), gTxt("items_updated", "{list}" => done.join(", ")))
    end
  end
end
