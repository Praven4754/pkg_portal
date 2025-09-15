pipeline {
    agent any

    environment {
        // Read GHCR credentials from mounted .env file
        GHCR_USERNAME = sh(script: "grep GHCR_USERNAME /var/jenkins_home/.env | cut -d'=' -f2", returnStdout: true).trim()
        GHCR_TOKEN    = sh(script: "grep GHCR_TOKEN /var/jenkins_home/.env | cut -d'=' -f2", returnStdout: true).trim()
        
        // Path to Terraform variables
        TFVARS_FILE   = '/var/jenkins_home/terraform.tfvars'
        
        // AWS environment variables (point to mounted AWS credentials)
        AWS_SHARED_CREDENTIALS_FILE = '/var/jenkins_home/.aws/credentials'
        AWS_CONFIG_FILE             = '/var/jenkins_home/.aws/config'
    }

    stages {

        stage('Checkout Repo') {
            steps {
                // Checkout into the workspace automatically
                git branch: 'main', url: 'https://github.com/Praven4754/pkg_portal.git'
            }
        }

        stage('Terraform Init & Apply') {
            steps {
                dir("${WORKSPACE}") {
                    sh """
                        echo '🔹 Initializing Terraform...'
                        terraform init
                        echo '🔹 Applying Terraform...'
                        terraform apply -var-file=${TFVARS_FILE} -auto-approve
                    """
                }
            }
        }

        stage('GHCR Login') {
            steps {
                sh """
                    echo '🔑 Logging into GHCR...'
                    echo "${GHCR_TOKEN}" | docker login ghcr.io -u "${GHCR_USERNAME}" --password-stdin
                """
            }
        }

        stage('Deploy Docker Compose') {
            steps {
                dir("${WORKSPACE}") {
                    sh """
                        echo '🚀 Deploying Docker Compose...'
                        docker compose -f docker-compose.yml up -d
                        echo '✅ Docker Compose deployment finished'
                        docker compose ps
                    """
                }
            }
        }

        stage('Verify Deployment') {
            steps {
                dir("${WORKSPACE}") {
                    sh """
                        echo '🔍 Verifying containers...'
                        docker compose ps
                        echo '🎉 Deployment verification finished!'
                    """
                }
            }
        }
    }

    post {
        success {
            echo "✅ Pipeline finished successfully!"
        }
        failure {
            echo "❌ Pipeline failed. Check logs above!"
        }
    }
}
