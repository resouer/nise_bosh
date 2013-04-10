require "runner"

require 'spec_helper'

describe Runner do
  let(:tmp_dir) { File.join("/", "tmp", "nise_bosh_spec") }
  let(:install_dir) { File.join(tmp_dir, "install") }
  let(:working_dir) { File.join(tmp_dir, "nise_bosh_spec") }
  let(:assets_dir) { File.join(".", "spec", "assets") }
  let(:release_dir) { File.join(assets_dir, "release") }
  let(:release_noindex_dir) { File.join(assets_dir, "release_noindex") }
  let(:deploy_conf) { File.join(assets_dir, "deploy.conf") }
  let(:success_job) { "angel" }
  let(:packages) do
    [{:name => "miku", :file_contents => "miku 39", :version => "39"},
     {:name => "luca", :file_contents => "tenshi", :version => "39-dev"}]
  end
  let(:archive_dir) { File.join(tmp_dir, "archive") }
  let(:default_archive_name) { "test-angel-39.3-dev.tar.gz" }

  before do
    FileUtils.rm_rf(tmp_dir)
  end

  def package_file_path(package)
    File.join(install_dir, "packages", package[:name], "dayo")
  end

  def check_installed_package_files
    packages.each do |package|
      expect_contents(package_file_path(package)).to eq(package[:file_contents] + "\n")
      expect_contents(install_dir, "packages", package[:name], ".version").to eq(package[:version] + "\n")
    end
  end

  def check_installed_job_files
    expect_contents(install_dir, "jobs", "angel", "config", "miku.conf").to eq("tenshi\n0\n#{current_ip}\n")
    expect_file_mode(install_dir, "jobs", "angel", "bin", "miku_ctl").to eq(0100755)
    expect_contents(install_dir, "bosh", "etc", "monitrc").to eq("monit\n")
    expect_directory_exists(install_dir, "data", "packages").to be_true
  end

  def check_installed_files
    check_installed_package_files
    check_installed_job_files
  end

  context "default mode" do
    it "should setup given job" do
      out = %x[echo y | bundle exec ./bin/nise-bosh -d #{install_dir} --working-dir #{working_dir} #{release_dir} #{deploy_conf} #{success_job} > /dev/null]
      expect($?.exitstatus).to eq(0)
      check_installed_files
    end

    it "should setup given job in the given directory" do
      dir = File.join(tmp_dir, "another_install")
      out = %x[echo y | bundle exec ./bin/nise-bosh -d #{dir} --working-dir #{working_dir} #{release_dir} #{deploy_conf} #{success_job} > /dev/null]
      expect($?.exitstatus).to eq(0)
      packages.each do |package|
        expect_contents(File.join(dir, "packages", package[:name], "dayo")).to eq(package[:file_contents] + "\n")
        expect_contents(dir, "packages", package[:name], ".version").to eq(package[:version] + "\n")
      end
    end

    it "should use the given working directory while setup" do
      out = %x[echo y | bundle exec ./bin/nise-bosh -d #{install_dir} --working-dir #{working_dir} #{release_dir} #{deploy_conf} #{success_job} > /dev/null]
      expect($?.exitstatus).to eq(0)
      expect(File.directory?(working_dir)).to be_true
      expect(File.exists?(File.join(working_dir, "packaging"))).to be_true
    end

    it "should abort execution when 'n' given to the prompt" do
      out = %x[echo n | bundle exec ./bin/nise-bosh -d #{install_dir} --working-dir #{working_dir} #{release_dir} #{deploy_conf} #{success_job} 2>&1]
      expect($?.exitstatus).to eq(0)
      expect(out.match(/Abort.$/)).to be_true
    end

    it "should setup given job with -y option" do
      r = %x[bundle exec ./bin/nise-bosh -y -d #{install_dir} --working-dir #{working_dir} #{release_dir} #{deploy_conf} #{success_job} > /dev/null]
      expect($?.exitstatus).to eq(0)
      check_installed_files
    end

    it "should setup given job with given IP (-n)  and index number (-i)" do
      out = %x[bundle exec ./bin/nise-bosh -y -i 39 -n 39.39.39.39 -d #{install_dir} --working-dir #{working_dir} #{release_dir} #{deploy_conf} #{success_job} > /dev/null]
      expect($?.exitstatus).to eq(0)
      check_installed_package_files
      expect_contents(install_dir, "jobs", "angel", "config", "miku.conf").to eq("tenshi\n39\n39.39.39.39\n")
    end

    it "should setup only job template files when given -t option" do
      out = %x[bundle exec ./bin/nise-bosh -y -t -d #{install_dir} --working-dir #{working_dir} #{release_dir} #{deploy_conf} #{success_job} > /dev/null]
      expect($?.exitstatus).to eq(0)
      check_installed_job_files
      expect_contents(install_dir, "jobs", "angel", "config", "miku.conf").to eq("tenshi\n0\n#{current_ip}\n")
      expect_directory_exists(install_dir, "data", "packages").to be_true
    end

    it "should raise an error when the number of command line arguments is wrong" do
      out = %x[bundle exec ./bin/nise-bosh -y  2>&1]
      expect($?.exitstatus).to eq(1)
      expect(out.match(/^Arguments number error!$/)).to be_true
    end

    it "should raise an error when invalid job name givent" do
      out = %x[bundle exec ./bin/nise-bosh -y -d #{install_dir} --working-dir #{working_dir} #{release_dir} #{deploy_conf} not_exist_job 2>&1]
      expect($?.exitstatus).to eq(1)
      expect(out).to eq("Given job does not exist!\n")
    end

    it "should raise an error when given release file does not exist" do
      out = %x[bundle exec ./bin/nise-bosh -y -d #{install_dir} --working-dir #{working_dir} not_exist #{deploy_conf} #{success_job} 2>&1]
      expect($?.exitstatus).to eq(1)
      expect(out).to eq("Release repository does not exist.\n")
    end

    it "should raise an error when given release has no release index" do
      out = %x[bundle exec ./bin/nise-bosh -y -d #{install_dir} --working-dir #{working_dir} #{release_noindex_dir} #{deploy_conf} #{success_job} 2>&1]
      expect($?.exitstatus).to eq(1)
      expect(out).to eq("No release index found!\nTry `bosh cleate release` in your release repository.\n")
    end

    it "should not re-install the packages of the given job which has been already installed the same version" do
      out = %x[bundle exec ./bin/nise-bosh -y -d #{install_dir} --working-dir #{working_dir} #{release_dir} #{deploy_conf} #{success_job} 2>&1]
      before =  File.mtime(package_file_path(packages[0]))
      expect($?.exitstatus).to eq(0)
      check_installed_files
      out = %x[bundle exec ./bin/nise-bosh -y -d #{install_dir} --working-dir #{working_dir} #{release_dir} #{deploy_conf} #{success_job} 2>&1]
      expect(out).to match(/The same version of the package is already installed. Skipping/)
      after =  File.mtime(package_file_path(packages[0]))
      expect(before).to eq(after)
    end

    it "should re-install the packages of the given when -f option given, even if they have been already installed the same version" do
      out = %x[bundle exec ./bin/nise-bosh -y -d #{install_dir} --working-dir #{working_dir} #{release_dir} #{deploy_conf} #{success_job} 2>&1]
      before = File.mtime(package_file_path(packages[0]))
      expect($?.exitstatus).to eq(0)
      check_installed_files
      out = %x[bundle exec ./bin/nise-bosh -y -f -d #{install_dir} --working-dir #{working_dir} #{release_dir} #{deploy_conf} #{success_job} 2>&1]
      packages.each do |package|
        expect(out).to match(/Running the packaging script for #{package[:name]}/)
      end
      after = File.mtime(package_file_path(packages[0]))
      expect(before).to_not eq(after)
    end
  end

  context "packages mode" do
    it "should install given packages and dependencies" do
      out = %x[bundle exec ./bin/nise-bosh -y -p -d #{install_dir} --working-dir #{working_dir} #{release_dir} miku luca kaito 2>&1]
      expect($?.exitstatus).to eq(0)
      expect_contents(install_dir, "packages", "miku", "dayo").to eq("miku 39\n")
      expect_contents(install_dir, "packages", "luca", "dayo").to eq("tenshi\n")
      expect_contents(install_dir, "packages", "kaito", "dayo").to eq("tenshi\n")
    end

    it "should install only given packages when --no-dpendency option given" do
      out = %x[bundle exec ./bin/nise-bosh -y -p --no-dependency -d #{install_dir} --working-dir #{working_dir} #{release_dir} luca 2>&1]
      expect($?.exitstatus).to eq(0)
      expect_file_exists(install_dir, "packages", "miku", "dayo").to be_false
      expect_contents(install_dir, "packages", "luca", "dayo").to eq("tenshi\n")
    end

    it "should raise an error when given package does not exist" do
      out = %x[bundle exec ./bin/nise-bosh -y -p -d #{install_dir} --working-dir #{working_dir} #{release_dir} not_exist_package 2>&1]
      expect($?.exitstatus).to eq(1)
      expect(out).to eq("Given package not_exist_package does not exist!\n")
    end
  end

  context "archive mode" do
    before do
      setup_directory(archive_dir)
    end

    it "should create job archive" do
      if File.exists?(default_archive_name)
        raise "Oops, archive file already exists"
      end
      out = %x[bundle exec ./bin/nise-bosh -y -a -d #{install_dir} --working-dir #{working_dir} #{release_dir} #{success_job} 2>&1]
      expect($?.exitstatus).to eq(0)
      expect_file_exists(default_archive_name).to be_true
      FileUtils.rm(default_archive_name)
    end

    it "should create job archive in given directory with default file name" do
      out = %x[bundle exec ./bin/nise-bosh -y -a -d #{install_dir} --working-dir #{working_dir} #{release_dir} #{success_job} #{archive_dir} 2>&1]
      expect($?.exitstatus).to eq(0)
      expect_file_exists(archive_dir, default_archive_name).to be_true
    end

    it "should create job archive with given file name " do
      archive_name = "#{archive_dir}/angel.tar.gz"
      out = %x[bundle exec ./bin/nise-bosh -y -a -d #{install_dir} --working-dir #{working_dir} #{release_dir} #{success_job} #{archive_name} 2>&1]
      expect($?.exitstatus).to eq(0)
      expect_file_exists(archive_name).to be_true
    end
  end
end
