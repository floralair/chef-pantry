#!/usr/bin/ruby

require 'optparse'
require 'ostruct'
require 'date'
require 'json'

class ConfigDistro
  DISTRO_ROOT_DIR = '/opt/serengeti/www/distros'
  MANIFEST_PATH = "/opt/serengeti/www/distros/manifest"

  VENDORS_REPO = ["GENERIC", "MESOS", "MAPR", "PHD", "BIGTOP", "CDH"]
  VENDORS_TARS = ["APACHE", "GPHD", "HDP", "KUBERNETES"]
  VENDORS = VENDORS_REPO + VENDORS_TARS

  attr_reader :options

  def initialize(arguments)
    @arguments = arguments

    # Set defaults
    @options = OpenStruct.new
    @options.name = nil
    @options.hadoop = nil
    @options.pig = nil
    @options.hive = nil
    @options.vendor = nil
    @options.version = nil
    @options.hbase = nil
    @options.zookeeper = nil
    @options.tarball = nil
    @options.roles = nil

    @distro = {}
    @errors = []
    @distros = []

    @opts = nil
    @backup_manifest = false
  end

  # Parse options, check arguments, then process the command
  def run
    if arguments_valid?

      read_manifest

      validates_presence_of :name, :vendor, :version
      validates_option_can_be_used :hadoop, :pig, :hive, :hbase, :zookeeper, :tarball, :repos
      if should_have_option_repos?
        validates_presence_of :repos
        validates_format_of_repos
      elsif !@options.tarball
        validates_presence_of :hadoop, :pig, :hive
        validate_params_dependency :hbase, :zookeeper
      end
      validates_distro_name
      validates_distro_vendor_name
      validates_uniqueness_vendor_and_version
      validates_hve_supported if @options.hve_supported

      process_command

    else
      show_errors
    end

  end

  protected

  def parse_options
    # Specify options
    @opts = OptionParser.new

    @opts.on('-n', '--name DISTRO_NAME', 'Distro name.') do |name|
      @options.name = name
    end

    @opts.on('-d', '--vendor DISTRO_VENDOR', 'Valid distro vendor name.') do |vendor|
      @options.vendor = vendor.upcase
    end

    @opts.on('-v', '--version DISTRO_VERSION', 'Release version of the hadoop distro.') do |version|
      @options.version = version
    end

    @opts.on('-a', '--hadoop TARBALL_URL', 'Hadoop tarball url.') do |package_url|
      @options.hadoop = package_url
    end

    @opts.on('-p', '--pig TARBALL_URL', 'Pig tarball url.') do |package_url|
      @options.pig = package_url
    end

    @opts.on('-i', '--hive TARBALL_URL', 'Hive tarball url.') do |package_url|
      @options.hive = package_url
    end

    @opts.on('-b', '--hbase TARBALL_URL', 'Hbase tarball url.') do |package_url|
      @options.hbase = package_url
    end

    @opts.on('-z', '--zookeeper TARBALL_URL', 'Zookeeper tarball url.') do |package_url|
      @options.zookeeper = package_url
    end

    @opts.on('-t', '--tarball TARBALL_URL', 'The tarball url.') do |package_url|
      @options.tarball = package_url
    end

    @opts.on('-e', '--hve HVE_SUPPORTED', 'Is HVE supported? Apache Hadoop 1.2+ and Pivotal HD support HVE.') do |hve_supported|
      case hve_supported
      when "true"
        @options.hve_supported = true
      when "false"
        @options.hve_supported = false
      end
    end

    @opts.on('-r', '--repos REPOS', Array, 'Package repos url') do |repos|
      @options.repos = repos
    end

    @opts.on('-o', '--roles ROLES', Array, 'Chef roles supported by this distro') do |roles|
      @options.roles = roles
    end

    @opts.on('-y', '--yes', 'Answer yes for all confirmation.') do
      @options.yes = true
    end

    @opts.on('-h', '--help', 'Show this help.') do
      show_help
      exit 0
    end

    @opts.parse!(@arguments.dup)
  end

  def parsed_options?
    begin
      parse_options
      return true
    rescue OptionParser::ParseError => ex
      @errors << ex.to_s
      return false
    end
  end

  def show_help
    puts @opts
  end

  def arguments_valid?
    parsed_options? and !@arguments.empty?
  end

  # TO DO - do whatever this app does
  def process_command
    show_errors if has_error

    create_distro_folder

    generate_distro_basic_info

    if @options.repos
      generate_package_info_with_repos
    else
      download_tarballs
    end

    generate_manifest

    show_errors if has_error
  end

  def create_distro_folder
    return if has_error
    @distro_path = File.join("#{DISTRO_ROOT_DIR}", @options.name)
    unless File.exists?(@distro_path)
      result = system("mkdir -p #{@distro_path}")
      @errors << "Can not create the folder." unless result
    end
  end

  def generate_distro_basic_info
    return if has_error
    @distro["name"] = @options.name
    @distro["vendor"] = @options.vendor
    @distro["version"] = @options.version
    update_hve_supported
    @distro["packages"] = []
  end

  def generate_package_info_with_repos
    case @options.vendor
    when "CDH"
      @distro["packages"] = [{"package_repos" => @options.repos, "roles" => ["hadoop_namenode", "hadoop_datanode", "hadoop_jobtracker", "hadoop_tasktracker", "hadoop_resourcemanager", "hadoop_nodemanager", "hadoop_journalnode", "hadoop_client", "hive", "hive_server", "pig", "hbase_master", "hbase_regionserver", "hbase_client", "zookeeper"]}]
    when "MAPR"
      @distro["packages"] = [{"package_repos" => @options.repos, "roles" => ["mapr_zookeeper", "mapr_cldb", "mapr_jobtracker", "mapr_tasktracker", "mapr_fileserver", "mapr_nfs", "mapr_webserver", "mapr_metrics", "mapr_client", "mapr_pig", "mapr_hive", "mapr_hive_server", "mapr_mysql_server", "mapr_hbase_master", "mapr_hbase_regionserver", "mapr_hbase_client"]}]
      if @options.version.to_f >= 4
        @distro["packages"][0]["roles"] += ["mapr_resourcemanager", "mapr_historyserver", "mapr_nodemanager"]
      end
    when "PHD"
      packages_for_yarn
    when "HDP"
      if @options.version.to_f < 2
        packages_for_hadoop1
      else
        packages_for_yarn
      end
    when "BIGTOP"
      if @options.version.to_f < 0.4
        packages_for_hadoop1
      else @options.version.to_f >= 0.4
        packages_for_yarn
      end
    when "MESOS"
      @distro["packages"] = [{"package_repos" => @options.repos, "roles" => ["zookeeper", "mesos_master", "mesos_slave", "mesos_docker", "mesos_chronos", "mesos_marathon"]}]
    else
      @distro["packages"] = [{"package_repos" => @options.repos, "roles" => []}]
    end

    @distro["packages"][0]["roles"] = @options.roles if @options.roles
  end

  def packages_for_hadoop1
    @distro["packages"] = [{"package_repos" => @options.repos, "roles" => ["hadoop_namenode", "hadoop_datanode", "hadoop_jobtracker", "hadoop_tasktracker", "hadoop_client", "hive", "hive_server", "pig", "hbase_master", "hbase_regionserver", "hbase_client", "zookeeper"]}]
  end

  def packages_for_yarn
    @distro["packages"] = [{"package_repos" => @options.repos, "roles" => ["hadoop_namenode", "hadoop_datanode", "hadoop_resourcemanager", "hadoop_nodemanager", "hadoop_journalnode", "hadoop_client", "hive", "hive_server", "pig", "hbase_master", "hbase_regionserver", "hbase_client", "zookeeper"]}]
  end

  def download_tarballs
    return if has_error

    for item in ['tarball', 'hadoop', 'pig', 'hive', 'hbase', 'zookeeper'] do
      url = @options.send item
      download_tartall(url, item) if url
    end
  end

  def download_tartall(package_url, type)
    return if has_error
    name = package_url.split("/").last
    tarball_path = File.join(@distro_path, name)
    if File.exists?(tarball_path)
      puts "Warning: The file #{tarball_path} already exists."
      if @options.yes
        download(package_url, name)
      else
        print "Do you want to overwrite it ? [Y/N]:"
        while true
          case STDIN.gets.strip.downcase
          when "y"
            download(package_url, name)
            break
          when "n"
            break
          end
        end
      end
    else
      download(package_url, name)
    end
    generate_package_info(name, type)
  end

  def download(package_url, name)
    tarball_path = File.join(@distro_path, name)
    ret = system("wget --no-check-certificate #{package_url} -O #{tarball_path}")
    unless ret
      system("rm -f #{tarball_path}")
      @errors << "Failed to download the tarball #{name}."
    else
      if File.size(tarball_path) == 0
        system("rm -f #{tarball_path}")
        @errors << "Failed to download the tarball #{name}."
      end
    end
  end

  def generate_package_info(name, type)
    tarball = File.join(@options.name, name)
    case type
    when "tarball"
      roles = @options.roles
      case @options.vendor
      when "KUBERNETES"
        roles ||= ["kubernetes_workstation", "kubernetes_master", "kubernetes_minion"]
      end
      @distro["packages"][0] = {"tarball" => tarball, "roles" => roles}
      return
    when "hadoop"
      @distro["packages"][0] = {"tarball" => tarball, "roles" => ["hadoop_namenode", "hadoop_jobtracker", "hadoop_tasktracker", "hadoop_datanode", "hadoop_client"]}
    when "pig"
      @distro["packages"][1] = {"tarball" => tarball, "roles" => ["pig"]}
    when "hive"
      @distro["packages"][2] = {"tarball" => tarball, "roles" => ["hive", "hive_server"]}
    when "hbase"
      @distro["packages"][3] = {"tarball" => tarball, "roles" => ["hbase_master", "hbase_regionserver", "hbase_client"]}
    when "zookeeper"
      @distro["packages"][4] = {"tarball" => tarball, "roles" => ["zookeeper"]}
    end
  end

  def generate_manifest
    return if has_error
    if @distros.empty?
      @distros << @distro
    else
      if distros_name.include?(@distro["name"])
        update_distro
      else
        @distros << @distro
      end
    end
    write_manifest
  end

  def validates_presence_of(*attr_names)
    attr_names.each do |attr_name|
      unless @options.send(attr_name)
        @errors << "The option --#{attr_name.to_s} is missing."
      end
    end
  end

  def validates_uniqueness_of(*attr_names)
    attr_names.each do |attr_name|
      if @options.send(attr_name) and @distros.collect {|distro| distro[attr_name.to_s]}.include?(@options.send(attr_name))
        name = @options.send(attr_name)
        puts "Warning: The distro named #{name} already exists."
        confirm "Do you want to overwrite the existing #{name} distro ? [Y/N]:"
      end
    end
  end

  def validates_distro_name
    if /\W/ =~ @options.name
      @errors << "The value of option --name can contain only letter, number, and underscore."
      return
    end
    validates_uniqueness_of :name
  end

  def should_have_option_repos?
    VENDORS_REPO.include? @options.vendor or (@options.vendor == "HDP" and @options.version.to_f >= 2)
  end

  def validates_distro_vendor_name
    unless VENDORS.include?(@options.vendor)
      @errors << "The value of option --vendor must be one of these: #{VENDORS.join(', ')} (GENERIC => User Customized Distro, Apache => Apache Hadoop, GPHD => GreenPlum HD, PHD => Pivotal HD, HDP => Hortonworks Data Platform, CDH => Cloudera Hadoop, MAPR => MapR, BIGTOP => Apache Bigtop)."
    end
  end

  def validate_params_dependency(attr_name, basic_attr_name)
    if @options.send(attr_name)
      @errors << "The option --#{attr_name.to_s} depends on --#{basic_attr_name.to_s}. Please also specify option --#{basic_attr_name.to_s}." unless @options.send(basic_attr_name)
    end
  end

  def confirm(msg)
    unless @options.yes
      print msg
      while true
        case STDIN.gets.strip.downcase
        when "y"
          break
        when "n"
          exit 1
        end
      end
    end
  end

  def validates_uniqueness_vendor_and_version
    if @distros.collect { |distro| [distro["vendor"], distro["version"]] }.include?([@options.vendor, @options.version])
      puts "Warning: A distro with the same vendor #{@options.vendor} and version #{@options.version} already exists."
      confirm "Do you still want to add this new distro ? [Y/N]:"
    end
  end

  def validates_hve_supported
    unless [true, false].include?(@options.hve_supported)
      @errors << "The value of option --hve must be true or false."
    end
  end

  def validates_option_can_be_used(*attr_names)
    attr_names.each do |attr_name|

      if @options.send(attr_name)

        # Validates the option --repos whether can be used
        if attr_name.to_s == "repos"
          unless should_have_option_repos?
            @errors << "The option --repos can be used only for one of these distros: #{VENDORS_REPO.join(', ')}."
          end
        end

        # Validates options of using tarball whether can be used
        if ["hadoop", "pig", "hive", "hbase", "zookeeper", "tarball"].include?(attr_name.to_s)
          if should_have_option_repos?
            @errors << "The option --#{attr_name.to_s} can be used only for one of these distros: #{VENDORS_TARS.join(', ')}."
          end
        end

      end

    end
  end

  def validates_format_of_repos
    if @options.repos
      @options.repos.each do |repo|
        unless /^http:|https:/.match(repo)
          @errors << "The value of option --repos must start with http or https."
        end
      end
    end
  end

  def read_manifest
    if File.exist?(MANIFEST_PATH)
      unless File.read(MANIFEST_PATH).empty?
        begin
          @distros = JSON.parse(File.read(MANIFEST_PATH))
          @backup_manifest = true if system("cp -rf #{MANIFEST_PATH} #{MANIFEST_PATH}.bak")
        rescue JSON::ParserError => ex
          @errors << "The #{MANIFEST_PATH} is not a valid json file."
          @errors << ex.to_s
          show_errors
        end
      else
        @distros = []
      end
    else
      @distros = []
    end
  end

  def write_manifest
    begin
      File.open(MANIFEST_PATH, "w") do |file|
        file.write(JSON.pretty_generate(@distros))
      end
      puts "Distro #{@distro["name"]} is added into #{MANIFEST_PATH} successfully"
      puts "The old manifest is backup to #{MANIFEST_PATH}.bak" if @backup_manifest
    rescue Exception => ex
      puts "Failed to add distro #{@distro["name"]}: #{ex.to_s}"
      exit 2
    end
  end

  def show_errors
    unless @errors.empty?
      puts "Errors:"
      @errors.each do |error|
        puts "  #{error}"
      end
    end
    show_help
    exit 1
  end

  def distros_name
    @distros.collect {|distro| distro["name"]}
  end

  def update_distro
    @distros.each_with_index do |distro, index|
      if distro["name"] == @distro["name"]
        @distros[index] = @distro
      end
    end
  end

  def update_hve_supported
    unless @options.hve_supported == nil
      @distro["hveSupported"] = @options.hve_supported
    else
      default_hve_supported
    end
  end

  def default_hve_supported
    @distro["hveSupported"] = true if hve_supported?
  end

  def hve_supported?
    hve_supported = false
    case @options.vendor
    when "APACHE"
      hve_supported = true if @options.version.to_f >= 1.2
    when "PHD"
      hve_supported = true
    end
    hve_supported
  end

  def has_error
    !@errors.empty?
  end

end

# Create and run the configDistro
configDistro = ConfigDistro.new(ARGV)
configDistro.run
