#
# Cookbook Name:: mesos
# Recipe:: slave
#
# Copyright (C) 2013 Medidata Solutions, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

class ::Chef::Recipe
  include ::Mesos
end

include_recipe 'mesos::install'
include_recipe 'mesos::docker' if node.role?('mesos_docker')

zk_server_list = []
zk_port = ''
zk_path = ''

template '/etc/default/mesos' do
  source 'mesos.erb'
  variables config: node['mesos']['common']
  notifies :run, 'bash[restart-mesos-slave]', :delayed
end

template '/etc/default/mesos-slave' do
  source 'mesos.erb'
  variables config: node['mesos']['slave']
  notifies :run, 'bash[restart-mesos-slave]', :delayed
end

pairs = {
  :logging_level => node['mesos']['common']['logging_level']
}
generate_mesos_param_files('slave', pairs)

if node['mesos']['zookeeper_server_list'].count > 0
  zk_server_list = node['mesos']['zookeeper_server_list']
  zk_port = node['mesos']['zookeeper_port']
  zk_path = node['mesos']['zookeeper_path']
end

if node['mesos']['zookeeper_exhibitor_discovery'] && node['mesos']['zookeeper_exhibitor_url']
  zk_nodes = discover_zookeepers_with_retry(node['mesos']['zookeeper_exhibitor_url'])

  zk_server_list = zk_nodes['servers']
  zk_port = zk_nodes['port']
  zk_path = node['mesos']['zookeeper_path']
end

unless zk_server_list.count == 0 && zk_port.empty? && zk_path.empty?
  Chef::Log.info("Zookeeper Server List: #{zk_server_list}")
  Chef::Log.info("Zookeeper Port: #{zk_port}")
  Chef::Log.info("Zookeeper Path: #{zk_path}")

  template '/etc/mesos/zk' do
    source 'zk.erb'
    variables(
      zookeeper_server_list: zk_server_list,
      zookeeper_port: zk_port,
      zookeeper_path: zk_path,
    )
    notifies :run, 'bash[restart-mesos-slave]', :delayed
  end
end

template '/usr/local/etc/mesos/mesos-slave-env.sh' do
  source 'mesos-slave-env.sh.erb'
  variables(
    zookeeper_server_list: zk_server_list,
    zookeeper_port: zk_port,
    zookeeper_path: zk_path,
    logs_dir: node['mesos']['common']['logs'],
    work_dir: node['mesos']['slave']['work_dir'],
    isolation: node['mesos']['isolation'],
  )
  notifies :run, 'bash[restart-mesos-slave]', :delayed
end

# If we are on ec2 set the public dns as the hostname so that
# mesos slave reports work properly in the UI.
if node.attribute?('ec2') && node['mesos']['set_ec2_hostname']
  bash 'set-aws-public-hostname' do
    user 'root'
    code <<-EOH
      PUBLIC_DNS=`wget -q -O - http://instance-data.ec2.internal/latest/meta-data/public-hostname`
      hostname $PUBLIC_DNS
      echo $PUBLIC_DNS > /etc/hostname
      HOSTNAME=$PUBLIC_DNS  # Fix the bash built-in hostname variable too
    EOH
    not_if 'hostname | grep amazonaws.com'
  end
end

# Set init to 'start' by default for mesos slave.
# This ensures that mesos-slave is started on restart
template '/etc/init/mesos-slave.conf' do
  source 'mesos-slave.conf.erb'
  variables(
    action: 'start',
  )
  notifies :run, 'bash[reload-configuration]'
end

if node['platform'] == 'debian'
  bash 'reload-configuration' do
    action :nothing
    user 'root'
    code <<-EOH
    update-rc.d mesos-slave defaults
    EOH
  end
else
  bash 'reload-configuration' do
    action :nothing
    user 'root'
    code <<-EOH
    initctl reload-configuration
    EOH
  end
end

set_bootstrap_action(ACTION_START_SERVICE, 'mesos-slave', true)

if node['platform'] == 'debian'
  bash 'start-mesos-slave' do
    user 'root'
    code <<-EOH
    service mesos-slave start
    EOH
    not_if 'service mesos-slave status|grep start/running'
  end
else
  bash 'start-mesos-slave' do
    user 'root'
    code <<-EOH
    start mesos-slave
    EOH
    not_if 'status mesos-slave|grep start/running'
  end
end

if node['platform'] == 'debian'
  bash 'restart-mesos-slave' do
    action :nothing
    user 'root'
    code <<-EOH
    service mesos-slave restart
    EOH
    not_if 'service mesos-slave status|grep stop/waiting'
  end
else
  bash 'restart-mesos-slave' do
    action :nothing
    user 'root'
    code <<-EOH
    restart mesos-slave
    EOH
    not_if 'status mesos-slave|grep stop/waiting'
  end
end
