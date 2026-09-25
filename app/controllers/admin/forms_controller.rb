module Admin
  # The Forms panel (event=form): reusable template snippets of a theme.
  class FormsController < BaseController
    include TemplateEditing

    self.event_name = "form"
    self.default_step = :index
    self.template_model = Form
    self.content_column = :Form
    self.label_prefix = "form"

    step "form_edit", :index
    step "form_save", :save, post: true
    step "form_delete", :destroy, post: true
    step "form_multi_edit", :multi_edit, post: true

    private

    def extra_attributes(record)
      types = Form.types(@prefs)
      record.type = types.include?(params[:type].to_s) ? params[:type].to_s : (record.type.presence || "misc")
    end

    def protected_template?(record)
      record.essential?
    end

    def multi_edit
      @skin = params[:skin].to_s
      case params[:edit_method]
      when "delete" then destroy
      when "changetype"
        type = params[:type].to_s
        forms = Form.where(skin: @skin, name: selected_ids)
        forms.update_all(type: type) if Form.types(@prefs).include?(type)
        redirect_with_message(admin_url(event: "form", skin: @skin), gTxt("items_updated", "{list}" => selected_ids.join(", ")))
      else
        redirect_to admin_url(event: "form", skin: @skin)
      end
    end
  end
end
