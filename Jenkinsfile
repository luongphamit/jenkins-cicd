env.GIT_CREDENTIALS_ID="4113d2cf-0e7f-458f-b8f9-687ec233c2f4"

pipeline {
    agent any
    environment {
        // Telegram configuration
        TOKEN = credentials('b4a49b21-4caa-4f7a-834b-ffa7d6b9c41e')
        CHAT_ID = credentials('69503db3-8106-40c6-8bd0-876b2eb2adb7')
    }
    post {
        success {
            script {
                sh "curl -X POST -H 'Content-Type: application/json' -d '{\"chat_id\": \"${CHAT_ID}\", \"text\": \"${JOB_NAME}: #${BUILD_NUMBER}\n=====\n✅ Deploy succeeded! \", \"disable_notification\": false}' \"https://api.telegram.org/bot${TOKEN}/sendMessage\""
            }
        }
        failure {
            script {
                sh "curl -X POST -H 'Content-Type: application/json' -d '{\"chat_id\": \"${CHAT_ID}\", \"text\": \"${JOB_NAME}: #${BUILD_NUMBER}\n=====\n❌Deploy failure!\", \"disable_notification\": false}' \"https://api.telegram.org/bot${TOKEN}/sendMessage\""
            }
        }

        aborted {
            script {
                sh "curl -X POST -H 'Content-Type: application/json' -d '{\"chat_id\": \"${CHAT_ID}\", \"text\": \"${JOB_NAME}: #${BUILD_NUMBER}\n=====\n❌Deploy aborted!\", \"disable_notification\": false}' \"https://api.telegram.org/bot${TOKEN}/sendMessage\""
            }
        }    
    }
    stages {
        stage('Noti') {
            steps {
                sh "curl -X POST -H 'Content-Type: application/json' -d '{\"chat_id\": \"${CHAT_ID}\", \"text\": \"${JOB_NAME}: #${BUILD_NUMBER}\n=====\n🎉Started!\", \"disable_notification\": false}' \"https://api.telegram.org/bot${TOKEN}/sendMessage\""
            }
        }
        stage('Checkout Code') {
            steps {
                gitCheckoutBranch()
            }
        }
        
        stage('Build and Push image') {
            steps {
                withCredentials([file(credentialsId: 'e4d281ee-df99-4332-af67-9e71976e3f66', variable: 'CommonENV'), file(credentialsId: 'f432f859-ee87-4839-9c10-a417795b2e55', variable: 'BridgeENV'), file(credentialsId: 'bf118c81-dd8b-4293-8744-13029caa1ea7', variable: 'SwapENV')]) {
                    withDockerRegistry(credentialsId: 'eeaa327e-4f33-4f7d-bfda-016f138a659d', url: 'https://hub.playgroundvina.com/') {
                        sh '''
                            echo "$CommonENV"
                            cat "$CommonENV" "$BridgeENV" > client-v2/.env
                            docker build -t hub.playgroundvina.com/pg/poolsbridge:dev -f docker/Dockerfile .
                            docker push hub.playgroundvina.com/pg/poolsbridge:dev
                            
                            cat "$CommonENV" "$SwapENV" > client-v2/.env
                            docker build -t hub.playgroundvina.com/pg/poolsswap:dev -f docker/Dockerfile .
                            docker push hub.playgroundvina.com/pg/poolsswap:dev
                        '''
                    }
                }
            }
        }
        
        
        stage('Deploy') {
            steps {
                sshagent(['5e7982bd-6f22-4cb5-961d-3c18032ed467']) {
                    sh '''
                        ssh -o StrictHostKeyChecking=no -l ubuntu 42.112.59.88 "cd /home/ubuntu/pools-swap-stake && bash deploy.dev.sh"
                    '''
                }
            }
        }
    }
}

def gitCheckoutBranch(){
  checkout([
    $class: 'GitSCM', 
    branches: [[name: "*/${GIT_BRANCH}"]],
    doGenerateSubmoduleConfigurations: false,
    extensions: [],
    submoduleCfg: [],
    userRemoteConfigs: [[ credentialsId: "${GIT_CREDENTIALS_ID}", url: "${GIT_URL}" ]]
  ])
}
