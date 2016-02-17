# Warning: This is a test base image, please do not use in production!!
FROM nghiant2710/device-sync:jessie

# Add the apt sources for raspbian
RUN echo "deb http://archive.raspbian.org/raspbian jessie main contrib non-free rpi firmware" >>  /etc/apt/sources.list
RUN apt-key adv --keyserver pgp.mit.edu  --recv-key 0x9165938D90FDDD2E

# Install dependencies.
RUN apt-get update \
	&& apt-get install -yq wget \
  build-essential \
  python \
	# Remove package lists to free up space
	&& rm -rf /var/lib/apt/lists/*

# Install Node.js
RUN wget https://nodejs.org/dist/v4.0.0/node-v4.0.0-linux-armv7l.tar.gz && \
		tar -xvf node-v4.0.0-linux-armv7l.tar.gz && \
		cd node-v4.0.0-linux-armv7l && \
		cp -R * /usr/local/

# These env vars enable sync_mode on all devices.
ENV SYNC_MODE=on
ENV INITSYSTEM=on
COPY entry.sh /usr/bin/entry.sh 

ENV VERSION 2
RUN npm install -g coffee-script
RUN mkdir -p /usr/src/app && ln -s /usr/src/app /app
WORKDIR /usr/src/app
COPY . /usr/src/app
RUN DEBIAN_FRONTEND=noninteractive JOBS=MAX npm install --unsafe-perm

CMD ["bash", "/usr/src/app/start.sh"]
