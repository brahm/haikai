require "test_helper"

# /images/thumb/<params>/<id><ext>: automatic thumbnails made with ImageMagick.
class ThumbnailsTest < ActionDispatch::IntegrationTest
  setup do
    skip "ImageMagick is not installed" unless Txp::Images.magick

    TxpTestSite.install!
    # Keep image files out of public/images.
    @dir = Pathname.new(Dir.mktmpdir)
    @images_dir = Txp::Images.method(:dir)
    dir = @dir
    Txp::Images.define_singleton_method(:dir) { |*| dir }

    @image = Image.create!(name: "red.png", ext: ".png", w: 64, h: 48, alt: "", category: "")
    system(Txp::Images.magick, "-size", "64x48", "xc:red", @image.path.to_s, exception: true)
    @paramlist = Txp::Thumbnails.encode("w" => 16)
  end

  teardown do
    Txp::Images.define_singleton_method(:dir, @images_dir) if @images_dir
    FileUtils.rm_rf(@dir) if @dir
  end

  def thumb_url(file, token: Txp::Thumbnails.token(@image.id.to_s, @paramlist, Pref.site_prefs))
    "/images/thumb/#{@paramlist}/#{file}?token=#{token}"
  end

  def thumbnails
    Dir[@dir.join("thumb", "**", "*")].select { |f| File.file?(f) }
  end

  test "a thumbnail is made in the image's type" do
    get thumb_url("#{@image.id}.png")
    assert_response :success
    assert_equal "image/png", response.media_type
    assert_equal [ @dir.join("thumb", @paramlist, "#{@image.id}.png").to_s ], thumbnails
    assert_equal [ 16, 12 ], Txp::Images.dimensions(thumbnails.first)
  end

  test "thumbnails need a valid token" do
    get thumb_url("#{@image.id}.png", token: "0" * 64)
    assert_response :forbidden
    assert_empty thumbnails
  end

  test "the file name cannot pick another type" do
    # The token covers the image id and the parameters, not the extension:
    # ImageMagick would write .html, .svg... files into public/images/thumb.
    %w[html svg txt gif].each do |ext|
      get thumb_url("#{@image.id}.#{ext}")
      assert_response :not_found
    end
    assert_empty thumbnails
  end

  test "the t parameter converts to another image type" do
    @paramlist = Txp::Thumbnails.encode("w" => 16, "t" => "gif")
    get thumb_url("#{@image.id}.gif")
    assert_response :success
    assert_equal "image/gif", response.media_type

    get thumb_url("#{@image.id}.png")
    assert_response :not_found
  end
end
