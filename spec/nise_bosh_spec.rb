require 'logger'
require "nise_bosh"
require 'yaml'

require 'spec_helper'

describe NiseBosh do
  before do
    @tmp_dir = File.join(%w[/tmp nise_bosh_spec])
    @options = {
      :repo_dir => File.join(File.expand_path("."), "spec", "assets", "release"),
      :install_dir => File.join(@tmp_dir, "install"),
      :deploy_config => File.join(File.expand_path("."), "spec", "assets", "deploy.conf"),
      :working_dir => File.join(@tmp_dir, "working"),
    }
    @log = Logger.new("/dev/null")

    @package = "miku"
    @package_installed_file = File.join( @options[:install_dir], "packages", @package, "dayo")
    @package_installed_file_contents = "miku 39\n"
    @src_file_nonglob = ["miku/file"]
    @src_file_glob = ["variant/haku/file", "variant/neru/file"]
    @src_file = @src_file_nonglob + @src_file_glob

    setup_directory(@options[:working_dir])
    setup_directory(@options[:install_dir])

    @nb = NiseBosh.new(@options, @log)
    @current_ip = current_ip()
  end

  describe "#new" do
    it "should not raise an error when repo_dir exists" do
      expect { NiseBosh.new(@options, @log) }.to_not raise_error
    end

    it "should raise an error when repo_dir does not exist" do
      @options[:repo_dir] = "/not/exist"
      expect { NiseBosh.new(@options, @log) }.to raise_error
    end

    it "should raise an error when repo_dir does have no release index" do
      expect do
        NiseBosh.new(@options.merge({:repo_dir => File.join(File.expand_path("."), "spec", "assets", "release_noindex")}), @log)
      end.to raise_error("No release index found!\nTry `bosh cleate release` in your release repository.")
    end
  end

  describe "#setup_working_directory" do
    it "should copy files from the archive" do
      @nb.setup_working_directory(@package)
      expect(Dir.glob(File.join(@options[:working_dir], "**/*")).sort.reject {|f| File.directory?(f) })
        .to eq((@src_file << "packaging").sort.map {|v| File.join(@options[:working_dir], v) })
    end
  end

  describe "#run_packaging" do
    it "should create the install directory and run the packaging script" do
      @nb.setup_working_directory(@package)
      @nb.run_packaging(@package)
      expect_contents(@package_installed_file).to eq(@package_installed_file_contents)
    end

    it "should raise an error when packaging script fails" do
      @nb.setup_working_directory("fail_packaging")
      expect { @nb.run_packaging("fail_packaging") }.to raise_error
    end
  end

  describe "#resolve_dependency" do
    it "should resolve linear dependencies" do
      expect(@nb.resolve_dependency(%w{tako kaito})).to eq(%w{miku luca tako kaito})
    end

    it "should resolve part-and-rejoin dependencies" do
      expect(@nb.resolve_dependency(%w{meiko})).to eq(%w{miku luca tako meiko})
    end

    it "should raise an error when detects a cyclic dependency" do
      expect { @nb.resolve_dependency(%w{ren}) }.to raise_error
    end
  end

  describe "#install_package" do
    let(:version_file) { File.join(@options[:install_dir], "packages", @package, ".version") }

    it "should install the given package" do
      @nb.install_package(@package)
      expect_contents(@package_installed_file).to eq(@package_installed_file_contents)
      expect_contents(version_file).to eq("39\n")
    end

    it "should not install the given package when the package is already installed" do
      @nb.install_package(@package)
      expect_contents(@package_installed_file).to eq(@package_installed_file_contents)
      expect_contents(version_file).to eq("39\n")
      FileUtils.rm_rf(@package_installed_file)
      expect_file_exists(@package_installed_file).to be_false
      @nb.install_package(@package)
      expect_file_exists(@package_installed_file).to be_false
      expect_contents(version_file).to eq("39\n")
    end

    it "should install the given package even if the package is already installed when force_compile option is true" do
      @nb.install_package(@package)
      expect_contents(@package_installed_file).to eq(@package_installed_file_contents)
      expect_contents(version_file).to eq("39\n")
      FileUtils.rm_rf(@package_installed_file)
      expect_file_exists(@package_installed_file).to be_false
      force_nb = NiseBosh.new(@options.merge({:force_compile => true}), @log)
      force_nb.install_package(@package)
      expect_contents(@package_installed_file).to eq(@package_installed_file_contents)
      expect_contents(version_file).to eq("39\n")
    end

    it "delete the version file before start packaging" do
      @nb.install_package(@package)
      expect_contents(version_file).to eq("39\n")
      expect do
        fail_while_packaging_nb = NiseBosh.new(@options.merge({:working_dir => nil, :force_compile => true}), @log)
        fail_while_packaging_nb.install_package(@package)
      end.to raise_error
      expect_file_exists(version_file).to be_false
    end
  end

  describe "#install_packages" do
    let(:packages) { %w{meiko kaito tako} }
    let(:related_packages) { %w{luca} }

    it "should install all related packages" do
      @nb.install_packages(packages)
      (packages + related_packages).each do |package|
        expect_contents(@options[:install_dir], "packages", package, "dayo").to eq("tenshi\n")
      end
      expect_contents(@package_installed_file).to eq(@package_installed_file_contents)
    end

    it "should install only given packages when given no_dependency" do
      @nb.install_packages(packages, true)
      packages.each do |package|
        expect_contents(@options[:install_dir], "packages", package, "dayo").to eq("tenshi\n")
      end
      related_packages do |package|
        expect_file_exists(@options[:install_dir], "packages", package).to be_false
      end
    end
  end

  describe "#write_template" do
    before do
      @spec = YAML.load_file(File.join(@options[:repo_dir], "jobs", "angel", "spec"))
      @config_template = File.join(@options[:repo_dir], "jobs", "angel", "templates", @spec["templates"].keys[0])
      @config_write_to =  File.join(@options[:install_dir], "jobs", "angel",  @spec["templates"].values[0])
      @bin_template = File.join(@options[:repo_dir], "jobs", "angel", "templates", @spec["templates"].keys[1])
      @bin_write_to =  File.join(@options[:install_dir], "jobs", "angel",  @spec["templates"].values[1])
    end

    it "should fill template and save file" do
      @nb.write_template(@spec, @config_template, @config_write_to)
      expect_contents(@config_write_to).to eq("tenshi\n0\n#{@current_ip}\n")
    end

    it "should fill template with given IP address and index number, and save file" do
      @nb = NiseBosh.new(@options.merge({:ip_address => "39.39.39.39", :index => 39}), @log)
      @nb.write_template(@spec, @config_template, @config_write_to)
      expect_contents(@config_write_to).to eq("tenshi\n39\n39.39.39.39\n")
    end

    it "should fill template with given spec.index in deploy file, and save file" do
      @nb = NiseBosh.new(@options.merge({:deploy_config => File.join(File.expand_path("."), "spec", "assets", "deploy_overwrite_spec.conf")}), @log)
      @nb.write_template(@spec, @config_template, @config_write_to)
      expect_contents(@config_write_to).to eq("tenshi\n39\n#{@current_ip}\n")
    end

    it "should chmod 0755 when the file is in 'bin' directory" do
      @nb.write_template(@spec, @bin_template, @bin_write_to)
      expect_file_mode(@bin_write_to).to eq(0100755)
    end

    it "should raise an error when template not found" do
      expect do
        @nb.write_template(YAML.load_file(File.join(@options[:repo_dir], "jobs", "missing_template_spec", "spec")))
      end.to raise_error
    end
  end

  describe "#install_job" do
    def check_templates
      expect_contents(@options[:install_dir], "jobs", "angel", "config", "miku.conf")
        .to eq("tenshi\n0\n#{@current_ip}\n")
      expect_contents(@options[:install_dir], "bosh", "etc", "monitrc")
        .to eq("monit\n")
      expect_directory_exists(@options[:install_dir], "data", "packages").to be_true
    end

    it "should install packags and generate required files from template files" do
      @nb.install_job("angel")
      expect_contents(@options[:install_dir], "packages", "miku", "dayo").to eq("miku 39\n")
      expect_contents(@options[:install_dir], "packages", "luca", "dayo").to eq("tenshi\n")
      check_templates
    end

    it "should not install packags and only generate required files from template files when template_only given" do
      @nb.install_job("angel", true)
      expect_file_exists(@options[:install_dir], "packages", "miku", "dayo").to be_false
      expect_file_exists(@options[:install_dir], "packages", "luca", "dayo").to be_false
      check_templates
    end

    it "should run post install hook" do
      @nb.should_receive(:run_post_install_hook).with("angel")
      @nb.install_job("angel", true)
    end
  end

  describe "#run_post_install_hook" do
    let(:post_install_hook_path) { File.join(@options[:install_dir], "jobs", "miku", "bin", "post_install") }

    before do
      if defined?(post_install)
        FileUtils.mkdir_p(File.dirname(post_install_hook_path))
        open(post_install_hook_path, "w") do |io|
          io.write post_install
        end
        File.chmod(0755, post_install_hook_path)
      end
    end
    
    after do
      File.delete(post_install_hook_path) if File.exist?(post_install_hook_path)
    end

    context "when bin/post_install file exist" do
      let(:post_install) { "#!/bin/sh\necho ha ore no yome" }

      it "should run post install hook" do
        expect(File.executable?(post_install_hook_path)).to be_true
        expect(@nb.run_post_install_hook("miku")).to eq("ha ore no yome\n")
      end
    end

    context "when post_install file not exist" do
      it "should not run anything" do
        expect(File.exist?(post_install_hook_path)).to be_false
        expect(@nb.run_post_install_hook("miku")).to be_nil
      end
    end

    context "when post_install file exit with error" do
      let(:post_install) { "#!/bin/sh\nexit 1" }

      it "should raise an error" do
        expect(File.executable?(post_install_hook_path)).to be_true
        expect { @nb.run_post_install_hook("miku") }.to raise_error
      end
    end
  end

  describe "#sort_release_version" do
    before do
      @nb = NiseBosh.new(@options, @log)
    end

    it "should sort version numbers" do
      expect(@nb.sort_release_version(%w{1 2 1.1 1.1-dev 33 2.1-dev 33-dev 2.1}))
        .to eq(%w{1 1.1-dev 1.1 2 2.1-dev 2.1 33-dev 33})
    end
  end

  describe "#archive" do
    before do
      @archive_dir = File.join(@tmp_dir, "archive")
      @archive_check_dir = File.join(@tmp_dir, "archive_check")
      setup_directory(@archive_dir)
      setup_directory(@archive_check_dir)
    end

    def check_archive_contents(file_name)
      FileUtils.cd(@archive_check_dir) do
        system("tar xvzf #{file_name} > /dev/null")
        expect_to_same(%W{#{@options[:repo_dir]} dev_releases test-39.3-dev.yml}, [@archive_check_dir, "release.yml"])
        expect_to_has_same_files([@archive_check_dir, "release"], @options[:repo_dir], ["jobs", "angel"])
        expect_to_has_same_files([@archive_check_dir, "release"], @options[:repo_dir], [".dev_builds", "packages", "luca"])
        expect_to_has_same_files([@archive_check_dir, "release"], @options[:repo_dir], [".final_builds", "packages", "miku"])
      end
    end

    it "create archive in current directory" do
      file_name = File.join(@archive_dir, "test-angel-39.3-dev.tar.gz")
      FileUtils.cd(@archive_dir) do
        @nb.archive("angel", file_name)
        expect(File.exists?(file_name)).to be_true
      end
      check_archive_contents(file_name)
    end

    it "create archive at given file path" do
      file_name = File.join(@archive_dir, "miku.tar.gz")
      @nb.archive("angel", file_name)
      expect(File.exists?(file_name)).to be_true
      check_archive_contents(file_name)
    end

    it "create archive in given directory" do
      file_name = File.join(@archive_dir, "test-angel-39.3-dev.tar.gz")
      @nb.archive("angel", @archive_dir)
      expect(File.exists?(file_name)).to be_true
      check_archive_contents(file_name)
    end
  end

  describe "#job_exists?" do
    it "should return true when given job exists" do
      expect(@nb.job_exists?("angel")).to be_true
    end

    it "should return false when given job does not exist" do
      expect(@nb.job_exists?("not_exist_job")).to be_false
    end
  end

  describe "#package_exists?" do
    it "should return true when given package exists" do
      expect(@nb.package_exists?(@package)).to be_true
    end

    it "should return false when given package does not exist" do
      expect(@nb.package_exists?("not_exist_package")).to be_false
    end
  end
end
