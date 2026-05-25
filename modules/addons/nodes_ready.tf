resource "terraform_data" "nodes_ready" {
  input = var.nodes_ready_dependency
}
