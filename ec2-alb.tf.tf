# -------------------------
# ALB
# -------------------------
resource "aws_lb" "app_alb" {
  name               = var.alb_name
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]

  # MUST include two subnets in two AZs for an ALB
  subnets = [
    aws_subnet.public_subnet.id,
    aws_subnet.public_subnet_2.id
  ]

  tags = {
    Name = "app-alb"
  }
}

# -------------------------
# Target Group
# -------------------------
resource "aws_lb_target_group" "tg" {
  name     = "private-app-tg"
  port     = 5000
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  # healthy check (optional but recommended)
  health_check {
    protocol = "HTTP"
    path     = "/"
    matcher  = "200-399"
    interval = 30
    timeout  = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

# -------------------------
# Listener
# -------------------------
resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.app_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

# -------------------------
# EC2 Instance
# -------------------------
resource "aws_instance" "app_server" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private_subnet.id
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  key_name               = var.ssh_key_name != "" ? var.ssh_key_name : null

  user_data = <<-EOF
#!/bin/bash
yum update -y
yum install -y python3
pip3 install flask

cat << 'APP' > /home/ec2-user/app.py
from flask import Flask
app = Flask(__name__)

@app.route('/')
def hello():
    return "Hello World from Private EC2!"

app.run(host='0.0.0.0', port=5000)
APP

# run app as ec2-user
chown ec2-user:ec2-user /home/ec2-user/app.py
su - ec2-user -c "nohup python3 /home/ec2-user/app.py >/home/ec2-user/app.log 2>&1 &"
EOF

  tags = {
    Name = "private-app-ec2"
  }
}

# -------------------------
# Attach EC2 to target group
# -------------------------
resource "aws_lb_target_group_attachment" "attach" {
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = aws_instance.app_server.id
  port             = 5000
}
