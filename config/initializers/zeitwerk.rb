# Acronyms used by the Txp namespace.
Rails.autoloaders.each do |autoloader|
  autoloader.inflector.inflect("db" => "DB", "theme_io" => "ThemeIO")
end
