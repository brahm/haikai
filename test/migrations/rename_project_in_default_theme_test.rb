require "test_helper"
require Rails.root.join("db", "migrate", "20260925000003_rename_project_in_default_theme").to_s

# Existing sites name the project Haikai in the default theme.
class RenameProjectInDefaultThemeTest < ActiveSupport::TestCase
  THEME = RenameProjectInDefaultTheme::THEME

  # A template of the default theme as it was before the project was renamed.
  def self.previous(file, current = File.read(THEME.join(file)))
    current
      .sub(%(<meta name="generator" content="Haikai">), %(<meta name="generator" content="Textpattern CMS">))
      .sub(%(<a rel="external" href="https://github.com/brahm/haikai">Haikai</a></p>),
        %(<a rel="external" href="https://textpattern.com/">Textpattern CMS</a> (on Rails)</p>))
  end

  setup { Txp::Installer.install! }

  def template(table, name)
    table == "txp_page" ? Page.find_by(skin: "default", name: name) : Form.find_by(skin: "default", name: name)
  end

  def content(record)
    record.is_a?(Page) ? record.user_html : record.Form
  end

  def migrate
    capture_io { RenameProjectInDefaultTheme.new.migrate(:up) }
  end

  test "templates and author as the previous version shipped them take the new name" do
    RenameProjectInDefaultTheme::UPDATES.each do |table, name, file, shipped|
      old = self.class.previous(file)
      assert_equal shipped, Digest::SHA256.hexdigest(old), file
      record = template(table, name)
      record.update_columns((record.is_a?(Page) ? :user_html : :Form) => old)
    end
    Skin.where(name: "default").update_all(author: "Textpattern on Rails",
      description: "Starter theme bundled with Textpattern on Rails. Uses standard Textpattern tags only.")

    migrate

    RenameProjectInDefaultTheme::UPDATES.each do |table, name, file, _|
      assert_equal File.read(THEME.join(file)), content(template(table, name)), file
    end
    assert_includes content(template("txp_form", "footer")), ">Haikai</a>"
    skin = Skin.find("default")
    assert_equal [ "Haikai", "Starter theme bundled with Haikai. Uses standard Textpattern tags only." ], [ skin.author, skin.description ]
  end

  test "edited templates and an edited author are left alone" do
    footer = template("txp_form", "footer")
    footer.update_columns(Form: "#{self.class.previous('forms/misc/footer.txp')}<!-- mine -->\n")
    Skin.where(name: "default").update_all(author: "Me")
    migrate
    assert_includes content(footer.reload), "<!-- mine -->"
    assert_equal "Me", Skin.find("default").author
  end
end
