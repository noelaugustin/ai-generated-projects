1. Create root ca
1. Create intermediary CA that issues ssh host key certificates to machines
1. Create intermediary ca that issues ssh user key certificates to users
1. One ca server that the client can connect based on ssh -A <user>@<server> against a username and password listed in the server, which writes the key and certificate to the client's ssh agent
1. all servers that use ssh servers should implement ssh host key signing on first boot, calling the ca server and client should trust the root ca. Normal host key validation prompt should not come up anymore. the certs should have proper expiry and attributes that help identify the user.
1. provision user so that there are 3 users, one with normal access, other with sudo access and last with root access
1. demo instructions on how to verify the functionality
1. possibility of trusting the root ca in the linux trust store/mac trust store. write this finding in a exploration doc