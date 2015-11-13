#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
#

default[:cassandra][:seed_service_name] = 'cassandra'
default[:cassandra][:node_service_name] = 'cassandra'

# Allow Cassandra to use system disk?
default[:cassandra][:use_root_as_scratch_vol]    = false

## Config local disks for cassandra
# { mount_point => device }  e.g. '/mnt/sdb1' => '/dev/sdb1'
default[:disk][:data_disks] = {}
# { device => disk }  e.g. '/dev/sdb1' => '/dev/sdb'
default[:disk][:disk_devices] = {}
