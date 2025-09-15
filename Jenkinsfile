pipeline {
    agent {
        docker {
            image 'docker:20.10.16'                  // lightweight Docker runner
            args '-v /var/run/docker.sock:/var/run/docker.sock'
        }
    }
    environment {
        DOCKERHUB_CREDENTIALS = credentials('dockerhub-creds')
    }
    stages {
        stage('Checkout') {
            steps {
                git branch: 'main', url: 'https://github.com/Praven4754/pkg_portal.git'
            }
        }
        stage('Docker Login') {
            steps {
                sh """
                    export DOCKER_CONFIG=\$WORKSPACE/.docker
                    mkdir -p \$DOCKER_CONFIG
                    echo \$DOCKERHUB_CREDENTIALS_PSW | docker login -u \$DOCKERHUB_CREDENTIALS_USR --password-stdin
                """
            }
        }
        stage('Build Docker Image') {
            steps {
                dir("${WORKSPACE}") {
                    sh 'docker build -t pravenkumar871/pkg_portal .'
                }
            }
        }
        stage('Push to DockerHub') {
            steps {
                dir("${WORKSPACE}") {
                    sh 'docker push pravenkumar871/pkg_portal'
                }
            }
        }
        stage('Run Container') {
            steps {
                dir("${WORKSPACE}") {
                    sh 'docker compose -f docker-compose.yml up -d'
                }
            }
        }
    }
    post {
        always {
            echo 'Pipeline finished.'
        }
    }
}
