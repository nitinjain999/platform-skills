package kubernetes.admission

import rego.v1

# Default deny — nothing passes unless explicitly allowed
default allow := false

allow if {
    not any_violation
}

any_violation if {
    count(deny) > 0
}

# Deny privileged containers
deny contains msg if {
    input.request.kind.kind == "Pod"
    container := input.request.object.spec.containers[_]
    container.securityContext.privileged == true
    msg := sprintf("container '%v' must not run as privileged", [container.name])
}

# Deny containers running as root
deny contains msg if {
    input.request.kind.kind == "Pod"
    container := input.request.object.spec.containers[_]
    not container.securityContext.runAsNonRoot == true
    msg := sprintf("container '%v' must set runAsNonRoot: true", [container.name])
}

# Deny missing resource limits
deny contains msg if {
    input.request.kind.kind == "Pod"
    container := input.request.object.spec.containers[_]
    not container.resources.limits.memory
    msg := sprintf("container '%v' must set resources.limits.memory", [container.name])
}

# Deny hostNetwork
deny contains msg if {
    input.request.kind.kind == "Pod"
    input.request.object.spec.hostNetwork == true
    msg := "pod must not use hostNetwork"
}
