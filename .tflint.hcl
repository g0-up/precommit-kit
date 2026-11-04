# .tflint.hcl — https://github.com/terraform-linters/tflint
config {
  call_module_type = "local"   # lint cả module local; "all" sẽ tải module remote
  force            = false
}

# Ruleset core (built-in, không cần tải)
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# Bật khi dùng AWS/GCP/Azure (tflint --init sẽ tải plugin)
# plugin "aws" {
#   enabled = true
#   version = "0.44.0"
#   source  = "github.com/terraform-linters/tflint-ruleset-aws"
# }
