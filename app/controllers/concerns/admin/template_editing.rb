module Admin
  # Shared behaviour of the Pages, Forms and Styles panels: templates are
  # edited per theme, like Textpattern's skin-aware template editors.
  module TemplateEditing
    extend ActiveSupport::Concern

    included do
      class_attribute :template_model
      class_attribute :content_column
      class_attribute :label_prefix
    end

    private

    def editing_skin
      skin = params[:skin].presence || @prefs["#{event_name}_skin_editing"].presence || Section.where(name: "default").pick(:skin)
      skin = Skin.order(:name).pick(:name) unless Skin.exists?(name: skin)
      if params[:skin].present? && params[:skin] != @prefs["#{event_name}_skin_editing"] && Skin.exists?(name: params[:skin])
        set_user_pref("#{event_name}_skin_editing", params[:skin])
      end
      skin
    end

    def index
      @skin = editing_skin
      @templates = template_model.where(skin: @skin).order(:name).to_a
      name = params[:name].presence
      @template = if params[:new].present?
        template_model.new(skin: @skin)
      elsif name
        template_model.find_by(name: name, skin: @skin)
      end
      @template ||= @templates.find { |t| t.name == "default" } || @templates.first || template_model.new(skin: @skin)
      @used_by = used_by_map
      @label_prefix = label_prefix
      @content_column = content_column
      @page_title = @template.persisted? ? "#{gTxt("edit_#{label_prefix}")}: #{@template.name}" : gTxt("create_#{label_prefix}")
      render "admin/templates/edit"
    end

    def save
      @skin = params[:skin].to_s
      return redirect_with_message(admin_url(event: event_name), gTxt("not_found"), :error) unless Skin.exists?(name: @skin)

      name = Txp::Text.sanitize_for_page(params[:newname].presence || params[:name].to_s)
      old_name = params[:name].to_s
      content = params[:code].to_s.gsub("\r\n", "\n")
      copy = params[:copy].present?

      return redirect_with_message(admin_url(event: event_name, skin: @skin), gTxt("invalid_name"), :error) if name.empty? || name.include?("/")

      record = old_name.present? && !copy ? template_model.find_by(name: old_name, skin: @skin) : nil
      if (record.nil? || name != old_name) && template_model.exists?(name: name, skin: @skin)
        return redirect_with_message(admin_url(event: event_name, skin: @skin, name: old_name.presence), gTxt("name_already_exists", "{name}" => name), :error)
      end

      created = record.nil?
      template_model.transaction do
        if record
          if name != old_name
            template_model.where(name: old_name, skin: @skin).update_all(name: name)
            rename_references(old_name, name)
            record = template_model.find_by(name: name, skin: @skin)
          end
        else
          record = template_model.new(name: name, skin: @skin)
        end
        record[content_column] = content
        extra_attributes(record)
        record.save!
        Skin.where(name: @skin).update_all(lastmod: Time.now.utc.change(usec: 0))
      end

      Pref.touch_lastmod!
      key = created ? "#{label_prefix}_created" : "#{label_prefix}_updated"
      redirect_with_message(admin_url(event: event_name, skin: @skin, name: name), gTxt(key, "{list}" => name))
    end

    def destroy
      @skin = params[:skin].to_s
      names = Array(params[:selected]).presence || [ params[:name].to_s ]
      records = template_model.where(skin: @skin, name: names).to_a
      blocked = records.select { |r| protected_template?(r) }
      deleted = records - blocked
      deleted.each(&:destroy)
      msg = gTxt("#{label_prefix}_deleted", "{list}" => deleted.map(&:name).join(", "))
      msg = gTxt("#{label_prefix}_in_use", "{name}" => blocked.map(&:name).join(", ")) if deleted.empty? && blocked.any?
      redirect_with_message(admin_url(event: event_name, skin: @skin), msg, blocked.any? ? :warning : :success)
    end

    def extra_attributes(_record); end

    def rename_references(_old, _new); end

    def protected_template?(record)
      record.respond_to?(:in_use?) && record.in_use?
    end

    def used_by_map
      {}
    end
  end
end
