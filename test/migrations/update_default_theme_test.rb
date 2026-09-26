require "test_helper"
require Rails.root.join("db", "migrate", "20260925000002_update_default_theme").to_s
require_relative "rename_project_in_default_theme_test"

# Existing sites get the fixes of the default theme where they did not edit it.
class UpdateDefaultThemeTest < ActiveSupport::TestCase
  THEME = UpdateDefaultTheme::THEME

  setup { Txp::Installer.install! }

  # A template as the first version of the theme shipped it.
  def shipped(file)
    current = RenameProjectInDefaultThemeTest.previous(file)
    case file
    when "pages/archive.txp"
      current.sub(%r{    <txp:if_section filter="in_rss">\n.*?    </txp:if_section>\n}m,
        %(    <txp:feed_link flavor="rss" format="link" section='<txp:section />' />\n))
    when "forms/misc/footer.txp"
      current.sub(%r{        <txp:if_section filter="in_rss">\n.*?        </txp:if_section>\n}m,
        %(        &middot; <txp:feed_link label="RSS" /> &middot; <txp:feed_link flavor="atom" label="Atom" />\n))
    when "forms/article/article_listing.txp"
      current.sub(%(        <txp:evaluate> &middot; <txp:comments_invite /></txp:evaluate>\n),
        %(        <txp:if_comments> &middot; <txp:comments_count /> <txp:text item="comments" /></txp:if_comments>\n))
    when "forms/comment/comments_display.txp"
      current.sub(%(    <a id="<txp:text item="comment" />"></a>\n), "")
    end
  end

  def template(table, name)
    table == "txp_page" ? Page.find_by(skin: "default", name: name) : Form.find_by(skin: "default", name: name)
  end

  def content(record)
    record.is_a?(Page) ? record.user_html : record.Form
  end

  def migrate
    capture_io { UpdateDefaultTheme.new.migrate(:up) }
  end

  test "templates as an earlier version shipped them are brought up to date" do
    UpdateDefaultTheme::UPDATES.each do |table, name, file, digests|
      old = shipped(file)
      assert_includes digests, Digest::SHA256.hexdigest(old), file
      record = template(table, name)
      record.update_columns((record.is_a?(Page) ? :user_html : :Form) => old)
    end
    Form.where(skin: "default", name: "popup_comments").delete_all
    Pref.set("lastmod", "2020-01-01 00:00:00", type: Txp::PREF_HIDDEN)

    migrate

    UpdateDefaultTheme::UPDATES.each do |table, name, file, _|
      assert_equal File.read(THEME.join(file)), content(template(table, name)), file
    end
    assert_equal File.read(THEME.join("forms/comment/popup_comments.txp")), content(template("txp_form", "popup_comments"))
    assert_not_equal "2020-01-01 00:00:00", Pref.get("lastmod")
  end

  test "edited templates are left alone" do
    footer = template("txp_form", "footer")
    footer.update_columns(Form: "#{shipped('forms/misc/footer.txp')}<!-- mine -->\n")
    migrate
    assert_includes content(footer.reload), "<!-- mine -->"
  end

  test "an up-to-date site is not touched" do
    Pref.set("lastmod", "2020-01-01 00:00:00", type: Txp::PREF_HIDDEN)
    migrate
    assert_equal "2020-01-01 00:00:00", Pref.get("lastmod")
  end
end
