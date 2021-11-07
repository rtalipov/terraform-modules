This repository is used by rtalipov/terraform-learning/cahpter4-module-versioning

The module location is specified with the code under stage/webservices-cluster/main.tf:

module "webserver_cluster" {
source = "git@github.com:rtalipov/terraform-modules.git//services/webserver-cluster?ref=v0.0.2
...}

For prod/webservices-cluster/main.tf:

module "webserver_cluster" {
  source = "git@github.com:rtalipov/terraform-modules.git//services/webserver-cluster?ref=v0.0.1"
  ..
  }

