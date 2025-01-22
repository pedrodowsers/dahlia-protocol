pipeline {
    options {
        buildDiscarder(logRotator(artifactDaysToKeepStr: '', artifactNumToKeepStr: '', daysToKeepStr: '5', numToKeepStr: '5'))
    }
    environment {
        GIT_SHA = "${sh(returnStdout: true, script: 'echo ${GIT_COMMIT} | cut -c1-12').trim()}"
    }
    agent {
        node {
            label 'debian1'
        }
    }
    stages {
        stage('Install') {
            parallel {
                stage('pnpm install') {
                    steps {
                        sh 'pnpm install --frozen-lockfile --unsafe-perm'
                        sh 'git submodule update --init --recursive'
//                        sh 'cd lib/royco && git submodule deinit lib/solady && git submodule deinit lib/solmate && git submodule deinit lib/openzeppelin-contracts'
                    }
                }
                stage('Debug') {
                    steps {
                        sh 'node --version'
                        sh 'npm --version'
                        sh 'pnpm --version'
                        sh 'pre-commit --version'
                        sh 'printenv'
                        script {
                            def branchName = sh(returnStdout: true, script: 'git rev-parse --abbrev-ref HEAD').trim()
                            echo "The current branch name is: ${branchName}"
                            echo "GIT_SHA is: ${GIT_SHA}"
                        }
                    }
                }
            }
        }
        stage('Build and Lint') {
            parallel {
                stage('Lint') {
                    steps {
                        withCredentials([string(credentialsId: 'MAINNET_RPC_URL', variable: 'MAINNET_RPC_URL'),
                                         string(credentialsId: 'SEPOLIA_RPC_URL', variable: 'SEPOLIA_RPC_URL')]) {
                            script {
                                sh 'pnpm run lint'
                                sh 'pnpm run size'
                            }
                        }
                    }
                }
//                stage('Coverage') {
//                    steps {
//                        withCredentials([string(credentialsId: 'MAINNET_RPC_URL', variable: 'MAINNET_RPC_URL'),
//                                         string(credentialsId: 'SEPOLIA_RPC_URL', variable: 'SEPOLIA_RPC_URL')]) {
//                            script {
//                                sh 'pnpm run coverage'
//                            }
//                        }
//                    }
//                }
                stage('Diff') {
                    steps {
                        withCredentials([string(credentialsId: 'MAINNET_RPC_URL', variable: 'MAINNET_RPC_URL'),
                                         string(credentialsId: 'SEPOLIA_RPC_URL', variable: 'SEPOLIA_RPC_URL')]) {
                            script {
                                sh 'pnpm run diff'
                            }
                        }
                    }
                }
                stage('Debug') {
                    steps {
                        withCredentials([string(credentialsId: 'MAINNET_RPC_URL', variable: 'MAINNET_RPC_URL'),
                                         string(credentialsId: 'SEPOLIA_RPC_URL', variable: 'SEPOLIA_RPC_URL')]) {
                            script {
                                sh 'forge test -vvvv'
                            }
                        }
                    }
                }
//                stage('Coverage') {
//                    steps {
//                        withCredentials([string(credentialsId: 'MAINNET_RPC_URL', variable: 'MAINNET_RPC_URL'),
//                                         string(credentialsId: 'SEPOLIA_RPC_URL', variable: 'SEPOLIA_RPC_URL')]) {
//                            script {
//                                sh 'forge coverage --no-match-coverage=.s.sol --ir-minimum --report lcov'
//                                cobertura(autoUpdateHealth: false, autoUpdateStability: false, coberturaReportFile: 'lcov.info')
//                            }
//                        }
//                    }
//                }
            }
        }
    }
}
