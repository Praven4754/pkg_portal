pipeline {
    agent {
        docker {
            image 'docker:20.10.16'  // lightweight docker runner
            args '-v /var/run/docker.sock:/var/run/docker.sock'
        }
    }
    environment {
        DOCKERHUB_CREDENTIALS = credentials('dockerhub-creds')
    }
    stages {
        stage('Checkout') {
            steps {
                git 'https://github.com/Praven4754/pkg_portal.git'
            }
        }
        stage('Build Docker Image') {
            steps {
                sh 'docker build -t pravenkumar871/pkg_portal .'
            }
        }
        stage('Push to DockerHub') {
            steps {
                sh "echo ${DOCKERHUB_CREDENTIALS_PSW} | docker login -u ${DOCKERHUB_CREDENTIALS_USR} --password-stdin"
                sh 'docker push pravenkumar871/pkg_portal'
            }
        }
        stage('Run Container') {
            steps {
                sh 'docker compose -f compose.yml up -d'
            }
        }
    }
}
