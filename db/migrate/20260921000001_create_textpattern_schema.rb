# Mirrors the Textpattern 4.9 database schema (table and column names are kept
# verbatim so that templates using raw SQL fragments -- e.g. sort="Posted desc"
# or sort="custom_1 asc" -- keep working).
class CreateTextpatternSchema < ActiveRecord::Migration[8.1]
  def change
    create_table :textpattern, primary_key: "ID" do |t|
      t.datetime :Posted, null: false, precision: 0
      t.datetime :Expires, null: true, precision: 0
      t.string :AuthorID, limit: 64, null: false, default: ""
      t.datetime :LastMod, null: false, precision: 0
      t.string :LastModID, limit: 64, null: false, default: ""
      t.string :Title, null: false, default: ""
      t.string :Title_html, null: false, default: ""
      t.text :Body, null: false, default: ""
      t.text :Body_html, null: false, default: ""
      t.text :Excerpt, null: false, default: ""
      t.text :Excerpt_html, null: false, default: ""
      t.string :Image, null: false, default: ""
      t.string :Category1, limit: 64, null: false, default: ""
      t.string :Category2, limit: 64, null: false, default: ""
      t.integer :Annotate, null: false, default: 0
      t.string :AnnotateInvite, null: false, default: ""
      t.integer :comments_count, null: false, default: 0
      t.integer :Status, null: false, default: 4
      t.string :textile_body, limit: 32, null: false, default: "1"
      t.string :textile_excerpt, limit: 32, null: false, default: "1"
      t.string :Section, null: false, default: ""
      t.string :override_form, null: false, default: ""
      t.string :Keywords, null: false, default: ""
      t.string :description, null: false, default: ""
      t.string :url_title, null: false, default: ""
      (1..10).each { |i| t.string :"custom_#{i}", null: false, default: "" }
      t.string :uid, limit: 32, null: false, default: ""
      t.date :feed_time, null: true
    end
    add_index :textpattern, [ :Category1, :Category2 ], name: "categories_idx"
    add_index :textpattern, :Posted, name: "Posted"
    add_index :textpattern, :Expires, name: "Expires_idx"
    add_index :textpattern, :AuthorID, name: "author_idx"
    add_index :textpattern, [ :Section, :Status ], name: "section_status_idx"
    add_index :textpattern, :url_title, name: "url_title_idx"

    create_table :txp_category do |t|
      t.string :name, limit: 64, null: false, default: ""
      t.string :type, limit: 64, null: false, default: ""
      t.string :parent, limit: 64, null: false, default: ""
      t.integer :lft, null: false, default: 0
      t.integer :rgt, null: false, default: 0
      t.string :title, null: false, default: ""
      t.string :description, limit: 1023, null: false, default: ""
    end
    add_index :txp_category, [ :type, :name ], unique: true, name: "type_name_idx"

    create_table :txp_css, primary_key: [ :name, :skin ] do |t|
      t.string :name, null: false
      t.text :css, null: false, default: ""
      t.string :skin, limit: 63, null: false, default: "default"
      t.datetime :lastmod, null: true, precision: 0
    end

    create_table :txp_discuss_nonce, id: false do |t|
      t.datetime :issue_time, null: false, precision: 0
      t.string :nonce, null: false, default: "", primary_key: true
      t.integer :used, null: false, default: 0
      t.string :secret, null: false, default: ""
    end

    create_table :txp_discuss, primary_key: "discussid" do |t|
      t.integer :parentid, null: false, default: 0
      t.string :name, null: false, default: ""
      t.string :email, limit: 254, null: false, default: ""
      t.string :web, null: false, default: ""
      t.datetime :posted, null: false, precision: 0
      t.text :message, null: false, default: ""
      t.integer :visible, null: false, default: 1
    end
    add_index :txp_discuss, :parentid, name: "parentid"

    create_table :txp_file do |t|
      t.string :filename, null: false, default: ""
      t.string :title, null: true
      t.string :category, limit: 64, null: false, default: ""
      t.string :permissions, limit: 32, null: false, default: "0"
      t.text :description, null: false, default: ""
      t.integer :downloads, null: false, default: 0
      t.integer :status, null: false, default: 4
      t.datetime :modified, null: false, precision: 0
      t.datetime :created, null: false, precision: 0
      t.bigint :size, null: true
      t.string :author, limit: 64, null: false, default: ""
    end
    add_index :txp_file, :filename, unique: true, name: "filename"
    add_index :txp_file, :author, name: "file_author_idx"

    create_table :txp_form, primary_key: [ :name, :skin ] do |t|
      t.string :name, null: false, default: ""
      t.string :type, limit: 28, null: false, default: ""
      t.text :Form, null: false, default: ""
      t.string :skin, limit: 63, null: false, default: "default"
      t.datetime :lastmod, null: true, precision: 0
    end

    create_table :txp_image do |t|
      t.string :name, null: false, default: ""
      t.string :category, limit: 64, null: false, default: ""
      t.string :ext, limit: 20, null: false, default: ""
      t.integer :w, null: false, default: 0
      t.integer :h, null: false, default: 0
      t.string :alt, null: false, default: ""
      t.text :caption, null: false, default: ""
      t.datetime :date, null: false, precision: 0
      t.string :author, limit: 64, null: false, default: ""
      t.integer :thumbnail, null: false, default: 0
      t.integer :thumb_w, null: false, default: 0
      t.integer :thumb_h, null: false, default: 0
    end
    add_index :txp_image, :author, name: "image_author_idx"

    create_table :txp_lang do |t|
      t.string :lang, limit: 16, null: false
      t.string :name, limit: 64, null: false
      t.string :event, limit: 64, null: false
      t.string :owner, limit: 64, null: false, default: ""
      t.text :data
      t.datetime :lastmod, precision: 0
    end
    add_index :txp_lang, [ :lang, :name ], unique: true, name: "lang"
    add_index :txp_lang, [ :lang, :event ], name: "lang_2"
    add_index :txp_lang, :owner, name: "owner"

    create_table :txp_link do |t|
      t.datetime :date, null: false, precision: 0
      t.string :category, limit: 64, null: false, default: ""
      t.text :url, null: false, default: ""
      t.string :linkname, null: false, default: ""
      t.string :linksort, limit: 128, null: false, default: ""
      t.text :description, null: false, default: ""
      t.string :author, limit: 64, null: false, default: ""
    end
    add_index :txp_link, :author, name: "link_author_idx"

    create_table :txp_log do |t|
      t.datetime :time, null: false, precision: 0
      t.string :page, null: false, default: ""
      t.text :refer, null: false, default: ""
      t.integer :status, null: false, default: 200
      t.string :method, limit: 16, null: false, default: "GET"
    end
    add_index :txp_log, :time, name: "time"

    create_table :txp_page, primary_key: [ :name, :skin ] do |t|
      t.string :name, null: false, default: ""
      t.text :user_html, null: false, default: ""
      t.string :skin, limit: 63, null: false, default: "default"
      t.datetime :lastmod, null: true, precision: 0
    end

    create_table :txp_plugin, id: false do |t|
      t.string :name, limit: 64, null: false, default: "", primary_key: true
      t.integer :status, null: false, default: 1
      t.string :author, limit: 128, null: false, default: ""
      t.string :author_uri, limit: 128, null: false, default: ""
      t.string :version, null: false, default: "1.0"
      t.text :description, null: false, default: ""
      t.text :help, null: false, default: ""
      t.text :code, null: false, default: ""
      t.text :code_restore, null: false, default: ""
      t.string :code_md5, limit: 32, null: false, default: ""
      t.text :textpack, null: false, default: ""
      t.text :data, null: false, default: ""
      t.integer :type, null: false, default: 0
      t.integer :load_order, null: false, default: 5
      t.integer :flags, null: false, default: 0
    end
    add_index :txp_plugin, [ :status, :type ], name: "status_type_idx"

    create_table :txp_prefs, primary_key: [ :name, :user_name ] do |t|
      t.string :name, null: false, default: ""
      t.text :val, null: false, default: ""
      t.integer :type, null: false, default: 2
      t.string :event, null: false, default: "publish"
      t.string :collection, null: false, default: ""
      t.string :html, null: false, default: "text_input"
      t.integer :position, null: false, default: 0
      t.string :user_name, limit: 64, null: false, default: ""
    end
    add_index :txp_prefs, :user_name, name: "user_name"

    create_table :txp_section, id: false do |t|
      t.string :name, null: false, default: "", primary_key: true
      t.string :skin, limit: 63, null: false, default: "default"
      t.string :page, null: false, default: ""
      t.string :css, null: false, default: ""
      t.string :permlink_mode, limit: 63, null: false, default: ""
      t.string :description, limit: 1023, null: false, default: ""
      t.integer :in_rss, null: false, default: 1
      t.integer :on_frontpage, null: false, default: 1
      t.integer :searchable, null: false, default: 1
      t.string :title, null: false, default: ""
      t.string :dev_skin, limit: 63, null: false, default: ""
      t.string :dev_page, null: false, default: ""
      t.string :dev_css, null: false, default: ""
    end
    add_index :txp_section, [ :page, :skin ], name: "page_skin"
    add_index :txp_section, [ :css, :skin ], name: "css_skin"

    create_table :txp_skin, id: false do |t|
      t.string :name, limit: 63, null: false, default: "default", primary_key: true
      t.string :title, null: false, default: "Default"
      t.string :version, null: true, default: "1.0"
      t.string :description, limit: 10240, null: true, default: ""
      t.string :author, null: true, default: ""
      t.string :author_uri, null: true, default: ""
      t.datetime :lastmod, null: true, precision: 0
    end

    create_table :txp_token do |t|
      t.integer :reference_id, null: false
      t.string :type, null: false
      t.string :selector, limit: 12, null: false, default: ""
      t.string :token, null: false
      t.datetime :expires, null: true, precision: 0
    end
    add_index :txp_token, [ :reference_id, :type ], unique: true, name: "ref_type"

    create_table :txp_users, primary_key: "user_id" do |t|
      t.string :name, limit: 64, null: false, default: ""
      t.string :pass, limit: 128, null: false
      t.string :RealName, null: false, default: ""
      t.string :email, limit: 254, null: false, default: ""
      t.integer :privs, null: false, default: 1
      t.datetime :last_access, null: true, precision: 0
      t.string :nonce, limit: 64, null: false, default: ""
    end
    add_index :txp_users, :name, unique: true, name: "name"
  end
end
