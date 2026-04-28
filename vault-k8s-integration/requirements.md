# Stage 1

1. two kind clusters.
2. one vault instance with local storage. 
3. both clusters and pods in it should be able to access vault.
4. vault needs to be able to access k8s clusters' api servers
5. register each cluster as an oidc provider in vault
6. vault needs to have a path called persona, and persona/<namespace-name>/<service-account-name> should have a secret path where there are multiple secrets stored and anyone can be accessed by the server. This is automated for all namespace-name/service-account-name combinations
7. All this needs to be done with terraform(cluster/ vault/ policies)
8. Create a pod in two namespaces, which uses the k8s auth method to authenticate with vault and access the secrets stored in the persona path. It should also try to access the other secret and fail.  This is the acceptance criteria



# Stage 2
1. Create a cronjob that creates identity keys and add it in the respective secret path that the SA can access.
1. The workload takes the private key and uses it to perform oauth2 with a server, and gets a JWT. 
1. the server checks for the public key of the server, which is also kept public somehwere in the DB so that it can access.
1. A short lived JWT generated is used for all s2s authentication. 
1. The auth is used against the respective audience so that the token is not misused by the receiving party
1. claims also can be issued by the oauth server based on the identity
1. The cron changing the identity key should be done in rotating fashion. The app also should incorporate this. multiple keys should be active, and upto 3 at any point in time
1. 


