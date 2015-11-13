name		'cassandra_node'
description	'A role for running Apache Cassandra node'

run_list *%w[
  cassandra
  cassandra::node
]
