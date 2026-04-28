FROM ubuntu:24.04

RUN apt-get update && apt-get install -y openssh-server curl sudo socat sshpass bc && \
    mkdir /var/run/sshd

# Create target users
RUN useradd -m -s /bin/bash npc && echo 'npc:*' | chpasswd && \
    useradd -m -s /bin/bash mc && echo 'mc:*' | chpasswd && \
    usermod -aG sudo mc

# Allow users in sudo group to run sudo without password
RUN echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

COPY rotate-host-cert.sh /usr/local/bin/rotate-host-cert.sh
COPY init-target.sh /usr/local/bin/init-target.sh
COPY sshd_config /etc/ssh/sshd_config
RUN chmod +x /usr/local/bin/init-target.sh /usr/local/bin/rotate-host-cert.sh

EXPOSE 22

CMD ["/usr/local/bin/init-target.sh"]
