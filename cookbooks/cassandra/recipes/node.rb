#
# Cookbook Name:: cassandra::node
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

# Launch Non-Seed daemon after the Seeds have started
set_bootstrap_action(ACTION_START_SERVICE, node[:cassandra][:node_service_name])
wait_for_cassandra_seeds

# Have to launch Non-Seed nodes one at a time to avoid error:
# "Other bootstrapping/leaving/moving nodes detected, cannot bootstrap while cassandra.consistent.rangemovement is true"
num_secs = rand(1..31)
sleep(num_secs)

is_node_running = system("service #{node[:cassandra][:node_service_name]} status")
service "restart-#{node[:cassandra][:node_service_name]}" do
  service_name node[:cassandra][:node_service_name]
  supports :status => true, :restart => true
  subscribes :restart, resources("template[/etc/cassandra/conf/cassandra.yaml]"), :delayed
  subscribes :restart, resources("template[/etc/cassandra/default.conf/cassandra-env.sh]"), :delayed
  notifies :create, resources("ruby_block[#{node[:cassandra][:node_service_name]}]"), :immediately
end if is_node_running

service "start-#{node[:cassandra][:node_service_name]}" do
  service_name node[:cassandra][:node_service_name]
  action [ :disable, :start ]
  supports :status => true, :restart => true
  notifies :create, resources("ruby_block[#{node[:cassandra][:node_service_name]}]"), :immediately
end

clear_bootstrap_action
