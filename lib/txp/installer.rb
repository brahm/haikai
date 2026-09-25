module Txp
  # Installs a fresh site: preferences, default theme, sections, categories,
  # the publisher account and some starter content (like Textpattern's setup).
  module Installer
    module_function

    def install!(sitename: "My site", lang: "en", user: nil, sample_content: true)
      ActiveRecord::Base.transaction do
        DefaultPrefs.install!("language" => lang, "language_ui" => lang, "sitename" => sitename)
        Pref.set("sitename", sitename, event: "site", position: 20)
        theme = ThemeIO.import(Rails.root.join("db", "themes", "default"), name: "default", overwrite: false)

        { "default" => [ "Default", "default", 0, 1 ], "articles" => [ "Articles", "archive", 1, 1 ], "about" => [ "About", "archive", 0, 0 ] }.each do |name, (title, page, front, rss)|
          Section.find_or_create_by!(name: name) do |s|
            s.title = title
            s.skin = theme.name
            s.page = page
            s.css = "default"
            s.on_frontpage = front
            s.in_rss = rss
          end
        end

        Category::TYPES.each { |type| Category.find_or_create_by!(type: type, name: "root") { |c| c.title = "root" } }
        if sample_content
          { "article" => [ %w[general General], %w[news News] ], "image" => [ %w[photos Photos] ],
            "file" => [ %w[downloads Downloads] ], "link" => [ %w[resources Resources] ] }.each do |type, cats|
            cats.each { |name, title| Category.find_or_create_by!(type: type, name: name) { |c| c.title = title; c.parent = "root" } }
          end
        end
        Category::TYPES.each { |type| Category.rebuild_tree(type) }

        if user
          user.privs = 1
          user.save!
          Pref.set("publisher_email", user.email, event: "mail", position: 115)
          Pref.set("blog_mail_uid", user.email, type: PREF_HIDDEN) if user.email.present?
        end
        author = user&.name || User.where(privs: 1).pick(:name) || "admin"

        if sample_content && Article.count.zero?
          Article.create!(
            Title: welcome_title(lang), Section: "articles", AuthorID: author, Status: STATUS_LIVE, Category1: "general",
            Annotate: 1, AnnotateInvite: "Comment", textile_body: USE_TEXTILE, Body: welcome_body(lang),
            Excerpt: welcome_excerpt(lang)
          )
          Link.find_or_create_by!(url: "https://textpattern.com/") do |l|
            l.linkname = "Textpattern CMS"
            l.category = "resources"
            l.description = "The original Textpattern CMS"
            l.author = author
          end
        end

        Pref.set("default_section", "articles", event: "section", type: PREF_HIDDEN)
        Pref.touch_lastmod!
      end
    end

    def welcome_title(lang)
      lang.to_s.start_with?("pt") ? "Bem-vindo ao seu site" : "Welcome to your site"
    end

    def welcome_excerpt(lang)
      lang.to_s.start_with?("pt") ? "Seu novo site compatível com o Textpattern está pronto." : "Your new Textpattern-compatible site is ready. Here is what you can do next."
    end

    def welcome_body(lang)
      if lang.to_s.start_with?("pt")
        <<~TEXTILE
          h2. Funcionou!

          Este site roda no *Textpattern on Rails*: um clone do "Textpattern CMS":https://textpattern.com em Ruby on Rails que renderiza templates padrão do Textpattern -- páginas, formulários e estilos feitos com marcação @<txp:tag />@.

          * Edite o tema no painel administrativo (Apresentação → Páginas, Formulários, Estilos).
          * Escreva artigos usando Textile, como este.
          * Importe qualquer tema do Textpattern 4.x no painel Temas.

          Artigos também podem conter tags: este site se chama <txp:site_name />.
        TEXTILE
      else
        <<~TEXTILE
          h2. It works!

          This site runs on *Textpattern on Rails*: a Ruby on Rails clone of "Textpattern CMS":https://textpattern.com that renders standard Textpattern templates -- pages, forms and styles made of @<txp:tag />@ markup.

          * Edit the theme in the admin panel (Presentation → Pages, Forms, Styles).
          * Write articles using Textile, like this one.
          * Import any Textpattern 4.x theme from the Themes panel.

          Articles may also contain tags, e.g. this site is called <txp:site_name />.
        TEXTILE
      end
    end
  end
end
