module Admin
  # The Themes panel (event=skin): theme records plus import/export in the
  # Textpattern theme directory format.
  class SkinsController < BaseController
    self.event_name = "skin"
    self.default_step = :index

    step "skin_list", :index
    step "list", :index
    step "skin_edit", :edit
    step "skin_save", :save, post: true
    step "skin_import", :import, post: true
    step "skin_upload", :upload, post: true
    step "skin_export", :export, post: true
    step "skin_download", :download
    step "skin_multi_edit", :multi_edit, post: true

    private

    def index
      @page_title = gTxt("tab_skin")
      @skins = Skin.order(:title).to_a
      @sections = Section.pluck(:skin, :name).group_by(&:first).transform_values { |v| v.map(&:last) }
      @dev_sections = Section.where.not(dev_skin: "").pluck(:dev_skin, :name).group_by(&:first).transform_values { |v| v.map(&:last) }
      @counts = {
        "page" => Page.group(:skin).count, "form" => Form.group(:skin).count, "css" => Style.group(:skin).count
      }
      @on_disk = Txp::ThemeIO.available_on_disk
      render "admin/skins/index"
    end

    def edit
      @skin = params[:name].present? ? Skin.find_by(name: params[:name]) : Skin.new(version: "1.0", author: current_user.display_name)
      return redirect_with_message(admin_url(event: "skin"), gTxt("not_found"), :error) unless @skin

      @page_title = @skin.persisted? ? gTxt("edit_skin") : gTxt("create_skin")
      render "admin/skins/edit"
    end

    def save
      return require_privs!("skin.edit") unless has_privs?("skin.edit")

      old_name = params[:old_name].to_s
      name = Txp::Text.sanitize_for_theme(params[:name].presence || params[:title]).to_s
      return redirect_with_message(admin_url(event: "skin", step: "skin_edit", name: old_name.presence), gTxt("invalid_name"), :error) if name.empty?
      if name != old_name && Skin.exists?(name: name)
        return redirect_with_message(admin_url(event: "skin", step: "skin_edit", name: old_name.presence), gTxt("name_already_exists", "{name}" => name), :error)
      end

      attrs = { title: params[:title].presence || name, version: params[:version].to_s, description: params[:description].to_s,
                author: params[:author].to_s, author_uri: params[:author_uri].to_s, lastmod: Time.now.utc.change(usec: 0) }
      Skin.transaction do
        if old_name.present?
          if name != old_name
            Skin.where(name: old_name).update_all(name: name)
            [ Page, Form, Style ].each { |m| m.where(skin: old_name).update_all(skin: name) }
            Section.where(skin: old_name).update_all(skin: name)
            Section.where(dev_skin: old_name).update_all(dev_skin: name)
          end
          Skin.find_by(name: name).update!(attrs)
        else
          Skin.create!(attrs.merge(name: name))
          # New themes start with the essentials so sections using them render.
          Page.create!(name: "default", skin: name, user_html: "<!DOCTYPE html>\n<html lang=\"<txp:lang />\">\n<head>\n<meta charset=\"utf-8\">\n<title><txp:page_title /></title>\n<txp:css format=\"link\" />\n</head>\n<body>\n<txp:article />\n</body>\n</html>\n")
          Style.create!(name: "default", skin: name, css: "")
          Form::ESSENTIAL.each { |form, type| Form.create!(name: form, skin: name, type: type, Form: form == "default" ? "<h1><txp:permlink><txp:title /></txp:permlink></h1>\n<txp:body />\n" : "") }
        end
      end
      redirect_with_message(admin_url(event: "skin"), gTxt(old_name.present? ? "skin_updated" : "skin_created", "{list}" => name))
    end

    def import
      name = Txp::Text.sanitize_for_theme(params[:theme].to_s)
      dir = Txp::ThemeIO.skin_dir(@prefs).join(name)
      return redirect_with_message(admin_url(event: "skin"), gTxt("not_found"), :error) unless name.present? && dir.directory?

      Txp::ThemeIO.import(dir, name: name)
      redirect_with_message(admin_url(event: "skin"), gTxt("skin_imported", "{list}" => name))
    rescue StandardError => e
      redirect_with_message(admin_url(event: "skin"), "#{gTxt('skin_import_failed', '{list}' => name)} #{ERB::Util.h(e.message)}", :error)
    end

    def upload
      file = upload_param(:theme_zip)
      return redirect_with_message(admin_url(event: "skin"), gTxt("upload_err_no_file"), :error) unless file

      name = params[:name].present? ? Txp::Text.sanitize_for_theme(params[:name]) : nil
      skin = Txp::ThemeIO.import_zip(file.path, name: name)
      redirect_with_message(admin_url(event: "skin"), gTxt("skin_imported", "{list}" => skin.name))
    rescue StandardError => e
      redirect_with_message(admin_url(event: "skin"), "#{gTxt('skin_import_failed', '{list}' => name || file.original_filename)} #{ERB::Util.h(e.message)}", :error)
    end

    def export
      skin = Skin.find_by(name: params[:name].to_s)
      return redirect_with_message(admin_url(event: "skin"), gTxt("not_found"), :error) unless skin

      dir = Txp::ThemeIO.export(skin.name, Txp::ThemeIO.skin_dir(@prefs).join(skin.name))
      redirect_with_message(admin_url(event: "skin"), "#{gTxt('skin_exported', '{list}' => skin.name)} (#{ERB::Util.h(dir.relative_path_from(Rails.root))})")
    end

    def download
      skin = Skin.find_by(name: params[:name].to_s)
      return redirect_with_message(admin_url(event: "skin"), gTxt("not_found"), :error) unless skin

      send_data Txp::ThemeIO.zip(skin.name), filename: "#{skin.name}.zip", type: "application/zip"
    end

    def multi_edit
      skins = Skin.where(name: selected_ids).to_a
      case params[:edit_method]
      when "delete"
        in_use = skins.select(&:in_use?)
        deletable = skins - in_use
        Skin.transaction do
          deletable.each do |s|
            [ Page, Form, Style ].each { |m| m.where(skin: s.name).delete_all }
            s.destroy
          end
        end
        msg = gTxt("skins_deleted", "{list}" => deletable.map(&:name).join(", "))
        msg += " #{gTxt('skin_in_use', '{list}' => in_use.map(&:name).join(', '))}" if in_use.any?
        redirect_with_message(admin_url(event: "skin"), msg, in_use.any? ? :warning : :success)
      when "duplicate"
        done = skins.map do |s|
          new_name = "#{s.name}-copy"
          new_name = "#{s.name}-copy-#{SecureRandom.hex(2)}" if Skin.exists?(name: new_name)
          Txp::ThemeIO.duplicate(s.name, new_name)
          new_name
        end
        redirect_with_message(admin_url(event: "skin"), gTxt("skin_duplicated", "{name}" => done.join(", ")))
      when "export"
        skins.each { |s| Txp::ThemeIO.export(s.name, Txp::ThemeIO.skin_dir(@prefs).join(s.name)) }
        redirect_with_message(admin_url(event: "skin"), gTxt("skin_exported", "{list}" => skins.map(&:name).join(", ")))
      when "assign_sections"
        target = skins.first
        Section.where(name: Array(params[:sections])).update_all(skin: target.name) if target
        redirect_with_message(admin_url(event: "skin"), gTxt("items_updated", "{list}" => Array(params[:sections]).join(", ")))
      else
        redirect_to admin_url(event: "skin")
      end
    end
  end
end
