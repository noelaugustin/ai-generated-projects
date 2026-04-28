FROM ubuntu:24.04

RUN apt-get update && apt-get install -y openssh-client curl sudo sshpass && \
    useradd -m -s /bin/bash user && echo 'user:password' | chpasswd

USER user
WORKDIR /home/user

# Download the Host CA Public Key so the client trusts target servers
# We will use an entrypoint script to do this.
COPY entrypoint.sh /home/user/entrypoint.sh

# Need to run as root to change permissions, then su to user, or just stay as root and su.
# Let's switch back to root so entrypoint can run, we'll run entrypoint as user inside.
USER root
RUN chmod +x /home/user/entrypoint.sh

CMD ["/bin/bash", "/home/user/entrypoint.sh"]
