require "test_helper"
require Rails.root.join("db", "migrate", "20260925000004_remove_plugins").to_s

# Existing sites lose the plugins table and its preferences, but keep the code
# of their plugins in files.
class RemovePluginsTest < ActiveSupport::TestCase
  def migrate(migration, direction)
    capture_io { migration.migrate(direction) }
  end

  test "the table and the preferences go, the plugins' code stays in files" do
    migration = RemovePlugins.new
    db = ActiveRecord::Base.connection
    migrate(migration, :down)
    db.execute("INSERT INTO txp_plugin (name, version, code) VALUES ('abc_hi', '1.2', 'tag :abc_hi do end')")

    Dir.mktmpdir do |dir|
      migration.define_singleton_method(:plugins_dir) { Pathname.new(dir) }
      migrate(migration, :up)
      assert_equal "tag :abc_hi do end", File.read(File.join(dir, "abc_hi-1.2.txt"))
    end
    assert_not db.table_exists?(:txp_plugin)
    assert_not Pref.exists?(name: %w[use_plugins admin_side_plugins])
  end
end
