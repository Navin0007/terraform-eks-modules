output "validation_resource_id" {
  description = "ID of the post-apply validation null_resource (null when disabled)."
  value       = var.enabled ? null_resource.post_apply_validation[0].id : null
}

output "validation_script_path" {
  description = "Path to the validation script (for CI reuse)."
  value       = "${path.module}/scripts/validate-eks-cluster.sh"
}
