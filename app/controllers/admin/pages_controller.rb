module Admin
  # The Pages panel (event=page): page templates of a theme.
  class PagesController < BaseController
    include TemplateEditing

    self.event_name = "page"
    self.default_step = :index
    self.template_model = Page
    self.content_column = :user_html
    self.label_prefix = "page"

    step "page_edit", :index
    step "page_save", :save, post: true
    step "page_delete", :destroy, post: true

    private

    def rename_references(old_name, name)
      Section.where(page: old_name, skin: @skin).update_all(page: name)
      Section.where(dev_page: old_name, dev_skin: @skin).update_all(dev_page: name)
    end

    def used_by_map
      Section.where(skin: @skin).pluck(:page, :name).group_by(&:first).transform_values { |v| v.map(&:last) }
    end
  end
end
