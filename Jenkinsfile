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
        stage('Checkout Code') {
            steps {
                git branch: 'main', credentialsId: '4113d2cf-0e7f-458f-b8f9-687ec233c2f4', url: 'https://github.com/playgroundvina/pools-swap-stake'
            }
        }
        
        stage('Build and Push image') {
            steps {
                withCredentials([file(credentialsId: '966848c2-cfcf-48d4-af6e-d85534886b4b', variable: 'CommonENV'), file(credentialsId: 'b96bcde3-71c2-483a-87fe-bd4c44614d31', variable: 'BridgeENV'), file(credentialsId: '1582f7ec-e981-47c9-92c7-a64a9d345324', variable: 'SwapENV')]) {
                    withDockerRegistry(credentialsId: 'eeaa327e-4f33-4f7d-bfda-016f138a659d', url: 'https://hub.playgroundvina.com/') {
                        sh '''
                            cat "$CommonENV" "$BridgeENV" > client-v2/.env
                            docker build -t hub.playgroundvina.com/pg/poolsbridge:pro -f docker/Dockerfile .
                            docker push hub.playgroundvina.com/pg/poolsbridge:pro
                            
                            cat "$CommonENV" "$SwapENV" > client-v2/.env
                            docker build -t hub.playgroundvina.com/pg/poolsswap:pro -f docker/Dockerfile .
                            docker push hub.playgroundvina.com/pg/poolsswap:pro
                        '''
                    }
                }
            }
        }
        
        
        stage('Deploy') {
            steps {
                sshagent(['3d24d712-2b75-42a1-b813-b35ee0348847']) {
                    sh '''
                        ssh -o StrictHostKeyChecking=no -l ubuntu 13.251.215.146 "cd /home/ubuntu/pools-swap-stake && bash deploy.pro.sh"
                    '''
                }
            }
        }
    }
}
