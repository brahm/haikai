Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  # Admin side, using Textpattern's URL scheme:
  #   /textpattern/index.php?event=<panel>&step=<action>
  # Each event is served by its own controller.
  admin_events = {
    "article" => "write", "list" => "list", "image" => "images", "file" => "files", "link" => "links",
    "discuss" => "comments", "category" => "categories", "section" => "sections", "page" => "pages",
    "form" => "forms", "css" => "styles", "skin" => "skins", "diag" => "diagnostics", "prefs" => "prefs",
    "admin" => "users", "lang" => "languages", "plugin" => "plugins", "log" => "logs", "lore" => "logs",
    "tag" => "tag_builder", "help" => "help"
  }

  scope "textpattern" do
    admin_events.each do |event, controller|
      match "(index.php)", to: "admin/#{controller}#handle", via: [ :get, :post ],
        constraints: ->(req) { req.params["event"] == event }
    end
    match "(index.php)", to: "admin/sessions#handle", via: [ :get, :post ], as: :admin_root
    get "css.php", to: "public#css"
    post "preview", to: "admin/write#textile_preview", as: :admin_textile_preview
  end

  # Stylesheets and automatic thumbnails.
  get "css.php", to: "public#css", as: :txp_css
  get "images/thumb/:params/:file", to: "public#thumbnail", constraints: { file: /[^\/]+/ }

  # Shortcut to the admin side (/textpattern/), unless the site has a section
  # called "admin". Temporary, so creating that section later still works.
  get "admin", to: redirect("/textpattern/", status: 302),
    constraints: ->(_req) { !Section.exists?(name: "admin") }

  # Everything else is the public site.
  root "public#show", via: [ :get, :post ]
  match "*path", to: "public#show", via: [ :get, :post ], format: false
end
