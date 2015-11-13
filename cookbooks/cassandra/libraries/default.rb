module Cassandra

  def is_seed
    node.role?("cassandra_seed")
  end

  def cassandra_seeds_ip
    servers = all_providers_fqdn_for_role("cassandra_seed")
    Chef::Log.info("Cassandra seed nodes in cluster #{node[:cluster_name]} are: #{servers.inspect}")
    servers
  end

  def cassandra_nodes_ip
    servers = all_providers_fqdn_for_role("cassandra_node")
    Chef::Log.info("Cassandra worker nodes in cluster #{node[:cluster_name]} are: #{servers.inspect}")
    servers
  end

  def wait_for_cassandra_seeds(in_ruby_block = true)
    return if is_seed

    run_in_ruby_block __method__, in_ruby_block do
      set_action(HadoopCluster::ACTION_WAIT_FOR_SERVICE, node[:cassandra][:seed_service_name])
      seed_count = all_nodes_count({"role" => "cassandra_seed"})
      all_providers_for_service(node[:cassandra][:seed_service_name], true, seed_count)
      clear_action
    end
  end

  def local_cassandra_dirs
    dirs = node[:disk][:data_disks].map do |mount_point, device|
      mount_point + '/cassandra' if File.exists?(node[:disk][:disk_devices][device])
    end
    dirs.compact!
    dirs.unshift('/mnt/cassandra') if node[:cassandra][:use_root_as_scratch_vol]
    dirs.uniq
  end

    # Make a cassandra-owned directory
  def make_cassandra_dir dir, dir_owner="cassandra", dir_mode="0755"
    directory dir do
      owner    dir_owner
      group    "cassandra"
      mode     dir_mode
      action   :create
      recursive true
    end
  end

end

class Chef::Recipe; include Cassandra; end
