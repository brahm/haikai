module Txp
  # Privilege table (port of $txp_permissions in admin_config.php).
  module Privs
    module_function

    PERMISSIONS = {
      "admin" => "1,2,3,4,5,6", "admin.edit" => "1", "admin.edit.own" => "1,2,3,4,5,6", "admin.list" => "1,2,3",
      "article.delete.own" => "1,2,3,4,5", "article.delete" => "1,2", "article.edit" => "1,2,3",
      "article.edit.published" => "1,2,3", "article.edit.own" => "1,2,3,4,5,6",
      "article.edit.own.published" => "1,2,3,4", "article.preview" => "1,2,3,4", "article.publish" => "1,2,3,4",
      "article.php" => "1,2,3", "article.set_markup" => "1,2,3,6", "article" => "1,2,3,4,5,6",
      "list" => "1,2,3,4,5,6", "category" => "1,2,3", "css" => "1,2,6", "debug.verbose" => "1,2",
      "debug.backtrace" => "1", "diag" => "1,2", "discuss" => "1,2,3", "file" => "1,2,3,4", "file.edit" => "1,2",
      "file.edit.own" => "1,2,3,4", "file.delete" => "1,2", "file.delete.own" => "1,2,3,4", "file.publish" => "1,2,3,4",
      "form" => "1,2,3,6", "image" => "1,2,3,4,5,6", "image.create.trusted" => "1,2", "image.edit" => "1,2,3,6",
      "image.edit.own" => "1,2,3,4,5,6", "image.delete" => "1,2", "image.delete.own" => "1,2,3,4,5,6",
      "lang" => "1,2,3,4,5,6", "lang.edit" => "1,2", "link" => "1,2,3", "link.edit" => "1,2,3",
      "link.edit.own" => "1,2,3", "link.delete" => "1,2", "link.delete.own" => "1,2,3", "lore" => "1,2,3",
      "page" => "1,2,3,6", "pane" => "1,2,3,4,5,6", "prefs" => "1,2,3,4,5,6",
      "prefs.edit" => "1,2", "prefs.site" => "1,2", "prefs.admin" => "1,2", "prefs.publish" => "1,2",
      "prefs.mail" => "1,2", "prefs.feeds" => "1,2", "prefs.custom" => "1,2", "section" => "1,2,6",
      "section.edit" => "1,2,6", "skin" => "1,2,6", "skin.edit" => "1,2,6", "tab.admin" => "1,2,3,4,5,6",
      "tab.content" => "1,2,3,4,5,6", "tab.presentation" => "1,2,3,6",
      "tag" => "1,2,3,4,5,6", "help" => "1,2,3,4,5,6", "log" => "1,2", "skin.preview" => "1,2,6"
    }.freeze

    def has?(resource, privs)
      return false if privs.nil?

      list = PERMISSIONS[resource.to_s]
      return false if list.nil?

      list.split(",").map(&:strip).include?(privs.to_i.to_s)
    end
  end
end
