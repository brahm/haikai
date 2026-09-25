namespace :txp do
  desc "Back up the database, files, images and themes (BACKUP_DIR, default storage/backups; BACKUP_KEEP, default 7)"
  task backup: :environment do
    dir = ENV["BACKUP_DIR"].presence || Rails.root.join("storage", "backups")
    puts Txp::Backup.create(dir, keep: Integer(ENV.fetch("BACKUP_KEEP", 7)))
  end

  desc "Restore a backup made by txp:backup (FILE=...), after saving the current site; stop the site first"
  task restore: :environment do
    file = ENV["FILE"].presence or abort "Usage: bin/rails txp:restore FILE=storage/backups/txp-<time>.tar.gz"
    abort "#{file} not found" unless File.file?(file)

    dir = ENV["BACKUP_DIR"].presence || Rails.root.join("storage", "backups")
    # Without pruning, which could remove the very backup being restored.
    puts "Current site saved in #{Txp::Backup.create(dir, keep: nil)}"
    Txp::Backup.restore(file)
    puts "Restored #{file}"
  end
end
