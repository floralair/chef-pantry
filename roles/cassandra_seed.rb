name		'cassandra_seed'
description	'A role for running Apache Cassandra seed'

run_list *%w[
  cassandra
  cassandra::seed
]
