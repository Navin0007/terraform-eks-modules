output "control_plane_sg_id" {
  description = "ID of the EKS control plane security group."
  value       = aws_security_group.control_plane.id
}

output "node_sg_id" {
  description = "ID of the EKS worker node security group."
  value       = aws_security_group.node.id
}

output "bastion_sg_id" {
  description = "ID of the bastion host security group."
  value       = aws_security_group.bastion.id
}

output "pod_sg_id" {
  description = "ID of the pod security group for Security Groups for Pods. No default ingress; workloads attach rules as needed."
  value       = aws_security_group.pod.id
}
