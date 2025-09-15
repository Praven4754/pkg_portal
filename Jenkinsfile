pipeline {
    agent any

    environment {
        TERRAFORM_DIR = "${WORKSPACE}"
        SSH_KEY = credentials('ec2-ssh-key')  // Store your PEM key as Jenkins credential
    }

    stages {
        stage('Clone Repository') {
            steps {
                git branch: 'main', url: 'https://github.com/Praven4754/pkg_portal.git'
            }
        }

        stage('Terraform Init & Apply') {
            steps {
                dir("${TERRAFORM_DIR}") {
                    sh """
                    terraform init
                    terraform apply -auto-approve
                    """
                }
            }
        }

        stage('Upload docker-compose.yml to EC2') {
            steps {
                script {
                    sh """
                    scp -i ${SSH_KEY} docker-compose.yml ubuntu@<EC2_PUBLIC_IP>:/home/ubuntu/pkg_portal/docker-compose.yml
                    """
                }
            }
        }

        stage('Run Docker Compose on EC2') {
            steps {
                script {
                    sh """
                    ssh -i ${SSH_KEY} ubuntu@<EC2_PUBLIC_IP> 'cd /home/ubuntu/pkg_portal && docker compose up -d'
                    """
                }
            }
        }
    }

    post {
        always {
            echo "Pipeline finished!"
        }
        success {
            echo "✅ Terraform + Docker deployment succeeded!"
        }
        failure {
            echo "❌ Deployment failed!"
        }
    }
}
