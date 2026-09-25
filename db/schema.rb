# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_25_000001) do
  create_table "textpattern", primary_key: "ID", force: :cascade do |t|
    t.integer "Annotate", default: 0, null: false
    t.string "AnnotateInvite", default: "", null: false
    t.string "AuthorID", limit: 64, default: "", null: false
    t.text "Body", default: "", null: false
    t.text "Body_html", default: "", null: false
    t.string "Category1", limit: 64, default: "", null: false
    t.string "Category2", limit: 64, default: "", null: false
    t.text "Excerpt", default: "", null: false
    t.text "Excerpt_html", default: "", null: false
    t.datetime "Expires", precision: 0
    t.string "Image", default: "", null: false
    t.string "Keywords", default: "", null: false
    t.datetime "LastMod", precision: 0, null: false
    t.string "LastModID", limit: 64, default: "", null: false
    t.datetime "Posted", precision: 0, null: false
    t.string "Section", default: "", null: false
    t.integer "Status", default: 4, null: false
    t.string "Title", default: "", null: false
    t.string "Title_html", default: "", null: false
    t.integer "comments_count", default: 0, null: false
    t.string "custom_1", default: "", null: false
    t.string "custom_10", default: "", null: false
    t.string "custom_2", default: "", null: false
    t.string "custom_3", default: "", null: false
    t.string "custom_4", default: "", null: false
    t.string "custom_5", default: "", null: false
    t.string "custom_6", default: "", null: false
    t.string "custom_7", default: "", null: false
    t.string "custom_8", default: "", null: false
    t.string "custom_9", default: "", null: false
    t.string "description", default: "", null: false
    t.date "feed_time"
    t.string "override_form", default: "", null: false
    t.string "textile_body", limit: 32, default: "1", null: false
    t.string "textile_excerpt", limit: 32, default: "1", null: false
    t.string "uid", limit: 32, default: "", null: false
    t.string "url_title", default: "", null: false
    t.index ["AuthorID"], name: "author_idx"
    t.index ["Category1", "Category2"], name: "categories_idx"
    t.index ["Expires"], name: "Expires_idx"
    t.index ["Posted"], name: "Posted"
    t.index ["Section", "Status"], name: "section_status_idx"
    t.index ["url_title"], name: "url_title_idx"
  end

  create_table "txp_category", force: :cascade do |t|
    t.string "description", limit: 1023, default: "", null: false
    t.integer "lft", default: 0, null: false
    t.string "name", limit: 64, default: "", null: false
    t.string "parent", limit: 64, default: "", null: false
    t.integer "rgt", default: 0, null: false
    t.string "title", default: "", null: false
    t.string "type", limit: 64, default: "", null: false
    t.index ["type", "name"], name: "type_name_idx", unique: true
  end

  create_table "txp_css", primary_key: ["name", "skin"], force: :cascade do |t|
    t.text "css", default: "", null: false
    t.datetime "lastmod", precision: 0
    t.string "name", null: false
    t.string "skin", limit: 63, default: "default", null: false
  end

  create_table "txp_discuss", primary_key: "discussid", force: :cascade do |t|
    t.string "email", limit: 254, default: "", null: false
    t.text "message", default: "", null: false
    t.string "name", default: "", null: false
    t.integer "parentid", default: 0, null: false
    t.datetime "posted", precision: 0, null: false
    t.integer "visible", default: 1, null: false
    t.string "web", default: "", null: false
    t.index ["parentid"], name: "parentid"
  end

  create_table "txp_discuss_nonce", primary_key: "nonce", id: :string, default: "", force: :cascade do |t|
    t.datetime "issue_time", precision: 0, null: false
    t.string "secret", default: "", null: false
    t.integer "used", default: 0, null: false
  end

  create_table "txp_file", force: :cascade do |t|
    t.string "author", limit: 64, default: "", null: false
    t.string "category", limit: 64, default: "", null: false
    t.datetime "created", precision: 0, null: false
    t.text "description", default: "", null: false
    t.integer "downloads", default: 0, null: false
    t.string "filename", default: "", null: false
    t.datetime "modified", precision: 0, null: false
    t.string "permissions", limit: 32, default: "0", null: false
    t.bigint "size"
    t.integer "status", default: 4, null: false
    t.string "title"
    t.index ["author"], name: "file_author_idx"
    t.index ["filename"], name: "filename", unique: true
  end

  create_table "txp_form", primary_key: ["name", "skin"], force: :cascade do |t|
    t.text "Form", default: "", null: false
    t.datetime "lastmod", precision: 0
    t.string "name", default: "", null: false
    t.string "skin", limit: 63, default: "default", null: false
    t.string "type", limit: 28, default: "", null: false
  end

  create_table "txp_image", force: :cascade do |t|
    t.string "alt", default: "", null: false
    t.string "author", limit: 64, default: "", null: false
    t.text "caption", default: "", null: false
    t.string "category", limit: 64, default: "", null: false
    t.datetime "date", precision: 0, null: false
    t.string "ext", limit: 20, default: "", null: false
    t.integer "h", default: 0, null: false
    t.string "name", default: "", null: false
    t.integer "thumb_h", default: 0, null: false
    t.integer "thumb_w", default: 0, null: false
    t.integer "thumbnail", default: 0, null: false
    t.integer "w", default: 0, null: false
    t.index ["author"], name: "image_author_idx"
  end

  create_table "txp_lang", force: :cascade do |t|
    t.text "data"
    t.string "event", limit: 64, null: false
    t.string "lang", limit: 16, null: false
    t.datetime "lastmod", precision: 0
    t.string "name", limit: 64, null: false
    t.string "owner", limit: 64, default: "", null: false
    t.index ["lang", "event"], name: "lang_2"
    t.index ["lang", "name"], name: "lang", unique: true
    t.index ["owner"], name: "owner"
  end

  create_table "txp_link", force: :cascade do |t|
    t.string "author", limit: 64, default: "", null: false
    t.string "category", limit: 64, default: "", null: false
    t.datetime "date", precision: 0, null: false
    t.text "description", default: "", null: false
    t.string "linkname", default: "", null: false
    t.string "linksort", limit: 128, default: "", null: false
    t.text "url", default: "", null: false
    t.index ["author"], name: "link_author_idx"
  end

  create_table "txp_log", force: :cascade do |t|
    t.string "method", limit: 16, default: "GET", null: false
    t.string "page", default: "", null: false
    t.text "refer", default: "", null: false
    t.integer "status", default: 200, null: false
    t.datetime "time", precision: 0, null: false
    t.index ["time"], name: "time"
  end

  create_table "txp_page", primary_key: ["name", "skin"], force: :cascade do |t|
    t.datetime "lastmod", precision: 0
    t.string "name", default: "", null: false
    t.string "skin", limit: 63, default: "default", null: false
    t.text "user_html", default: "", null: false
  end

  create_table "txp_plugin", primary_key: "name", id: { type: :string, limit: 64, default: "" }, force: :cascade do |t|
    t.string "author", limit: 128, default: "", null: false
    t.string "author_uri", limit: 128, default: "", null: false
    t.text "code", default: "", null: false
    t.string "code_md5", limit: 32, default: "", null: false
    t.text "code_restore", default: "", null: false
    t.text "data", default: "", null: false
    t.text "description", default: "", null: false
    t.integer "flags", default: 0, null: false
    t.text "help", default: "", null: false
    t.integer "load_order", default: 5, null: false
    t.integer "status", default: 1, null: false
    t.text "textpack", default: "", null: false
    t.integer "type", default: 0, null: false
    t.string "version", default: "1.0", null: false
    t.index ["status", "type"], name: "status_type_idx"
  end

  create_table "txp_prefs", primary_key: ["name", "user_name"], force: :cascade do |t|
    t.string "collection", default: "", null: false
    t.string "event", default: "publish", null: false
    t.string "html", default: "text_input", null: false
    t.string "name", default: "", null: false
    t.integer "position", default: 0, null: false
    t.integer "type", default: 2, null: false
    t.string "user_name", limit: 64, default: "", null: false
    t.text "val", default: "", null: false
    t.index ["user_name"], name: "user_name"
  end

  create_table "txp_section", primary_key: "name", id: :string, default: "", force: :cascade do |t|
    t.string "css", default: "", null: false
    t.string "description", limit: 1023, default: "", null: false
    t.string "dev_css", default: "", null: false
    t.string "dev_page", default: "", null: false
    t.string "dev_skin", limit: 63, default: "", null: false
    t.integer "in_rss", default: 1, null: false
    t.integer "on_frontpage", default: 1, null: false
    t.string "page", default: "", null: false
    t.string "permlink_mode", limit: 63, default: "", null: false
    t.integer "searchable", default: 1, null: false
    t.string "skin", limit: 63, default: "default", null: false
    t.string "title", default: "", null: false
    t.index ["css", "skin"], name: "css_skin"
    t.index ["page", "skin"], name: "page_skin"
  end

  create_table "txp_skin", primary_key: "name", id: { type: :string, limit: 63, default: "default" }, force: :cascade do |t|
    t.string "author", default: ""
    t.string "author_uri", default: ""
    t.string "description", limit: 10240, default: ""
    t.datetime "lastmod", precision: 0
    t.string "title", default: "Default", null: false
    t.string "version", default: "1.0"
  end

  create_table "txp_token", force: :cascade do |t|
    t.datetime "expires", precision: 0
    t.integer "reference_id", null: false
    t.string "selector", limit: 12, default: "", null: false
    t.string "token", null: false
    t.string "type", null: false
    t.index ["reference_id", "type"], name: "ref_type", unique: true
  end

  create_table "txp_users", primary_key: "user_id", force: :cascade do |t|
    t.string "RealName", default: "", null: false
    t.string "email", limit: 254, default: "", null: false
    t.datetime "last_access", precision: 0
    t.string "name", limit: 64, default: "", null: false
    t.string "nonce", limit: 64, default: "", null: false
    t.string "pass", limit: 128, null: false
    t.integer "privs", default: 1, null: false
    t.index ["name"], name: "name", unique: true
  end
end
