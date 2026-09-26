# Haikai has no plugins (README, "O que fica de fora"): the plugins table and
# its preferences go. The code of installed plugins is saved to files first
# (storage/removed-plugins), so none is lost silently.
class RemovePlugins < ActiveRecord::Migration[8.1]
  def up
    if table_exists?(:txp_plugin)
      save_plugins
      drop_table :txp_plugin
    end
    execute "DELETE FROM txp_prefs WHERE name IN ('use_plugins', 'admin_side_plugins')"
  end

  def down
    create_table "txp_plugin", primary_key: "name", id: { type: :string, limit: 64, default: "" } do |t|
      t.string "author", limit: 128, default: "", null: false
      t.string "author_uri", limit: 128, default: "", null: false
      t.text "code", default: "", null: false
      t.string "code_md5", limit: 32, default: "", null: false
      t.text "code_restore", default: "", null: false
      t.text "data", default: "", null: false
      t.text "description", default: "", null: false
      t.integer "flags", default: 0, null: false
      t.text "help", default: "", null: false
      t.integer "load_order", default: 5, null: false
      t.integer "status", default: 1, null: false
      t.text "textpack", default: "", null: false
      t.integer "type", default: 0, null: false
      t.string "version", default: "1.0", null: false
      t.index [ "status", "type" ], name: "status_type_idx"
    end
    execute <<~SQL
      INSERT INTO txp_prefs (name, val, type, event, html, position, user_name) VALUES
        ('use_plugins', '1', 0, 'publish', 'yesnoradio', 260, ''),
        ('admin_side_plugins', '1', 0, 'publish', 'yesnoradio', 280, '')
    SQL
  end

  def plugins_dir
    Rails.root.join("storage", "removed-plugins")
  end

  private

  def save_plugins
    plugins = connection.select_all("SELECT name, version, code FROM txp_plugin ORDER BY name").to_a
    return if plugins.empty?

    FileUtils.mkdir_p(plugins_dir)
    plugins.each do |plugin|
      file = "#{plugin['name']}-#{plugin['version']}".gsub(/[^\w.-]/, "_")
      File.write(plugins_dir.join("#{file}.txt"), plugin["code"].to_s)
    end
    say "#{plugins.size} plugin(s) saved to #{plugins_dir}"
  end
end
