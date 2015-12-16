FROM resin/raspberrypi2-node:4.0.0
MAINTAINER Shaun Mulligan <shaun@ resin.io>

RUN apt-get update && apt-get install -yq\
    openssh-server\
    jq\
    curl\
    rsync && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

#TODO: remove password login.
RUN mkdir /var/run/sshd
RUN echo 'root:resin' | chpasswd
RUN sed -i 's/PermitRootLogin without-password/PermitRootLogin yes/' /etc/ssh/sshd_config
RUN sed -i 's/UsePAM yes/UsePAM no/' /etc/ssh/sshd_config

# SSH login fix. Otherwise user is kicked off after login
RUN sed 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' -i /etc/pam.d/sshd

#change the port of systemd-sshd to 80
#TODO find a better way to do this.
# RUN sed -i 's/ListenStream=22/ListenStream=80/' /lib/systemd/system/ssh.socket
# RUN sed -i 's/sshd -D $SSHD_OPTS/sshd -D -p80 $SSHD_OPTS/' /lib/systemd/system/ssh.service

#create the ssh keys dir with correct perms
RUN mkdir -p /root/.ssh
#COPY keys/id_rsa.pub /root/.ssh/authorized_keys
RUN chmod 700  /root/.ssh
#RUN chmod 640  /root/.ssh/authorized_keys

#=================================================================
#User Dockerfile

#Enable systemd init system in the container
ENV INITSYSTEM on
RUN npm install -g coffee-script
RUN mkdir -p /usr/src/app && ln -s /usr/src/app /app
WORKDIR /usr/src/app
COPY . /usr/src/app
RUN DEBIAN_FRONTEND=noninteractive JOBS=MAX npm install --unsafe-perm

CMD ["bash", "/usr/src/app/start.sh"]
