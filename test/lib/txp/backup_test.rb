require "test_helper"
require "rake"

class Txp::BackupTest < ActiveSupport::TestCase
  # VACUUM INTO cannot run inside the transaction of a transactional test.
  self.use_transactional_tests = false

  setup do
    TxpTestSite.install!
    @tmp = Pathname.new(Dir.mktmpdir("txp-backup-test"))
    @dirs = %w[files images themes].to_h { |name| [ name, @tmp.join(name) ] }
    @dirs.each_value { |dir| FileUtils.mkdir_p(dir) }
    File.write(@dirs["files"].join("notes.txt"), "notes\n")
    File.write(@dirs["images"].join("1.png"), "png")
    FileUtils.mkdir_p(@dirs["themes"].join("mine"))
    File.write(@dirs["themes"].join("mine", "manifest.json"), "{}")
    dirs = @dirs
    @directories = Txp::Backup.method(:directories)
    Txp::Backup.define_singleton_method(:directories) { |*| dirs }
  end

  teardown do
    Txp::Backup.define_singleton_method(:directories, @directories)
    FileUtils.rm_rf(@tmp)
    ActiveRecord::Base.with_connection { |db| db.truncate_tables(*db.tables) }
  end

  def entries(archive)
    Zlib::GzipReader.open(archive.to_s) { |gz| Gem::Package::TarReader.new(gz).map(&:full_name) }
  end

  test "a backup has a working copy of the database and the site's directories" do
    archive = Txp::Backup.create(@tmp.join("backups"))
    assert_match(/\Atxp-\d{8}-\d{6}-\d{3}\.tar\.gz\z/, archive.basename.to_s)
    assert_equal %w[database.sqlite3 files files/notes.txt images images/1.png themes themes/mine themes/mine/manifest.json], entries(archive).sort

    Dir.mktmpdir do |dir|
      Txp::Backup.extract(archive, dir)
      copy = SQLite3::Database.new(File.join(dir, "database.sqlite3"))
      assert_equal Article.count, copy.get_first_value("SELECT COUNT(*) FROM textpattern")
      copy.close
    end
  end

  test "restoring puts the database and the directories back" do
    archive = Txp::Backup.create(@tmp.join("backups"))
    Article.where(url_title: "first").delete_all
    File.delete(@dirs["files"].join("notes.txt"))
    File.write(@dirs["images"].join("2.png"), "new")

    Txp::Backup.restore(archive)
    assert Article.exists?(url_title: "first")
    assert_equal "notes\n", File.read(@dirs["files"].join("notes.txt"))
    assert_not File.exist?(@dirs["images"].join("2.png"))
  end

  test "only the newest backups are kept" do
    dir = @tmp.join("backups")
    FileUtils.mkdir_p(dir)
    %w[20200101 20200102 20200103].each { |day| FileUtils.touch(dir.join("txp-#{day}-000000-000.tar.gz")) }
    newest = Txp::Backup.create(dir, keep: 2)
    assert_equal [ newest.basename.to_s, "txp-20200103-000000-000.tar.gz" ].sort, Dir.children(dir).sort
  end

  test "archives reaching outside the site are refused" do
    evil = @tmp.join("evil.tar.gz")
    Zlib::GzipWriter.open(evil.to_s) do |gz|
      Gem::Package::TarWriter.new(gz) { |tar| tar.add_file_simple("files/../../evil.txt", 0o644, 4) { |io| io.write("evil") } }
    end
    assert_raises(ArgumentError) { Txp::Backup.restore(evil) }
    assert_not File.exist?(@tmp.join("evil.txt"))
    assert Article.exists?
  end

  test "the rake tasks back up and restore" do
    Rails.application.load_tasks unless Rake::Task.task_defined?("txp:backup")
    ENV["BACKUP_DIR"] = @tmp.join("backups").to_s
    out, = capture_io { Rake::Task["txp:backup"].execute }
    archive = out.strip
    assert File.file?(archive)

    Article.delete_all
    ENV["FILE"] = archive
    out, = capture_io { Rake::Task["txp:restore"].execute }
    assert_includes out, "Restored #{archive}"
    assert Article.exists?
    assert_equal 2, Dir.children(ENV["BACKUP_DIR"]).size
  ensure
    ENV.delete("BACKUP_DIR")
    ENV.delete("FILE")
  end
end
