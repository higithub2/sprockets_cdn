require 'sprockets_cdn_test'
require 'fileutils'
require 'tmpdir'
require 'securerandom'
require 'pry'
class TestManifest < SprocketsCDN::TestCase
  def setup
    @env = Sprockets::Environment.new(".") do |env|
      env.append_path(fixture_path('default'))
    end
    @dir = File.join(Dir::tmpdir, 'sprockets/manifest')
    @asset_host = Spro
    FileUtils.mkdir_p(@dir)
    SprocketsCDN.config do |config|
      config.adapter = 'qiniu'
      # config.access_key = "xx"
      # config.secret_key = "xxx"
      config.bucket = "sprockets"
      config.asset_host = "http://xxx.0.glb.clouddn.com"
    end
  end

  def teardown
    # FileUtils.rm_rf(@dir)
    # wtf, dunno
    system "rm -rf #{@dir}"
    assert Dir["#{@dir}/*"].empty?
  end

  test "compile asset" do
    manifest = Sprockets::Manifest.new(@env, File.join(@dir, 'manifest.json'))

    digest_path = @env['application.js'].digest_path

    assert !File.exist?("#{@dir}/#{digest_path}")

    manifest.compile('application.js')
    assert File.directory?(manifest.directory)
    assert File.file?(manifest.filename)

    assert File.exist?("#{@dir}/manifest.json")
    assert File.exist?("#{@dir}/#{digest_path}")

    data = JSON.parse(File.read(manifest.filename))
    assert data['files'][digest_path]
    assert_equal "application.js", data['files'][digest_path]['logical_path']
    assert data['files'][digest_path]['size'] > 230
    assert_equal digest_path, data['assets']['application.js']
    # binding.pry
    assert_equal data['assets'].keys, manifest.remote_data.keys
  end

  test "compile to directory and seperate location" do
    manifest = Sprockets::Manifest.new(@env, File.join(@dir, 'manifest.json'))

    root  = File.join(Dir::tmpdir, 'public')
    dir   = File.join(root, 'assets')
    path  = File.join(root, 'manifests', 'manifest-123.json')

    system "rm -rf #{root}"
    assert !File.exist?(root)

    manifest = Sprockets::Manifest.new(@env, dir, path)

    manifest.compile('application.js')
    assert File.directory?(manifest.directory)
    assert File.file?(manifest.filename)
  end

  test "compile with legacy manifest" do
    root  = File.join(Dir::tmpdir, 'public')
    dir   = File.join(root, 'assets')
    path  = File.join(root, "manifest-#{SecureRandom.hex(16)}.json")

    system "rm -rf #{root}"
    assert !File.exist?(root)

    system "rm -rf #{dir}/.sprockets-manifest*.json"
    system "rm -rf #{dir}/manifest*.json"
    FileUtils.mkdir_p(dir)
    File.open(path, 'w') { |f| f.write "{}" }

    manifest = Sprockets::Manifest.new(@env, dir)

    manifest.compile('application.js')
    assert File.directory?(manifest.directory)
    assert File.file?(manifest.filename)
    assert_match %r{.sprockets-manifest-[a-f0-9]{32}.json}, manifest.filename
  end

  test "compile asset with absolute path" do
    manifest = Sprockets::Manifest.new(@env, File.join(@dir, 'manifest.json'))

    digest_path = @env['gallery.js'].digest_path

    assert !File.exist?("#{@dir}/#{digest_path}")

    manifest.compile(fixture_path('default/gallery.js'))

    assert File.exist?("#{@dir}/manifest.json")
    assert File.exist?("#{@dir}/#{digest_path}")

    data = JSON.parse(File.read(manifest.filename))
    assert data['files'][digest_path]
    assert_equal digest_path, data['assets']['gallery.js']
  end

  test "compile multiple assets" do
    manifest = Sprockets::Manifest.new(@env, File.join(@dir, 'manifest.json'))

    app_digest_path = @env['application.js'].digest_path
    gallery_digest_path = @env['gallery.css'].digest_path

    assert !File.exist?("#{@dir}/#{app_digest_path}")
    assert !File.exist?("#{@dir}/#{gallery_digest_path}")

    manifest.compile('application.js', 'gallery.css')

    assert File.exist?("#{@dir}/manifest.json")
    assert File.exist?("#{@dir}/#{app_digest_path}")
    assert File.exist?("#{@dir}/#{gallery_digest_path}")

    data = JSON.parse(File.read(manifest.filename))
    assert data['files'][app_digest_path]
    assert data['files'][gallery_digest_path]
    assert_equal app_digest_path, data['assets']['application.js']
    assert_equal gallery_digest_path, data['assets']['gallery.css']
  end

  test "compile with transformed asset" do
    assert svg_digest_path = @env['logo.svg'].digest_path
    assert png_digest_path = @env['logo.png'].digest_path

    assert !File.exist?("#{@dir}/#{svg_digest_path}")
    assert !File.exist?("#{@dir}/#{png_digest_path}")

    manifest = Sprockets::Manifest.new(@env, File.join(@dir, 'manifest.json'))
    manifest.compile('logo.svg', 'logo.png')

    assert File.exist?("#{@dir}/manifest.json")
    assert File.exist?("#{@dir}/#{svg_digest_path}")
    assert File.exist?("#{@dir}/#{png_digest_path}")

    data = JSON.parse(File.read(manifest.filename))
    assert data['files'][svg_digest_path]
    assert data['files'][png_digest_path]
    assert_equal svg_digest_path, data['assets']['logo.svg']
    assert_equal png_digest_path, data['assets']['logo.png']
  end

  test "compile asset with links" do
    manifest = Sprockets::Manifest.new(@env, File.join(@dir, 'manifest.json'))

    main_digest_path = @env['gallery-link.js'].digest_path
    dep_digest_path  = @env['gallery.js'].digest_path

    assert !File.exist?("#{@dir}/#{main_digest_path}")
    assert !File.exist?("#{@dir}/#{dep_digest_path}")

    manifest.compile('gallery-link.js')
    assert File.directory?(manifest.directory)
    assert File.file?(manifest.filename)

    assert File.exist?("#{@dir}/manifest.json")
    assert File.exist?("#{@dir}/#{main_digest_path}")
    assert File.exist?("#{@dir}/#{dep_digest_path}")

    data = JSON.parse(File.read(manifest.filename))
    assert data['files'][main_digest_path]
    assert data['files'][dep_digest_path]
    assert_equal "gallery-link.js", data['files'][main_digest_path]['logical_path']
    assert_equal "gallery.js", data['files'][dep_digest_path]['logical_path']
    assert_equal main_digest_path, data['assets']['gallery-link.js']
    assert_equal dep_digest_path, data['assets']['gallery.js']
  end

  test "compile nested asset with links" do
    manifest = Sprockets::Manifest.new(@env, File.join(@dir, 'manifest.json'))

    main_digest_path   = @env['explore-link.js'].digest_path
    dep_digest_path    = @env['gallery-link.js'].digest_path
    subdep_digest_path = @env['gallery.js'].digest_path

    assert !File.exist?("#{@dir}/#{main_digest_path}")
    assert !File.exist?("#{@dir}/#{dep_digest_path}")
    assert !File.exist?("#{@dir}/#{subdep_digest_path}")

    manifest.compile('explore-link.js')
    assert File.directory?(manifest.directory)
    assert File.file?(manifest.filename)

    assert File.exist?("#{@dir}/manifest.json")
    assert File.exist?("#{@dir}/#{main_digest_path}")
    assert File.exist?("#{@dir}/#{dep_digest_path}")
    assert File.exist?("#{@dir}/#{subdep_digest_path}")

    data = JSON.parse(File.read(manifest.filename))
    assert data['files'][main_digest_path]
    assert data['files'][dep_digest_path]
    assert data['files'][subdep_digest_path]
    assert_equal "explore-link.js", data['files'][main_digest_path]['logical_path']
    assert_equal "gallery-link.js", data['files'][dep_digest_path]['logical_path']
    assert_equal "gallery.js", data['files'][subdep_digest_path]['logical_path']
    assert_equal main_digest_path, data['assets']['explore-link.js']
    assert_equal dep_digest_path, data['assets']['gallery-link.js']
    assert_equal subdep_digest_path, data['assets']['gallery.js']
  end

  test "recompile asset" do
    manifest = Sprockets::Manifest.new(@env, File.join(@dir, 'manifest.json'))

    digest_path = @env['application.js'].digest_path
    filename = fixture_path('default/application.coffee')

    sandbox filename do
      assert !File.exist?("#{@dir}/#{digest_path}"), Dir["#{@dir}/*"].inspect

      manifest.compile('application.js')

      assert File.exist?("#{@dir}/manifest.json")
      assert File.exist?("#{@dir}/#{digest_path}")

      data = JSON.parse(File.read(manifest.filename))
      assert data['files'][digest_path]
      assert_equal digest_path, data['assets']['application.js']

      File.open(filename, 'w') { |f| f.write "change;" }
      mtime = Time.now + 1
      File.utime(mtime, mtime, filename)
      new_digest_path = @env['application.js'].digest_path

      manifest.compile('application.js')

      assert File.exist?("#{@dir}/manifest.json")
      assert File.exist?("#{@dir}/#{digest_path}")
      assert File.exist?("#{@dir}/#{new_digest_path}")

      data = JSON.parse(File.read(manifest.filename))
      assert data['files'][digest_path]
      assert data['files'][new_digest_path]
      assert_equal new_digest_path, data['assets']['application.js']
    end
  end

  test "remove asset" do
    manifest = Sprockets::Manifest.new(@env, @dir)

    digest_path = @env['application.js'].digest_path

    manifest.compile('application.js')
    assert File.exist?("#{@dir}/#{digest_path}")

    data = JSON.parse(File.read(manifest.filename))
    assert data['files'][digest_path]
    assert data['assets']['application.js']

    manifest.remove(digest_path)

    assert !File.exist?("#{@dir}/#{digest_path}")

    data = JSON.parse(File.read(manifest.filename))
    assert !data['files'][digest_path]
    assert !data['assets']['application.js']
  end

  test "remove old asset" do
    manifest = Sprockets::Manifest.new(@env, @dir)

    digest_path = @env['application.js'].digest_path
    filename = fixture_path('default/application.coffee')

    sandbox filename do
      manifest.compile('application.js')
      assert File.exist?("#{@dir}/#{digest_path}")

      File.open(filename, 'w') { |f| f.write "change;" }
      mtime = Time.now + 1
      File.utime(mtime, mtime, filename)
      new_digest_path = @env['application.js'].digest_path

      manifest.compile('application.js')
      assert File.exist?("#{@dir}/#{new_digest_path}")

      manifest.remove(digest_path)
      assert !File.exist?("#{@dir}/#{digest_path}")

      data = JSON.parse(File.read(manifest.filename))
      assert !data['files'][digest_path]
      assert data['files'][new_digest_path]
      assert_equal new_digest_path, data['assets']['application.js']
    end
  end

  test "remove old backups(count)" do
    manifest = Sprockets::Manifest.new(@env, @dir)

    digest_path = @env['application.js'].digest_path
    filename = fixture_path('default/application.coffee')

    sandbox filename do
      manifest.compile('application.js')
      assert File.exist?("#{@dir}/#{digest_path}")

      File.open(filename, 'w') { |f| f.write "a;" }
      mtime = Time.now + 1
      File.utime(mtime, mtime, filename)
      new_digest_path1 = @env['application.js'].digest_path

      manifest.compile('application.js')
      assert File.exist?("#{@dir}/#{new_digest_path1}")

      File.open(filename, 'w') { |f| f.write "b;" }
      mtime = Time.now + 2
      File.utime(mtime, mtime, filename)
      new_digest_path2 = @env['application.js'].digest_path

      manifest.compile('application.js')
      assert File.exist?("#{@dir}/#{new_digest_path2}")

      File.open(filename, 'w') { |f| f.write "c;" }
      mtime = Time.now + 3
      File.utime(mtime, mtime, filename)
      new_digest_path3 = @env['application.js'].digest_path

      manifest.compile('application.js')
      assert File.exist?("#{@dir}/#{new_digest_path3}")

      manifest.clean(1, 0)

      assert !File.exist?("#{@dir}/#{digest_path}")
      assert !File.exist?("#{@dir}/#{new_digest_path1}")
      assert File.exist?("#{@dir}/#{new_digest_path2}")
      assert File.exist?("#{@dir}/#{new_digest_path3}")

      data = JSON.parse(File.read(manifest.filename))
      assert !data['files'][digest_path]
      assert !data['files'][new_digest_path1]
      assert data['files'][new_digest_path2]
      assert data['files'][new_digest_path3]
      assert_equal new_digest_path3, data['assets']['application.js']
    end
  end

  test "test manifest does not exist" do
    assert !File.exist?("#{@dir}/manifest.json")

    manifest = Sprockets::Manifest.new(@env, File.join(@dir, 'manifest.json'))
    manifest.compile('application.js')

    assert File.exist?("#{@dir}/manifest.json")
    data = JSON.parse(File.read(manifest.filename))
    assert data['assets']['application.js']
  end

  test "test blank manifest" do
    assert !File.exist?("#{@dir}/manifest.json")

    FileUtils.mkdir_p(@dir)
    File.open("#{@dir}/manifest.json", 'w') { |f| f.write "" }
    assert_equal "", File.read("#{@dir}/manifest.json")

    manifest = Sprockets::Manifest.new(@env, File.join(@dir, 'manifest.json'))
    manifest.compile('application.js')

    assert File.exist?("#{@dir}/manifest.json")
    data = JSON.parse(File.read(manifest.filename))
    assert data['assets']['application.js']
  end

  test "test skip invalid manifest" do
    assert !File.exist?("#{@dir}/manifest.json")

    FileUtils.mkdir_p(@dir)
    File.open("#{@dir}/manifest.json", 'w') { |f| f.write "not valid json;" }
    assert_equal "not valid json;", File.read("#{@dir}/manifest.json")

    manifest = Sprockets::Manifest.new(@env, File.join(@dir, 'manifest.json'))
    manifest.compile('application.js')

    assert File.exist?("#{@dir}/manifest.json")
    data = JSON.parse(File.read(manifest.filename))
    assert data['assets']['application.js']
  end

  test "nil environment raises compilation error" do
    assert !File.exist?("#{@dir}/manifest.json")

    manifest = Sprockets::Manifest.new(nil, File.join(@dir, 'manifest.json'))
    assert_raises Sprockets::Error do
      manifest.compile('application.js')
    end
  end

  test "no environment raises compilation error" do
    assert !File.exist?("#{@dir}/manifest.json")

    manifest = Sprockets::Manifest.new(File.join(@dir, 'manifest.json'))
    assert_raises Sprockets::Error do
      manifest.compile('application.js')
    end
  end
end
