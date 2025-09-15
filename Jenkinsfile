pipeline {
    agent any

    environment {
        // Load GHCR and other environment variables from the mounted .env
        DOTENV_FILE = '/mnt/jenkins_env/.env'
    }

    stages {

        stage('Load Env') {
            steps {
                script {
                    // Export all variables from the mounted .env
                    def props = readFile(DOTENV_FILE).split("\n")
                    for (line in props) {
                        if (line.contains("=")) {
                            def (key, value) = line.split("=", 2)
                            env."${key.trim()}" = value.trim()
                        }
                    }
                }
            }
        }

        stage('Checkout Repo') {
            steps {
                git branch: 'main',
                    url: 'https://github.com/Praven4754/pkg_portal.git'
            }
        }

        stage('Deploy Docker Compose') {
            steps {
                script {
                    // Ensure docker-compose is installed on the host
                    sh '''
                        docker-compose --version || sudo apt-get update && sudo apt-get install -y docker-compose
                    '''

                    // Login to GHCR using variables from .env
                    sh 'echo $GHCR_TOKEN | docker login ghcr.io -u $GHCR_USERNAME --password-stdin'

                    // Run docker-compose using the repo's file
                    sh '''
                        docker-compose -f docker-compose.yml up -d
                    '''
                }
            }
        }

        stage('Verify Deployment') {
            steps {
                script {
                    sh '''
                        docker ps
                        docker-compose -f docker-compose.yml ps
                    '''
                }
            }
        }
    }

    post {
        failure {
            echo "❌ Deployment failed. Check logs above."
        }
        success {
            echo "✅ Deployment succeeded!"
        }
    }
}
