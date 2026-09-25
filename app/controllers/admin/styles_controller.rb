module Admin
  # The Styles panel (event=css): stylesheets of a theme.
  class StylesController < BaseController
    include TemplateEditing

    self.event_name = "css"
    self.default_step = :index
    self.template_model = Style
    self.content_column = :css
    self.label_prefix = "css"

    step "css_edit", :index
    step "css_save", :save, post: true
    step "css_delete", :destroy, post: true

    private

    def rename_references(old_name, name)
      Section.where(css: old_name, skin: @skin).update_all(css: name)
      Section.where(dev_css: old_name, dev_skin: @skin).update_all(dev_css: name)
    end

    def used_by_map
      Section.where(skin: @skin).pluck(:css, :name).group_by(&:first).transform_values { |v| v.map(&:last) }
    end
  end
end
