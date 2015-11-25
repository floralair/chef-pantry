#
# Cookbook Name:: cassandra
# Recipe:: default
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

include_recipe "java::sun"
include_recipe "hadoop_common::pre_run"
include_recipe "hadoop_common::mount_disks"
include_recipe "hadoop_cluster::update_attributes"
# Setup package repository
include_recipe "hadoop_common::add_repo"

## Setup the repo file for installing Cassandra
#template '/etc/yum.repos.d/datastax.repo' do
#  source 'datastax.repo.erb'
#  action :create
#end

%w{dsc22 cassandra22-tools}.each do |pkg|
  package pkg do
    action :install
  end
end


all_seeds_ip = cassandra_seeds_ip
all_nodes_ip = cassandra_nodes_ip

#Make cassandra's own dirs
all_local_dirs = local_cassandra_dirs
all_local_dirs.each do |dir|
  make_cassandra_dir(dir, 'cassandra', '0775')
end

template '/etc/cassandra/conf/cassandra.yaml' do
  source 'cassandra.yaml.erb'
  action :create
  variables(
    seeds_list: all_seeds_ip,
     dirs_list: all_local_dirs,
     cluster_value: node[:cluster_name]
  )
  action :create
end

template '/etc/cassandra/default.conf/cassandra-env.sh' do
  source 'cassandra-env.sh.erb'
  action :create
end

set_java_home('/etc/default/cassandra')

clear_bootstrap_action
