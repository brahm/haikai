module Admin
  # The Languages panel (event=lang).
  class LanguagesController < BaseController
    self.event_name = "lang"
    self.default_step = :index

    step "list_languages", :index
    step "list", :index
    step "save_language", :save, post: true
    step "save_language_ui", :save_ui, post: true
    step "import_textpack", :import, post: true
    step "remove_customizations", :remove, post: true

    private

    def index
      @page_title = gTxt("tab_languages")
      @languages = Txp::Textpack.names
      @file_counts = @languages.keys.index_with { |code| Txp::Textpack.parse_ini(Txp::Textpack.read_file(code)).values.sum(&:size) }
      @db_counts = LangString.group(:lang).count
      render "admin/languages/index"
    end

    def save
      return require_privs!("lang.edit") unless has_privs?("lang.edit")

      code = params[:language].to_s
      Pref.set("language", code, type: Txp::PREF_HIDDEN) if Txp::Textpack.names.key?(code)
      Txp::Textpack.reset!
      redirect_with_message(admin_url(event: "lang"), gTxt("preferences_saved"))
    end

    def save_ui
      code = params[:language_ui].to_s
      if Txp::Textpack.names.key?(code)
        Pref.set("language_ui", code, event: "admin", type: Txp::PREF_HIDDEN, user: current_user.name)
      end
      redirect_with_message(admin_url(event: "lang"), Txp::Textpack.txt(code, "preferences_saved"))
    end

    def import
      return require_privs!("lang.edit") unless has_privs?("lang.edit")

      content = if (file = upload_param(:textpack_file))
        File.read(file.path, encoding: "UTF-8")
      else
        params[:textpack].to_s
      end
      return redirect_with_message(admin_url(event: "lang"), gTxt("upload_err_no_file"), :error) if content.strip.empty?

      lang = params[:lang_code].presence
      if lang.nil? && (file = upload_param(:textpack_file))
        base = File.basename(file.original_filename.to_s, ".*")
        lang = base if base.match?(/\A[a-z]{2,3}(-[a-z0-9]+)?\z/i)
      end
      count = Txp::Textpack.import(content, lang: lang)
      redirect_with_message(admin_url(event: "lang"), gTxt("textpack_imported", "{count}" => count))
    end

    def remove
      return require_privs!("lang.edit") unless has_privs?("lang.edit")

      LangString.where(lang: params[:code].to_s, owner: "").delete_all
      Txp::Textpack.reset!
      redirect_with_message(admin_url(event: "lang"), gTxt("customizations_removed"))
    end
  end
end
