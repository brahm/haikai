module Admin
  # The Categories panel (event=category): nested trees for article, image,
  # file and link categories.
  class CategoriesController < BaseController
    self.event_name = "category"
    self.default_step = :index

    step "cat_category_list", :index
    step "list", :index
    step "cat_article_create", :create, post: true
    step "cat_create", :create, post: true
    step "cat_category_edit", :edit
    step "cat_edit", :edit
    step "cat_category_save", :save, post: true
    step "cat_save", :save, post: true
    step "cat_category_multiedit", :multi_edit, post: true
    step "multi_edit", :multi_edit, post: true

    private

    def index
      @page_title = gTxt("tab_organise")
      @trees = Category::TYPES.index_with { |t| Category.tree(t) }
      @counts = {
        "article" => Article.group(:Category1).count.merge(Article.group(:Category2).count) { |_k, a, b| a + b },
        "image" => Image.group(:category).count, "file" => TxpFile.group(:category).count, "link" => Link.group(:category).count
      }
      render "admin/categories/index"
    end

    def create
      type = valid_type(params[:type])
      title = params[:title].to_s.strip
      name = Txp::Text.strip_space(params[:name].presence || title, @prefs, force: true).to_s
      return redirect_with_message(admin_url(event: "category"), gTxt("invalid_name"), :error) if name.empty?
      if Category.exists?(type: type, name: name)
        return redirect_with_message(admin_url(event: "category"), gTxt("category_already_exists", "{name}" => name), :error)
      end

      parent = params[:parent].presence || "root"
      parent = "root" unless Category.exists?(type: type, name: parent)
      Category.create!(type: type, name: name, title: title.presence || name, parent: parent)
      Category.rebuild_tree(type)
      redirect_with_message(admin_url(event: "category"), gTxt("category_created", "{name}" => name))
    end

    def edit
      @category = Category.find_by(id: params[:id])
      return redirect_with_message(admin_url(event: "category"), gTxt("not_found"), :error) unless @category

      @page_title = gTxt("edit_category")
      excluded = [ @category.name ] + @category.descendant_names
      @parents = Category.tree(@category.type).reject { |c, _| excluded.include?(c.name) }
      render "admin/categories/edit"
    end

    def save
      cat = Category.find_by(id: params[:id])
      return redirect_with_message(admin_url(event: "category"), gTxt("not_found"), :error) unless cat

      old_name = cat.name
      name = Txp::Text.strip_space(params[:name].presence || cat.name, @prefs, force: true).to_s
      if name != old_name && Category.exists?(type: cat.type, name: name)
        return redirect_with_message(admin_url(event: "category", step: "cat_category_edit", id: cat.id), gTxt("category_already_exists", "{name}" => name), :error)
      end

      parent = params[:parent].presence || "root"
      parent = "root" if parent == name || !Category.exists?(type: cat.type, name: parent) || cat.descendant_names.include?(parent)

      Category.transaction do
        cat.update!(name: name, title: params[:title].to_s, description: params[:description].to_s, parent: parent)
        rename_references(cat.type, old_name, name) if name != old_name
        Category.rebuild_tree(cat.type)
      end
      redirect_with_message(admin_url(event: "category"), gTxt("category_updated", "{name}" => name))
    end

    def rename_references(type, old_name, name)
      Category.where(type: type, parent: old_name).update_all(parent: name)
      case type
      when "article"
        Article.where(Category1: old_name).update_all(Category1: name)
        Article.where(Category2: old_name).update_all(Category2: name)
      when "image" then Image.where(category: old_name).update_all(category: name)
      when "file" then TxpFile.where(category: old_name).update_all(category: name)
      when "link" then Link.where(category: old_name).update_all(category: name)
      end
    end

    def multi_edit
      type = valid_type(params[:type])
      cats = Category.where(type: type, id: selected_ids.map(&:to_i)).where.not(name: "root").to_a
      names = cats.map(&:name)

      case params[:edit_method]
      when "delete"
        Category.transaction do
          cats.each do |c|
            Category.where(type: type, parent: c.name).update_all(parent: c.parent.presence || "root")
            c.destroy
          end
          Category.rebuild_tree(type)
        end
        redirect_with_message(admin_url(event: "category"), gTxt("categories_deleted", "{list}" => names.join(", ")))
      when "changeparent"
        parent = params[:new_parent].presence || "root"
        cats.each do |c|
          next if c.name == parent || c.descendant_names.include?(parent)

          c.update(parent: parent)
        end
        Category.rebuild_tree(type)
        redirect_with_message(admin_url(event: "category"), gTxt("items_updated", "{list}" => names.join(", ")))
      else
        redirect_to admin_url(event: "category")
      end
    end

    def valid_type(type)
      Category::TYPES.include?(type.to_s) ? type.to_s : "article"
    end
  end
end
