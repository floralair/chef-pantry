#
# Cookbook Name:: cassandra::seed
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

# Launch the cassandra service on the seed nodes first
set_bootstrap_action(ACTION_START_SERVICE, node[:cassandra][:seed_service_name])

is_seed_running = system("service #{node[:cassandra][:seed_service_name]} status")
service "restart-#{node[:cassandra][:seed_service_name]}" do
  service_name node[:cassandra][:seed_service_name]
  supports :status => true, :restart => true

  notifies :create, resources("ruby_block[#{node[:cassandra][:seed_service_name]}]"), :immediately
end if is_seed_running

service "start-#{node[:cassandra][:seed_service_name]}" do
  service_name node[:cassandra][:seed_service_name]
  action [ :disable, :start]
  supports :status => true, :restart => true

  notifies :create, resources("ruby_block[#{node[:cassandra][:seed_service_name]}]"), :immediately
end

# Register with cluster_service_discovery
provide_service(node[:cassandra][:seed_service_name])

clear_bootstrap_action
