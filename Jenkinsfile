pipeline {
    agent any

    environment {
        // Read GHCR credentials from mounted .env
        GHCR_USERNAME = sh(script: "grep GHCR_USERNAME /var/jenkins_home/.env | cut -d '=' -f2", returnStdout: true).trim()
        GHCR_TOKEN    = sh(script: "grep GHCR_TOKEN /var/jenkins_home/.env | cut -d '=' -f2", returnStdout: true).trim()
    }

    stages {
        stage('Checkout Repo') {
            steps {
                echo "🔄 Checking out pkg_portal repo..."
                git branch: 'main', url: 'https://github.com/Praven4754/pkg_portal.git'
            }
        }

        stage('Run Docker Compose') {
            steps {
                dir("${WORKSPACE}") {
                    echo "🚀 Running Docker Compose..."
                    sh '''
                        # Ensure Docker socket is accessible
                        if [ ! -S /var/run/docker.sock ]; then
                            echo "❌ Docker socket not found!"
                            exit 1
                        fi

                        # Login to GHCR
                        echo $GHCR_TOKEN | docker login ghcr.io -u $GHCR_USERNAME --password-stdin

                        # Run docker-compose with mounted .env and tfvars
                        docker compose -f docker-compose.yml up -d
                    '''
                }
            }
        }

        stage('Verify Deployment') {
            steps {
                dir("${WORKSPACE}") {
                    sh '''
                        echo "🔍 Checking container statuses..."
                        docker compose -f docker-compose.yml ps
                    '''
                }
            }
        }
    }

    post {
        success {
            echo "🎉 Deployment completed successfully!"
        }
        failure {
            echo "❌ Deployment failed. Check logs above."
        }
    }
}
