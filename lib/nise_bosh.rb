require 'yaml'
require 'erb'

require 'recursive_os'

class NiseBosh
  def initialize(options, logger)
    check_ruby_version
    initialize_options(options)
    initialize_release_file
    initialize_depoy_config

    @log = logger
    @ip_address = @options[:ip_address]
    @ip_address ||= %x[ip -4 -o address show].match('inet ([\d.]+)/.*? scope global') { |md| md[1] }
    @index ||=  @options[:index] || 0
  end

  def check_ruby_version
    if RUBY_VERSION < '1.9.0'
      raise "Ruby 1.9.0 or higher is required. Your Ruby version is #{RUBY_VERSION}"
    end
  end

  def initialize_options(options)
    @options = options
    @options[:repo_dir] = File.expand_path(@options[:repo_dir])
    raise "Release repository does not exist." unless File.exists?(@options[:repo_dir])

  end

  def initialize_release_file
    config_dir = File.join(@options[:repo_dir], "config")

    final_config_path = File.join(config_dir, "final.yml")
    final_name = File.exists?(final_config_path) ? YAML.load_file(final_config_path)["final_name"] : nil
    final_index_path = File.join(@options[:repo_dir], "releases", "index.yml")
    final_index = File.exists?(final_index_path) ? YAML.load_file(final_index_path)["builds"] : {}

    dev_config_path = File.join(config_dir, "dev.yml")
    dev_name = File.exists?(dev_config_path) ? YAML.load_file(dev_config_path)["dev_name"] : nil
    dev_index_path = File.join(@options[:repo_dir], "dev_releases", "index.yml")
    dev_index = File.exists?(dev_index_path) ? YAML.load_file(dev_index_path)["builds"] : {}

    if @options[:release_file].nil? && final_index.size == 0 && dev_index.size == 0
      raise "No release index found!\nTry `bosh cleate release` in your release repository."
    end
    newest_release = get_newest_release(final_index.merge(dev_index).map {|k, v| v["version"]})

    begin
      @release_file = @options[:release_file] ||
        (newest_release.split("-")[1] == "dev" ?
         File.join(@options[:repo_dir], "dev_releases", "#{dev_name}-#{newest_release}.yml"):
         File.join(@options[:repo_dir], "releases", "#{final_name}-#{newest_release}.yml"))
      @release = YAML.load_file(@release_file)
      @spec = @release["packages"].inject({}){|h, e| h[e["name"]] = e; h}
    rescue
      raise "Faild to load release file!"
    end
  end

  def get_newest_release(index)
    sort_release_version(index).last
  end

  def sort_release_version(index)
    result = index.map {|v| v.to_s.split("-")}.sort do |(v1, v1_dev) , (v2, v2_dev)|
      (v1, v1_frc) = v1.split("."); (v2, v2_frc) = v2.split(".")
      v1_frc ||= "0"; v2_frc ||= "0"
      (v1 != v2) ? v1.to_i <=> v2.to_i :
        (v1_frc != v2_frc) ? v1_frc.to_i <=> v2_frc.to_i :
        (v1_dev == v2_dev) ? raise("Invalid index file") :
        (v2_dev == "dev") ? 1 :
        -1
    end
    result.map {|v| v[1] ? v.join("-") : v[0]}
  end

  def initialize_depoy_config()
    begin
      @deploy_config = YAML.load_file(@options[:deploy_config]) if @options[:deploy_config]
    rescue
      raise "Deploy config file not found!"
    end
  end


  def archive(job, archive_name = nil)
    cleanup_working_directory()
    release_dir = File.join(@options[:working_dir], "release")
    FileUtils.mkdir_p(release_dir)

    resolve_dependency(job_packages(job)).each do |package|
      copy_release_file_relative(find_package_archive(package), release_dir)
    end

    copy_release_file_relative(File.join(@options[:repo_dir], "jobs", job), release_dir)

    FileUtils.cp(@release_file, File.join(@options[:working_dir], "release.yml"))

    default_name = "#{@release["name"]}-#{job}-#{@release["version"]}.tar.gz"
    out_file_name = archive_name ? (File.directory?(archive_name) ? File.join(archive_name, default_name) : archive_name ) : default_name
    system("tar -C #{@options[:working_dir]} -cvzf #{out_file_name} . > /dev/null")
  end

  def cleanup_working_directory()
    FileUtils.rm_rf(@options[:working_dir])
    FileUtils.mkdir_p(@options[:working_dir])
  end

  def copy_release_file_relative(from_path, to_release_dir)
    to_path = File.join(to_release_dir, from_path[@options[:repo_dir].length..-1])
    FileUtils.mkdir_p(File.dirname(to_path))
    FileUtils.cp_r(from_path, to_path)
  end

  def find_package_archive(package)
    v = @spec[package]["version"]
    major, minor = v.to_s.split("-")
    file_name = File.join(@options[:repo_dir],
      minor == "dev" ? ".dev_builds" : ".final_builds",
      "packages",
      package,
      "#{v}.tgz")
    unless File.exists?(file_name)
      raise "Package archive for #{package} not found in #{file_name}."
    end
    File.expand_path(file_name)
  end

  def install_packages(packages, no_dependency = false)
    unless no_dependency
      @log.info("Resolving package dependencies...")
      resolved_packages = resolve_dependency(packages)
    else
      resolved_packages = packages
    end
    @log.info("Installing the following packages: ")
    resolved_packages.each do |package|
      @log.info(" * #{package}")
    end
    resolved_packages.each do |package|
      @log.info("Installing package #{package}")
      install_package(package)
    end
  end

  def install_package(package)
    version_file = File.join(@options[:install_dir], "packages", package, ".version")
    current_version = nil
    if File.exists?(version_file)
      current_version = File.read(version_file).strip
    end
    if @options[:force_compile] || current_version != @spec[package]["version"].to_s
      FileUtils.rm_rf(version_file)
      setup_working_directory(package)
      run_packaging(package)
      File.open(version_file, 'w') do |file|
        file.puts(@spec[package]["version"].to_s)
      end
    else
      @log.info("The same version of the package is already installed. Skipping")
    end
  end

  def setup_working_directory(package)
    @log.info("Setting up the working directory for #{package}")
    @log.info("Cleaning up the working directory")
    cleanup_working_directory()
    @log.info("Copying pakage archive")
    file_name = find_package_archive(package)
    FileUtils.cd(@options[:working_dir]) do
      system("tar xzf #{file_name}  > /dev/null")
    end
  end

  def run_packaging(package)
    @log.info("Running the packaging script for #{package}")
    install_dir = File.join(@options[:install_dir], "packages", package)
    FileUtils.rm_rf(install_dir)
    FileUtils.mkdir_p(install_dir)
    FileUtils.cd(@options[:working_dir]) do
      ENV["BOSH_INSTALL_TARGET"] = install_dir
      ENV["BOSH_COMPILE_TARGET"] = @options[:working_dir]
      ENV["BOSH_PACKAGE_NAME"] = package
      ENV["BOSH_PACKAGE_VERSION"] = @spec[package]["version"].to_s
      %w{GEM_HOME BUNDLE_GEMFILE RUBYOPT}.each { |key| ENV.delete(key) }
      result = system("/bin/bash packaging")
      unless result
        raise "Error! Aborting..."
      end
    end
  end

  def resolve_dependency(packages, resolved_packages = [], trace = [])
    packages.each do |package|
      next if resolved_packages.include?(package)
      t = Array.new(trace) << package
      deps = @spec[package]["dependencies"] || []
      unless (deps & t).empty?
        raise "Detected a cyclic dependency"
      end
      resolve_dependency(deps, resolved_packages, t)
      resolved_packages << package
    end
    return resolved_packages
  end

  def package_exists?(package)
    File.exists?(File.join(@options[:repo_dir], "packages", package))
  end

  def install_job(job, template_only = false)
    unless template_only
      install_packages(job_packages(job))
    end
    install_job_templates(job)
  end

  def install_job_templates(job)
    spec = job_spec(job)
    template_base = File.join(@options[:repo_dir], "jobs", job, "templates")
    install_base = File.join(@options[:install_dir], "jobs", job)
    spec["templates"].each_pair do |template, to|
      write_template(spec, File.join(template_base, template), File.join(install_base, to))
    end
    write_template(spec, File.join(@options[:repo_dir], "jobs", job, "monit"), File.join(@options[:install_dir], "bosh", "etc", "monitrc"))
  end

  def job_packages(job)
    job_spec(job)["packages"]
  end

  def job_spec(job)
    YAML.load_file(File.join(@options[:repo_dir], "jobs", job, "spec"))
  end

  def write_template(spec, template, to)
    job = spec["name"]
    b = RecursiveOpenStruct.new(@deploy_config)
    # FIXME: add other variables
    b.update_value!("spec.index", @index) unless b.key_exists?("spec.index")
    b.update_value!("spec.networks.default.ip", @ip_address) unless b.key_exists?("spec.networks.default.ip")
    def b.fill(template)
      ERB.new(File.read(template)).result(binding)
    end
    @deploy_config.each_pair do |key, val|
      b.instance_variable_set("@#{key}", val)
    end
    to_result = b.fill(template)
    FileUtils.mkdir_p(File.dirname(to))
    open(to, "w") {|f| f.write(to_result)}

    FileUtils.mkdir_p(File.join(@options[:install_dir], "data", "packages"))
    if File.basename(File.dirname(to)) == "bin"
      FileUtils.chmod(0755, to)
    end
  end

  def job_exists?(job)
    File.exists?(File.join(@options[:repo_dir], "jobs", job))
  end
end
