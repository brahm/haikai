# The XML-RPC server and the PHP plugin cache are left out of this project
# (README, "O que fica de fora"): their preferences had no effect.
class RemoveXmlrpcAndPluginCachePrefs < ActiveRecord::Migration[8.1]
  def up
    execute "DELETE FROM txp_prefs WHERE name IN ('plugin_cache_dir', 'enable_xmlrpc_server')"
  end

  def down
    execute <<~SQL
      INSERT INTO txp_prefs (name, val, type, event, html, position, user_name) VALUES
        ('plugin_cache_dir', '', 0, 'admin', 'text_input', 100, ''),
        ('enable_xmlrpc_server', '0', 0, 'admin', 'yesnoradio', 130, '')
    SQL
  end
end
