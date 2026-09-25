# Brings the default theme of existing sites up to date where its templates
# are still as an earlier version shipped them (edited ones are left alone):
# the site feeds on sections left out of the feeds, comment invites that
# follow the comments mode and their anchor, and the popup_comments form.
class UpdateDefaultTheme < ActiveRecord::Migration[8.1]
  THEME = Rails.root.join("db", "themes", "default")

  # [table, template, file, SHA-256 of the versions shipped before]
  UPDATES = [
    [ "txp_page", "archive", "pages/archive.txp", %w[4799300d98049285eed2a4049a519cb37e19e3413a84d3947ee9296389d3c0be] ],
    [ "txp_form", "footer", "forms/misc/footer.txp", %w[32679e1014126c559695df8afd04fbcea1bfdc3087e7c80f1ea9ab1f7a0aee3a] ],
    [ "txp_form", "article_listing", "forms/article/article_listing.txp", %w[23b7d64d474fa26cd64ddd5f27e99cba1448670790fe981d62d5d063aca394f7] ],
    [ "txp_form", "comments_display", "forms/comment/comments_display.txp", %w[20985afd7a1e404af293f6237dc978872fb7b0131f480409ff1174ecb28eae45] ]
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
      template = theme_file(file)
      next if current.nil? || current == template

      if shipped.include?(Digest::SHA256.hexdigest(current))
        db.update("UPDATE #{table} SET #{column} = #{db.quote(template)}, lastmod = #{db.quote(now)} #{where}")
        say "#{file}: updated"
        changed = true
      else
        say "#{file}: edited on this site, left as it is"
      end
    end

    unless db.select_value("SELECT 1 FROM txp_form WHERE name = 'popup_comments' AND skin = 'default'")
      db.insert("INSERT INTO txp_form (name, type, skin, #{db.quote_column_name('Form')}, lastmod) " \
        "VALUES ('popup_comments', 'comment', 'default', #{db.quote(theme_file('forms/comment/popup_comments.txp'))}, #{db.quote(now)})")
      say "forms/comment/popup_comments.txp: added"
      changed = true
    end

    # Pages cached by browsers (Last-Modified, ETag) change too.
    db.update("UPDATE txp_prefs SET val = #{db.quote(now)} WHERE name = 'lastmod' AND user_name = ''") if changed
  end

  def down
    # Nothing to undo: the earlier templates had the flaws this fixes.
  end

  private

  def theme_file(file)
    File.read(THEME.join(file), encoding: "UTF-8")
  end
end
