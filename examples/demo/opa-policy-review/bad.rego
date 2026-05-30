package kubernetes.admission

# Default allow — anything not explicitly denied passes
default allow = true

# Deny privileged containers
allow = false {
    input.request.kind.kind == "Pod"
    container := input.request.object.spec.containers[_]
    container.securityContext.privileged == true
}
