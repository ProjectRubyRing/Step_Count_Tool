# Aurora クラスター

resource "aws_rds_cluster" "main" {
  cluster_identifier = "main"
  engine             = "aurora-postgresql"
  engine_version     = "16.4"
  master_username    = "admin"

  /*
   * パスワードは Secrets Manager で管理する
   */
  manage_master_user_password = true
}

resource "aws_rds_cluster_instance" "main" {
  count              = 2
  cluster_identifier = aws_rds_cluster.main.id
  instance_class     = "db.r6g.large"
  engine             = aws_rds_cluster.main.engine
}
