variable "REGISTRY" {
  default = "docker.io"
}

target "default" {
  inherits = ["shared"]
  args = {
    BUILD_TITLE = "CoreDNS/lego"
    BUILD_DESCRIPTION = "A dubo image for CoreDNS"
  }
  tags = [
    "${REGISTRY}/dubodubonduponey/coredns",
  ]
}
