data "aws_ecr_authorization_token" "token" {}
locals {
  proxy_endpoint      = data.aws_ecr_authorization_token.token.proxy_endpoint
  password            = data.aws_ecr_authorization_token.token.password
  ecr_repository_name = "my_lambda"
  ecr_image_tag       = "latest"
}

resource "aws_ecr_repository" "repo" {
  name         = local.ecr_repository_name
  tags         = var.common_tags
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "docker_image" "image" {
  name = local.ecr_repository_name
  build {
    path = "./src"
    tag  = ["${aws_ecr_repository.repo.repository_url}:${local.ecr_image_tag}"]
    label = {
      author : "Eugene Pokidov"
    }
  }

  triggers = {
    dir_sha1 = sha1(join("", [for f in fileset(path.module, "src/*") : filesha1(f)]))
  }

  depends_on = [aws_ecr_repository.repo]

  provisioner "local-exec" {
    command = <<EOF
      docker login ${local.proxy_endpoint} -u AWS --password-stdin < echo ${local.password}
      docker push ${aws_ecr_repository.repo.repository_url}:${local.ecr_image_tag}
    EOF
  }
}

data "aws_ecr_image" "pushed_image" {
  depends_on      = [docker_image.image]
  repository_name = local.ecr_repository_name
  image_tag       = local.ecr_image_tag
}

resource "aws_iam_role" "lambda_role" {
  name = "example-lambda-role"
  assume_role_policy = jsonencode({
    Version : "2012-10-17",
    Statement : [
      {
        Action : "sts:AssumeRole",
        Principal : {
          Service : "lambda.amazonaws.com"
        },
        Effect : "Allow"
      }
    ]
  })
  tags = var.common_tags
}


resource "aws_lambda_function" "example" {
  depends_on    = [docker_image.image]
  function_name = "example"
  image_uri     = "${aws_ecr_repository.repo.repository_url}@${data.aws_ecr_image.pushed_image.id}"
  package_type  = "Image"
  role          = aws_iam_role.lambda_role.arn

  tags = var.common_tags
}

output "lambda_name" {
  value = aws_lambda_function.example.id
}
