#----provider----

provider "aws" {
  access_key = "${var.aws_access_key}"
  secret_key = "${var.aws_secret_key}"
  region  = "us-east-1"
}

#-----ROle------

resource "aws_iam_role" "ec2_role" {
  name = "ec2_role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "admin_attach" {
  name = "adminaccess"
  role      = "${aws_iam_role.ec2_role.name}"

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "*",
            "Resource": "*"
        }
    ]
}
EOF
}

#---Key----

resource "aws_key_pair" "mykey" {
  key_name = "mykey"
  public_key = "${file("${var.PATH_TO_PUBLIC_KEY}")}"
}


#---Security groups----

#public security group

resource "aws_security_group" "wp_sg" {
  name        = "wp_sg"
  description = "used for elastic load balancer for public"
  vpc_id      = "${aws_vpc.wp_vpc.id}"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  #HTTP

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 8081
    to_port     = 8081
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
   ingress {
    from_port   = 5672
    to_port     = 5672
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
   }
  ingress {
    from_port   = 5673
    to_port     = 5673
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 15672
    to_port     = 15672
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
 egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#----VPC----

resource "aws_vpc" "wp_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags {
    Name = "wp_vpc"
  }
}

#intergateway

resource "aws_internet_gateway" "wp_internet_gateway" {
  vpc_id = "${aws_vpc.wp_vpc.id}"

  tags {
    Name = "wp_igw"
  }
        }

#Route tables

resource "aws_route_table" "wp_public_rt" {
  vpc_id = "${aws_vpc.wp_vpc.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.wp_internet_gateway.id}"
  }

  tags {
    Name = "wp_public"
  }
}

resource "aws_default_route_table" "wp_private_rt" {
  default_route_table_id = "${aws_vpc.wp_vpc.default_route_table_id}"

  tags {
    Name = "wp_private"
  }
}

#subnets

resource "aws_subnet" "wp_public1_subnet" {
  vpc_id                  = "${aws_vpc.wp_vpc.id}"
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${data.aws_availability_zones.available.names[0]}"

  tags {
    Name = "wp_public1"
  }
}

resource "aws_subnet" "wp_public2_subnet" {
  vpc_id                  = "${aws_vpc.wp_vpc.id}"
  cidr_block              = "10.0.2.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${data.aws_availability_zones.available.names[1]}"

  tags {
    Name = "wp_public2"
  }
}

resource "aws_subnet" "wp_private1_subnet" {
  vpc_id                  = "${aws_vpc.wp_vpc.id}"
  cidr_block              = "10.0.3.0/24"
  map_public_ip_on_launch = false
  availability_zone       = "${data.aws_availability_zones.available.names[0]}"

  tags {
    Name = "wp_private1"
  }
}

resource "aws_subnet" "wp_private2_subnet" {
  vpc_id                  = "${aws_vpc.wp_vpc.id}"
  cidr_block              = "10.0.4.0/24"
  map_public_ip_on_launch = false
  availability_zone       = "${data.aws_availability_zones.available.names[1]}"

  tags {
    Name = "wp_private2"
  }
}

#public subnet group

# subnet associations

resource "aws_route_table_association" "wp_public1_assoc" {
  subnet_id      = "${aws_subnet.wp_public1_subnet.id}"
  route_table_id = "${aws_route_table.wp_public_rt.id}"
}

resource "aws_route_table_association" "wp_public2_assoc" {
  subnet_id      = "${aws_subnet.wp_public2_subnet.id}"
  route_table_id = "${aws_route_table.wp_public_rt.id}"
}

#private associations

resource "aws_route_table_association" "wp_private1_assoc" {
  subnet_id      = "${aws_subnet.wp_private1_subnet.id}"
  route_table_id = "${aws_default_route_table.wp_private_rt.id}"
}

resource "aws_route_table_association" "wp_private2_assoc" {
  subnet_id      = "${aws_subnet.wp_private2_subnet.id}"
  route_table_id = "${aws_default_route_table.wp_private_rt.id}"
}

