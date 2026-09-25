require "rubygems/package"
require "zlib"

module Txp
  # Site backups (bin/rails txp:backup and txp:restore): one .tar.gz with a
  # consistent copy of the SQLite database, made with VACUUM INTO while the
  # site keeps running, and the uploaded files, images and exported themes.
  module Backup
    module_function

    DATABASE = "database.sqlite3".freeze
    DIRECTORIES = %w[files images themes].freeze
    PATTERN = "txp-*.tar.gz".freeze

    # The site's directories, by their name in the archive.
    def directories(prefs = Pref.site_prefs)
      DIRECTORIES.zip([ TxpFile.base_path, Images.dir(prefs), ThemeIO.skin_dir(prefs) ]).to_h
    end

    def database_path
      Rails.root.join(ActiveRecord::Base.connection_db_config.database.to_s)
    end

    # Writes <dir>/txp-<UTC time>.tar.gz and keeps the newest `keep` backups
    # (all of them with keep: nil).
    def create(dir, keep: 7)
      dir = Pathname.new(dir)
      FileUtils.mkdir_p(dir)
      archive = dir.join("txp-#{Time.now.utc.strftime('%Y%m%d-%H%M%S-%L')}.tar.gz")

      Dir.mktmpdir("txp-backup") do |tmp|
        copy = File.join(tmp, DATABASE)
        ActiveRecord::Base.with_connection { |db| db.execute("VACUUM INTO #{db.quote(copy)}") }
        Zlib::GzipWriter.open(archive.to_s) do |gz|
          Gem::Package::TarWriter.new(gz) do |tar|
            add_file(tar, DATABASE, copy)
            directories.each { |name, path| add_directory(tar, name, Pathname.new(path)) }
          end
        end
      end

      Dir[dir.join(PATTERN).to_s].sort.reverse.drop([ keep, 1 ].max).each { |old| FileUtils.rm_f(old) } if keep
      archive
    end

    # Puts back the database, then the directories where the restored
    # preferences say they are. The site must be stopped.
    def restore(archive)
      Dir.mktmpdir("txp-restore") do |tmp|
        extract(archive, tmp)
        database = File.join(tmp, DATABASE)
        raise ArgumentError, "#{archive} has no #{DATABASE}" unless File.file?(database)

        target = database_path
        ActiveRecord::Base.connection_handler.clear_all_connections!
        FileUtils.cp(database, "#{target}.restore")
        FileUtils.rm_f([ "#{target}-wal", "#{target}-shm" ])
        File.rename("#{target}.restore", target)

        directories.each do |name, path|
          source = File.join(tmp, name)
          next unless File.directory?(source)

          FileUtils.mkdir_p(path)
          FileUtils.rm_rf(Dir.children(path).map { |child| File.join(path, child) })
          FileUtils.cp_r(Dir.children(source).map { |child| File.join(source, child) }, path)
        end
      end
    end

    def add_file(tar, name, path)
      tar.add_file_simple(name, File.stat(path).mode & 0o777, File.size(path)) do |io|
        File.open(path, "rb") { |file| IO.copy_stream(file, io) }
      end
    end

    def add_directory(tar, name, path)
      return unless path.directory?

      tar.mkdir(name, 0o755)
      path.children.sort.each do |child|
        next if child.symlink?

        child.directory? ? add_directory(tar, "#{name}/#{child.basename}", child) : add_file(tar, "#{name}/#{child.basename}", child)
      end
    end

    # Unpacks only the database and the known directories, never outside tmp.
    def extract(archive, tmp)
      Zlib::GzipReader.open(archive.to_s) do |gz|
        Gem::Package::TarReader.new(gz) do |tar|
          tar.each do |entry|
            name = entry.full_name.delete_prefix("./")
            parts = name.split("/")
            next unless name == DATABASE || DIRECTORIES.include?(parts.first)
            raise ArgumentError, "unsafe path in #{archive}: #{name}" if parts.include?("..") || name.start_with?("/")

            dest = File.join(tmp, name)
            if entry.directory?
              FileUtils.mkdir_p(dest)
            elsif entry.file?
              FileUtils.mkdir_p(File.dirname(dest))
              File.open(dest, "wb") { |file| IO.copy_stream(entry, file) }
            end
          end
        end
      end
    end
  end
end
