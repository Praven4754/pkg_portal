pipeline {
    agent any

    environment {
        // Terraform vars path
        TFVARS_FILE   = '/var/jenkins_home/terraform.tfvars'

        // AWS credentials (mounted from host)
        AWS_SHARED_CREDENTIALS_FILE = '/root/.aws/credentials'
        AWS_CONFIG_FILE             = '/root/.aws/config'
    }

    stages {

        stage('Checkout Repo') {
            steps {
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
                script {
                    // Read from mounted .env dynamically
                    def ghcrUser = sh(script: "grep GHCR_USERNAME /var/jenkins_home/.env | cut -d'=' -f2", returnStdout: true).trim()
                    def ghcrToken = sh(script: "grep GHCR_TOKEN /var/jenkins_home/.env | cut -d'=' -f2", returnStdout: true).trim()

                    sh """
                        echo '🔑 Logging into GHCR...'
                        echo "${ghcrToken}" | docker login ghcr.io -u "${ghcrUser}" --password-stdin
                    """
                }
            }
        }

        stage('Deploy Docker Compose') {
            steps {
                dir("${WORKSPACE}") {
                    sh """
                        echo '🚀 Deploying Docker Compose...'
                        docker compose -f docker-compose.yml up -d
                        echo '✅ Docker Compose deployment finished'
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