#NAT gateway

# NAT
resource "aws_eip" "neweip" {
  vpc   = true
}

resource "aws_nat_gateway" "nat" {
  allocation_id = "${element(aws_eip.neweip.*.id, count.index)}"
  subnet_id     = "${element(aws_subnet.wp_public1_subnet.*.id, count.index)}"
}

resource "aws_route" "nat_gateway" {
  route_table_id         = "${element(aws_default_route_table.wp_private_rt.*.id, count.index)}"
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = "${element(aws_nat_gateway.nat.*.id, count.index)}"

}

#----Route53----


#Primary zone

resource "aws_route53_zone" "primary" {
  name              = "www.sandeep078.tk"
}

#www

resource "aws_route53_record" "www" {
  zone_id = "${aws_route53_zone.primary.zone_id}"
  name    = "www.sandeep078.tk"
  type    = "A"
  alias {
    name                   = "${aws_elb.wp_elb.dns_name}"
    zone_id                = "${aws_elb.wp_elb.zone_id}"
    evaluate_target_health = false
  }
}


#private zone

resource "aws_route53_zone" "secondary" {
  name   = "www.sandeep078.tk"
  vpc_id = "${aws_vpc.wp_vpc.id}"
}


#----ELB---

resource "aws_iam_server_certificate" "test_cert" {
  name             = "some_test_cert"
  certificate_body = "${file("server.cert")}"
  private_key      = "${file("server.key")}"
}

resource "aws_elb" "wp_elb" {
  name = "newbalancer-elb"

  subnets = ["${aws_subnet.wp_public1_subnet.id}",
    "${aws_subnet.wp_public2_subnet.id}",
  ]

  security_groups = ["${aws_security_group.wp_sg.id}"]

  listener {
    instance_port     = 8080
    instance_protocol = "tcp"
    lb_port           = 8080
    lb_protocol       = "tcp"
  }
 listener {
    instance_port     = 443
    instance_protocol = "https"
    lb_port           = 443
    lb_protocol       = "https"
    ssl_certificate_id = "${aws_iam_server_certificate.test_cert.arn}"
  }



  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "HTTP:8080/"
    interval            = 30
  }

 cross_zone_load_balancing   = true
  idle_timeout                = 400
  connection_draining         = true
  connection_draining_timeout = 400

  tags {
    Name = "wp_elb_new"
  }
}

#launch configuration

resource "aws_launch_configuration" "wp_lc" {
  name_prefix   = "wp_lc-"
  image_id      = "${aws_ami_from_instance.wp_golden.id}"
  instance_type = "t2.micro"

  security_groups = ["${aws_security_group.wp_sg.id}"]

  key_name                    = "${aws_key_pair.mykey.key_name}"

  lifecycle {
    create_before_destroy = true
  }
}

#autoscaling

