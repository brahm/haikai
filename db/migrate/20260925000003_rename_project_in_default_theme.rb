# The project is now called Haikai: the default theme names it in the footer
# credit, in the generator meta of its pages and as its author, where the site
# did not edit them.
class RenameProjectInDefaultTheme < ActiveRecord::Migration[8.1]
  THEME = Rails.root.join("db", "themes", "default")

  # [table, template, file, SHA-256 of the version shipped before]
  UPDATES = [
    [ "txp_page", "default", "pages/default.txp", "b9bf0cd724f9a74a3ac918189c8c9caca5ff9859afc6b38e844a8612a8e363f8" ],
    [ "txp_page", "archive", "pages/archive.txp", "b9db5a4770751ab1b0994175ffc072f21cdc41cfb671a62cf3f2ac96ed5b8955" ],
    [ "txp_form", "footer", "forms/misc/footer.txp", "45a22976b0f9f8889f43f3357fccc7cf2671e40db72f6450ab9a4d7803dc717b" ],
    [ "txp_form", "popup_comments", "forms/comment/popup_comments.txp", "4a82d7e76130c4d3d87c72287547ab74109d65be85236cd325a343f37c67d06d" ]
  ].freeze

  def up
    db = connection
    return unless db.select_value("SELECT 1 FROM txp_skin WHERE name = 'default'")

    now = Time.now.utc.strftime("%Y-%m-%d %H:%M:%S")
    changed = false
    UPDATES.each do |table, name, file, shipped|
      column = db.quote_column_name(table == "txp_page" ? "user_html" : "Form")
      where = "WHERE name = #{db.quote(name)} AND skin = 'default'"
      current = db.select_value("SELECT #{column} FROM #{table} #{where}")
      template = File.read(THEME.join(file), encoding: "UTF-8")
      next if current.nil? || current == template

      if Digest::SHA256.hexdigest(current) == shipped
        db.update("UPDATE #{table} SET #{column} = #{db.quote(template)}, lastmod = #{db.quote(now)} #{where}")
        say "#{file}: updated"
        changed = true
      else
        say "#{file}: edited on this site, left as it is"
      end
    end
    # Pages cached by browsers (Last-Modified, ETag) change too.
    db.update("UPDATE txp_prefs SET val = #{db.quote(now)} WHERE name = 'lastmod' AND user_name = ''") if changed

    db.update("UPDATE txp_skin SET author = 'Haikai', " \
      "description = REPLACE(description, 'Textpattern on Rails', 'Haikai') " \
      "WHERE name = 'default' AND author = 'Textpattern on Rails'")
  end

  def down
    # Nothing to undo: only the name of the project changed.
  end
end
