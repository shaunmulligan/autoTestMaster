#!/bin/bash

coffee /usr/src/app/src/server.coffee | /usr/src/app/node_modules/bunyan/bin/bunyan -o short