resource "aws_autoscaling_group" "wp_asg" {
  launch_configuration = "${aws_launch_configuration.wp_lc.name}"

  vpc_zone_identifier = ["${aws_subnet.wp_private1_subnet.id}",
    "${aws_subnet.wp_private2_subnet.id}",
  ]

  min_size          = 2
  max_size          = 4
  load_balancers    = ["${aws_elb.wp_elb.id}"]
  health_check_type = "EC2"

  tags {
    key                 = "Name"
    value               = "wp_asg-instance"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_policy" "cpu_policy" {
  name                   = "CpuPolicy"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = "${aws_autoscaling_group.wp_asg.name}"
}

resource "aws_cloudwatch_metric_alarm" "monitor_cpu" {
  namespace           = "CPUwatch"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = "3"
  metric_name         = "CPUUtilization"
  namespace           = "AWSec2"
  period              = "120"
  statistic           = "Average"
  threshold           = "50"

  dimensions = {
    "AutoScalingGroupName" = "${aws_autoscaling_group.wp_asg.name}"
  }

  alarm_name    = "cpuwatch-asg"
  alarm_actions = ["${aws_autoscaling_policy.cpu_policy.arn}"]
}

resource "aws_autoscaling_policy" "policy_down" {
  name                   = "downPolicy"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = "${aws_autoscaling_group.wp_asg.name}"
}


resource "aws_cloudwatch_metric_alarm" "monitor_down" {
  namespace           = "downwatch"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWSec2"
  period              = "120"
  statistic           = "Average"
  threshold           = "10"

  dimensions = {
    "AutoScalingGroupName" = "${aws_autoscaling_group.wp_asg.name}"
  }

  alarm_name    = "downwatch-asg"
  alarm_actions = ["${aws_autoscaling_policy.cpu_policy.arn}"]
}

#---AMI--

resource "aws_ami_from_instance" "wp_golden" {
  name               = "wp_ami_tomcat"
  source_instance_id = "${aws_instance.webserver.id}"
}

resource "aws_instance" "webserver" {
  ami             =  "${lookup(var.AMIS, var.AWS_REGION)}"
  instance_type   = "t2.micro"
  key_name        = "${aws_key_pair.mykey.key_name}"
  vpc_security_group_ids = ["${aws_security_group.wp_sg.id}"]
  subnet_id       = "${aws_subnet.wp_public1_subnet.id}"
  #iam_instance_profile = "aws_iam_role.ec2_role.Name"

 
provisioner "local-exec" {
     command = "sleep 30 && echo \"[tomcat-servers]\n${aws_instance.webserver.public_ip} ansible_connection=ssh ansible_ssh_user=ec2-user ansible_ssh_private_key_file=mykey host_key_checking=False\" > tomcat-inventory &&  ansible-playbook -i tomcat-inventory ansible-playbooks/tomcat-site.yml "
  }
 connection {
    user = "${var.INSTANCE_USERNAME}"
    private_key = "${file("${var.PATH_TO_PRIVATE_KEY}")}"
  }
  

 tags {
     Name = "Dev"
   }
}

resource "aws_elb_attachment" "baz" {
  elb      = "${aws_elb.wp_elb.id}"
  instance = "${aws_instance.webserver.id}"
}

# resource "aws_instance" "jenkins" {
#  ami = "${lookup(var.AMIS, var.AWS_REGION)}"
#  instance_type = "t2.micro"
#  vpc_security_group_ids = [ "${aws_security_group.wp_sg.id}" ]
#  key_name = "${aws_key_pair.mykey.key_name}"
 # iam_instance_profile = "${aws_iam_role.test_role.name}"
#  subnet_id       = "${aws_subnet.wp_public1_subnet.id}"

 #  provisioner "local-exec" {
 #  command = "sleep 30 && echo \"[jenkins-server]\n${aws_instance.jenkins.public_ip} ansible_connection=ssh ansible_ssh_user=ec2-user ansible_ssh_private_key_file=mykey host_key_checking=False\" > jenkins-inventory &&  ansible-playbook -i jenkins-inventory ansible-playbooks/jenkins-create.yml "
 # }

 # connection {
 #   user = "${var.INSTANCE_USERNAME}"
 #   private_key = "${file("${var.PATH_TO_PRIVATE_KEY}")}"
 # }
# tags {
 #    Name = "QA"
 #  }

#}

resource "aws_iam_instance_profile" "test_profile" {
  name = "test_profile"
  role = "${aws_iam_role.ec2_role.name}"
}

resource "aws_instance" "bastion" {
  ami             = "ami-43a15f3e"
  instance_type   = "t2.micro"
  key_name        =  "${aws_key_pair.mykey.key_name}"
  vpc_security_group_ids = ["${aws_security_group.wp_sg.id}"]
  subnet_id       = "${aws_subnet.wp_public1_subnet.id}"

  tags {
    Name = "bastion"
  }
}







