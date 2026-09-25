# Images (txp_image). Files live in public/<img_dir>/<id><ext>.
class Image < ApplicationRecord
  self.table_name = "txp_image"

  validates :name, presence: true

  before_validation { self.date ||= Time.now.utc.change(usec: 0) }
  after_destroy :remove_files

  def path(thumbnail: false)
    Txp::Images.path(id, ext, thumbnail: thumbnail)
  end

  def url(thumbnail: false)
    "/#{Pref.get('img_dir', 'images')}/#{id}#{thumbnail ? 't' : ''}#{ext}"
  end

  def thumbnail?
    thumbnail.to_i == 1 && File.exist?(path(thumbnail: true))
  end

  # Stores an uploaded file for this image.
  def store_upload(upload)
    ext = File.extname(upload.original_filename.to_s).downcase
    ext = ".jpg" if ext == ".jpeg"
    raise ArgumentError, "unsupported" unless Txp::Images::SAFE_TYPES.key?(ext)

    self.ext = ext
    self.name = upload.original_filename.to_s if name.blank?
    save! if new_record?
    FileUtils.mkdir_p(File.dirname(path))
    FileUtils.cp(upload.path, path)
    FileUtils.chmod(0o644, path)
    w, h = Txp::Images.dimensions(path)
    update!(w: w.to_i, h: h.to_i, date: Time.now.utc.change(usec: 0))
    remove_auto_thumbnails
    self
  end

  def create_thumbnail(width: nil, height: nil, crop: false)
    dims = Txp::Images.resize(path, path(thumbnail: true), width: width, height: height, crop: crop ? "1x1" : nil)
    return false unless dims

    update!(thumbnail: 1, thumb_w: dims[0], thumb_h: dims[1])
  end

  def store_thumbnail(upload)
    FileUtils.cp(upload.path, path(thumbnail: true))
    w, h = Txp::Images.dimensions(path(thumbnail: true))
    update!(thumbnail: 1, thumb_w: w.to_i, thumb_h: h.to_i)
  end

  def delete_thumbnail
    FileUtils.rm_f(path(thumbnail: true))
    update!(thumbnail: 0, thumb_w: 0, thumb_h: 0)
  end

  def remove_auto_thumbnails
    Dir[Txp::Images.dir.join("thumb", "*", "#{id}.*")].each { |f| FileUtils.rm_f(f) }
  end

  private

  def remove_files
    FileUtils.rm_f(path)
    FileUtils.rm_f(path(thumbnail: true))
    remove_auto_thumbnails
  end
end
