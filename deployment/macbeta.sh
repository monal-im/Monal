#!/bin/sh
# this is sthe script used to deploy mac betas to monal.im
# Argument 1 is the mac binary folder produced by exporting from xcode 
#Argument 2 is the user on the remote host 
# scp assumes you have a trusted key on  monal.im

cd "$1"
tar -zcvf  Monal-macOS.tar.gz Monal.app
scp -i ~/.ssh/id_rsa  Monal-macOS.tar.gz $2@www.monal.im:monal.im/macOS
