pipeline {
    agent any
    tools {
        ansible 'Ansible'
        terraform 'Terraform'
    }

    environment {
        PATH = "/usr/local/bin:${env.PATH}"
        AWS_REGION = "us-east-1"
        APP_REPO_NAME = "clarusway-repo/cw-todo-app"
        // Définit les variables d'environnement pour les credentials AWS
        AWS_ACCESS_KEY_ID = credentials('aws-credentials-id')
        AWS_SECRET_ACCESS_KEY = credentials('aws-credentials-id')
    }

    stages {
        stage('Setup AWS Credentials') {
            steps {
                script {
                    withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws-credentials-id']]) {
                        env.AWS_ACCOUNT_ID = sh(script: 'aws sts get-caller-identity --query Account --output text', returnStdout: true).trim()
                        env.ECR_REGISTRY = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
                        echo "AWS Account ID: ${AWS_ACCOUNT_ID}"
                        echo "ECR Registry: ${ECR_REGISTRY}"
                    }
                }
            }
        }

        stage('Checkout Code') {
            steps {
                echo 'Cloning repository...'
                git url: 'https://github.com/YanisDevops/JenkinsServer-3Nodes-TierAPP.git', branch: 'main'
            }
        }

        stage('Create Infrastructure for the App') {
            steps {
                script {
                    withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws-credentials-id']]) {
                        echo 'Creating Infrastructure for the App on AWS Cloud'
                        sh 'terraform init'
                        sh 'terraform apply --auto-approve'
                    }
                }
            }
        }

        stage('Create ECR Repo') {
            steps {
                script {
                    withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws-credentials-id']]) {
                        echo 'Creating ECR Repo for App'
                        sh '''
                        aws ecr describe-repositories --region ${AWS_REGION} --repository-name ${APP_REPO_NAME} > /dev/null 2>&1 || \
                        aws ecr create-repository \
                          --repository-name ${APP_REPO_NAME} \
                          --image-scanning-configuration scanOnPush=false \
                          --image-tag-mutability MUTABLE \
                          --region ${AWS_REGION}
                        '''
                    }
                }
            }
        }  
        
        stage('Build App Docker Image') {
            steps {
                script {
                    withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws-credentials-id']]) {
                        env.NODE_IP = sh(script: 'terraform output -raw node_public_ip', returnStdout: true).trim()
                        env.DB_HOST = sh(script: 'terraform output -raw postgre_private_ip', returnStdout: true).trim()
                        env.DB_NAME = sh(script: 'aws --region=${AWS_REGION} ssm get-parameters --names "db_name" --query "Parameters[*].{Value:Value}" --output text', returnStdout: true).trim()
                        env.DB_PASSWORD = sh(script: 'aws --region=${AWS_REGION} ssm get-parameters --names "db_password" --query "Parameters[*].{Value:Value}" --output text', returnStdout: true).trim()
                    }
                }
                sh 'echo ${DB_HOST}'
                sh 'echo ${NODE_IP}'
                sh 'echo ${DB_NAME}'
                sh 'echo ${DB_PASSWORD}'
                sh 'envsubst < node-env-template > ./nodejs/server/.env'
                sh 'cat ./nodejs/server/.env'
                sh 'envsubst < react-env-template > ./react/client/.env'
                sh 'cat ./react/client/.env'
                sh 'docker build --force-rm -t "$ECR_REGISTRY/$APP_REPO_NAME:postgre" -f ./postgresql/dockerfile-postgresql .'
                sh 'docker build --force-rm -t "$ECR_REGISTRY/$APP_REPO_NAME:nodejs" -f ./nodejs/dockerfile-nodejs .'
                sh 'docker build --force-rm -t "$ECR_REGISTRY/$APP_REPO_NAME:react" -f ./react/dockerfile-react .'
                sh 'docker image ls'
            }
        }

        stage('Push Image to ECR Repo') {
            steps {
                script {
                    withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws-credentials-id']]) {
                        echo 'Pushing App Image to ECR Repo'
                        sh 'aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin "$ECR_REGISTRY"'
                        sh 'docker push "$ECR_REGISTRY/$APP_REPO_NAME:postgre"'
                        sh 'docker push "$ECR_REGISTRY/$APP_REPO_NAME:nodejs"'
                        sh 'docker push "$ECR_REGISTRY/$APP_REPO_NAME:react"'
                    }
                }
            }
        }
        
        stage('Wait for the Instance') {
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws-credentials-id']]) {
                    script {
                        echo 'Waiting for the instance'
                        id = sh(script: 'aws ec2 describe-instances --filters Name=tag-value,Values=ansible_postgresql Name=instance-state-name,Values=running --query Reservations[*].Instances[*].[InstanceId] --output text', returnStdout:true).trim()
                        sh 'aws ec2 wait instance-status-ok --instance-ids $id'
                    }
                }
            }
        }

        stage('Deploy the App') {
            steps {
                echo 'Deploying the App'
                sh 'ls -l'
                sh 'ansible --version'
                
                // Utilisation des credentials AWS et SSH
                withCredentials([
                    // Credentials AWS pour l'authentification avec AWS
                    [$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws-credentials-id'],
                    
                    // Credentials SSH pour l'accès aux instances
                    sshUserPrivateKey(credentialsId: 'key_pair_name', keyFileVariable: 'SSH_KEY')
                ]) {
                    sh '''
                        # Exporte les variables d'environnement AWS
                        export AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
                        export AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
                        
                        # Vérifie la clé SSH temporaire
                        ls -l $SSH_KEY
                        
                        # Vérifie l'inventaire Ansible
                        ansible-inventory -i inventory_aws_ec2.yml --graph
                        
                        # Teste la connectivité avec Ansible
                        ansible all -i inventory_aws_ec2.yml -m ping --private-key $SSH_KEY -u ec2-user
                        
                        # Exécute le playbook Ansible
                        ansible-playbook -i inventory_aws_ec2.yml docker_project.yml --private-key $SSH_KEY -u ec2-user
                    '''
                }
            }
        }
        
        stage('Destroy the infrastructure'){
            steps{
                timeout(time:5, unit:'DAYS'){
                    input message:'Approve terminate'
                }
                sh """
                docker image prune -af
                terraform destroy --auto-approve
                aws ecr delete-repository \
                  --repository-name ${APP_REPO_NAME} \
                  --region ${AWS_REGION} \
                  --force
                """
            }
        }

    }

    post {
        always {
            echo 'Deleting all local images'
            sh 'docker image prune -af'
        }
    }
    
}
