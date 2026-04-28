FROM ubuntu:24.04

RUN apt-get update && apt-get install -y openssh-server python3 curl sudo && \
    mkdir /var/run/sshd

# Setup users
RUN useradd -m -s /bin/bash npc && echo 'npc:npc' | chpasswd && \
    useradd -m -s /bin/bash mc && echo 'mc:mc' | chpasswd && \
    useradd -m -s /bin/bash god && echo 'god:god' | chpasswd && \
    useradd -m -s /bin/bash provision && echo 'provision:provision' | chpasswd && \
    echo "npc ALL=(root) NOPASSWD: /usr/bin/ssh-keygen, /usr/bin/cat, /bin/cat" >> /etc/sudoers && \
    echo "mc ALL=(root) NOPASSWD: /usr/bin/ssh-keygen, /usr/bin/cat, /bin/cat" >> /etc/sudoers && \
    echo "god ALL=(root) NOPASSWD: /usr/bin/ssh-keygen, /usr/bin/cat, /bin/cat" >> /etc/sudoers && \
    echo "provision ALL=(root) NOPASSWD: /usr/bin/ssh-keygen, /usr/bin/cat, /bin/cat" >> /etc/sudoers

# We will mount configurations and scripts
COPY sshd_config /etc/ssh/sshd_config
COPY issue-user-cert.sh /usr/local/bin/issue-user-cert.sh
COPY provision-handler.sh /usr/local/bin/provision-handler.sh
COPY init-ca.sh /usr/local/bin/init-ca.sh

RUN chmod +x /usr/local/bin/issue-user-cert.sh /usr/local/bin/provision-handler.sh /usr/local/bin/init-ca.sh

EXPOSE 22 2222

CMD ["/usr/local/bin/init-ca.sh"]
