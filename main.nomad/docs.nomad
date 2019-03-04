job "{NS}-docs" {
  datacenters = ["dc-1"]
  group "webs" {
    count = 5
    task "frontend" {
      driver = "docker"
      config {
        image = "hashicorp/web-frontend"
      }
      resources {
        cpu    = 500 # MHz
        memory = 128 # MB
      }
      env {
        "CONSUL_NAMESPACE_ID" = "{NS}"
        "CONSUL_NAMESPACE_ID_FOR_FOO" = "{NS_FOO}"
      }
    }
  }
}
