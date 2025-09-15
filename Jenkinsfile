pipeline {
    agent any

    stages {
        stage('Checkout Repo') {
            steps {
                dir('/var/jenkins_home/workspace/pkg_portal') {
                    git branch: 'main', url: 'https://github.com/Praven4754/pkg_portal.git'
                }
            }
        }

        stage('Load Env Variables') {
            steps {
                script {
                    env.GHCR_USERNAME = sh(script: "grep GHCR_USERNAME /var/jenkins_home/.env | cut -d'=' -f2", returnStdout: true).trim()
                    env.GHCR_TOKEN    = sh(script: "grep GHCR_TOKEN /var/jenkins_home/.env | cut -d'=' -f2", returnStdout: true).trim()
                    env.TFVARS_FILE   = '/var/jenkins_home/terraform.tfvars'
                }
            }
        }

        stage('Terraform Init & Apply') {
            steps {
                dir('/var/jenkins_home/workspace/pkg_portal') {
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
                dir('/var/jenkins_home/workspace/pkg_portal') {
                    sh """
                        echo '🚀 Deploying Docker Compose...'
                        docker-compose -f docker-compose.yml up -d
                        docker-compose ps
                    """
                }
            }
        }

        stage('Verify Deployment') {
            steps {
                dir('/var/jenkins_home/workspace/pkg_portal') {
                    sh """
                        echo '🔍 Checking containers status...'
                        docker-compose ps
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
            echo "❌ Pipeline failed. Check the logs above!"
        }
    }
}
