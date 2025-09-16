pipeline {
    agent any

    environment {
        // Terraform vars path
        TFVARS_FILE = '/var/jenkins_home/terraform.tfvars'

        // AWS credentials (mounted from host)
        AWS_SHARED_CREDENTIALS_FILE = '/root/.aws/credentials'
        AWS_CONFIG_FILE             = '/root/.aws/config'
    }

    stages {

        stage('Checkout Repo') {
            steps {
                echo "📥 Checking out GitHub repo..."
                git branch: 'main', url: 'https://github.com/Praven4754/pkg_portal.git'
            }
        }

        stage('Terraform Init & Apply') {
            steps {
                dir("${WORKSPACE}") {
                    echo "🔹 Initializing Terraform..."
                    sh "terraform init"

                    echo "🔹 Planning Terraform..."
                    sh "terraform plan -var-file=${TFVARS_FILE}"

                    echo "🔹 Applying Terraform..."
                    sh "terraform apply -var-file=${TFVARS_FILE} -auto-approve"
                }
            }
        }

        stage('GHCR Login') {
            steps {
                script {
                    // Read GHCR credentials dynamically from mounted .env
                    def ghcrUser  = sh(script: "grep GHCR_USERNAME /var/jenkins_home/.env | cut -d'=' -f2", returnStdout: true).trim()
                    def ghcrToken = sh(script: "grep GHCR_TOKEN /var/jenkins_home/.env | cut -d'=' -f2", returnStdout: true).trim()

                    echo "🔑 Logging into GHCR..."
                    sh """
                        echo "${ghcrToken}" | docker login ghcr.io -u "${ghcrUser}" --password-stdin
                    """
                }
            }
        }

        stage('Deploy Docker Compose') {
            steps {
                dir("/var/jenkins_home/pkg_portal") {   // Must match main.tf uploaded location
                    echo "🚀 Deploying Docker Compose..."
                    sh """
                        docker compose up -d
                        echo '✅ Docker Compose deployment finished'
                    """
                }
            }
        }

        stage('Verify Deployment') {
            steps {
                dir("/var/jenkins_home/pkg_portal") {
                    echo "🔍 Verifying containers..."
                    sh """
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
