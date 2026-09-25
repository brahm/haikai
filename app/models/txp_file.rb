# Downloadable files (txp_file). Stored in the file_base_path directory.
class TxpFile < ApplicationRecord
  self.table_name = "txp_file"

  validates :filename, presence: true, uniqueness: true

  before_validation do
    now = Time.now.utc.change(usec: 0)
    self.created ||= now
    self.modified ||= now
  end
  after_destroy { FileUtils.rm_f(path) }

  def self.base_path
    dir = Pref.get("file_base_path").presence
    path = dir ? Pathname.new(dir) : Rails.root.join("files")
    FileUtils.mkdir_p(path)
    path
  end

  def path
    self.class.base_path.join(Txp::Text.sanitize_for_file(filename))
  end

  def exists?
    File.file?(path)
  end

  def store_upload(upload, name: nil)
    self.filename = Txp::Text.sanitize_for_file(name.presence || upload.original_filename.to_s)
    FileUtils.cp(upload.path, path)
    self.size = File.size(path)
    self.modified = Time.now.utc.change(usec: 0)
    save!
  end
end
